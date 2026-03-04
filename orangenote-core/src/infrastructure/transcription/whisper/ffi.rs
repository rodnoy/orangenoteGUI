//! FFI bindings for whisper.cpp
//!
//! This module provides low-level FFI bindings to the whisper.cpp C library.
//! These bindings are used internally by the whisper-rs wrapper crate.
//!
//! For high-level usage, see the `context` module which provides a safe Rust API.

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(dead_code)]

use std::os::raw::{c_char, c_float, c_int, c_void};

/// Opaque pointer to a whisper context
pub type WhisperContext = c_void;

/// Opaque pointer to whisper state (for multithreading)
pub type WhisperState = c_void;

/// Whisper token type
pub type WhisperToken = i32;

/// Sampling strategy constants
pub const WHISPER_SAMPLING_GREEDY: c_int = 0;
pub const WHISPER_SAMPLING_BEAM_SEARCH: c_int = 1;

/// Greedy sampling parameters
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WhisperGreedyParams {
    pub best_of: c_int,
}

/// Beam search sampling parameters
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WhisperBeamSearchParams {
    pub beam_size: c_int,
    pub patience: c_float,
}

/// VAD parameters
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WhisperVadParams {
    pub threshold: c_float,
    pub min_speech_duration_ms: c_int,
    pub min_silence_duration_ms: c_int,
    pub max_speech_duration_s: c_float,
    pub speech_pad_ms: c_int,
    pub samples_overlap: c_float,
}

/// Grammar element (opaque)
pub type WhisperGrammarElement = c_void;

/// Callback types
pub type WhisperNewSegmentCallback =
    Option<extern "C" fn(*mut WhisperContext, *mut WhisperState, c_int, *mut c_void)>;
pub type WhisperProgressCallback =
    Option<extern "C" fn(*mut WhisperContext, *mut WhisperState, c_int, *mut c_void)>;
pub type WhisperEncoderBeginCallback =
    Option<extern "C" fn(*mut WhisperContext, *mut WhisperState, *mut c_void) -> bool>;
pub type WhisperAbortCallback = Option<extern "C" fn(*mut c_void) -> bool>;
pub type WhisperLogitsFilterCallback = Option<
    extern "C" fn(
        *mut WhisperContext,
        *mut WhisperState,
        *const WhisperTokenData,
        c_int,
        *mut c_float,
        *mut c_void,
    ),
>;

/// Whisper full params structure - must match whisper.cpp exactly
/// Based on whisper.cpp v1.7+
#[repr(C)]
#[derive(Clone)]
pub struct WhisperFullParams {
    pub strategy: c_int,

    pub n_threads: c_int,
    pub n_max_text_ctx: c_int,
    pub offset_ms: c_int,
    pub duration_ms: c_int,

    pub translate: bool,
    pub no_context: bool,
    pub no_timestamps: bool,
    pub single_segment: bool,
    pub print_special: bool,
    pub print_progress: bool,
    pub print_realtime: bool,
    pub print_timestamps: bool,

    // Token-level timestamps
    pub token_timestamps: bool,
    pub thold_pt: c_float,
    pub thold_ptsum: c_float,
    pub max_len: c_int,
    pub split_on_word: bool,
    pub max_tokens: c_int,

    // Speed-up techniques
    pub debug_mode: bool,
    pub audio_ctx: c_int,

    // Tinydiarize
    pub tdrz_enable: bool,

    // Suppress regex
    pub suppress_regex: *const c_char,

    // Initial prompt
    pub initial_prompt: *const c_char,
    pub carry_initial_prompt: bool,
    pub prompt_tokens: *const WhisperToken,
    pub prompt_n_tokens: c_int,

    // Language
    pub language: *const c_char,
    pub detect_language: bool,

    // Decoding parameters
    pub suppress_blank: bool,
    pub suppress_nst: bool,

    pub temperature: c_float,
    pub max_initial_ts: c_float,
    pub length_penalty: c_float,

    // Fallback parameters
    pub temperature_inc: c_float,
    pub entropy_thold: c_float,
    pub logprob_thold: c_float,
    pub no_speech_thold: c_float,

    pub greedy: WhisperGreedyParams,
    pub beam_search: WhisperBeamSearchParams,

    // Callbacks
    pub new_segment_callback: WhisperNewSegmentCallback,
    pub new_segment_callback_user_data: *mut c_void,

    pub progress_callback: WhisperProgressCallback,
    pub progress_callback_user_data: *mut c_void,

    pub encoder_begin_callback: WhisperEncoderBeginCallback,
    pub encoder_begin_callback_user_data: *mut c_void,

    pub abort_callback: WhisperAbortCallback,
    pub abort_callback_user_data: *mut c_void,

