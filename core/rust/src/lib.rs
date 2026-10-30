//! DriveFlow native core. TDLib is loaded at runtime to keep local core builds
//! independent of per-platform TDLib compilation and linking.

mod app;
mod auth;
mod storage;
mod telegram_bridge;
mod transfer_queue;

use std::{ffi::{c_char, CStr, CString}, sync::{Mutex, OnceLock}};
use serde_json::{json, Value};

struct Session {
    bridge: TelegramBridge,
    api_id: i32,
    api_hash: String,
    database_dir: String,
    encryption_key: String,
    parameters_sent: bool,
    chats_requested: bool,
    authorization_state: String,
    error: Option<String>,
    chats: Vec<Value>,
}

static SESSION: OnceLock<Mutex<Option<Session>>> = OnceLock::new();

fn session() -> &'static Mutex<Option<Session>> { SESSION.get_or_init(|| Mutex::new(None)) }

pub use app::AppCore;
pub use auth::{AuthState, AuthUpdate};
pub use storage::MetadataStore;
pub use telegram_bridge::TelegramBridge;
pub use transfer_queue::{QueueError, Transfer, TransferQueue, TransferState};

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', "�")).expect("sanitized string has no NUL").into_raw()
}

/// Version string for the Dart FFI boundary. The returned string must be freed
/// with `driveflow_string_free`.
#[no_mangle]
pub extern "C" fn driveflow_version() -> *mut c_char {
    into_c_string(env!("CARGO_PKG_VERSION").to_owned())
}

/// Start a TDLib JSON client. Inputs are UTF-8 C strings and are never logged.
#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_start(api_id: i32, api_hash: *const c_char, database_dir: *const c_char, encryption_key: *const c_char) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        if api_hash.is_null() || database_dir.is_null() || encryption_key.is_null() { return Err("missing_argument".into()); }
        let hash = CStr::from_ptr(api_hash).to_str().map_err(|_| "invalid_api_hash")?.to_owned();
        let dir = CStr::from_ptr(database_dir).to_str().map_err(|_| "invalid_database_path")?.to_owned();
        let key = CStr::from_ptr(encryption_key).to_str().map_err(|_| "invalid_encryption_key")?.to_owned();
        if api_id <= 0 || hash.is_empty() || key.is_empty() { return Err("invalid_telegram_configuration".into()); }
        let bridge = TelegramBridge::load().map_err(|e| e.to_string())?;
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned")?;
        *guard = Some(Session { bridge, api_id, api_hash: hash, database_dir: dir, encryption_key: key,
            parameters_sent: false, chats_requested: false, authorization_state: "authorizationStateWaitTdlibParameters".into(), error: None, chats: Vec::new() });
        Ok(json!({"ok":true}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

fn with_input(value: *const c_char, label: &'static str, f: impl FnOnce(&mut Session, &str) -> Result<(), String>) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        if value.is_null() { return Err(format!("missing_{label}")); }
        let input = unsafe { CStr::from_ptr(value) }.to_str().map_err(|_| format!("invalid_{label}"))?;
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned".to_string())?;
        let current = guard.as_mut().ok_or_else(|| "telegram_not_started".to_string())?;
        f(current, input)?;
        Ok(json!({"ok":true}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_phone(phone: *const c_char) -> *mut c_char {
    with_input(phone, "phone", |s, v| s.bridge.submit_phone_number(v).map_err(|e| e.to_string()))
}
#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_code(code: *const c_char) -> *mut c_char {
    with_input(code, "code", |s, v| s.bridge.submit_code(v).map_err(|e| e.to_string()))
}
#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_password(password: *const c_char) -> *mut c_char {
    with_input(password, "password", |s, v| s.bridge.submit_password(v).map_err(|e| e.to_string()))
}
#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_send_file(chat_id: i64, path: *const c_char) -> *mut c_char {
    with_input(path, "path", |s, v| s.bridge.send_file(chat_id, v, "").map_err(|e| e.to_string()))
}

/// Poll one serialized TDLib response and expose the current auth/chats snapshot.
#[no_mangle]
pub extern "C" fn driveflow_telegram_status() -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned".to_string())?;
        let s = guard.as_mut().ok_or_else(|| "tdlib_not_initialized".to_string())?;
        for _ in 0..32 {
            let Some(update) = s.bridge.receive(0.0).map_err(|e| e.to_string())? else { break };
            let kind = update.get("@type").and_then(Value::as_str).unwrap_or_default();
            if kind == "updateAuthorizationState" {
                if let Some(state) = update.pointer("/authorization_state/@type").and_then(Value::as_str) {
                    s.authorization_state = state.to_owned();
                    if state == "authorizationStateWaitTdlibParameters" && !s.parameters_sent {
                        s.bridge.set_parameters(s.api_id, &s.api_hash, &s.database_dir, &s.encryption_key).map_err(|e| e.to_string())?;
                        s.parameters_sent = true;
                    }
                    if state == "authorizationStateReady" && !s.chats_requested {
                        s.bridge.request_personal_chats(200).map_err(|e| e.to_string())?;
                        s.chats_requested = true;
                    }
                }
            } else if kind == "updateNewChat" {
                if let Some(chat) = update.get("chat") {
                    if chat.pointer("/type/@type").and_then(Value::as_str) == Some("chatTypePrivate") {
                        let id = chat.get("id").cloned().unwrap_or(Value::Null);
                        if !s.chats.iter().any(|c| c.get("id") == Some(&id)) { s.chats.push(chat.clone()); }
                    }
                }
            } else if kind == "updateChatTitle" {
                let id = update.get("chat_id");
                if let Some(chat) = s.chats.iter_mut().find(|c| c.get("id") == id) { chat["title"] = update.get("title").cloned().unwrap_or(Value::Null); }
            } else if kind == "error" {
                s.error = update.get("message").and_then(Value::as_str).map(str::to_owned);
            }
        }
        Ok(json!({"ok":true,"authorization_state":s.authorization_state,"error":s.error,"chats":s.chats}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

#[no_mangle]
pub extern "C" fn driveflow_telegram_chats() -> *mut c_char {
    let guard = session().lock().ok();
    let response = guard.and_then(|g| g.as_ref().map(|s| json!({"ok":true,"chats":s.chats})))
        .unwrap_or_else(|| json!({"ok":false,"error":"tdlib_not_initialized"}));
    into_c_string(response.to_string())
}

/// Release a string allocated by DriveFlow's C ABI.
///
/// # Safety
/// `value` must be a non-null pointer returned by one of this library's string
/// functions, and must be freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn driveflow_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: guaranteed by the caller contract above.
        drop(CString::from_raw(value));
    }
}

/// Validate that an input C string is UTF-8. Useful for consumers that want a
/// stable ABI check when wiring additional JSON request functions.
#[no_mangle]
pub unsafe extern "C" fn driveflow_validate_utf8(value: *const c_char) -> bool {
    if value.is_null() { return false; }
    // SAFETY: caller provides a NUL-terminated pointer for the duration of call.
    CStr::from_ptr(value).to_str().is_ok()
}
