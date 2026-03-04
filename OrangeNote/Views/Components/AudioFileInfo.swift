//
//  AudioFileInfo.swift
//  OrangeNote
//
//  Displays metadata about a selected audio file.
//

import SwiftUI

/// Shows file name, size, and format information for a selected audio file.
struct AudioFileInfo: View {
    let fileName: String
    let fileSize: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let fileSize {
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // File extension badge
            let ext = (fileName as NSString).pathExtension.uppercased()
            if !ext.isEmpty {
                Text(ext)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        }
    }
}

// MARK: - Preview

#Preview {
    AudioFileInfo(
        fileName: "interview_recording.mp3",
        fileSize: "24.5 MB"
    )
    .padding()
    .frame(width: 400)
}
