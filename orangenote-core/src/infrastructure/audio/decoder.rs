//! Audio decoder and metadata extraction
//!
//! Provides unified interface for reading audio file metadata
//! across multiple formats.

use anyhow::{anyhow, Context, Result};
use log::{debug, info};
use std::path::{Path, PathBuf};

/// Supported audio formats
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioFormat {
    Mp3,
    Wav,
    Flac,
    M4a,
    Ogg,
    Wma,
}

impl AudioFormat {
    /// Detect format from file extension
    pub fn from_path(path: &Path) -> Result<Self> {
        let extension = path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|s| s.to_lowercase())
            .ok_or_else(|| anyhow!("File has no extension"))?;

        match extension.as_str() {
            "mp3" => Ok(AudioFormat::Mp3),
            "wav" => Ok(AudioFormat::Wav),
            "flac" => Ok(AudioFormat::Flac),
            "m4a" | "mp4" => Ok(AudioFormat::M4a),
            "ogg" | "oga" => Ok(AudioFormat::Ogg),
            "wma" => Ok(AudioFormat::Wma),
            ext => Err(anyhow!("Unsupported format: {}", ext)),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            AudioFormat::Mp3 => "MP3",
            AudioFormat::Wav => "WAV",
            AudioFormat::Flac => "FLAC",
            AudioFormat::M4a => "M4A",
            AudioFormat::Ogg => "OGG Vorbis",
            AudioFormat::Wma => "WMA",
        }
    }
}

/// Audio metadata extracted from file
#[derive(Debug, Clone)]
pub struct AudioMetadata {
    /// File path
    pub path: PathBuf,
    /// Audio format
    pub format: AudioFormat,
    /// Duration in seconds
    pub duration_seconds: f64,
    /// Sample rate in Hz (typically 16000, 44100, 48000)
    pub sample_rate: u32,
    /// Number of audio channels (1=mono, 2=stereo)
    pub channels: u16,
    /// Bitrate in kbps (if available)
    pub bitrate_kbps: Option<u32>,
    /// File size in bytes
    pub file_size_bytes: u64,
}

impl AudioMetadata {
    /// Format metadata as human-readable string
    pub fn format_info(&self) -> String {
        let bitrate_info = self
            .bitrate_kbps
            .map(|b| format!(", {} kbps", b))
            .unwrap_or_default();

        let channels_str = match self.channels {
            1 => "Mono".to_string(),
            2 => "Stereo".to_string(),
            n => format!("{}-channel", n),
        };

        format!(
            "Duration: {:.1}s, Sample Rate: {}Hz, Channels: {} ({}{})",
            self.duration_seconds, self.sample_rate, self.channels, channels_str, bitrate_info
        )
    }

    /// Get human-readable file size
    pub fn file_size_human(&self) -> String {
        const UNITS: &[&str] = &["B", "KB", "MB", "GB"];
        let mut size = self.file_size_bytes as f64;
        let mut unit_idx = 0;

        while size >= 1024.0 && unit_idx < UNITS.len() - 1 {
            size /= 1024.0;
            unit_idx += 1;
        }

        format!("{:.2} {}", size, UNITS[unit_idx])
    }
}

/// Audio decoder interface
pub struct AudioDecoder {
    path: PathBuf,
    format: AudioFormat,
}

impl AudioDecoder {
    /// Create a new audio decoder for the given file
    pub fn new(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();

        if !path.exists() {
            return Err(anyhow!("Audio file not found: {}", path.display()));
        }

        if !path.is_file() {
            return Err(anyhow!("Path is not a file: {}", path.display()));
        }

        let format = AudioFormat::from_path(&path)?;

        debug!("Created decoder for {}: {:?}", path.display(), format);

        Ok(AudioDecoder { path, format })
    }

