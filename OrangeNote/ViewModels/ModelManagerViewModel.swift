//
//  ModelManagerViewModel.swift
//  OrangeNote
//
//  View model for managing locally cached Whisper models.
//

import AppKit
import SwiftUI

/// Manages the list of cached Whisper models and provides Finder integration.
@MainActor
final class ModelManagerViewModel: ObservableObject {
    // MARK: - Published State

    /// All available models with their cache status.
    @Published var models: [WhisperModel] = []

    /// Whether the model list is being loaded.
    @Published var isLoading: Bool = false

    /// Error message to display.
    @Published var errorMessage: String?

    /// The model cache directory path.
    @Published var cacheDirectory: String?

    // MARK: - Computed

    /// Only models that are downloaded and available locally.
    var cachedModels: [WhisperModel] {
        models.filter(\.isCached)
    }

    // MARK: - Private

    private let engine = OrangeNoteEngine()

    // MARK: - Actions

    /// Loads the list of available models from the FFI layer and resolves file paths for cached ones.
    func loadModels() async {
        isLoading = true
        errorMessage = nil

        do {
            let allModels = try engine.listModels()
            models = allModels.map { model in
                guard model.isCached else { return model }
                let path = try? engine.modelPath(name: model.id)
                return model.withFilePath(path)
            }
            cacheDirectory = try? engine.modelCacheDir()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refreshes the cache status and file paths of all models.
    func refreshCacheStatus() {
        models = models.map { model in
            let cached = engine.isModelCached(name: model.id)
            let path: String? = cached ? (try? engine.modelPath(name: model.id)) : nil
            return model.withCachedStatus(cached).withFilePath(path)
        }
    }

    /// Opens the model cache directory in Finder.
    func openCacheDirectory() {
        guard let dir = cacheDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    /// Reveals a specific model file in Finder.
    func openInFinder(model: WhisperModel) {
        guard let path = model.filePath else {
            print("[ModelManager] ERROR: filePath is nil for model \(model.id)")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: path)
        print("[ModelManager] Attempting to open in Finder:")
        print("  - Model: \(model.id)")
        print("  - Path: \(path)")
        print("  - File exists: \(fileExists)")
        print("  - URL: \(url)")
        
        if !fileExists {
            print("[ModelManager] ERROR: File does not exist at path")
            errorMessage = "File not found at: \(path)"
            return
        }
        
        // Attempt to reveal in Finder
        NSWorkspace.shared.activateFileViewerSelecting([url])
        print("[ModelManager] NSWorkspace.activateFileViewerSelecting called")
    }
}
