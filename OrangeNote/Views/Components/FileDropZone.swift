//
//  FileDropZone.swift
//  OrangeNote
//
//  Drag-and-drop area for audio file selection with visual feedback.
//

import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts audio files via drag-and-drop.
struct FileDropZone: View {
    /// Called when a valid audio file is dropped.
    let onDrop: (URL) -> Void

    /// Called when the "Choose File" button is tapped.
    let onChooseFile: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: isTargeted)

            Text("Drop Audio File Here")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("or")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onChooseFile) {
                Label("Choose File", systemImage: "folder.badge.plus")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Text("Supports MP3, WAV, M4A, FLAC, OGG, and more")
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
        .onDrop(of: [.audio, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }

    // MARK: - Private

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try loading as file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                DispatchQueue.main.async {
                    onDrop(url)
                }
            }
            return true
        }

        return false
    }
}

// MARK: - Preview

#Preview {
    FileDropZone(
        onDrop: { url in print("Dropped: \(url)") },
        onChooseFile: { print("Choose file tapped") }
    )
    .padding()
    .frame(width: 400)
}
