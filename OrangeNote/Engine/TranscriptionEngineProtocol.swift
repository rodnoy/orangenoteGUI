//
//  TranscriptionEngineProtocol.swift
//  OrangeNote
//
//  Abstraction decoupling transcription consumers from concrete backend
//  implementations (D004). Concrete conformers (e.g. a Whisper-backed
//  adapter over `OrangeNoteEngine`) are introduced in later tasks.
//

import Foundation

/// A backend-agnostic transcription engine capable of transcribing a single
/// audio file described by a `TranscriptionRequest`.
///
/// ## Semantic Lifetime Contract
///
/// Conformers of `TranscriptionEngineProtocol` MUST honor the following
/// guarantees so that callers (e.g. `TranscriptionViewModel`) can reason
/// safely about state transitions and resource lifetime:
///
/// 1. **Drain guarantee on completion**: When `transcribe(request:progressHandler:)`
///    returns a value or throws an error, the underlying operation and any
///    resources it owns (native handles, background threads, file handles,
///    network connections, etc.) MUST be completely drained and finished.
///    Callers may safely assume no further work related to this invocation
///    is outstanding once the call returns or throws.
/// 2. **`Task.cancel()` is not implicit provider cancellation**: If the
///    calling `Task` is cancelled while `transcribe` is awaiting, this does
///    NOT automatically cancel any underlying native or provider-side
///    operation (see D011 for the Rust FFI blocking-call boundary). A
///    conformer that wraps a cancellable native/provider operation MUST
///    explicitly coordinate cancellation (e.g. checking
///    `Task.isCancelled`/`Task.checkCancellation()` and/or forwarding
///    cancellation to the underlying resource) if it wishes to honor
///    cooperative cancellation. Absent such explicit coordination, the
///    underlying operation continues running to completion even after the
///    calling `Task` is cancelled, and callers must guard against stale
///    results (e.g. via job-ID validation).
/// 3. **No progress after completion**: `progressHandler` MUST NOT be
///    invoked after `transcribe` has returned a result or thrown an error.
///    All progress reporting must happen strictly before the terminal
///    return/throw of the call. Callers may assume that once `await
///    transcribe(...)` completes (successfully or with an error), no further
///    `progressHandler` invocations for that call will occur.
protocol TranscriptionEngineProtocol: Sendable {
    /// A stable identifier for this concrete engine implementation (e.g.
    /// `"whisper-local"` for `WhisperTranscriptionEngine`), used to tag
    /// execution provenance and Canonical JSON export metadata with the
    /// actual engine that performed the transcription (Finding R3). Callers
    /// MUST read this value dynamically from the injected engine instance
    /// rather than hardcoding a specific conformer's identifier, so that
    /// alternative or mock engines are labeled honestly. No global engine
    /// registry is introduced; this is a per-instance, protocol-level
    /// identity only.
    var engineID: String { get }

    /// Transcribes the audio file described by `request`.
    ///
    /// - Parameters:
    ///   - request: The transcription request describing the source file and options.
    ///   - progressHandler: Invoked with progress fraction (0.0–1.0) as transcription proceeds.
    ///     Must never be invoked after this method returns or throws (see the
    ///     protocol-level "Semantic Lifetime Contract" above).
    /// - Returns: The completed transcription result.
    func transcribe(
        request: TranscriptionRequest,
        progressHandler: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult
}
