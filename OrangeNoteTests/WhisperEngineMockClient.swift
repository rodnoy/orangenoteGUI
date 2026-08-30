//
//  WhisperEngineMockClient.swift
//  OrangeNoteTests
//
//  Actor-based `WhisperEngineClient` test double used to exercise
//  `WhisperTranscriptionEngine` adapter-level orchestration (dispatch
//  selection, parameter forwarding, progress bridging, result mapping,
//  and error propagation) without invoking the real Rust/Whisper FFI.
//

import Foundation
@testable import OrangeNote

/// Error type usable by tests to verify error propagation through
/// `WhisperEngineClient` calls.
struct WhisperEngineMockClientError: Error, Equatable {
    let message: String
}

/// Records every call made against the `WhisperEngineClient` seam so tests
/// can assert on dispatch selection (`transcribeFile` vs
/// `transcribeFileChunked`) and exact parameter forwarding.
actor WhisperEngineMockClient: WhisperEngineClient {

    /// Parameters captured from a `transcribeFile` invocation.
    struct TranscribeFileCall: Equatable {
        let path: String
        let modelPath: String
        let language: String
        let translate: Bool
    }

    /// Parameters captured from a `transcribeFileChunked` invocation.
    struct TranscribeFileChunkedCall: Equatable {
        let path: String
        let modelPath: String
        let language: String
        let translate: Bool
        let chunkSeconds: Int
        let overlapSeconds: Int
    }

    // MARK: - Configuration

    private let modelPathToReturn: String
    private let modelPathErrorToThrow: Error?
    private let resultToReturn: TranscriptionResult
    private let progressValuesToEmit: [Float]
    private let transcribeErrorToThrow: Error?

    /// Optional controllable, non-cancellation-sensitive completion gate
    /// (Finding R4). When set, `transcribeFile`/`transcribeFileChunked`
    /// suspend on `completionGate.wait()` after emitting progress and before
    /// returning/throwing, so tests can verify that
    /// `WhisperTranscriptionEngine` genuinely awaits full completion of the
    /// underlying client call (drain contract) rather than returning early.
    private let completionGate: CompletionGate?

    // MARK: - Recorded State

    private(set) var requestedModelName: String?
    private(set) var transcribeFileCall: TranscribeFileCall?
    private(set) var transcribeFileChunkedCall: TranscribeFileChunkedCall?
    private(set) var reportedProgressValues: [Float] = []
    private(set) var transcribeFileInvocationCount: Int = 0
    private(set) var transcribeFileChunkedInvocationCount: Int = 0

    init(
        modelPathToReturn: String = "/models/mock.bin",
        modelPathErrorToThrow: Error? = nil,
        resultToReturn: TranscriptionResult,
        progressValuesToEmit: [Float] = [],
        transcribeErrorToThrow: Error? = nil,
        completionGate: CompletionGate? = nil
    ) {
        self.modelPathToReturn = modelPathToReturn
        self.modelPathErrorToThrow = modelPathErrorToThrow
        self.resultToReturn = resultToReturn
        self.progressValuesToEmit = progressValuesToEmit
        self.transcribeErrorToThrow = transcribeErrorToThrow
        self.completionGate = completionGate
    }

    func modelPath(name: String) throws -> String {
        requestedModelName = name
        if let modelPathErrorToThrow {
            throw modelPathErrorToThrow
        }
        return modelPathToReturn
    }

    func transcribeFile(
        path: String,
        modelPath: String,
        language: String,
        translate: Bool,
        progressCallback: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        transcribeFileInvocationCount += 1
        transcribeFileCall = TranscribeFileCall(
            path: path,
            modelPath: modelPath,
            language: language,
            translate: translate
        )

        for value in progressValuesToEmit {
            progressCallback(value)
            reportedProgressValues.append(value)
        }

        if let completionGate {
            await completionGate.wait()
        }

        if let transcribeErrorToThrow {
            throw transcribeErrorToThrow
        }
        return resultToReturn
    }

    func transcribeFileChunked(
        path: String,
        modelPath: String,
        language: String,
        translate: Bool,
        chunkSeconds: Int,
        overlapSeconds: Int,
        progressCallback: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        transcribeFileChunkedInvocationCount += 1
        transcribeFileChunkedCall = TranscribeFileChunkedCall(
            path: path,
            modelPath: modelPath,
            language: language,
            translate: translate,
            chunkSeconds: chunkSeconds,
            overlapSeconds: overlapSeconds
        )

        for value in progressValuesToEmit {
            progressCallback(value)
            reportedProgressValues.append(value)
        }

        if let completionGate {
            await completionGate.wait()
        }

        if let transcribeErrorToThrow {
            throw transcribeErrorToThrow
        }
        return resultToReturn
    }
}
