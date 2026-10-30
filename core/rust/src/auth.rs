use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum AuthState {
    NeedsTdlibParameters,
    WaitingForPhone,
    WaitingForCode,
    WaitingForPassword,
    Ready,
    Closing,
    Closed,
    Error { message: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthUpdate {
    pub state: AuthState,
    pub detail: Option<String>,
}

impl AuthUpdate {
    pub fn from_tdlib_state(state: &str) -> Self {
        let mapped = match state {
            "authorizationStateWaitTdlibParameters" => AuthState::NeedsTdlibParameters,
            "authorizationStateWaitPhoneNumber" => AuthState::WaitingForPhone,
            "authorizationStateWaitCode" => AuthState::WaitingForCode,
            "authorizationStateWaitPassword" => AuthState::WaitingForPassword,
            "authorizationStateReady" => AuthState::Ready,
            "authorizationStateClosing" => AuthState::Closing,
            "authorizationStateClosed" => AuthState::Closed,
            other => AuthState::Error { message: format!("Unhandled TDLib authorization state: {other}") },
        };
        Self { state: mapped, detail: None }
    }
}
