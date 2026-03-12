//! OrangeNote FFI Layer
//!
//! C-ABI bridge exposing orangenote-core functions for Swift interop.
//! All public functions use `extern "C"` calling convention and handle
//! panics via `catch_unwind`.
//!
//! # Memory Management
//!
//! - Strings returned by this library must be freed with [`orangenote_string_free`].
//! - Error strings written to `error_out` must be freed with [`orangenote_string_free`].
//! - The [`OrangeNoteTranscriber`] handle must be freed with [`orangenote_transcriber_free`].

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use orangenote_core::{
    ChunkConfig, ModelSize, TranscriptionResult, WhisperModelManager, WhisperTranscriber,
};

// ---------------------------------------------------------------------------
// Opaque handle
// ---------------------------------------------------------------------------

/// Opaque handle wrapping [`WhisperTranscriber`].
pub struct OrangeNoteTranscriber {
    inner: WhisperTranscriber,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Write an error message into the caller-provided `error_out` pointer.
fn set_error(error_out: *mut *mut c_char, message: &str) {
    if !error_out.is_null() {
        if let Ok(c_string) = CString::new(message) {
            unsafe {
                *error_out = c_string.into_raw();
            }
        }
    }
}

/// Convert a `*const c_char` to `&str`, returning `Err` on null or invalid UTF-8.
unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null pointer".to_string());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| format!("invalid UTF-8: {e}"))
}

/// Serialize a [`TranscriptionResult`] to a JSON C-string.
fn result_to_json(result: &TranscriptionResult) -> Result<*mut c_char, String> {
    #[derive(serde::Serialize)]
    struct SegmentJson<'a> {
        id: i32,
        start_ms: i64,
        end_ms: i64,
        text: &'a str,
        confidence: f32,
    }

    #[derive(serde::Serialize)]
    struct ResultJson<'a> {
        language: &'a str,
        segments: Vec<SegmentJson<'a>>,
    }

    let json_value = ResultJson {
        language: &result.language,
        segments: result
            .segments
            .iter()
            .map(|s| SegmentJson {
                id: s.id,
                start_ms: s.start_ms,
                end_ms: s.end_ms,
                text: &s.text,
                confidence: s.confidence,
            })
            .collect(),
    };

    let json_string =
        serde_json::to_string(&json_value).map_err(|e| format!("JSON serialization error: {e}"))?;

    CString::new(json_string)
        .map(|cs| cs.into_raw())
        .map_err(|e| format!("CString error: {e}"))
}

// ---------------------------------------------------------------------------
// Transcriber lifecycle
// ---------------------------------------------------------------------------

/// Initialize a transcriber with a model file.
///
/// Returns an opaque handle or null on error. On failure the error message is
/// written to `error_out` (caller must free it with [`orangenote_string_free`]).
#[no_mangle]
pub extern "C" fn orangenote_transcriber_new(
    model_path: *const c_char,
    threads: c_int,
    error_out: *mut *mut c_char,
) -> *mut OrangeNoteTranscriber {
    let result = catch_unwind(AssertUnwindSafe(
        || -> Result<*mut OrangeNoteTranscriber, String> {
            let path = unsafe { cstr_to_str(model_path) }?;
            let transcriber = WhisperTranscriber::new(path, threads.max(1) as usize)
                .map_err(|e| format!("{e:#}"))?;
            Ok(Box::into_raw(Box::new(OrangeNoteTranscriber {
                inner: transcriber,
            })))
        },
    ));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_transcriber_new");
            ptr::null_mut()
        }
    }
}

/// Free a transcriber handle previously returned by [`orangenote_transcriber_new`].
#[no_mangle]
pub extern "C" fn orangenote_transcriber_free(transcriber: *mut OrangeNoteTranscriber) {
    if !transcriber.is_null() {
        unsafe {
            drop(Box::from_raw(transcriber));
        }
    }
}

// ---------------------------------------------------------------------------
// Model management
// ---------------------------------------------------------------------------

