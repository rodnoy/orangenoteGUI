//! Audio processor for PCM conversion and resampling
//!
//! Handles converting audio files to PCM samples at 16kHz mono format
//! required by whisper.cpp. Supports MP3, WAV, FLAC, M4A, OGG formats.

use anyhow::{anyhow, Context, Result};
use log::{debug, info};

use std::path::Path;
use symphonia::core::audio::Signal;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::probe::Hint;

use super::chunk::{AudioChunk, ChunkConfig};

/// Target sample rate for whisper.cpp (16kHz)
pub const WHISPER_SAMPLE_RATE: u32 = 16000;

/// Audio samples container - stores mono PCM samples at 16kHz
#[derive(Debug, Clone)]
pub struct AudioSamples {
    /// PCM samples as f32 (normalized to -1.0..1.0)
    pub samples: Vec<f32>,
    /// Original sample rate before resampling
    pub original_sample_rate: u32,
    /// Original number of channels
    pub original_channels: u16,
    /// Duration in seconds
    pub duration_seconds: f64,
}

impl AudioSamples {
    /// Get duration in samples
    pub fn len(&self) -> usize {
        self.samples.len()
    }

    /// Check if samples are empty
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Get duration in milliseconds
    pub fn duration_ms(&self) -> i64 {
        (self.duration_seconds * 1000.0) as i64
    }

    /// Split audio samples into chunks according to configuration
    ///
    /// # Arguments
    ///
    /// * `config` - Chunking configuration (chunk duration, overlap)
    ///
    /// # Returns
    ///
    /// Vector of `AudioChunk` with samples and position metadata
    ///
    /// # Example
    ///
    /// ```ignore
    /// let samples = AudioProcessor::process("audio.mp3")?;
    /// let config = ChunkConfig {
    ///     chunk_duration_secs: 300, // 5 minutes
    ///     overlap_secs: 5,          // 5 seconds overlap
    /// };
    /// let chunks = samples.split_into_chunks(&config);
    /// for chunk in chunks {
    ///     println!("Chunk {}: {} samples, starts at {}ms",
    ///         chunk.index, chunk.samples.len(), chunk.start_offset_ms);
    /// }
    /// ```
    pub fn split_into_chunks(&self, config: &ChunkConfig) -> Vec<AudioChunk> {
        let total_samples = self.samples.len();

        if total_samples == 0 {
            return Vec::new();
        }

        // Calculate sizes in samples
        let samples_per_second = WHISPER_SAMPLE_RATE as usize;
        let chunk_samples = config.chunk_duration_secs as usize * samples_per_second;
        let overlap_samples = config.overlap_secs as usize * samples_per_second;

        // Step size = chunk size - overlap
        let step_samples = if chunk_samples > overlap_samples {
            chunk_samples - overlap_samples
        } else {
            chunk_samples // No overlap if misconfigured
        };

        // If audio is shorter than one chunk, return single chunk
        if total_samples <= chunk_samples {
            let duration_ms = (total_samples as f64 / samples_per_second as f64 * 1000.0) as i64;
            return vec![AudioChunk {
                samples: self.samples.clone(),
                index: 0,
                start_offset_ms: 0,
                duration_ms,
                is_last: true,
            }];
        }

        let mut chunks = Vec::new();
        let mut start_sample = 0usize;
        let mut chunk_index = 0usize;

        while start_sample < total_samples {
            let end_sample = (start_sample + chunk_samples).min(total_samples);
            let chunk_data = self.samples[start_sample..end_sample].to_vec();

            let start_offset_ms = (start_sample as f64 / samples_per_second as f64 * 1000.0) as i64;
            let duration_ms = (chunk_data.len() as f64 / samples_per_second as f64 * 1000.0) as i64;
            let is_last = end_sample >= total_samples;

            debug!(
                "Chunk {}: samples {}..{} ({} samples), offset {}ms, duration {}ms, is_last={}",
                chunk_index,
                start_sample,
                end_sample,
                chunk_data.len(),
                start_offset_ms,
                duration_ms,
                is_last
            );

            chunks.push(AudioChunk {
                samples: chunk_data,
                index: chunk_index,
                start_offset_ms,
                duration_ms,
                is_last,
            });

            if is_last {
                break;
            }

            start_sample += step_samples;
            chunk_index += 1;
        }

        info!(
            "Split {} samples ({:.1}s) into {} chunks ({}s each, {}s overlap)",
            total_samples,
            self.duration_seconds,
            chunks.len(),
            config.chunk_duration_secs,
            config.overlap_secs
        );

        chunks
    }
}

