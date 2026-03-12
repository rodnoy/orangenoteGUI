//
//  WhisperModel.swift
//  OrangeNote
//
//  Represents a Whisper model with its metadata and cache status.
//

import Foundation

/// Information about an available Whisper model.
struct WhisperModel: Identifiable, Sendable, Hashable {
    /// Unique identifier matching the model name (e.g. "base", "small", "medium", "large").
    let id: String

    /// Display name of the model.
    let name: String

    /// Human-readable size (e.g. "142 MB", "1.5 GB").
    let size: String

    /// Whether the model file is available locally.
    let isCached: Bool

    /// Full file-system path to the cached model file, if available.
    let filePath: String?

    /// Returns a copy with updated cache status.
    func withCachedStatus(_ cached: Bool) -> WhisperModel {
        WhisperModel(id: id, name: name, size: size, isCached: cached, filePath: filePath)
    }

    /// Returns a copy with the given file path.
    func withFilePath(_ path: String?) -> WhisperModel {
        WhisperModel(id: id, name: name, size: size, isCached: isCached, filePath: path)
    }
}
