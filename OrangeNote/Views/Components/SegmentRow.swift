//
//  SegmentRow.swift
//  OrangeNote
//
//  Displays a single transcription segment with timestamp and text.
//

import SwiftUI

/// A row displaying a single transcription segment with its timestamp range.
struct SegmentRow: View {
    let segment: TranscriptionSegment

    /// Whether this row is highlighted (e.g. from search).
    var isHighlighted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp badge
            Text(segment.timestampRange)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                }

            // Segment text
            Text(segment.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.08))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        SegmentRow(
            segment: TranscriptionSegment(
                id: UUID(),
                startTime: 5.0,
                endTime: 12.3,
                text: "Hello, this is a sample transcription segment."
            )
        )
        Divider()
        SegmentRow(
            segment: TranscriptionSegment(
                id: UUID(),
                startTime: 12.3,
                endTime: 18.7,
                text: "And this is another segment with some more text."
            ),
            isHighlighted: true
        )
    }
    .padding()
    .frame(width: 500)
}