    pub logits_filter_callback: WhisperLogitsFilterCallback,
    pub logits_filter_callback_user_data: *mut c_void,

    // Grammar
    pub grammar_rules: *const *const WhisperGrammarElement,
    pub n_grammar_rules: usize,
    pub i_start_rule: usize,
    pub grammar_penalty: c_float,

    // VAD
    pub vad: bool,
    pub vad_model_path: *const c_char,
    pub vad_params: WhisperVadParams,
}

/// Token data
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WhisperTokenData {
    /// Token ID
    pub id: WhisperToken,

    /// Token ID used for next token search
    pub tid: WhisperToken,

    /// Probability
    pub p: c_float,

    /// Log probability
    pub plog: c_float,

    /// Probability of being voiced vs unvoiced
    pub pt: c_float,

    /// Cumulative sum of pt
    pub ptsum: c_float,

    /// Timestamp start
    pub t0: i64,

    /// Timestamp end
    pub t1: i64,

    /// DTW timestamp
    pub t_dtw: i64,

    /// Voice length
    pub vlen: c_float,
}

// Link against whisper library when feature is enabled
// Build script (build.rs) sets up the library path and linking
#[cfg(feature = "whisper")]
#[link(name = "whisper")]
extern "C" {
    /// Initialize whisper context from file
    pub fn whisper_init_from_file(path: *const c_char) -> *mut WhisperContext;

    /// Initialize whisper context from buffer
    pub fn whisper_init_from_buffer(
        buffer: *const c_void,
        buffer_size: usize,
    ) -> *mut WhisperContext;

    /// Free whisper context
    pub fn whisper_free(ctx: *mut WhisperContext);

    /// Get default parameters
    pub fn whisper_full_default_params(strategy: c_int) -> WhisperFullParams;

    /// Run the full transcription pipeline
    pub fn whisper_full(
        ctx: *mut WhisperContext,
        params: WhisperFullParams,
        samples: *const c_float,
        n_samples: c_int,
    ) -> c_int;

    /// Run the full transcription pipeline with state
    pub fn whisper_full_with_state(
        ctx: *mut WhisperContext,
        state: *mut WhisperState,
        params: WhisperFullParams,
        samples: *const c_float,
        n_samples: c_int,
    ) -> c_int;

    /// Get number of segments
    pub fn whisper_full_n_segments(ctx: *mut WhisperContext) -> c_int;

    /// Get segment text
    pub fn whisper_full_get_segment_text(ctx: *mut WhisperContext, i: c_int) -> *const c_char;

    /// Get segment start time in centiseconds (100ths of a second)
    pub fn whisper_full_get_segment_t0(ctx: *mut WhisperContext, i: c_int) -> i64;

    /// Get segment end time in centiseconds (100ths of a second)
    pub fn whisper_full_get_segment_t1(ctx: *mut WhisperContext, i: c_int) -> i64;

    /// Get segment no-speech probability (higher = more likely silence/noise)
    pub fn whisper_full_get_segment_no_speech_prob(ctx: *mut WhisperContext, i: c_int) -> c_float;

    /// Get number of tokens in segment
    pub fn whisper_full_n_tokens(ctx: *mut WhisperContext, i: c_int) -> c_int;

    /// Get token data from segment
    pub fn whisper_full_get_token_data(
        ctx: *mut WhisperContext,
        i_segment: c_int,
        i_token: c_int,
    ) -> WhisperTokenData;

    /// Get token ID
    pub fn whisper_full_get_token_id(
        ctx: *mut WhisperContext,
        i_segment: c_int,
        i_token: c_int,
    ) -> WhisperToken;

    /// Get token text
    pub fn whisper_full_get_token_text(
        ctx: *mut WhisperContext,
        i_segment: c_int,
        i_token: c_int,
    ) -> *const c_char;

    /// Get token probability
    pub fn whisper_full_get_token_p(
        ctx: *mut WhisperContext,
        i_segment: c_int,
        i_token: c_int,
    ) -> c_float;

    /// Get language ID detected
    pub fn whisper_full_lang_id(ctx: *mut WhisperContext) -> c_int;

    /// Get language name by ID
    pub fn whisper_lang_str(id: c_int) -> *const c_char;

    /// Get language ID by name
    pub fn whisper_lang_id(lang: *const c_char) -> c_int;

    /// Create new state (for multithreading)
    pub fn whisper_state_new(ctx: *const WhisperContext) -> *mut WhisperState;

    /// Free state
    pub fn whisper_state_free(state: *mut WhisperState);

    /// Print system information
    pub fn whisper_print_system_info() -> *const c_char;
}
