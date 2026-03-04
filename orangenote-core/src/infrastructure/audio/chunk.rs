//! Audio chunking support
//!
//! This module provides structures for splitting audio into chunks
//! for processing long audio files in smaller pieces.

/// Represents a chunk of audio with position metadata
#[derive(Debug, Clone)]
pub struct AudioChunk {
    /// PCM samples for this chunk
    pub samples: Vec<f32>,
    /// Chunk index (0-based)
    pub index: usize,
    /// Start time offset in milliseconds from original audio
    pub start_offset_ms: i64,
    /// Duration of this chunk in milliseconds
    pub duration_ms: i64,
    /// Whether this is the last chunk
    pub is_last: bool,
}

/// Configuration for audio chunking
#[derive(Debug, Clone)]
pub struct ChunkConfig {
    /// Duration of each chunk in seconds
    pub chunk_duration_secs: u32,
    /// Overlap between chunks in seconds (for better continuity)
    pub overlap_secs: u32,
}

impl Default for ChunkConfig {
    fn default() -> Self {
        ChunkConfig {
            chunk_duration_secs: 300, // 5 minutes
            overlap_secs: 5,          // 5 seconds overlap
        }
    }
}

impl ChunkConfig {
    /// Create a new chunk config with specified duration and overlap
    pub fn new(chunk_duration_secs: u32, overlap_secs: u32) -> Self {
        ChunkConfig {
            chunk_duration_secs,
            overlap_secs,
        }
    }

    /// Create a config from chunk size in minutes
    pub fn from_minutes(minutes: u32, overlap_secs: u32) -> Self {
        ChunkConfig {
            chunk_duration_secs: minutes * 60,
            overlap_secs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_config_default() {
        let config = ChunkConfig::default();
        assert_eq!(config.chunk_duration_secs, 300);
        assert_eq!(config.overlap_secs, 5);
    }

    #[test]
    fn test_chunk_config_from_minutes() {
        let config = ChunkConfig::from_minutes(10, 10);
        assert_eq!(config.chunk_duration_secs, 600);
        assert_eq!(config.overlap_secs, 10);
    }
}
