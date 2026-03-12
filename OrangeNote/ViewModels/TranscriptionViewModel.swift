//
//  TranscriptionViewModel.swift
//  OrangeNote
//
//  Main view model for file selection, transcription control, and progress tracking.
//

import SwiftUI
import UniformTypeIdentifiers

/// Manages the transcription workflow: file selection, transcription execution, and results.
@MainActor
final class TranscriptionViewModel: ObservableObject {
    // MARK: - Published State

    /// URL of the selected audio file.
    @Published var selectedFileURL: URL?

    /// Whether a transcription is currently in progress.
    @Published var isTranscribing: Bool = false

    /// Transcription progress (0.0–1.0).
    @Published var progress: Float = 0.0

    /// The transcription result, available after successful completion.
    @Published var result: TranscriptionResult?

    /// Error message to display to the user.
    @Published var errorMessage: String?

    /// Current status message.
    @Published var statusMessage: String = L10n.localizedString("status.ready")

    // MARK: - Private

    private let engine = OrangeNoteEngine()
    private var transcriptionTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Display name of the selected file.
    var selectedFileName: String? {
        selectedFileURL?.lastPathComponent
    }

    /// Formatted file size of the selected file.
    var selectedFileSize: String? {
        guard let url = selectedFileURL else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Whether the start button should be enabled.
    var canStartTranscription: Bool {
        selectedFileURL != nil && !isTranscribing
    }

    // MARK: - Actions

    /// Opens a file picker for audio files.
    func selectFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.localizedString("transcription.selectFile")
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.mp3,
            UTType(filenameExtension: "ogg") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "m4a") ?? .audio,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            result = nil
            errorMessage = nil
            statusMessage = L10n.localizedString("status.fileSelected")
        }
    }

    /// Handles a file dropped onto the drop zone.
    func handleDroppedFile(_ url: URL) {
        // Validate that the file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = L10n.localizedString("error.fileNotFound")
            return
        }

        // Validate file extension
        let validExtensions = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"]
        let fileExtension = url.pathExtension.lowercased()
        if !validExtensions.contains(fileExtension) {
            errorMessage = String(format: L10n.localizedString("error.unsupportedFormat"), fileExtension)
            return
        }

        selectedFileURL = url
        result = nil
        errorMessage = nil
            statusMessage = L10n.localizedString("status.fileSelected")
    }

    /// Starts the transcription process.
    func startTranscription(settings: AppSettings) {
        guard let fileURL = selectedFileURL else {
            errorMessage = L10n.localizedString("error.noFile")
            return
        }

        errorMessage = nil
        isTranscribing = true
        progress = 0.0
        statusMessage = L10n.localizedString("status.preparing")

        transcriptionTask = Task {
            do {
                // Resolve model path
                let modelPathString = try engine.modelPath(name: settings.selectedModel)
                statusMessage = L10n.localizedString("status.transcribing")

                let transcriptionResult: TranscriptionResult

                let shouldTranslate = settings.language != "en" && settings.translateToEnglish

                if settings.useChunking {
                    transcriptionResult = try await engine.transcribeFileChunked(
                        path: fileURL.path,
                        modelPath: modelPathString,
                        language: settings.language,
                        translate: shouldTranslate,
                        chunkSeconds: settings.chunkDuration,
                        overlapSeconds: settings.overlapDuration,
                        progressCallback: { [weak self] progressValue in
                            Task { @MainActor in
                                self?.progress = progressValue
                            }
                        }
                    )
                } else {
                    transcriptionResult = try await engine.transcribeFile(
                        path: fileURL.path,
                        modelPath: modelPathString,
                        language: settings.language,
                        translate: shouldTranslate,
                        progressCallback: { [weak self] progressValue in
                            Task { @MainActor in
                                self?.progress = progressValue
                            }
                        }
                    )
                }

                result = transcriptionResult
                progress = 1.0
                statusMessage = L10n.localizedString("status.complete")

                NotificationService.sendTranscriptionComplete(
                    fileName: fileURL.lastPathComponent,
                    segmentCount: transcriptionResult.segmentCount,
                    duration: transcriptionResult.duration
                )
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    statusMessage = L10n.localizedString("status.failed")
                }
            }

            isTranscribing = false
        }
    }

    /// Cancels the current transcription.
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
        progress = 0.0
        statusMessage = L10n.localizedString("status.cancelled")
    }

    /// Clears the current result and resets state.
    func clearResult() {
        result = nil
        progress = 0.0
        errorMessage = nil
        statusMessage = L10n.localizedString("status.ready")
    }
}
