//! OrangeNote Core Library
//!
//! Core library for audio transcription using whisper.cpp.
//! Provides audio decoding, metadata extraction, and transcription pipeline.

pub mod infrastructure;

pub use infrastructure::audio::{
    AudioChunk, AudioDecoder, AudioFormat, AudioMetadata, AudioProcessor, AudioSamples,
    ChunkConfig, WHISPER_SAMPLE_RATE,
};

#[cfg(feature = "whisper")]
pub use infrastructure::{
    ModelSize, ModelSource, Segment, Token, TranscriptionResult, WhisperContextWrapper,
    WhisperModelManager, WhisperTranscriber,
};

/// Library version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Represents the result of operations in this library
pub type Result<T> = std::result::Result<T, anyhow::Error>;
