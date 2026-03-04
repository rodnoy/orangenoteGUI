//
//  TranscriptionSegment.swift
//  OrangeNote
//
//  A single transcription segment with start/end timestamps and text.
//

import Foundation

/// Represents one segment of a transcription with timing information.
struct TranscriptionSegment: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let startTime: Double  // seconds
    let endTime: Double    // seconds
    let text: String

    /// Formats a time value in seconds to `HH:MM:SS` or `MM:SS` string.
    private static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Human-readable start time (e.g. "01:23" or "01:23:45").
    var formattedStartTime: String {
        Self.formatTime(startTime)
    }

    /// Human-readable end time (e.g. "01:23" or "01:23:45").
    var formattedEndTime: String {
        Self.formatTime(endTime)
    }

    /// Combined timestamp range string (e.g. "00:05 → 00:12").
    var timestampRange: String {
        "\(formattedStartTime) → \(formattedEndTime)"
    }
}
