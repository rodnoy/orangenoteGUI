//
//  WhisperTranscriptionEngine.swift
//  OrangeNote
//
//  `TranscriptionEngineProtocol` adapter wrapping an instantiated
//  `OrangeNoteEngine` (local Whisper FFI) instance (D004).
//

import Foundation

/// Default chunk/overlap durations used when a chunking-enabled request
/// omits explicit values. Mirrors `AppSettings`' stored defaults
/// (`chunkDuration = 30`, `overlapDuration = 5`).
enum WhisperTranscriptionDefaults {
    static let chunkDurationSeconds: Int = 30
    static let overlapDurationSeconds: Int = 5
}

/// Resolved, FFI-ready parameters derived from a backend-agnostic
/// `TranscriptionRequest`. Extracted as a pure, side-effect-free mapping
/// so it is directly unit-testable without invoking the real Whisper FFI.
struct WhisperFFIParameters: Equatable {
    let path: String
    let language: String
    let translate: Bool
    let chunkSeconds: Int
    let overlapSeconds: Int
}

/// `TranscriptionEngineProtocol` adapter that delegates to an instantiated
/// `OrangeNoteEngine` for local, offline Whisper transcription (D003).
final class WhisperTranscriptionEngine: TranscriptionEngineProtocol {
    /// Single stable identifier source for the local Whisper engine (D003: local Whisper
    /// is the default engine). Used both when tagging execution provenance and as the
    /// Canonical JSON v1 `engine.id` value, so no other call site needs to hardcode the
    /// literal string.
    static let stableEngineID = "whisper-local"

    /// `TranscriptionEngineProtocol` conformance (Finding R3): exposes the
    /// same stable identifier as `stableEngineID` so callers can snapshot
    /// the actual injected engine's identity dynamically instead of
    /// hardcoding this type.
    var engineID: String { Self.stableEngineID }

    private let engine: WhisperEngineClient

    /// - Parameter engine: The `WhisperEngineClient` instance to delegate to.
    ///   Defaults to a freshly created `OrangeNoteEngine`; no singleton is
    ///   assumed. Tests may inject a lightweight mock conforming to
    ///   `WhisperEngineClient` instead of the real FFI-backed engine.
    init(engine: WhisperEngineClient = OrangeNoteEngine()) {
        self.engine = engine
    }

    func transcribe(
        request: TranscriptionRequest,
        progressHandler: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        let modelPath = try await engine.modelPath(name: request.modelName)
        let parameters = Self.makeFFIParameters(request: request, modelPath: modelPath)

        if request.chunkingEnabled {
            return try await engine.transcribeFileChunked(
                path: parameters.path,
                modelPath: modelPath,
                language: parameters.language,
                translate: parameters.translate,
                chunkSeconds: parameters.chunkSeconds,
                overlapSeconds: parameters.overlapSeconds,
                progressCallback: progressHandler
            )
        } else {
            return try await engine.transcribeFile(
                path: parameters.path,
                modelPath: modelPath,
                language: parameters.language,
                translate: parameters.translate,
                progressCallback: progressHandler
            )
        }
    }

    /// Pure mapping from a `TranscriptionRequest` to FFI-ready parameters.
    ///
    /// - `language` maps `nil` (auto-detect) to `"auto"`, matching the
    ///   convention already used by `OrangeNoteEngine.transcribeFile`/
    ///   `transcribeFileChunked` (which treat `"auto"` as "no language arg").
    /// - `chunkSeconds`/`overlapSeconds` fall back to
    ///   `WhisperTranscriptionDefaults` when the request enables chunking
    ///   but omits explicit durations.
    static func makeFFIParameters(request: TranscriptionRequest, modelPath: String) -> WhisperFFIParameters {
        let language = request.language ?? "auto"
        let chunkSeconds = Int(request.chunkDurationSeconds ?? Double(WhisperTranscriptionDefaults.chunkDurationSeconds))
        let overlapSeconds = Int(request.overlapDurationSeconds ?? Double(WhisperTranscriptionDefaults.overlapDurationSeconds))

        return WhisperFFIParameters(
            path: request.sourceURL.path,
            language: language,
            translate: request.translateToEnglish,
            chunkSeconds: chunkSeconds,
            overlapSeconds: overlapSeconds
        )
    }
}
