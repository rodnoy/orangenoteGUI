//! Audio processing module
//!
//! Handles audio file reading, metadata extraction, format detection,
//! and audio processing (decoding, resampling, PCM conversion).
//! Supports MP3, WAV, FLAC, M4A, OGG formats.

pub mod chunk;
pub mod decoder;
pub mod processor;

pub use chunk::{AudioChunk, ChunkConfig};
pub use decoder::{AudioDecoder, AudioFormat, AudioMetadata};
pub use processor::{AudioProcessor, AudioSamples, WHISPER_SAMPLE_RATE};
