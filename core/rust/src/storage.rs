use chacha20poly1305::{aead::{Aead, KeyInit}, ChaCha20Poly1305, Nonce};
use rand::{rngs::OsRng, RngCore};
use std::{fs, io::{Read, Write}, path::{Path, PathBuf}};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("metadata I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("metadata encryption or authentication failed")]
    Crypto,
    #[error("metadata is too short or has an unsupported format")]
    InvalidFormat,
}

/// Encrypted local JSON metadata. The 32-byte key must come from the OS secure
/// storage adapter; it is never generated or persisted by this type.
pub struct MetadataStore { path: PathBuf, key: [u8; 32] }

impl MetadataStore {
    pub fn new(path: impl Into<PathBuf>, key_from_secure_storage: [u8; 32]) -> Self {
        Self { path: path.into(), key: key_from_secure_storage }
    }

    pub fn write_json(&self, json: &[u8]) -> Result<(), StorageError> {
        let cipher = ChaCha20Poly1305::new_from_slice(&self.key).map_err(|_| StorageError::Crypto)?;
        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let ciphertext = cipher.encrypt(Nonce::from_slice(&nonce_bytes), json).map_err(|_| StorageError::Crypto)?;
        let mut encoded = Vec::with_capacity(4 + nonce_bytes.len() + ciphertext.len());
        encoded.extend_from_slice(b"DFM1");
        encoded.extend_from_slice(&nonce_bytes);
        encoded.extend_from_slice(&ciphertext);
        self.atomic_write(&encoded)
    }

    pub fn read_json(&self) -> Result<Option<Vec<u8>>, StorageError> {
        if !self.path.exists() { return Ok(None); }
        let mut encoded = Vec::new();
        fs::File::open(&self.path)?.read_to_end(&mut encoded)?;
        if encoded.len() < 4 + 12 + 16 || &encoded[..4] != b"DFM1" { return Err(StorageError::InvalidFormat); }
        let nonce = Nonce::from_slice(&encoded[4..16]);
        let cipher = ChaCha20Poly1305::new_from_slice(&self.key).map_err(|_| StorageError::Crypto)?;
        cipher.decrypt(nonce, &encoded[16..]).map(Some).map_err(|_| StorageError::Crypto)
    }

    fn atomic_write(&self, bytes: &[u8]) -> Result<(), StorageError> {
        if let Some(parent) = self.path.parent() { fs::create_dir_all(parent)?; }
        let temporary = self.path.with_extension("tmp");
        {
            let mut file = fs::File::create(&temporary)?;
            file.write_all(bytes)?;
            file.sync_all()?;
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
        }
        replace_file(&temporary, &self.path)
    }
}

fn replace_file(source: &Path, destination: &Path) -> Result<(), StorageError> {
    #[cfg(windows)]
    if destination.exists() { fs::remove_file(destination)?; }
    fs::rename(source, destination)?;
    Ok(())
}
