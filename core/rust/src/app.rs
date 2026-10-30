use crate::TransferQueue;

/// Application-wide native services. UI bindings should hold one instance and
/// expose queue snapshots as streams over the chosen Flutter/Rust bridge.
#[derive(Default)]
pub struct AppCore {
    pub transfers: TransferQueue,
}

impl AppCore {
    pub fn new() -> Self { Self::default() }
}
