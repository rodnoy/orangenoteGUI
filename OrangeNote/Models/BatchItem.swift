//
//  BatchItem.swift
//  OrangeNote
//
//  Represents an individual file's progress and outcome within a batch
//  transcription queue (Task 3.2 / D019).
//

import Foundation

/// The lifecycle status of a single `BatchItem` within a batch transcription run.
///
/// These are the exact approved statuses (D019 / plan Task 3.2) — deliberately
/// specific rather than generic pending/processing/completed states, so that the
/// batch UI and coordinator can distinguish each phase of per-item work.
enum BatchItemStatus: Equatable, Sendable, Codable {
    /// Queued and not yet started.
    case queued
    /// Actively being transcribed by the Whisper engine.
    case transcribing
    /// Transcription finished; result is being written to disk.
    case saving
    /// Completed successfully; `result` and `outputURL` are populated.
    case succeeded
    /// Failed at some stage; `errorMessage` describes the failure.
    case failed
    /// Skipped without attempting transcription (e.g. output already exists).
    case skipped
    /// Cancelled before completion (stop-after-current policy, D021).
    case cancelled
}

/// A single file's progress and outcome within an in-memory batch transcription
/// queue (D019 — no persistent database layer backs the batch queue).
struct BatchItem: Identifiable, Equatable, Sendable {
    /// Stable unique identifier for this batch item, distinct from its source file.
    let id: UUID

    /// The source audio file URL to be transcribed.
    let sourceURL: URL

    /// The destination URL the transcription result was (or will be) written to,
    /// once known.
    var outputURL: URL?

    /// The current lifecycle status of this item.
    var status: BatchItemStatus

    /// Progress of the current status, in the `0...1` range where applicable.
    var progress: Float

    /// Human-readable failure description, populated when `status == .failed`.
    var errorMessage: String?

    /// The transcription result, populated when `status == .succeeded`.
    var result: TranscriptionResult?

    /// Creates a freshly-collected batch item, queued and not yet processed.
    init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputURL: URL? = nil,
        status: BatchItemStatus = .queued,
        progress: Float = 0,
        errorMessage: String? = nil,
        result: TranscriptionResult? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.result = result
    }
}
