//
//  ProgressIndicator.swift
//  OrangeNote
//
//  Custom progress indicator with percentage display.
//

import SwiftUI

/// A styled progress bar with percentage label and optional status text.
struct ProgressIndicator: View {
    /// Progress value (0.0–1.0).
    let progress: Float

    /// Optional status message displayed below the bar.
    var statusMessage: String?

    /// Whether the progress is indeterminate.
    var isIndeterminate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isIndeterminate {
                    ProgressView()
                        .controlSize(.small)
                    Text("progress.processing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: Double(progress))
                        .progressViewStyle(.linear)
                        .tint(.orange)

                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Determinate") {
    ProgressIndicator(
        progress: 0.65,
        statusMessage: "Transcribing chunk 3 of 5…"
    )
    .padding()
    .frame(width: 400)
}

#Preview("Indeterminate") {
    ProgressIndicator(
        progress: 0,
        statusMessage: "Loading model…",
        isIndeterminate: true
    )
    .padding()
    .frame(width: 400)
}
