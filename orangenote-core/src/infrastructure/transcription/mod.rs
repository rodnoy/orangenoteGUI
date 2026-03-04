//! Transcription backend module
//!
//! This module contains implementations for different transcription backends.
//! Currently supports whisper.cpp via the whisper-rs crate.

#[cfg(feature = "whisper")]
pub mod whisper;

#[cfg(feature = "whisper")]
pub use whisper::{
    ModelSize, ModelSource, Segment, Token, TranscriptionResult, WhisperContextWrapper,
    WhisperModelManager, WhisperTranscriber,
};
