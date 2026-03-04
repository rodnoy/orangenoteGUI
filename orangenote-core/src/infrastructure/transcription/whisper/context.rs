//! Safe Rust wrapper for whisper.cpp context
//!
//! This module provides a safe, idiomatic Rust API for the whisper.cpp FFI bindings.
//! It handles memory management, error handling, and provides convenient methods
//! for transcription and result extraction.

use super::ffi;
use anyhow::{anyhow, Result};
use std::ffi::{CStr, CString};
use std::os::raw::c_float;
use std::path::Path;

/// Safe wrapper around whisper context
pub struct WhisperContextWrapper {
    ctx: *mut ffi::WhisperContext,
}

impl WhisperContextWrapper {
    /// Create a new whisper context from a model file
    ///
    /// # Arguments
    ///
    /// * `model_path` - Path to the whisper.cpp model file
    ///
    /// # Returns
    ///
    /// Result containing the initialized context, or an error if initialization failed
    pub fn new<P: AsRef<Path>>(model_path: P) -> Result<Self> {
        let path_str = model_path
            .as_ref()
            .to_str()
            .ok_or_else(|| anyhow!("Invalid model path"))?;

        let c_path = CString::new(path_str)?;

        unsafe {
            let ctx = ffi::whisper_init_from_file(c_path.as_ptr());
            if ctx.is_null() {
                return Err(anyhow!(
                    "Failed to initialize whisper context from model file"
                ));
            }
            Ok(WhisperContextWrapper { ctx })
        }
    }

    /// Create a new whisper context from a buffer
    ///
    /// # Arguments
    ///
    /// * `buffer` - Buffer containing the model data
    ///
    /// # Returns
    ///
    /// Result containing the initialized context, or an error if initialization failed
    pub fn from_buffer(buffer: &[u8]) -> Result<Self> {
        unsafe {
            let ctx = ffi::whisper_init_from_buffer(buffer.as_ptr() as *const _, buffer.len());
            if ctx.is_null() {
                return Err(anyhow!("Failed to initialize whisper context from buffer"));
            }
            Ok(WhisperContextWrapper { ctx })
        }
    }

    /// Get the raw FFI context pointer (for advanced usage)
    pub fn as_ptr(&self) -> *mut ffi::WhisperContext {
        self.ctx
    }

    /// Transcribe audio samples
    ///
    /// # Arguments
    ///
    /// * `samples` - Float samples at 16kHz
    /// * `language` - Optional language code (e.g., "en", "ru"). None for auto-detect
    /// * `translate` - Whether to translate to English
    ///
    /// # Returns
    ///
    /// Result containing the transcription results or an error
    pub fn transcribe(
        &self,
        samples: &[c_float],
        language: Option<&str>,
        translate: bool,
    ) -> Result<TranscriptionResult> {
        let mut params = unsafe { ffi::whisper_full_default_params(ffi::WHISPER_SAMPLING_GREEDY) };

        params.translate = translate;
        params.print_progress = false;
        params.print_realtime = false;
        params.print_timestamps = true;
        params.token_timestamps = true;

        // Disable VAD to avoid requiring VAD model
        params.vad = false;

        // Set language if provided
        let lang_c_string;
        if let Some(lang) = language {
            lang_c_string = CString::new(lang)?;
            params.language = lang_c_string.as_ptr();
        }

        unsafe {
            let ret = ffi::whisper_full(self.ctx, params, samples.as_ptr(), samples.len() as i32);
            if ret != 0 {
                return Err(anyhow!("Transcription failed with code {}", ret));
            }
        }

        self.extract_results()
    }

