//! DriveFlow native core. TDLib is loaded at runtime to keep local core builds
//! independent of per-platform TDLib compilation and linking.

mod app;
mod auth;
mod storage;
mod telegram_bridge;
mod transfer_queue;

use std::ffi::{c_char, CStr, CString};

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

/// A truthful status response until the app has configured TDLib.
#[no_mangle]
pub extern "C" fn driveflow_telegram_status() -> *mut c_char {
    into_c_string(r#"{"ok":false,"error":"tdlib_not_initialized"}"#.to_owned())
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
