//
//  BatchTranscriptionSummary.swift
//  OrangeNote
//
//  Aggregated summary of batch transcription results (Task 3.9 / D016).
//

import Foundation

/// Aggregated summary of the execution outcomes of a batch transcription job.
struct BatchTranscriptionSummary: Sendable, Equatable, Codable, CustomStringConvertible {
    /// Total number of items submitted for processing in the batch.
    let totalCount: Int

    /// Number of items that completed transcription and persistence successfully.
    let succeededCount: Int

    /// Number of items that encountered an error during transcription or saving.
    let failedCount: Int

    /// Number of items skipped (e.g. output already exists or pre-marked skipped).
    let skippedCount: Int

    /// Number of items cancelled before completion.
    let cancelledCount: Int

    /// Whether all submitted items in the batch succeeded without any failures, skips, or cancellations.
    var isAllSucceeded: Bool {
        totalCount > 0 && succeededCount == totalCount
    }

    /// Whether any item in the batch encountered a failure.
    var hasFailures: Bool {
        failedCount > 0
    }

    /// Total number of items that have reached a terminal state (succeeded, failed, skipped, or cancelled).
    var completedCount: Int {
        succeededCount + failedCount + skippedCount + cancelledCount
    }

    /// Initializes a summary with explicit counts.
    init(
        totalCount: Int,
        succeededCount: Int,
        failedCount: Int,
        skippedCount: Int,
        cancelledCount: Int
    ) {
        self.totalCount = totalCount
        self.succeededCount = succeededCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.cancelledCount = cancelledCount
    }

    /// Computes a summary from an array of processed `BatchItem`s.
    init(items: [BatchItem]) {
        self.totalCount = items.count
        var succeeded = 0
        var failed = 0
        var skipped = 0
        var cancelled = 0

        for item in items {
            switch item.status {
            case .succeeded:
                succeeded += 1
            case .failed:
                failed += 1
            case .skipped:
                skipped += 1
            case .cancelled:
                cancelled += 1
            case .queued, .transcribing, .saving:
                break
            }
        }

        self.succeededCount = succeeded
        self.failedCount = failed
        self.skippedCount = skipped
        self.cancelledCount = cancelled
    }

    var description: String {
        "BatchSummary(total: \(totalCount), succeeded: \(succeededCount), failed: \(failedCount), skipped: \(skippedCount), cancelled: \(cancelledCount))"
    }
}

extension Sequence where Element == BatchItem {
    /// Computes the `BatchTranscriptionSummary` for this sequence of batch items.
    var batchSummary: BatchTranscriptionSummary {
        BatchTranscriptionSummary(items: Array(self))
    }
}