/// Return the default model cache directory as a C-string.
///
/// Caller must free the returned string with [`orangenote_string_free`].
/// Returns null on error (error written to `error_out`).
#[no_mangle]
pub extern "C" fn orangenote_model_cache_dir(error_out: *mut *mut c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        let dir = WhisperModelManager::default_cache_dir().map_err(|e| format!("{e:#}"))?;
        let s = dir
            .to_str()
            .ok_or_else(|| "non-UTF-8 path".to_string())?
            .to_string();
        CString::new(s)
            .map(|cs| cs.into_raw())
            .map_err(|e| format!("CString error: {e}"))
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_model_cache_dir");
            ptr::null_mut()
        }
    }
}

/// Check whether a model is already cached locally.
///
/// `model_name` is a C-string such as `"tiny"`, `"base.en"`, etc.
/// Returns `false` on any error (invalid name, null pointer, etc.).
#[no_mangle]
pub extern "C" fn orangenote_model_is_cached(model_name: *const c_char) -> bool {
    let result = catch_unwind(AssertUnwindSafe(|| -> Option<bool> {
        let name = unsafe { cstr_to_str(model_name) }.ok()?;
        let size = ModelSize::from_str(name).ok()?;
        let manager = WhisperModelManager::new().ok()?;
        Some(manager.is_cached(size))
    }));

    result.unwrap_or(None).unwrap_or(false)
}

/// Return the file-system path of a cached model.
///
/// Returns null if the model is not cached or on error.
/// Caller must free the returned string with [`orangenote_string_free`].
#[no_mangle]
pub extern "C" fn orangenote_model_path(
    model_name: *const c_char,
    error_out: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        let name = unsafe { cstr_to_str(model_name) }?;
        let size = ModelSize::from_str(name).map_err(|e| format!("{e:#}"))?;
        let manager = WhisperModelManager::new().map_err(|e| format!("{e:#}"))?;
        let path = manager.get_model_path(size);
        if !path.exists() {
            return Err(format!("model '{name}' is not cached"));
        }
        let s = path
            .to_str()
            .ok_or_else(|| "non-UTF-8 path".to_string())?
            .to_string();
        CString::new(s)
            .map(|cs| cs.into_raw())
            .map_err(|e| format!("CString error: {e}"))
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_model_path");
            ptr::null_mut()
        }
    }
}

/// List all available models as a JSON array of objects.
///
/// Each object has `name` (string), `size_mb` (number), and `cached` (bool).
/// Caller must free the returned string with [`orangenote_string_free`].
#[no_mangle]
pub extern "C" fn orangenote_list_models(error_out: *mut *mut c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        let manager = WhisperModelManager::new().map_err(|e| format!("{e:#}"))?;
        let models = WhisperModelManager::list_available_models();

        #[derive(serde::Serialize)]
        struct ModelInfo {
            name: &'static str,
            size_mb: u32,
            cached: bool,
        }

        let list: Vec<ModelInfo> = models
            .iter()
            .map(|(size, mb)| ModelInfo {
                name: size.display_name(),
                size_mb: *mb,
                cached: manager.is_cached(*size),
            })
            .collect();

        let json = serde_json::to_string(&list).map_err(|e| format!("JSON error: {e}"))?;
        CString::new(json)
            .map(|cs| cs.into_raw())
            .map_err(|e| format!("CString error: {e}"))
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_list_models");
            ptr::null_mut()
        }
    }
}

/// Delete a cached model.
///
/// Returns `true` on success, `false` on error.
/// On error, `error_out` is set to a descriptive message.
#[no_mangle]
pub extern "C" fn orangenote_delete_model(
    model_name: *const c_char,
    error_out: *mut *mut c_char,
) -> bool {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let name = unsafe { cstr_to_str(model_name) }?;
        let size = ModelSize::from_str(name).map_err(|e| format!("{e:#}"))?;
        let manager = WhisperModelManager::new().map_err(|e| format!("{e:#}"))?;
        manager.delete_model(size).map_err(|e| format!("{e:#}"))
    }));

    match result {
        Ok(Ok(())) => true,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            false
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_delete_model");
            false
        }
    }
}

