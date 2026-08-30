//
//  FileDropZone.swift
//  OrangeNote
//
//  Drag-and-drop area for audio file and folder selection with visual feedback.
//

import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts audio files and folders via drag-and-drop.
///
/// This view is purely presentational: actual drop handling is attached at the
/// page level (see `TranscriptionView`) so the drop target remains active across
/// the entire view hierarchy, even after a file has been selected. `isTargeted`
/// is driven externally by the page-level drop target so this view's highlight
/// stays in sync with the shared drag-hover state.
struct FileDropZone: View {
    /// Called when the "Choose File" button is tapped.
    let onChooseFile: () -> Void

    /// Optional callback when "Choose Folder" is tapped.
    var onChooseFolder: (() -> Void)? = nil

    /// Whether the page-level drop target is currently being hovered by a drag (drives the visual highlight).
    var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: isTargeted)

            Text(L10n.string("dropzone.title"))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(L10n.string("dropzone.or"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: onChooseFile) {
                    Label(L10n.string("dropzone.chooseFile"), systemImage: "doc.badge.plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if let onChooseFolder = onChooseFolder {
                    Button(action: onChooseFolder) {
                        Label(L10n.string("dropzone.chooseFolder"), systemImage: "folder.badge.plus")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(L10n.string("dropzone.formats"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.orange : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.orange.opacity(0.05) : Color.clear)
                }
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

// MARK: - Preview

#Preview {
    FileDropZone(
        onChooseFile: { print("Choose file tapped") },
        onChooseFolder: { print("Choose folder tapped") }
    )
    .padding()
    .frame(width: 450)
}
