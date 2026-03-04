//
//  TranscriptionResult.swift
//  OrangeNote
//
//  Full transcription result containing all segments and metadata.
//

import Foundation

/// The complete result of a transcription operation.
struct TranscriptionResult: Codable, Sendable {
    let segments: [TranscriptionSegment]
    let fullText: String
    let language: String
    let duration: Double

    /// Human-readable duration string (e.g. "5m 23s").
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Number of segments in the result.
    var segmentCount: Int {
        segments.count
    }

    /// Word count of the full text.
    var wordCount: Int {
        fullText.split(separator: " ").count
    }
}
