//
//  BatchOutputPolicy.swift
//  OrangeNote
//
//  Defines output directory resolution, validation, persistence, and fallback policies
//  for batch transcription operations (Task 3.12 / D017 / D018 / D023).
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Darwin

/// Represents the source of audio files ingested for a batch run.
enum BatchInputSource: Equatable, Sendable {
    /// Ingested from a single top-level directory with an explicit folder grant.
    case folder(URL)
    /// Ingested as a collection of individual files (may originate from mixed directories).
    case files([URL])
    /// Empty batch draft without files.
    case empty

    /// Returns the source folder URL if the batch originated from a single folder grant.
    var sourceFolderURL: URL? {
        switch self {
        case .folder(let url):
            return url
        case .files, .empty:
            return nil
        }
    }

    /// Returns the number of items or files represented by this source.
    var count: Int {
        switch self {
        case .folder:
            return 1
        case .files(let urls):
            return urls.count
        case .empty:
            return 0
        }
    }
}

/// Errors that can occur during output directory validation and resolution.
enum BatchOutputDirectoryValidationError: Error, LocalizedError, Equatable {
    /// Provided URL is not a file URL.
    case notFileURL(URL)
    /// Destination directory does not exist on disk.
    case directoryNotFound(URL)
    /// Destination path exists but is a regular file, not a directory.
    case notADirectory(URL)
    /// Destination directory is read-only or not writable by the current process.
    case notWritable(URL)
    /// Saved bookmark data failed to resolve into a valid URL.
    case bookmarkResolutionFailed(String)
    /// No valid, writable output directory could be resolved after checking all fallback rules.
    case noValidDirectoryAvailable

    var errorDescription: String? {
        switch self {
        case .notFileURL(let url):
            return "The path is not a valid file URL: \(url.absoluteString)"
        case .directoryNotFound(let url):
            return "Output directory does not exist: \(url.path)"
        case .notADirectory(let url):
            return "Output path is a file, not a directory: \(url.path)"
        case .notWritable(let url):
            return "Output directory is not writable or is read-only: \(url.path)"
        case .bookmarkResolutionFailed(let reason):
            return "Failed to resolve saved output directory bookmark: \(reason)"
        case .noValidDirectoryAvailable:
            return "No valid, writable output directory is available."
        }
    }
}

/// The resolution origin of a chosen batch output directory.
enum BatchOutputPolicyResolutionSource: String, Sendable, Equatable {
    /// Explicit user override persisted in UserDefaults via security-scoped bookmark.
    case userOverride
    /// Proposing the source directory from a single explicitly-selected folder grant.
    case sourceFolder
    /// System default directory (e.g. Downloads or Documents or Temporary).
    case systemDefault
    /// Explicit custom directory supplied directly by the caller.
    case custom
}

/// Result of resolving an output directory for a batch transcription run.
struct BatchOutputDirectoryResolution: Equatable, Sendable {
    /// The standardized, validated destination directory URL.
    let url: URL
    /// The policy rule that produced this destination.
    let source: BatchOutputPolicyResolutionSource

    init(url: URL, source: BatchOutputPolicyResolutionSource) {
        self.url = url.standardizedFileURL
        self.source = source
    }
}

/// Protocol abstracting interactive directory selection (such as NSOpenPanel)
/// to enable deterministic, non-interactive unit testing of directory picker workflows.
protocol DirectoryPickerProtocol: Sendable {
    /// Prompts the user to pick a directory.
    ///
    /// - Parameters:
    ///   - prompt: Custom button title (e.g. "Select").
    ///   - initialDirectory: Initial directory to display in the picker.
    /// - Returns: The chosen directory `URL`, or `nil` if cancelled.
    func pickDirectory(prompt: String?, initialDirectory: URL?) async -> URL?
}

#if canImport(AppKit)
/// Default implementation of `DirectoryPickerProtocol` using macOS `NSOpenPanel`.
final class OpenPanelDirectoryPicker: DirectoryPickerProtocol, @unchecked Sendable {
    @MainActor
    func pickDirectory(prompt: String? = nil, initialDirectory: URL? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let prompt = prompt {
            panel.prompt = prompt
        }
        if let initialDirectory = initialDirectory {
            panel.directoryURL = initialDirectory
        }

        let response = panel.runModal()
        if response == .OK {
            return panel.url
        }
        return nil
    }
}
#endif

