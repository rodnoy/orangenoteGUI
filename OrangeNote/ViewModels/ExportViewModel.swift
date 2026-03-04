//
//  ExportViewModel.swift
//  OrangeNote
//
//  View model for exporting transcription results to various formats.
//

import SwiftUI
import UniformTypeIdentifiers

/// Manages export format selection, preview, and file saving.
@MainActor
final class ExportViewModel: ObservableObject {
    // MARK: - Published State

    /// Currently selected export format.
    @Published var selectedFormat: ExportFormat = .txt

    /// Preview of the exported content.
    @Published var exportedContent: String?

    /// Error message to display.
    @Published var errorMessage: String?

    /// Whether export was successful (for showing confirmation).
    @Published var exportSuccess: Bool = false

    // MARK: - Private

    private let engine = OrangeNoteEngine()

    // MARK: - Actions

    /// Generates the export content for the given result and selected format.
    func generateExport(result: TranscriptionResult) {
        errorMessage = nil
        do {
            exportedContent = try engine.export(result: result, format: selectedFormat)
        } catch {
            errorMessage = error.localizedDescription
            exportedContent = nil
        }
    }

    /// Opens a save panel and writes the exported content to a file.
    func saveToFile(result: TranscriptionResult) {
        // Ensure content is generated
        if exportedContent == nil {
            generateExport(result: result)
        }

        guard let content = exportedContent else {
            errorMessage = "No content to export"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Transcription"
        panel.nameFieldStringValue = "transcription.\(selectedFormat.fileExtension)"
        panel.allowedContentTypes = [
            UTType(filenameExtension: selectedFormat.fileExtension) ?? .plainText
        ]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportSuccess = true
                // Reset success after a delay
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    exportSuccess = false
                }
            } catch {
                errorMessage = "Failed to save file: \(error.localizedDescription)"
            }
        }
    }

    /// Copies the exported content to the clipboard.
    func copyToClipboard(result: TranscriptionResult) {
        if exportedContent == nil {
            generateExport(result: result)
        }

        guard let content = exportedContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
