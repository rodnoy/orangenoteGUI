//
//  TranscriptionRequest.swift
//  OrangeNote
//
//  Backend-agnostic request describing a single transcription operation.
//

import Foundation

/// A request describing everything a transcription engine needs to
/// transcribe a single audio file, independent of the concrete backend
/// (local Whisper, cloud provider, etc.).
struct TranscriptionRequest: Sendable, Equatable {
    /// File-system URL of the source audio file to transcribe.
    let sourceURL: URL

    /// Name of the model to use for transcription (e.g. "base", "small").
    let modelName: String

    /// Language code (e.g. "en", "ru") or `nil` for auto-detection.
    let language: String?

    /// Whether the transcription should be translated to English.
    let translateToEnglish: Bool

    /// Whether chunked processing should be used for long audio files.
    let chunkingEnabled: Bool

    /// Duration of each chunk in seconds, applicable only when chunking is enabled.
    let chunkDurationSeconds: Double?

    /// Overlap duration between chunks in seconds, applicable only when chunking is enabled.
    let overlapDurationSeconds: Double?
}