/// Policy service that validates, resolves, and persists output directories for batch transcription.
///
/// Implements:
/// 1. **Default Location & Fallbacks**:
///    - For a single folder grant (`.folder(URL)`), proposes that folder directly (if valid and writable).
///    - For multi-file / mixed selections (`.files`), requires an explicit user override or falls back to system Downloads/Documents.
/// 2. **User Override Persistence**:
///    - Persists user overrides in `UserDefaults` via security-scoped bookmarks (Task 3.11).
/// 3. **Validation**:
///    - Strictly validates that candidate directories exist on disk, are directories (not files), and are writable (preventing assuming parent directories are writable).
///    - Rejects missing, deleted, or read-only directories and falls back safely.
final class BatchOutputPolicy: @unchecked Sendable {
    /// Key used to store security-scoped bookmark data for user override directory in UserDefaults.
    static let bookmarkStorageKey = "batchOutputDirectoryBookmarkData"
    /// Key used to store standardized directory path string in UserDefaults (for display and fallback).
    static let pathStorageKey = "batchOutputDirectoryPath"

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let directoryPicker: DirectoryPickerProtocol?

    /// Initializes a `BatchOutputPolicy` instance with injectable dependencies.
    ///
    /// - Parameters:
    ///   - userDefaults: The `UserDefaults` instance used for persistence (defaults to `.standard`).
    ///   - fileManager: The `FileManager` instance used for directory validation (defaults to `.default`).
    ///   - directoryPicker: An optional directory picker conforming to `DirectoryPickerProtocol`.
    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        directoryPicker: DirectoryPickerProtocol? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.directoryPicker = directoryPicker
    }

    // MARK: - Validation

    /// Validates that a URL is a valid file URL, exists on disk, is a directory, and is writable.
    ///
    /// - Parameters:
    ///   - url: The candidate destination directory URL.
    ///   - fileManager: The `FileManager` instance used for filesystem checks.
    /// - Returns: `.success(standardizedURL)` if valid and writable; `.failure(error)` otherwise.
    static func validateDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Result<URL, BatchOutputDirectoryValidationError> {
        guard url.isFileURL else {
            return .failure(.notFileURL(url))
        }

        let standardized = url.standardizedFileURL
        let path = standardized.path

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            return .failure(.directoryNotFound(standardized))
        }

        guard isDir.boolValue else {
            return .failure(.notADirectory(standardized))
        }

        // Check POSIX writability and FileManager writable check
        guard fileManager.isWritableFile(atPath: path) && access(path, W_OK) == 0 else {
            return .failure(.notWritable(standardized))
        }

        return .success(standardized)
    }

    /// Instance convenience method for directory validation.
    func validateDirectory(_ url: URL) -> Result<URL, BatchOutputDirectoryValidationError> {
        Self.validateDirectory(url, fileManager: fileManager)
    }

    // MARK: - User Override Persistence

    /// Saves a user-selected output directory as an override in `UserDefaults` using a security-scoped bookmark.
    ///
    /// - Parameter directoryURL: The directory URL selected by the user.
    /// - Returns: The validated, standardized directory URL.
    /// - Throws: `BatchOutputDirectoryValidationError` if the directory is invalid/not writable,
    ///   or `SecurityScopeBookmarkError` if bookmark generation fails.
    @discardableResult
    func saveUserOverride(directory directoryURL: URL) throws -> URL {
        let validatedURL = try validateDirectory(directoryURL).get()

        let bookmarkData = try SecurityScopeHelper.createBookmark(for: validatedURL, isReadOnly: false)
        userDefaults.set(bookmarkData, forKey: Self.bookmarkStorageKey)
        userDefaults.set(validatedURL.path, forKey: Self.pathStorageKey)

        return validatedURL
    }

    /// Loads and validates the user override output directory from `UserDefaults`.
    ///
    /// - Returns: `.success(URL)` if a valid override is saved, `.failure(error)` if saved bookmark/path is invalid/missing/not writable, or `nil` if no override has been saved.
    func loadUserOverride() -> Result<URL, BatchOutputDirectoryValidationError>? {
        if let bookmarkData = userDefaults.data(forKey: Self.bookmarkStorageKey) {
            do {
                let resolved = try SecurityScopeHelper.resolveBookmark(data: bookmarkData)
                let validatedResult = validateDirectory(resolved.url)
                switch validatedResult {
                case .success(let url):
                    return .success(url)
                case .failure(let error):
                    return .failure(error)
                }
            } catch {
                return .failure(.bookmarkResolutionFailed(error.localizedDescription))
            }
        }

        if let savedPath = userDefaults.string(forKey: Self.pathStorageKey) {
            let url = URL(fileURLWithPath: savedPath)
            return validateDirectory(url)
        }

        return nil
    }

    /// Clears any saved user override directory from `UserDefaults`.
    func clearUserOverride() {
        userDefaults.removeObject(forKey: Self.bookmarkStorageKey)
        userDefaults.removeObject(forKey: Self.pathStorageKey)
    }

    // MARK: - Directory Resolution Logic

    /// Resolves the effective output directory for a batch transcription run according to priority rules:
    /// 1. If a valid, writable user override is saved in `UserDefaults`, uses it (`.userOverride`).
    /// 2. If the batch was ingested from a single folder grant (`.folder(URL)`), proposes that folder (`.sourceFolder`).
    /// 3. Otherwise, falls back to the system default directory (Downloads or Documents or Temporary) (`.systemDefault`).
    ///
    /// If any rule yields an invalid, deleted, or read-only directory, the resolver automatically
    /// tries the subsequent fallback rules before returning `.failure(.noValidDirectoryAvailable)`.
    ///
    /// - Parameter source: The source of audio files for the batch.
    /// - Returns: A `Result` containing `BatchOutputDirectoryResolution` on success or `BatchOutputDirectoryValidationError` on failure.
    func resolveOutputDirectory(
        for source: BatchInputSource
    ) -> Result<BatchOutputDirectoryResolution, BatchOutputDirectoryValidationError> {
        // Rule 1: Valid User Override in UserDefaults
        if let overrideResult = loadUserOverride(), case .success(let overrideURL) = overrideResult {
            return .success(BatchOutputDirectoryResolution(url: overrideURL, source: .userOverride))
        }

        // Rule 2: Single Folder Grant Source
        if case .folder(let folderURL) = source {
            if case .success(let validatedFolderURL) = validateDirectory(folderURL) {
                return .success(BatchOutputDirectoryResolution(url: validatedFolderURL, source: .sourceFolder))
            }
        }

        // Rule 3: System Default Directory (Downloads -> Documents -> Desktop -> Temporary)
        if let validatedDefaultURL = resolveSystemDefaultDirectory() {
            return .success(BatchOutputDirectoryResolution(url: validatedDefaultURL, source: .systemDefault))
        }

        return .failure(.noValidDirectoryAvailable)
    }

    /// Candidate system default directories to try in order of preference.
    private var candidateSystemDefaultDirectories: [URL] {
        var candidates: [URL] = []
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            candidates.append(downloads)
        }
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(documents)
        }
        if let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            candidates.append(desktop)
        }
        candidates.append(fileManager.temporaryDirectory)
        candidates.append(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        return candidates
    }

    /// Resolves the first valid, writable candidate system default directory.
    private func resolveSystemDefaultDirectory() -> URL? {
        for candidate in candidateSystemDefaultDirectories {
            if !fileManager.fileExists(atPath: candidate.path) {
                try? fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
            }
            if case .success(let validatedURL) = validateDirectory(candidate) {
                return validatedURL
            }
        }
        return nil
    }

    // MARK: - Interactive Prompt Helper

    /// Prompts the user to pick an output directory override using the configured or provided `DirectoryPickerProtocol`,
    /// validates the chosen directory, and persists it in `UserDefaults`.
    ///
    /// - Parameters:
    ///   - picker: Optional custom directory picker (overriding instance picker).
    ///   - initialDirectory: Initial directory to display.
    ///   - prompt: Button title for picker.
    /// - Returns: The chosen and validated directory `URL`, or `nil` if cancelled.
    /// - Throws: `BatchOutputDirectoryValidationError` or `SecurityScopeBookmarkError` if validation or saving fails.
    func promptAndSaveUserOverride(
        picker: DirectoryPickerProtocol? = nil,
        initialDirectory: URL? = nil,
        prompt: String? = nil
    ) async throws -> URL? {
        guard let activePicker = picker ?? directoryPicker else {
            return nil
        }

        guard let selectedURL = await activePicker.pickDirectory(prompt: prompt, initialDirectory: initialDirectory) else {
            return nil
        }

        return try saveUserOverride(directory: selectedURL)
    }
}
