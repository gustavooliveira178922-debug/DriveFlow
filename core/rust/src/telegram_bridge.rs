use libloading::Library;
use serde_json::{json, Value};
use std::{ffi::{c_char, c_void, CStr, CString}, ptr};
use thiserror::Error;

type CreateClient = unsafe extern "C" fn() -> *mut c_void;
type SendRequest = unsafe extern "C" fn(*mut c_void, *const c_char);
type ReceiveResponse = unsafe extern "C" fn(*mut c_void, f64) -> *const c_char;
type DestroyClient = unsafe extern "C" fn(*mut c_void);

#[derive(Debug, Error)]
pub enum TelegramError {
    #[error("TDLib native library is not installed or could not be loaded: {0}")]
    Library(String),
    #[error("TDLib symbol is missing: {0}")]
    Symbol(&'static str),
    #[error("failed to create a TDLib client")]
    CreateClient,
    #[error("request contains an invalid NUL byte")]
    InvalidRequest,
    #[error("TDLib returned invalid UTF-8")]
    InvalidResponse,
}

/// A single TDLib JSON client. Keep one instance per Telegram account and feed
/// its updates through a serialized receive loop; TDLib requires updates to be
/// handled in arrival order.
pub struct TelegramBridge {
    _library: Library,
    client: *mut c_void,
    send: SendRequest,
    receive: ReceiveResponse,
    destroy: DestroyClient,
}

impl TelegramBridge {
    pub fn load() -> Result<Self, TelegramError> {
        let library = load_tdlib_library()?;
        // SAFETY: symbol names and signatures are defined by TDLib's JSON C ABI.
        unsafe {
            let create: CreateClient = *library.get(b"td_json_client_create\0").map_err(|_| TelegramError::Symbol("td_json_client_create"))?;
            let send: SendRequest = *library.get(b"td_json_client_send\0").map_err(|_| TelegramError::Symbol("td_json_client_send"))?;
            let receive: ReceiveResponse = *library.get(b"td_json_client_receive\0").map_err(|_| TelegramError::Symbol("td_json_client_receive"))?;
            let destroy: DestroyClient = *library.get(b"td_json_client_destroy\0").map_err(|_| TelegramError::Symbol("td_json_client_destroy"))?;
            let client = create();
            if client.is_null() { return Err(TelegramError::CreateClient); }
            Ok(Self { _library: library, client, send, receive, destroy })
        }
    }

    pub fn send_request(&self, request: &Value) -> Result<(), TelegramError> {
        let serialized = CString::new(request.to_string()).map_err(|_| TelegramError::InvalidRequest)?;
        // SAFETY: client is owned by this instance and serialized is NUL-terminated for this call.
        unsafe { (self.send)(self.client, serialized.as_ptr()); }
        Ok(())
    }

    /// Wait for one update/response. A zero timeout is a poll. The caller must
    /// preserve receive ordering when processing events.
    pub fn receive(&self, timeout_seconds: f64) -> Result<Option<Value>, TelegramError> {
        // SAFETY: client is live and TDLib returns either null or a transient C string.
        let response = unsafe { (self.receive)(self.client, timeout_seconds.max(0.0)) };
        if response.is_null() { return Ok(None); }
        // SAFETY: TDLib promises a NUL-terminated UTF-8 JSON string until the next receive.
        let string = unsafe { CStr::from_ptr(response) }.to_str().map_err(|_| TelegramError::InvalidResponse)?;
        Ok(serde_json::from_str(string).ok())
    }

    pub fn set_parameters(&self, api_id: i32, api_hash: &str, database_dir: &str, encryption_key: &str) -> Result<(), TelegramError> {
        self.send_request(&json!({
            "@type": "setTdlibParameters", "use_test_dc": false,
            "database_directory": database_dir, "files_directory": format!("{database_dir}/files"),
            "database_encryption_key": encryption_key,
            "use_file_database": true, "use_chat_info_database": true,
            "use_message_database": true, "use_secret_chats": false,
            "api_id": api_id, "api_hash": api_hash, "system_language_code": "en",
            "device_model": "DriveFlow", "application_version": env!("CARGO_PKG_VERSION"), "enable_storage_optimizer": true
        }))
    }

    pub fn submit_phone_number(&self, phone: &str) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "setAuthenticationPhoneNumber", "phone_number": phone }))
    }

    pub fn submit_code(&self, code: &str) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "checkAuthenticationCode", "code": code }))
    }

    pub fn submit_password(&self, password: &str) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "checkAuthenticationPassword", "password": password }))
    }

    pub fn request_personal_chats(&self, limit: i32) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "loadChats", "chat_list": { "@type": "chatListMain" }, "limit": limit.clamp(1, 1000) }))
    }

    pub fn request_chat(&self, chat_id: i64) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "getChat", "chat_id": chat_id }))
    }

    pub fn send_file(&self, chat_id: i64, path: &str, caption: &str) -> Result<(), TelegramError> {
        self.send_request(&json!({
            "@type": "sendMessage", "chat_id": chat_id,
            "input_message_content": {
                "@type": "inputMessageDocument", "document": { "@type": "inputFileLocal", "path": path },
                "caption": { "@type": "formattedText", "text": caption, "entities": [] },
                "disable_content_type_detection": false
            }
        }))
    }

    pub fn close(&self) -> Result<(), TelegramError> {
        self.send_request(&json!({ "@type": "close" }))
    }
}

impl Drop for TelegramBridge {
    fn drop(&mut self) {
        if !self.client.is_null() {
            // SAFETY: client is owned by this bridge and destroyed exactly once.
            unsafe { (self.destroy)(self.client); }
            self.client = ptr::null_mut();
        }
    }
}

fn load_tdlib_library() -> Result<Library, TelegramError> {
    let candidates: &[&str] = if cfg!(target_os = "windows") { &["tdjson.dll", "libtdjson.dll"] }
        else if cfg!(target_os = "macos") { &["libtdjson.dylib", "tdjson"] }
        else { &["libtdjson.so", "tdjson"] };
    for name in candidates {
        // SAFETY: loading a library is unsafe; symbols are checked before use and its
        // handle is retained as long as any function pointer may be called.
        if let Ok(library) = unsafe { Library::new(name) } { return Ok(library); }
    }
    Err(TelegramError::Library(candidates.join(", ")))
}