/// Audio processor for decoding and resampling
pub struct AudioProcessor;

impl AudioProcessor {
    /// Process an audio file and return PCM samples at 16kHz mono
    ///
    /// # Arguments
    ///
    /// * `path` - Path to the audio file
    ///
    /// # Returns
    ///
    /// `AudioSamples` containing normalized PCM samples at 16kHz mono
    pub fn process<P: AsRef<Path>>(path: P) -> Result<AudioSamples> {
        let path = path.as_ref();
        info!("Processing audio file: {}", path.display());

        let file = std::fs::File::open(path).context("Failed to open audio file")?;

        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        // Create a probe to detect the format
        let mut hint = Hint::new();
        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            hint.with_extension(ext);
        }

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &FormatOptions::default(), &Default::default())
            .context("Failed to probe audio format")?;

        let mut format = probed.format;

        info!("Format detected");

        // Get track information
        let track = format
            .default_track()
            .ok_or_else(|| anyhow!("No audio track found in file"))?;

        let codec_params = &track.codec_params;
        let original_sample_rate = codec_params
            .sample_rate
            .ok_or_else(|| anyhow!("Sample rate unknown"))?;

        // Channel count may be unknown for some M4A files - we'll detect from first packet
        let channels_from_params = codec_params.channels.map(|c| c.count() as u16);

        let duration_frames = codec_params.n_frames.unwrap_or(0);
        let original_duration_seconds = if original_sample_rate > 0 {
            duration_frames as f64 / original_sample_rate as f64
        } else {
            0.0
        };

        debug!(
            "Audio info: {}Hz, channels={:?}, {:.1}s",
            original_sample_rate, channels_from_params, original_duration_seconds
        );

        // Create decoder
        let decoder = symphonia::default::get_codecs()
            .make(codec_params, &DecoderOptions::default())
            .context("Failed to create decoder")?;

        // Decode all samples
        let mut all_samples = Vec::new();
        let mut decoder = decoder;
        let mut detected_channels: Option<u16> = channels_from_params;

        loop {
            match format.next_packet() {
                Ok(packet) => match decoder.decode(&packet) {
                    Ok(decoded) => {
                        let spec = decoded.spec();
                        let channels_in_spec = spec.channels.count();

                        // Detect channels from first decoded packet if not known
                        if detected_channels.is_none() {
                            detected_channels = Some(channels_in_spec as u16);
                            info!("Detected {} channels from decoded audio", channels_in_spec);
                        }

                        debug!(
                            "Packet decoded: {} frames, {} channels in spec",
                            decoded.frames(),
                            channels_in_spec
                        );

                        match decoded {
                            symphonia::core::audio::AudioBufferRef::F32(buf) => {
                                Self::extract_f32_samples(&buf, channels_in_spec, &mut all_samples);
                            }
                            symphonia::core::audio::AudioBufferRef::S16(buf) => {
                                Self::extract_s16_samples(&buf, channels_in_spec, &mut all_samples);
                            }
                            symphonia::core::audio::AudioBufferRef::U8(buf) => {
                                Self::extract_u8_samples(&buf, channels_in_spec, &mut all_samples);
                            }
                            _ => {
                                debug!("Unsupported sample format, skipping");
                            }
                        }
                    }
                    Err(e) => {
                        debug!("Decode error: {}", e);
                    }
                },
                Err(symphonia::core::errors::Error::IoError(_)) => {
                    break;
                }
                Err(e) => {
                    debug!("Format error: {}", e);
                    break;
                }
            }
        }

        if all_samples.is_empty() {
            return Err(anyhow!("No audio samples decoded"));
        }

        let channels = detected_channels.unwrap_or(2); // Default to stereo if still unknown

        info!(
            "Decoded {} samples from {} channels at {}Hz",
            all_samples.len(),
            channels,
            original_sample_rate
        );

        // Debug: Check sample range
        if !all_samples.is_empty() {
            let min_val = all_samples.iter().cloned().fold(f32::INFINITY, f32::min);
            let max_val = all_samples
                .iter()
                .cloned()
                .fold(f32::NEG_INFINITY, f32::max);
            let sum: f32 = all_samples.iter().sum();
            let mean = sum / all_samples.len() as f32;
            let rms =
                (all_samples.iter().map(|x| x * x).sum::<f32>() / all_samples.len() as f32).sqrt();
            info!(
                "Sample stats: min={:.4}, max={:.4}, mean={:.4}, rms={:.4}",
                min_val, max_val, mean, rms
            );

            // Warn if samples are outside expected range or very quiet
            if min_val < -1.0 || max_val > 1.0 {
                info!("WARNING: Samples outside normalized range [-1.0, 1.0]");
            }
            if rms < 0.001 {
                info!("WARNING: Audio appears to be very quiet (RMS < 0.001)");
            }
        }

        // Convert to mono if multi-channel
        // Data is stored as interleaved: [L0, R0, L1, R1, ...]
        let mono_samples = if channels > 1 {
            info!("Converting {} channels to mono", channels);
            Self::to_mono(&all_samples, channels as usize)
        } else {
            all_samples
        };

        info!(
            "After mono conversion: {} samples (was {} with {} channels)",
            mono_samples.len(),
            mono_samples.len() * channels as usize,
            channels
        );

        // Resample to 16kHz if needed
        let resampled_samples = if original_sample_rate != WHISPER_SAMPLE_RATE {
            debug!(
                "Resampling from {}Hz to {}Hz",
                original_sample_rate, WHISPER_SAMPLE_RATE
            );
            Self::resample(&mono_samples, original_sample_rate, WHISPER_SAMPLE_RATE)
                .context("Resampling failed")?
        } else {
            mono_samples
        };

        let duration_seconds = resampled_samples.len() as f64 / WHISPER_SAMPLE_RATE as f64;

        // Debug: Check final sample range after resampling
        if !resampled_samples.is_empty() {
            let min_val = resampled_samples
                .iter()
                .cloned()
                .fold(f32::INFINITY, f32::min);
            let max_val = resampled_samples
                .iter()
                .cloned()
                .fold(f32::NEG_INFINITY, f32::max);
            let rms = (resampled_samples.iter().map(|x| x * x).sum::<f32>()
                / resampled_samples.len() as f32)
                .sqrt();
            info!(
                "Final audio: {} samples at {}Hz ({:.1}s), range=[{:.4}, {:.4}], rms={:.4}",
                resampled_samples.len(),
                WHISPER_SAMPLE_RATE,
                duration_seconds,
                min_val,
                max_val,
                rms
            );
        } else {
            info!(
                "Final audio: {} samples at {}Hz ({:.1}s)",
                resampled_samples.len(),
                WHISPER_SAMPLE_RATE,
                duration_seconds
            );
        }

        Ok(AudioSamples {
            samples: resampled_samples,
            original_sample_rate,
            original_channels: channels,
            duration_seconds,
        })
    }

    /// Extract f32 samples from buffer as interleaved multi-channel data
    fn extract_f32_samples(
        buf: &symphonia::core::audio::AudioBuffer<f32>,
        channels: usize,
        out: &mut Vec<f32>,
    ) {
        let frames = buf.frames();

        // Store samples as interleaved: [L0, R0, L1, R1, ...]
        // This allows proper mono conversion later
        for frame in 0..frames {
            for ch in 0..channels {
                out.push(buf.chan(ch)[frame]);
            }
        }
    }

    /// Extract s16 samples from buffer and convert to f32 as interleaved data
    fn extract_s16_samples(
        buf: &symphonia::core::audio::AudioBuffer<i16>,
        channels: usize,
        out: &mut Vec<f32>,
    ) {
        let frames = buf.frames();
        const S16_MAX: f32 = 32767.0;

        // Store samples as interleaved: [L0, R0, L1, R1, ...]
        for frame in 0..frames {
            for ch in 0..channels {
                out.push(buf.chan(ch)[frame] as f32 / S16_MAX);
            }
        }
    }

    /// Extract u8 samples from buffer and convert to f32 as interleaved data
    fn extract_u8_samples(
        buf: &symphonia::core::audio::AudioBuffer<u8>,
        channels: usize,
        out: &mut Vec<f32>,
    ) {
        let frames = buf.frames();

        // Store samples as interleaved: [L0, R0, L1, R1, ...]
        for frame in 0..frames {
            for ch in 0..channels {
                // Convert from [0, 255] to [-1.0, 1.0]
                out.push((buf.chan(ch)[frame] as f32 - 128.0) / 128.0);
            }
        }
    }

    /// Convert multi-channel samples to mono by averaging channels
    fn to_mono(samples: &[f32], channels: usize) -> Vec<f32> {
        if channels == 1 {
            return samples.to_vec();
        }

        let frames = samples.len() / channels;
        let mut mono = Vec::with_capacity(frames);

        for frame in 0..frames {
            let mut sum = 0.0f32;
            for ch in 0..channels {
                sum += samples[frame * channels + ch];
            }
            mono.push(sum / channels as f32);
        }

        mono
    }

    /// Resample audio to target sample rate using high-quality resampling
    fn resample(samples: &[f32], from_rate: u32, to_rate: u32) -> Result<Vec<f32>> {
        if from_rate == to_rate {
            return Ok(samples.to_vec());
        }

        // Use simple linear resampling for reliability
        let ratio = to_rate as f64 / from_rate as f64;
        let output_len = ((samples.len() as f64) * ratio).ceil() as usize;
        let mut output = Vec::with_capacity(output_len);

        for i in 0..output_len {
            let pos = i as f64 / ratio;
            let lower = pos.floor() as usize;
            let upper = (lower + 1).min(samples.len() - 1);
            let frac = pos - lower as f64;

            let sample = if lower < samples.len() {
                samples[lower] * (1.0 - frac) as f32 + samples[upper] * frac as f32
            } else {
                samples[lower]
            };

            output.push(sample);
        }

        output.truncate(output_len);
        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mono_conversion() {
        let stereo = vec![0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
        let mono = AudioProcessor::to_mono(&stereo, 2);
        assert_eq!(mono.len(), 3);
        assert!((mono[0] - 0.15).abs() < 0.0001);
        assert!((mono[1] - 0.35).abs() < 0.0001);
        assert!((mono[2] - 0.55).abs() < 0.0001);
    }

    #[test]
    fn test_s16_conversion() {
        let converted: Vec<f32> = vec![0i16, 16384, -16384, 32767, -32768]
            .iter()
            .map(|&s| s as f32 / 32767.0)
            .collect();
        assert_eq!(converted.len(), 5);
        assert!((converted[0] - 0.0).abs() < 0.0001);
        assert!((converted[3] - 1.0).abs() < 0.0001);
    }

    #[test]
    fn test_split_into_chunks_single_chunk() {
        // Audio shorter than chunk size -> single chunk
        let samples = AudioSamples {
            samples: vec![0.0; 16000 * 60], // 1 minute at 16kHz
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 60.0,
        };
        let config = ChunkConfig {
            chunk_duration_secs: 300, // 5 minutes
            overlap_secs: 5,
        };
        let chunks = samples.split_into_chunks(&config);

        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].index, 0);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert!(chunks[0].is_last);
        assert_eq!(chunks[0].samples.len(), 16000 * 60);
    }

    #[test]
    fn test_split_into_chunks_multiple() {
        // 12 minutes audio with 5 minute chunks and 30 second overlap
        // Expected: chunks at 0:00, 4:30, 9:00 (3 chunks)
        let samples = AudioSamples {
            samples: vec![0.0; 16000 * 60 * 12], // 12 minutes
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 720.0,
        };
        let config = ChunkConfig {
            chunk_duration_secs: 300, // 5 minutes
            overlap_secs: 30,         // 30 seconds overlap
        };
        let chunks = samples.split_into_chunks(&config);

        assert_eq!(chunks.len(), 3);

        // First chunk: 0:00 - 5:00
        assert_eq!(chunks[0].index, 0);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert!(!chunks[0].is_last);
        assert_eq!(chunks[0].samples.len(), 16000 * 300);

        // Second chunk: 4:30 - 9:30
        assert_eq!(chunks[1].index, 1);
        assert_eq!(chunks[1].start_offset_ms, 270_000); // 4:30 in ms
        assert!(!chunks[1].is_last);
        assert_eq!(chunks[1].samples.len(), 16000 * 300);

        // Third chunk: 9:00 - 12:00 (partial, only 3 minutes)
        assert_eq!(chunks[2].index, 2);
        assert_eq!(chunks[2].start_offset_ms, 540_000); // 9:00 in ms
        assert!(chunks[2].is_last);
        assert_eq!(chunks[2].samples.len(), 16000 * 180); // 3 minutes remaining
    }

    #[test]
    fn test_split_into_chunks_empty() {
        let samples = AudioSamples {
            samples: vec![],
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 0.0,
        };
        let config = ChunkConfig::default();
        let chunks = samples.split_into_chunks(&config);

        assert!(chunks.is_empty());
    }

    #[test]
    fn test_split_into_chunks_exact_fit() {
        // Exactly 10 minutes with 5 minute chunks, no overlap
        // Should produce exactly 2 chunks
        let samples = AudioSamples {
            samples: vec![0.0; 16000 * 60 * 10], // 10 minutes
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 600.0,
        };
        let config = ChunkConfig {
            chunk_duration_secs: 300, // 5 minutes
            overlap_secs: 0,          // no overlap
        };
        let chunks = samples.split_into_chunks(&config);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert_eq!(chunks[1].start_offset_ms, 300_000); // 5:00
        assert!(chunks[1].is_last);
    }

    #[test]
    fn test_split_into_chunks_basic() {
        // 10 seconds with 5s chunks and 1s overlap
        let ten_seconds_samples = 16000 * 10;
        let samples = AudioSamples {
            samples: vec![0.1; ten_seconds_samples],
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 10.0,
        };

        let config = ChunkConfig {
            chunk_duration_secs: 5,
            overlap_secs: 1,
        };

        let chunks = samples.split_into_chunks(&config);

        // With 5s chunks and 1s overlap, step = 4s
        // 0-5s (chunk 0), 4-9s (chunk 1), 8-10s (chunk 2)
        assert_eq!(chunks.len(), 3, "Expected 3 chunks");

        // First chunk: 0-5s
        assert_eq!(chunks[0].index, 0);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert_eq!(chunks[0].samples.len(), 16000 * 5);
        assert!(!chunks[0].is_last);

        // Second chunk: 4-9s (5s of audio)
        assert_eq!(chunks[1].index, 1);
        assert_eq!(chunks[1].start_offset_ms, 4000);
        assert_eq!(chunks[1].samples.len(), 16000 * 5);
        assert!(!chunks[1].is_last);

        // Third chunk: 8-10s (2s of audio)
        assert_eq!(chunks[2].index, 2);
        assert_eq!(chunks[2].start_offset_ms, 8000);
        assert_eq!(chunks[2].samples.len(), 16000 * 2);
        assert!(chunks[2].is_last);
    }

    #[test]
    fn test_split_short_audio() {
        // Audio shorter than chunk size
        let three_seconds_samples = 16000 * 3;
        let samples = AudioSamples {
            samples: vec![0.5; three_seconds_samples],
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 3.0,
        };

        let config = ChunkConfig {
            chunk_duration_secs: 5,
            overlap_secs: 1,
        };

        let chunks = samples.split_into_chunks(&config);

        assert_eq!(chunks.len(), 1, "Short audio should produce single chunk");
        assert_eq!(chunks[0].index, 0);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert_eq!(chunks[0].samples.len(), three_seconds_samples);
        assert!(chunks[0].is_last);
        assert_eq!(chunks[0].duration_ms, 3000);
    }

    #[test]
    fn test_split_no_overlap() {
        // 10 seconds with 5s chunks, 0s overlap = exactly 2 chunks
        let samples = AudioSamples {
            samples: vec![1.0; 16000 * 10],
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 10.0,
        };

        let config = ChunkConfig {
            chunk_duration_secs: 5,
            overlap_secs: 0,
        };

        let chunks = samples.split_into_chunks(&config);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].start_offset_ms, 0);
        assert_eq!(chunks[0].samples.len(), 16000 * 5);
        assert_eq!(chunks[1].start_offset_ms, 5000);
        assert_eq!(chunks[1].samples.len(), 16000 * 5);
        assert!(chunks[1].is_last);
    }

    #[test]
    fn test_chunk_samples_content() {
        // Create samples with distinct pattern
        let mut data = vec![0.0; 16000 * 10];
        for i in 0..data.len() {
            data[i] = (i as f32) / 1000.0;
        }

        let samples = AudioSamples {
            samples: data,
            original_sample_rate: 16000,
            original_channels: 1,
            duration_seconds: 10.0,
        };

        let config = ChunkConfig {
            chunk_duration_secs: 5,
            overlap_secs: 0,
        };

        let chunks = samples.split_into_chunks(&config);

        // Verify first chunk has correct samples from beginning
        for i in 0..chunks[0].samples.len() {
            assert_eq!(chunks[0].samples[i], samples.samples[i]);
        }

        // Verify second chunk has correct samples from position 80000
        let start = 16000 * 5;
        for (i, sample) in chunks[1].samples.iter().enumerate() {
            assert_eq!(*sample, samples.samples[start + i]);
        }
    }
}
