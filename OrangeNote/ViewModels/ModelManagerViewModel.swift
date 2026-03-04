//
//  ModelManagerViewModel.swift
//  OrangeNote
//
//  View model for managing Whisper model downloads and availability.
//

import SwiftUI

/// Manages the list of available Whisper models and their download status.
@MainActor
final class ModelManagerViewModel: ObservableObject {
    // MARK: - Published State

    /// All available models with their cache status.
    @Published var models: [WhisperModel] = []

    /// Whether the model list is being loaded.
    @Published var isLoading: Bool = false

    /// Name of the model currently being downloaded.
    @Published var downloadingModel: String?

    /// Download progress (0.0–1.0) for the active download.
    @Published var downloadProgress: Float = 0.0

    /// Error message to display.
    @Published var errorMessage: String?

    /// The model cache directory path.
    @Published var cacheDirectory: String?

    // MARK: - Private

    private let engine = OrangeNoteEngine()

    // MARK: - Actions

    /// Loads the list of available models from the FFI layer.
    func loadModels() async {
        isLoading = true
        errorMessage = nil

        do {
            models = try engine.listModels()
            cacheDirectory = try? engine.modelCacheDir()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the cache status of all models.
    func refreshCacheStatus() {
        models = models.map { model in
            model.withCachedStatus(engine.isModelCached(name: model.id))
        }
    }

    /// Opens the model cache directory in Finder.
    func openCacheDirectory() {
        guard let dir = cacheDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
}
