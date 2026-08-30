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
    ///
    /// - Parameters:
    ///   - result: The transcription result to export.
    ///   - sourceFileName: The display name of the source file to embed in Canonical
    ///     JSON v1 metadata (Task 2.20 / Finding F3), if explicitly known (e.g. from
    ///     `ExecutionProvenance.sourceFileName` on an imported result with no real
    ///     `sourceURL`). `nil` (the default) falls back to `sourceURL?.lastPathComponent`,
    ///     and finally to the honest placeholder `"unknown"` if neither is known.
    ///   - sourceURL: The URL of the original source audio file, used to populate Canonical
    ///     JSON v1 metadata (D013) when `selectedFormat == .json`. Pass the real
    ///     `ExecutionProvenance.sourceURL` from the orchestration layer when available. `nil`
    ///     (the default) is used honestly for results with no known source file (e.g.
    ///     imported transcripts) rather than fabricating a fake path.
    ///   - modelName: The transcription model identifier to embed in Canonical JSON v1
    ///     metadata. Pass the real `ExecutionProvenance.modelName` when available. Defaults
    ///     to "unknown" — an honest placeholder, never a fabricated model name.
    ///   - engineID: The transcription engine identifier to embed in Canonical JSON v1
    ///     metadata. Pass the real `ExecutionProvenance.engineID` when available. Defaults
    ///     to the honest placeholder `"unknown"` — never a fabricated local engine ID
    ///     (Task 2.16 / Finding R1): provenance being unavailable does not imply the
    ///     result actually came from `whisper-local`.
    func generateExport(
        result: TranscriptionResult,
        sourceFileName: String? = nil,
        sourceURL: URL? = nil,
        modelName: String = "unknown",
        engineID: String = "unknown"
    ) {
        errorMessage = nil
        do {
            if selectedFormat == .json {
                // Honest fallback chain (Task 2.20 / Finding F3): an explicitly known
                // `sourceFileName` (e.g. recovered from a Canonical import with no real
                // `sourceURL`) wins; otherwise derive from `sourceURL` when a real local
                // file is known; otherwise fall back to the honest placeholder
                // `"unknown"` rather than fabricating a fake file path.
                let effectiveFileName = sourceFileName ?? sourceURL?.lastPathComponent ?? "unknown"
                let document = try CanonicalTranscriptionSerializer.makeDocument(
                    from: result,
                    sourceFileName: effectiveFileName,
                    sourceURL: sourceURL,
                    modelName: modelName,
                    engineID: engineID,
                    // Privacy-safe by default: the real absolute file path is never
                    // embedded in exported Canonical JSON unless a caller explicitly opts
                    // in via `CanonicalTranscriptionSerializer.makeDocument` directly.
                    includeSourcePath: false
                )
                let data = try CanonicalTranscriptionSerializer.encode(document)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    throw OrangeNoteFFIError.decodingError("Failed to encode canonical document to JSON")
                }
                exportedContent = jsonString
            } else {
                exportedContent = try engine.export(result: result, format: selectedFormat)
            }
        } catch {
            errorMessage = error.localizedDescription
            exportedContent = nil
        }
    }

    /// Opens a save panel and writes the exported content to a file.
    func saveToFile(result: TranscriptionResult, provenance: ExecutionProvenance? = nil) {
        // Always regenerate to ensure fresh content for current transcription
        generateExport(
            result: result,
            sourceFileName: provenance?.sourceFileName,
            sourceURL: provenance?.sourceURL,
            modelName: provenance?.modelName ?? "unknown",
            engineID: provenance?.engineID ?? "unknown"
        )

        guard let content = exportedContent else {
            errorMessage = L10n.localizedString("error.noContent")
            return
        }

        let format = selectedFormat

        // Present the save panel on the next main run-loop turn rather than synchronously
        // within the caller's current SwiftUI update transaction. `saveToFile` is invoked
        // directly from `onChange` handlers (menu commands) and view button actions; calling
        // `NSSavePanel().runModal()` (a blocking modal run loop) synchronously from within
        // such a callback can re-enter SwiftUI's view-update machinery mid-transaction,
        // which manifests as an `EXC_BREAKPOINT` trap. Deferring to `DispatchQueue.main.async`
        // lets the current update transaction finish first, avoiding the reentrancy.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let panel = NSSavePanel()
            panel.title = L10n.localizedString("export.panelTitle")
            panel.nameFieldStringValue = "transcription.\(format.fileExtension)"
            panel.allowedContentTypes = [
                UTType(filenameExtension: format.fileExtension) ?? .plainText
            ]

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    self.exportSuccess = true
                    // Reset success after a delay
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        self.exportSuccess = false
                    }
                } catch {
                    self.errorMessage = String(format: L10n.localizedString("error.saveFailed"), error.localizedDescription)
                }
            }
        }
    }

    /// Copies the exported content to the clipboard.
    func copyToClipboard(result: TranscriptionResult, provenance: ExecutionProvenance? = nil) {
        // Always regenerate to ensure fresh content for current transcription
        generateExport(
            result: result,
            sourceFileName: provenance?.sourceFileName,
            sourceURL: provenance?.sourceURL,
            modelName: provenance?.modelName ?? "unknown",
            engineID: provenance?.engineID ?? "unknown"
        )

        guard let content = exportedContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