/// Progress callback type for model downloads.
///
/// Parameters: (bytes_downloaded, total_bytes, user_data)
/// If total_bytes is 0, the total size is unknown.
pub type DownloadProgressCallback =
    Option<extern "C" fn(downloaded: u64, total: u64, user_data: *mut c_void)>;

/// Download a model with progress reporting.
///
/// This function blocks until the download completes or fails.
/// The progress callback is called periodically with download progress.
/// Returns `true` on success, `false` on error.
#[no_mangle]
pub extern "C" fn orangenote_download_model(
    model_name: *const c_char,
    progress_callback: DownloadProgressCallback,
    user_data: *mut c_void,
    error_out: *mut *mut c_char,
) -> bool {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let name = unsafe { cstr_to_str(model_name) }?;
        let size = ModelSize::from_str(name).map_err(|e| format!("{e:#}"))?;
        let manager = WhisperModelManager::new().map_err(|e| format!("{e:#}"))?;

        manager
            .download_model_with_progress(size, |downloaded, total| {
                if let Some(cb) = progress_callback {
                    cb(downloaded, total, user_data);
                }
            })
            .map_err(|e| format!("{e:#}"))
    }));

    match result {
        Ok(Ok(())) => true,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            false
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_download_model");
            false
        }
    }
}

// ---------------------------------------------------------------------------
// Transcription
// ---------------------------------------------------------------------------

/// Transcribe an audio file.
///
/// Returns a JSON string with the transcription result or null on error.
/// `language` may be null for auto-detection.
/// Caller must free the returned string with [`orangenote_string_free`].
#[no_mangle]
pub extern "C" fn orangenote_transcribe_file(
    transcriber: *mut OrangeNoteTranscriber,
    audio_path: *const c_char,
    language: *const c_char,
    translate: bool,
    error_out: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        if transcriber.is_null() {
            return Err("null transcriber handle".to_string());
        }
        let t = unsafe { &*transcriber };
        let path = unsafe { cstr_to_str(audio_path) }?;
        let lang: Option<&str> = if language.is_null() {
            None
        } else {
            Some(unsafe { cstr_to_str(language) }?)
        };

        let result = t
            .inner
            .transcribe_file(path, lang, translate)
            .map_err(|e| format!("{e:#}"))?;

        result_to_json(&result)
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_transcribe_file");
            ptr::null_mut()
        }
    }
}

/// Progress callback type for chunked transcription.
///
/// Parameters: `current_chunk`, `total_chunks`, `user_data`.
pub type TranscriptionProgressCallback = Option<extern "C" fn(c_int, c_int, *mut c_void)>;

