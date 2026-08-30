//
//  AudioFileValidator.swift
//  OrangeNote
//
//  Centralized single-file audio validation shared by file picker and
//  drag-and-drop ingestion paths.
//

import Foundation

/// Errors raised while validating a candidate audio file URL.
enum AudioValidationError: LocalizedError, Equatable {
    /// No file exists at the given path.
    case fileNotFound(String)
    /// The path points to a directory rather than a file.
    case isDirectory(String)
    /// The file extension is not part of the supported audio pipeline formats.
    case unsupportedFormat(String)
    /// The file exists but is not readable (permissions).
    case notReadable(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return L10n.localizedString("error.fileNotFound")
        case .isDirectory:
            return L10n.localizedString("error.fileNotFound")
        case .unsupportedFormat(let ext):
            return String(format: L10n.localizedString("error.unsupportedFormat"), ext)
        case .notReadable:
            return L10n.localizedString("error.fileNotFound")
        }
    }
}

/// Validates candidate audio file URLs against the actual Whisper audio
/// pipeline's supported formats (see `orangenote-core/src/infrastructure/audio/processor.rs`
/// and `symphonia`-based decoding).
///
/// This is the single source of truth for single-file audio validation,
/// used both by the file picker (`TranscriptionViewModel.selectFile`) and
/// drag-and-drop ingestion (`TranscriptionViewModel.handleDroppedFile`).
enum AudioFileValidator {
    /// Audio file extensions verified as supported by the Rust audio pipeline
    /// (`orangenote-core/src/infrastructure/audio/processor.rs`, decoded via `symphonia`).
    /// The single source of truth now lives in `AudioTypeCatalog`, shared with
    /// the batch ingestion pipeline.
    static let supportedExtensions: Set<String> = AudioTypeCatalog.allowedExtensions

    /// Validates a candidate audio file URL.
    ///
    /// Checks, in order: path existence, non-directory status, readable
    /// permissions, and supported file extension.
    ///
    /// - Parameter url: Candidate file URL to validate.
    /// - Returns: `.success(url)` when the file passes all checks, otherwise `.failure`.
    static func validate(_ url: URL) -> Result<URL, AudioValidationError> {
        let path = url.path
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failure(.fileNotFound(path))
        }

        if isDirectory.boolValue {
            return .failure(.isDirectory(path))
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            return .failure(.notReadable(path))
        }

        let fileExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            return .failure(.unsupportedFormat(fileExtension))
        }

        return .success(url)
    }
}