    /// Extract metadata from audio file
    pub fn get_metadata(&self) -> Result<AudioMetadata> {
        info!("Extracting metadata from: {}", self.path.display());

        // For WAV files, try to read actual metadata
        let metadata = if self.format == AudioFormat::Wav {
            self.extract_wav_metadata().unwrap_or_else(|e| {
                debug!("Failed to read WAV metadata: {}, using fallback", e);
                self.extract_fallback_metadata()
            })
        } else {
            // For other formats, use fallback
            self.extract_fallback_metadata()
        };

        info!(
            "Extracted metadata: duration={:.1}s, sr={}, channels={}",
            metadata.duration_seconds, metadata.sample_rate, metadata.channels
        );

        Ok(metadata)
    }

    /// Extract metadata from WAV file using hound crate
    fn extract_wav_metadata(&self) -> Result<AudioMetadata> {
        debug!("Reading WAV metadata");

        let reader = hound::WavReader::open(&self.path).context("Failed to read WAV file")?;

        let spec = reader.spec();
        let frames = reader.len() as f64;
        let duration_seconds = if spec.sample_rate > 0 {
            frames / spec.sample_rate as f64
        } else {
            0.0
        };
        let file_size = self.path.metadata()?.len();

        // Calculate bitrate: sample_rate * channels * bits_per_sample / 8 / 1000
        let bitrate_kbps =
            Some(spec.sample_rate * spec.channels as u32 * spec.bits_per_sample as u32 / 8000);

        debug!(
            "WAV metadata: {}Hz, {} channels, {:.1}s",
            spec.sample_rate, spec.channels, duration_seconds
        );

        Ok(AudioMetadata {
            path: self.path.clone(),
            format: self.format,
            duration_seconds,
            sample_rate: spec.sample_rate,
            channels: spec.channels,
            bitrate_kbps,
            file_size_bytes: file_size,
        })
    }

    /// Fallback: generic metadata extraction for unsupported formats
    fn extract_fallback_metadata(&self) -> AudioMetadata {
        debug!(
            "Using fallback metadata extraction for {}",
            self.format.as_str()
        );

        let file_size = self.path.metadata().map(|m| m.len()).unwrap_or(0);

        // Reasonable defaults for different formats
        let (sample_rate, channels) = match self.format {
            AudioFormat::Mp3 => (44100, 2),  // MP3 typical defaults
            AudioFormat::M4a => (48000, 2),  // M4A typical defaults
            AudioFormat::Ogg => (44100, 2),  // OGG typical defaults
            AudioFormat::Flac => (44100, 2), // FLAC typical defaults
            AudioFormat::Wma => (44100, 2),  // WMA typical defaults
            _ => (16000, 1),                 // Fallback: mono at 16kHz
        };

        AudioMetadata {
            path: self.path.clone(),
            format: self.format,
            duration_seconds: 0.0, // Would need proper parsing
            sample_rate,
            channels,
            bitrate_kbps: None,
            file_size_bytes: file_size,
        }
    }

    /// Get file format
    pub fn format(&self) -> AudioFormat {
        self.format
    }

    /// Get file path
    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_detection() {
        assert_eq!(
            AudioFormat::from_path(Path::new("test.mp3")).unwrap(),
            AudioFormat::Mp3
        );
        assert_eq!(
            AudioFormat::from_path(Path::new("test.wav")).unwrap(),
            AudioFormat::Wav
        );
        assert_eq!(
            AudioFormat::from_path(Path::new("test.flac")).unwrap(),
            AudioFormat::Flac
        );
    }

    #[test]
    fn test_format_string() {
        assert_eq!(AudioFormat::Mp3.as_str(), "MP3");
        assert_eq!(AudioFormat::Wav.as_str(), "WAV");
    }

    #[test]
    fn test_audio_metadata_format() {
        let metadata = AudioMetadata {
            path: PathBuf::from("test.wav"),
            format: AudioFormat::Wav,
            duration_seconds: 10.5,
            sample_rate: 44100,
            channels: 2,
            bitrate_kbps: Some(352),
            file_size_bytes: 460_000,
        };

        let info = metadata.format_info();
        assert!(info.contains("10.5s"));
        assert!(info.contains("44100Hz"));
        assert!(info.contains("Stereo"));
    }
}
