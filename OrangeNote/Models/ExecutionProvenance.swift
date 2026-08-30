//
//  ExecutionProvenance.swift
//  OrangeNote
//
//  Orchestration-layer metadata describing how a transcription result was produced
//  (source file, model, engine), tracked alongside the domain `TranscriptionResult`
//  without extending it (Task 2.13 / Finding B3).
//

import Foundation

/// Captures the execution provenance of a transcription run: which source file was
/// transcribed, which model was used, and which engine produced the result.
///
/// This is deliberately kept separate from the domain `TranscriptionResult` model —
/// it lives at the view-model/orchestration layer so that `TranscriptionResult` stays
/// focused on transcription content. Consumers (e.g. `ExportViewModel`) use this to
/// populate honest Canonical JSON v1 metadata instead of hardcoded placeholders.
struct ExecutionProvenance: Equatable, Sendable {
    /// The display name of the source audio/document file that was transcribed or
    /// imported (e.g. `"interview.wav"`), always known and never fabricated.
    let sourceFileName: String

    /// The real URL of the source audio file on disk, if one is actually known (Task
    /// 2.20 / Finding F3).
    ///
    /// `nil` for results that did not originate from a local file transcription run in
    /// this session (e.g. imported Canonical JSON transcripts) — in that case only
    /// `sourceFileName` is honestly recoverable, and callers must never fabricate a
    /// fake file URL to fill this gap.
    let sourceURL: URL?

    /// The model identifier used for transcription (e.g. "base", "large-v3").
    let modelName: String

    /// The stable identifier of the transcription engine used (e.g. "whisper-local").
    let engineID: String

    /// Primary initializer taking honest source metadata directly: a required display
    /// `sourceFileName` and an optional real `sourceURL` (Task 2.20 / Finding F3).
    init(sourceFileName: String, sourceURL: URL? = nil, modelName: String, engineID: String) {
        self.sourceFileName = sourceFileName
        self.sourceURL = sourceURL
        self.modelName = modelName
        self.engineID = engineID
    }

    /// Convenience initializer for local transcription runs where a real source `URL`
    /// is known; `sourceFileName` is derived from `sourceURL.lastPathComponent`.
    init(sourceURL: URL, modelName: String, engineID: String) {
        self.sourceFileName = sourceURL.lastPathComponent
        self.sourceURL = sourceURL
        self.modelName = modelName
        self.engineID = engineID
    }
}
