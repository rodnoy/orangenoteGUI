//
//  MockTranscriptionEngine.swift
//  OrangeNoteTests
//
//  Shared, concurrency-safe `TranscriptionEngineProtocol` test double used
//  across engine contract tests and view model integration tests. Modeled
//  as an `actor` (rather than a `class` with `@unchecked Sendable`) so all
//  mutable state is synchronized by the Swift runtime, eliminating the
//  unsynchronized data-race risk of the previous per-test mock duplicates.
//

import Foundation
@testable import OrangeNote

/// Error type usable by tests to verify error propagation through the
/// `TranscriptionEngineProtocol` contract.
struct MockTranscriptionEngineError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// An actor-based mock `TranscriptionEngineProtocol` conformer.
///
/// Honors the protocol's semantic lifetime contract:
/// - All configured `progressValuesToEmit` are reported strictly before
///   `transcribe` returns or throws (drain guarantee).
/// - No progress reporting occurs after the terminal return/throw.
/// - An optional `delaySeconds` allows tests to create a window during which
///   the "operation" is still in flight (e.g. to exercise stale-completion /
///   cancellation-boundary behavior in `TranscriptionViewModel`), without
///   ever invoking `progressHandler` after that delay completes.
actor MockTranscriptionEngine: TranscriptionEngineProtocol {
    /// The stable identifier for this mock engine (Finding R3). Distinct from
    /// `WhisperTranscriptionEngine.stableEngineID` by default so tests can
    /// assert that `TranscriptionViewModel` snapshots the actual injected
    /// engine's identity rather than hardcoding the Whisper engine's ID.
    /// `nonisolated` (a plain `let`) so it is synchronously readable across
    /// actor boundaries, matching the protocol's non-async requirement.
    nonisolated let engineID: String

    /// The last request received by `transcribe(request:progressHandler:)`.
    private(set) var receivedRequest: TranscriptionRequest?

    /// All requests received across successive invocations, in order.
    private(set) var receivedRequests: [TranscriptionRequest] = []

    /// The progress values actually reported to `progressHandler` during the
    /// most recent invocation, in order, recorded before returning/throwing.
    private(set) var reportedProgressValues: [Float] = []

    /// Number of times `transcribe` has been invoked.
    private(set) var invocationCount: Int = 0

    /// If set, `transcribe` throws this error instead of returning a result.
    private let errorToThrow: Error?

    /// Optional sequence of errors (or nil for success) to throw per invocation.
    private var errorsSequence: [Error?]

    /// The result to return when `errorToThrow` is `nil` and `resultsSequence` is empty.
    private let resultToReturn: TranscriptionResult

    /// Optional queue of results to return across successive invocations, in order
    /// (Task 2.21 / Finding F5). Lets a single mock instance model a realistic
    /// multi-run scenario (e.g. the user replacing the selected file and re-running
    /// transcription) without needing a mutable `resultToReturn`. Falls back to
    /// `resultToReturn` once exhausted. `nil`/empty (the default) preserves prior
    /// single-result behavior for all existing call sites.
    private var resultsSequence: [TranscriptionResult]

    /// Progress values to emit via `progressHandler` before returning/throwing.
    private let progressValuesToEmit: [Float]

    /// Optional delay (in seconds) before returning/throwing, letting tests
    /// interleave cancellation/superseding with an in-flight mock "call".
    ///
    /// NOTE (Finding R4): `Task.sleep` is cancellable, so a `delaySeconds`-only
    /// fake responds to `Task.cancel()` by unwinding immediately (via `try?`)
    /// rather than continuing to run — unlike a genuinely non-cooperative
    /// resource such as a blocking Rust FFI call (D011). Tests that need to
    /// verify the drain contract holds even when the caller's `Task` is
    /// cancelled should use `completionGate` instead, which never observes or
    /// responds to cancellation.
    private let delaySeconds: Double

    /// Optional controllable, non-cancellation-sensitive completion gate
    /// (Finding R4). When set, `transcribe` suspends on `completionGate.wait()`
    /// after emitting progress and does not resume until the test explicitly
    /// calls `completionGate.open()`, regardless of whether the calling
    /// `Task` has been cancelled. This lets tests verify that engine drain
    /// waits for the underlying operation to truly finish rather than for
    /// cancellation to merely propagate.
    private let completionGate: CompletionGate?
    private var completionGatesSequence: [CompletionGate]

    init(
        resultToReturn: TranscriptionResult,
        progressValuesToEmit: [Float] = [],
        errorToThrow: Error? = nil,
        delaySeconds: Double = 0,
        completionGate: CompletionGate? = nil,
        engineID: String = "mock-engine",
        resultsSequence: [TranscriptionResult] = [],
        errorsSequence: [Error?] = [],
        completionGatesSequence: [CompletionGate] = []
    ) {
        self.completionGatesSequence = completionGatesSequence
        self.resultToReturn = resultToReturn
        self.progressValuesToEmit = progressValuesToEmit
        self.errorToThrow = errorToThrow
        self.delaySeconds = delaySeconds
        self.completionGate = completionGate
        self.engineID = engineID
        self.resultsSequence = resultsSequence
        self.errorsSequence = errorsSequence
    }

    func transcribe(
        request: TranscriptionRequest,
        progressHandler: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        invocationCount += 1
        receivedRequest = request
        receivedRequests.append(request)
        reportedProgressValues = []

        for value in progressValuesToEmit {
            progressHandler(value)
            reportedProgressValues.append(value)
        }

        if delaySeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }

        if !completionGatesSequence.isEmpty {
            let gate = completionGatesSequence.removeFirst()
            await gate.wait()
        } else if let completionGate {
            await completionGate.wait()
        }

        if !errorsSequence.isEmpty {
            if let error = errorsSequence.removeFirst() {
                throw error
            }
        } else if let errorToThrow {
            throw errorToThrow
        }

        if !resultsSequence.isEmpty {
            return resultsSequence.removeFirst()
        }
        return resultToReturn
    }
}
