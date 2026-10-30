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
    history_chat_id: Option<i64>,
    messages: Vec<Value>,
    files: Vec<Value>,
    my_user_id: Option<i64>,
    saved_messages_chat_id: Option<i64>,
    me_requested: bool,
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
            parameters_sent: false, chats_requested: false, authorization_state: "authorizationStateWaitTdlibParameters".into(), error: None, chats: Vec::new(), history_chat_id: None, messages: Vec::new(), files: Vec::new(), my_user_id: None, saved_messages_chat_id: None, me_requested: false });
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
pub unsafe extern "C" fn driveflow_telegram_send_file(chat_id: i64, path: *const c_char, caption: *const c_char) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        if path.is_null() || caption.is_null() { return Err("missing_argument".into()); }
        let path = CStr::from_ptr(path).to_str().map_err(|_| "invalid_path")?;
        let caption = CStr::from_ptr(caption).to_str().map_err(|_| "invalid_caption")?;
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned")?;
        let current = guard.as_mut().ok_or("telegram_not_started")?;
        current.bridge.send_file(chat_id, path, caption).map_err(|e| e.to_string())?;
        Ok(json!({"ok":true}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

#[no_mangle]
pub unsafe extern "C" fn driveflow_telegram_send_text(chat_id: i64, text: *const c_char) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        if text.is_null() { return Err("missing_argument".into()); }
        let text = CStr::from_ptr(text).to_str().map_err(|_| "invalid_text")?;
        let mut guard = SESSION.lock().map_err(|_| "session_lock_poisoned")?;
        let current = guard.as_mut().ok_or("telegram_not_started")?;
        current.bridge.send_text(chat_id, text).map_err(|e| e.to_string())?;
        Ok(json!({"ok":true}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}


#[no_mangle]
pub extern "C" fn driveflow_telegram_history(chat_id: i64, limit: i32) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned".to_string())?;
        let current = guard.as_mut().ok_or_else(|| "telegram_not_started".to_string())?;
        if current.history_chat_id != Some(chat_id) {
            current.bridge.request_chat_history(chat_id, limit).map_err(|e| e.to_string())?;
            current.history_chat_id = Some(chat_id);
            current.messages.clear();
        }
        Ok(json!({"ok":true,"messages":current.messages,"files":current.files}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

#[no_mangle]
pub extern "C" fn driveflow_telegram_download_file(file_id: i32) -> *mut c_char {
    let result = (|| -> Result<Value, String> {
        if file_id <= 0 { return Err("invalid_file_id".into()); }
        let mut guard = session().lock().map_err(|_| "session_lock_poisoned".to_string())?;
        let current = guard.as_mut().ok_or_else(|| "telegram_not_started".to_string())?;
        current.bridge.download_file(file_id).map_err(|e| e.to_string())?;
        Ok(json!({"ok":true}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
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
                    if state == "authorizationStateReady" && !s.me_requested {
                        s.bridge.request_me().map_err(|e| e.to_string())?;
                        s.me_requested = true;
                    }
                }
            } else if kind == "updateNewChat" {
                if let Some(chat) = update.get("chat") {
                    let private_user = chat.pointer("/type/user_id").and_then(Value::as_i64);
                    if chat.pointer("/type/@type").and_then(Value::as_str) == Some("chatTypePrivate") && private_user.is_some() && private_user == s.my_user_id {
                        let id = chat.get("id").cloned().unwrap_or(Value::Null);
                        s.saved_messages_chat_id = id.as_i64();
                        let mut saved_chat = chat.clone();
                        saved_chat["title"] = Value::String("Saved Messages".into());
                        saved_chat["is_saved_messages"] = Value::Bool(true);
                        if !s.chats.iter().any(|c| c.get("id") == Some(&id)) { s.chats.push(saved_chat); }
                    }
                }
            } else if kind == "user" && update.get("@extra").and_then(Value::as_str) == Some("driveflow_me") {
                if let Some(user_id) = update.get("id").and_then(Value::as_i64) {
                    s.my_user_id = Some(user_id);
                    s.bridge.request_saved_messages_chat(user_id).map_err(|e| e.to_string())?;
                }
            } else if kind == "chat" && update.get("@extra").and_then(Value::as_str) == Some("driveflow_saved_messages") {
                if update.pointer("/type/@type").and_then(Value::as_str) == Some("chatTypePrivate") && update.pointer("/type/user_id").and_then(Value::as_i64) == s.my_user_id {
                    let mut saved_chat = update.clone();
                    saved_chat["title"] = Value::String("Saved Messages".into());
                    saved_chat["is_saved_messages"] = Value::Bool(true);
                    let id = saved_chat.get("id").and_then(Value::as_i64);
                    s.saved_messages_chat_id = id;
                    if !s.chats.iter().any(|c| c.get("id").and_then(Value::as_i64) == id) { s.chats.push(saved_chat); }
                }
            } else if kind == "updateChatTitle" {
                let id = update.get("chat_id");
                if Some(id.and_then(Value::as_i64).unwrap_or_default()) != s.saved_messages_chat_id {
                    if let Some(chat) = s.chats.iter_mut().find(|c| c.get("id") == id) { chat["title"] = update.get("title").cloned().unwrap_or(Value::Null); }
                }
            } else if kind == "messages" && update.get("@extra").and_then(Value::as_str) == Some("driveflow_history") {
                s.messages = update.get("messages").and_then(Value::as_array).cloned().unwrap_or_default();
            } else if kind == "updateNewMessage" {
                if let Some(message) = update.get("message") {
                    if message.get("chat_id").and_then(Value::as_i64) == s.history_chat_id {
                        let id = message.get("id").cloned();
                        s.messages.retain(|item| item.get("id") != id.as_ref());
                        s.messages.push(message.clone());
                        s.messages.sort_by(|left, right| right.get("id").and_then(Value::as_i64).cmp(&left.get("id").and_then(Value::as_i64)));
                        s.messages.truncate(100);
                    }
                }
            } else if kind == "updateFile" {
                if let Some(file) = update.get("file") {
                    if let Some(id) = file.get("id") {
                        if let Some(existing) = s.files.iter_mut().find(|item| item.get("id") == Some(id)) { *existing = file.clone(); }
                        else { s.files.push(file.clone()); }
                        for message in &mut s.messages {
                            if message.pointer("/content/document/document/file/id") == Some(id) {
                                if let Some(slot) = message.pointer_mut("/content/document/document/file") { *slot = file.clone(); }
                            }
                        }
                    }
                }
            } else if kind == "error" {
                s.error = update.get("message").and_then(Value::as_str).map(str::to_owned);
            }
        }
        Ok(json!({"ok":true,"authorization_state":s.authorization_state,"error":s.error,"chats":s.chats,"messages":s.messages,"files":s.files}))
    })();
    into_c_string(result.unwrap_or_else(|e| json!({"ok":false,"error":e})).to_string())
}

#[no_mangle]
pub extern "C" fn driveflow_telegram_chats() -> *mut c_char {
    let guard = session().lock().ok();
    let response = guard.and_then(|g| g.as_ref().map(|s| json!({"ok":true,"chats":s.chats.iter().filter(|c| c.get("id").and_then(Value::as_i64) == s.saved_messages_chat_id).collect::<Vec<_>>()})))
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
