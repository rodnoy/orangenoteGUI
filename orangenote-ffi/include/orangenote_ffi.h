/* OrangeNote FFI C Header
 *
 * C-ABI interface for the OrangeNote transcription library.
 * All returned strings must be freed with orangenote_string_free().
 */

#ifndef ORANGENOTE_FFI_H
#define ORANGENOTE_FFI_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------ */
/* Opaque types                                                             */
/* ------------------------------------------------------------------------ */

/** Opaque handle to a transcriber instance. */
typedef struct OrangeNoteTranscriber OrangeNoteTranscriber;

/* ------------------------------------------------------------------------ */
/* Callback types                                                           */
/* ------------------------------------------------------------------------ */

/**
 * Progress callback for chunked transcription.
 *
 * @param current_chunk  Zero-based index of the chunk being processed.
 * @param total_chunks   Total number of chunks.
 * @param user_data      Opaque pointer passed through from the caller.
 */
typedef void (*TranscriptionProgressCallback)(int32_t current_chunk,
                                              int32_t total_chunks,
                                              void *user_data);

/* ------------------------------------------------------------------------ */
/* Transcriber lifecycle                                                    */
/* ------------------------------------------------------------------------ */

/**
 * Create a new transcriber from a model file.
 *
 * @param model_path  Path to the whisper.cpp GGML model file.
 * @param threads     Number of threads for inference (clamped to >= 1).
 * @param error_out   On failure, receives an error string (caller frees).
 * @return            Handle to the transcriber, or NULL on error.
 */
OrangeNoteTranscriber *orangenote_transcriber_new(const char *model_path,
                                                  int32_t threads,
                                                  char **error_out);

/**
 * Free a transcriber handle.
 *
 * Safe to call with NULL.
 *
 * @param transcriber  Handle previously returned by orangenote_transcriber_new.
 */
void orangenote_transcriber_free(OrangeNoteTranscriber *transcriber);

/* ------------------------------------------------------------------------ */
/* Model management                                                         */
/* ------------------------------------------------------------------------ */

/**
 * Get the default model cache directory.
 *
 * @param error_out  On failure, receives an error string (caller frees).
 * @return           Path string (caller frees with orangenote_string_free),
 *                   or NULL on error.
 */
char *orangenote_model_cache_dir(char **error_out);

/**
 * Check whether a model is cached locally.
 *
 * @param model_name  Model name, e.g. "tiny", "base.en", "large".
 * @return            true if cached, false otherwise (including on error).
 */
bool orangenote_model_is_cached(const char *model_name);

/**
 * Get the file-system path of a cached model.
 *
 * @param model_name  Model name, e.g. "tiny", "base.en".
 * @param error_out   On failure, receives an error string (caller frees).
 * @return            Path string (caller frees with orangenote_string_free),
 *                    or NULL if not cached / on error.
 */
char *orangenote_model_path(const char *model_name, char **error_out);

/**
 * List all available models as a JSON array.
 *
 * Each element: { "name": "tiny", "size_mb": 39, "cached": false }
 *
 * @param error_out  On failure, receives an error string (caller frees).
 * @return           JSON string (caller frees with orangenote_string_free),
 *                   or NULL on error.
 */
char *orangenote_list_models(char **error_out);

/* ------------------------------------------------------------------------ */
/* Transcription                                                            */
/* ------------------------------------------------------------------------ */

/**
 * Transcribe an audio file.
 *
 * @param transcriber  Transcriber handle.
 * @param audio_path   Path to the audio file.
 * @param language     Language code ("en", "ru", …) or NULL for auto-detect.
 * @param translate    If true, translate to English.
 * @param error_out    On failure, receives an error string (caller frees).
 * @return             JSON string with transcription result
 *                     (caller frees with orangenote_string_free), or NULL.
 */
char *orangenote_transcribe_file(OrangeNoteTranscriber *transcriber,
                                 const char *audio_path,
                                 const char *language,
                                 bool translate,
                                 char **error_out);

/**
 * Transcribe an audio file with chunked processing for long files.
 *
 * @param transcriber         Transcriber handle.
 * @param audio_path          Path to the audio file.
 * @param language            Language code or NULL for auto-detect.
 * @param translate           If true, translate to English.
 * @param chunk_duration_secs Duration of each chunk in seconds.
 * @param overlap_secs        Overlap between chunks in seconds.
 * @param progress_callback   Optional progress callback (may be NULL).
 * @param user_data           Opaque pointer forwarded to the callback.
 * @param error_out           On failure, receives an error string (caller frees).
 * @return                    JSON string with merged transcription result
 *                            (caller frees with orangenote_string_free), or NULL.
 */
char *orangenote_transcribe_file_chunked(OrangeNoteTranscriber *transcriber,
                                         const char *audio_path,
                                         const char *language,
                                         bool translate,
                                         int32_t chunk_duration_secs,
                                         int32_t overlap_secs,
                                         TranscriptionProgressCallback progress_callback,
                                         void *user_data,
                                         char **error_out);

/* ------------------------------------------------------------------------ */
/* Export                                                                    */
/* ------------------------------------------------------------------------ */

/**
 * Export a transcription result to a specific format.
 *
 * @param transcription_json  JSON string from a transcribe function.
 * @param format              One of: "txt", "srt", "vtt", "json".
 * @param error_out           On failure, receives an error string (caller frees).
 * @return                    Formatted string (caller frees with
 *                            orangenote_string_free), or NULL on error.
 */
char *orangenote_export(const char *transcription_json,
                        const char *format,
                        char **error_out);

/* ------------------------------------------------------------------------ */
/* Memory management                                                        */
/* ------------------------------------------------------------------------ */

/**
 * Free a string previously allocated by this library.
 *
 * Safe to call with NULL.
 *
 * @param s  String to free.
 */
void orangenote_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* ORANGENOTE_FFI_H */
