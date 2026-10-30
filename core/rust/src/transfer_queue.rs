use serde::{Deserialize, Serialize};
use std::sync::{atomic::{AtomicU64, Ordering}, Mutex};
use thiserror::Error;

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferState { Pending, Uploading, Paused, Retry, Completed, Failed, Cancelled }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transfer {
    pub id: u64,
    pub path: String,
    pub chat_id: i64,
    pub bytes_total: u64,
    pub bytes_sent: u64,
    pub attempts: u32,
    pub state: TransferState,
    pub error: Option<String>,
}

#[derive(Debug, Error)]
pub enum QueueError {
    #[error("transfer {0} was not found")]
    NotFound(u64),
    #[error("cannot {action} transfer in state {state:?}")]
    InvalidTransition { action: &'static str, state: TransferState },
    #[error("transfer queue lock was poisoned")]
    LockPoisoned,
}

#[derive(Default)]
pub struct TransferQueue { items: Mutex<Vec<Transfer>> }

impl TransferQueue {
    pub fn enqueue(&self, path: String, chat_id: i64, bytes_total: u64) -> Result<Transfer, QueueError> {
        let transfer = Transfer { id: NEXT_ID.fetch_add(1, Ordering::Relaxed), path, chat_id, bytes_total, bytes_sent: 0, attempts: 0, state: TransferState::Pending, error: None };
        self.items.lock().map_err(|_| QueueError::LockPoisoned)?.push(transfer.clone());
        Ok(transfer)
    }

    pub fn snapshot(&self) -> Result<Vec<Transfer>, QueueError> { Ok(self.items.lock().map_err(|_| QueueError::LockPoisoned)?.clone()) }

    pub fn pause(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "pause", |item| match item.state {
            TransferState::Pending | TransferState::Uploading | TransferState::Retry => { item.state = TransferState::Paused; Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "pause", state: item.state }),
        })
    }

    pub fn resume(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "resume", |item| match item.state {
            TransferState::Paused | TransferState::Retry => { item.state = TransferState::Pending; item.error = None; Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "resume", state: item.state }),
        })
    }

    pub fn retry(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "retry", |item| match item.state {
            TransferState::Failed | TransferState::Retry => { item.attempts += 1; item.state = TransferState::Pending; item.error = None; Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "retry", state: item.state }),
        })
    }

    pub fn start(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "start", |item| match item.state {
            TransferState::Pending => { item.state = TransferState::Uploading; item.attempts += 1; Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "start", state: item.state }),
        })
    }

    pub fn record_progress(&self, id: u64, bytes_sent: u64) -> Result<(), QueueError> {
        self.update(id, "record progress", |item| {
            if item.state != TransferState::Uploading { return Err(QueueError::InvalidTransition { action: "record progress", state: item.state }); }
            item.bytes_sent = bytes_sent.min(item.bytes_total);
            Ok(())
        })
    }

    pub fn complete(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "complete", |item| match item.state {
            TransferState::Uploading => { item.state = TransferState::Completed; item.bytes_sent = item.bytes_total; Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "complete", state: item.state }),
        })
    }

    pub fn fail(&self, id: u64, message: String, retryable: bool) -> Result<(), QueueError> {
        self.update(id, "fail", |item| match item.state {
            TransferState::Uploading => { item.state = if retryable { TransferState::Retry } else { TransferState::Failed }; item.error = Some(message); Ok(()) },
            _ => Err(QueueError::InvalidTransition { action: "fail", state: item.state }),
        })
    }

    pub fn cancel(&self, id: u64) -> Result<(), QueueError> {
        self.update(id, "cancel", |item| match item.state {
            TransferState::Completed | TransferState::Cancelled => Err(QueueError::InvalidTransition { action: "cancel", state: item.state }),
            _ => { item.state = TransferState::Cancelled; Ok(()) },
        })
    }

    fn update(&self, id: u64, _action: &'static str, f: impl FnOnce(&mut Transfer) -> Result<(), QueueError>) -> Result<(), QueueError> {
        let mut items = self.items.lock().map_err(|_| QueueError::LockPoisoned)?;
        let item = items.iter_mut().find(|item| item.id == id).ok_or(QueueError::NotFound(id))?;
        f(item)
    }
}
