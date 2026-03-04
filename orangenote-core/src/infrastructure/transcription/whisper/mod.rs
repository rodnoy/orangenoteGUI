//! Whisper.cpp transcription backend
//!
//! This module provides integration with whisper.cpp for audio transcription.
//! It includes FFI bindings, safe wrappers, model management, and high-level transcription APIs.
//!
//! # Feature Gate
//!
//! This module is only available when the `whisper` feature is enabled:
//!
//! ```toml
//! [features]
//! whisper = ["reqwest", "indicatif"]
//! ```

#[cfg(feature = "whisper")]
pub mod ffi;

#[cfg(feature = "whisper")]
pub mod context;

#[cfg(feature = "whisper")]
pub mod merger;

#[cfg(feature = "whisper")]
pub mod model_manager;

#[cfg(feature = "whisper")]
pub mod transcriber;

#[cfg(feature = "whisper")]
pub use context::{Segment, Token, TranscriptionResult, WhisperContextWrapper};

#[cfg(feature = "whisper")]
pub use merger::{merge_transcription_results, MergeConfig, MergeResult};

#[cfg(feature = "whisper")]
pub use model_manager::{ModelSize, ModelSource, WhisperModelManager};

#[cfg(feature = "whisper")]
pub use transcriber::WhisperTranscriber;