    /// Extract transcription results from the context
    ///
    /// # Returns
    ///
    /// Result containing the transcription data
    pub fn extract_results(&self) -> Result<TranscriptionResult> {
        unsafe {
            let n_segments = ffi::whisper_full_n_segments(self.ctx);
            let lang_id = ffi::whisper_full_lang_id(self.ctx);
            let lang_name_ptr = ffi::whisper_lang_str(lang_id);
            let language = if lang_name_ptr.is_null() {
                "unknown".to_string()
            } else {
                CStr::from_ptr(lang_name_ptr).to_string_lossy().to_string()
            };

            let mut segments = Vec::new();
            for i in 0..n_segments {
                let text_ptr = ffi::whisper_full_get_segment_text(self.ctx, i);
                let text = if text_ptr.is_null() {
                    String::new()
                } else {
                    CStr::from_ptr(text_ptr).to_string_lossy().to_string()
                };

                // t0 and t1 are in centiseconds (100ths of a second), convert to milliseconds
                let t0 = ffi::whisper_full_get_segment_t0(self.ctx, i) * 10;
                let t1 = ffi::whisper_full_get_segment_t1(self.ctx, i) * 10;
                // no_speech_prob is inverted - higher means more likely silence
                // so confidence = 1.0 - no_speech_prob
                let no_speech_prob = ffi::whisper_full_get_segment_no_speech_prob(self.ctx, i);
                let p = 1.0 - no_speech_prob;
                let n_tokens = ffi::whisper_full_n_tokens(self.ctx, i);

                let mut tokens = Vec::new();
                for j in 0..n_tokens {
                    let token_text_ptr = ffi::whisper_full_get_token_text(self.ctx, i, j);
                    let token_text = if token_text_ptr.is_null() {
                        String::new()
                    } else {
                        CStr::from_ptr(token_text_ptr).to_string_lossy().to_string()
                    };
                    let token_p = ffi::whisper_full_get_token_p(self.ctx, i, j);

                    tokens.push(Token {
                        text: token_text,
                        probability: token_p,
                    });
                }

                segments.push(Segment {
                    id: i,
                    start_ms: t0,
                    end_ms: t1,
                    text,
                    confidence: p,
                    tokens,
                });
            }

            Ok(TranscriptionResult { language, segments })
        }
    }
}

impl Drop for WhisperContextWrapper {
    fn drop(&mut self) {
        unsafe {
            ffi::whisper_free(self.ctx);
        }
    }
}

/// A single transcribed segment
#[derive(Debug, Clone)]
pub struct Segment {
    /// Segment index
    pub id: i32,
    /// Start time in milliseconds
    pub start_ms: i64,
    /// End time in milliseconds
    pub end_ms: i64,
    /// Transcribed text
    pub text: String,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Individual tokens with probabilities
    pub tokens: Vec<Token>,
}

impl Segment {
    /// Format start time as HH:MM:SS.mmm
    pub fn start_time_formatted(&self) -> String {
        format_timestamp(self.start_ms)
    }

    /// Format end time as HH:MM:SS.mmm
    pub fn end_time_formatted(&self) -> String {
        format_timestamp(self.end_ms)
    }
}

/// A single token with probability
#[derive(Debug, Clone)]
pub struct Token {
    /// Token text
    pub text: String,
    /// Probability (0.0 - 1.0)
    pub probability: f32,
}

/// Complete transcription result
#[derive(Debug, Clone)]
pub struct TranscriptionResult {
    /// Detected language
    pub language: String,
    /// Transcribed segments
    pub segments: Vec<Segment>,
}

impl TranscriptionResult {
    /// Get full transcript as a single string
    pub fn full_text(&self) -> String {
        self.segments
            .iter()
            .map(|s| s.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Get average confidence across all segments
    pub fn average_confidence(&self) -> f32 {
        if self.segments.is_empty() {
            return 0.0;
        }
        self.segments.iter().map(|s| s.confidence).sum::<f32>() / self.segments.len() as f32
    }
}

/// Format milliseconds as HH:MM:SS.mmm
fn format_timestamp(ms: i64) -> String {
    let total_seconds = ms / 1000;
    let milliseconds = ms % 1000;
    let seconds = total_seconds % 60;
    let minutes = (total_seconds / 60) % 60;
    let hours = total_seconds / 3600;

    format!(
        "{:02}:{:02}:{:02}.{:03}",
        hours, minutes, seconds, milliseconds
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_timestamp() {
        assert_eq!(format_timestamp(0), "00:00:00.000");
        assert_eq!(format_timestamp(1000), "00:00:01.000");
        assert_eq!(format_timestamp(61000), "00:01:01.000");
        assert_eq!(format_timestamp(3661000), "01:01:01.000");
        assert_eq!(format_timestamp(3661500), "01:01:01.500");
    }
}