/// Transcribe an audio file using chunked processing for long files.
///
/// Returns a JSON string with the merged transcription result or null on error.
/// `language` may be null for auto-detection.
/// Caller must free the returned string with [`orangenote_string_free`].
#[no_mangle]
pub extern "C" fn orangenote_transcribe_file_chunked(
    transcriber: *mut OrangeNoteTranscriber,
    audio_path: *const c_char,
    language: *const c_char,
    translate: bool,
    chunk_duration_secs: c_int,
    overlap_secs: c_int,
    progress_callback: TranscriptionProgressCallback,
    user_data: *mut c_void,
    error_out: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        if transcriber.is_null() {
            return Err("null transcriber handle".to_string());
        }
        let t = unsafe { &*transcriber };
        let path = unsafe { cstr_to_str(audio_path) }?;
        let lang: Option<&str> = if language.is_null() {
            None
        } else {
            Some(unsafe { cstr_to_str(language) }?)
        };

        let chunk_config = ChunkConfig::new(
            chunk_duration_secs.max(1) as u32,
            overlap_secs.max(0) as u32,
        );

        let result = t
            .inner
            .transcribe_file_chunked(path, lang, translate, &chunk_config, |current, total| {
                if let Some(cb) = progress_callback {
                    cb(current as c_int, total as c_int, user_data);
                }
            })
            .map_err(|e| format!("{e:#}"))?;

        result_to_json(&result)
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_transcribe_file_chunked");
            ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Export helpers
// ---------------------------------------------------------------------------

/// Export a transcription result (JSON) to a specific format.
///
/// `format` is one of: `"txt"`, `"srt"`, `"vtt"`, `"json"`.
/// `transcription_json` is the JSON string previously returned by a transcribe function.
/// Returns the formatted string or null on error.
/// Caller must free the returned string with [`orangenote_string_free`].
#[no_mangle]
pub extern "C" fn orangenote_export(
    transcription_json: *const c_char,
    format: *const c_char,
    error_out: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<*mut c_char, String> {
        let json_str = unsafe { cstr_to_str(transcription_json) }?;
        let fmt = unsafe { cstr_to_str(format) }?;

        #[derive(serde::Deserialize)]
        struct SegmentJson {
            #[allow(dead_code)]
            id: i32,
            start_ms: i64,
            end_ms: i64,
            text: String,
            #[allow(dead_code)]
            confidence: f32,
        }

        #[derive(serde::Deserialize)]
        struct ResultJson {
            #[allow(dead_code)]
            language: String,
            segments: Vec<SegmentJson>,
        }

        let parsed: ResultJson =
            serde_json::from_str(json_str).map_err(|e| format!("JSON parse error: {e}"))?;

        let output = match fmt {
            "txt" => parsed
                .segments
                .iter()
                .map(|s| s.text.as_str())
                .collect::<Vec<_>>()
                .join(" "),
            "srt" => {
                let mut buf = String::new();
                for (i, seg) in parsed.segments.iter().enumerate() {
                    buf.push_str(&format!("{}\n", i + 1));
                    buf.push_str(&format!(
                        "{} --> {}\n",
                        format_srt_time(seg.start_ms),
                        format_srt_time(seg.end_ms)
                    ));
                    buf.push_str(&seg.text);
                    buf.push_str("\n\n");
                }
                buf
            }
            "vtt" => {
                let mut buf = String::from("WEBVTT\n\n");
                for seg in &parsed.segments {
                    buf.push_str(&format!(
                        "{} --> {}\n",
                        format_vtt_time(seg.start_ms),
                        format_vtt_time(seg.end_ms)
                    ));
                    buf.push_str(&seg.text);
                    buf.push_str("\n\n");
                }
                buf
            }
            "json" => json_str.to_string(),
            _ => return Err(format!("unsupported export format: '{fmt}'")),
        };

        CString::new(output)
            .map(|cs| cs.into_raw())
            .map_err(|e| format!("CString error: {e}"))
    }));

    match result {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(msg)) => {
            set_error(error_out, &msg);
            ptr::null_mut()
        }
        Err(_) => {
            set_error(error_out, "panic in orangenote_export");
            ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Memory management
// ---------------------------------------------------------------------------

/// Free a C-string previously allocated by this library.
///
/// Safe to call with null.
#[no_mangle]
pub extern "C" fn orangenote_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Format milliseconds as SRT timestamp `HH:MM:SS,mmm`.
fn format_srt_time(ms: i64) -> String {
    let total_secs = ms / 1000;
    let millis = ms % 1000;
    let secs = total_secs % 60;
    let mins = (total_secs / 60) % 60;
    let hours = total_secs / 3600;
    format!("{hours:02}:{mins:02}:{secs:02},{millis:03}")
}

/// Format milliseconds as WebVTT timestamp `HH:MM:SS.mmm`.
fn format_vtt_time(ms: i64) -> String {
    let total_secs = ms / 1000;
    let millis = ms % 1000;
    let secs = total_secs % 60;
    let mins = (total_secs / 60) % 60;
    let hours = total_secs / 3600;
    format!("{hours:02}:{mins:02}:{secs:02}.{millis:03}")
}
