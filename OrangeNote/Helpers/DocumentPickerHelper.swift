//
//  DocumentPickerHelper.swift
//  OrangeNote
//
//  Provides modal and programmatic document/folder picker helpers for batch ingestion
//  and destination output directory selection, integrated with AudioTypeCatalog filtering,
//  SecurityScopeHelper (Task 3.11), BatchFileCollector (Tasks 3.3–3.5), and BatchOutputPolicy (Task 3.12).
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

/// Protocol abstracting interactive file, folder, and directory picking
/// to enable deterministic, non-interactive unit testing of picker workflows.
protocol BatchDocumentPickerProtocol: Sendable {
    /// Prompts the user to pick one or more audio files.
    ///
    /// - Parameters:
    ///   - prompt: Custom button title (e.g. "Select").
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: Array of selected file URLs, or `nil` if cancelled.
    func pickMultipleAudioFiles(prompt: String?, initialDirectory: URL?) async -> [URL]?

    /// Prompts the user to pick a single folder for batch ingestion.
    ///
    /// - Parameters:
    ///   - prompt: Custom button title (e.g. "Choose Folder").
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: The selected folder URL, or `nil` if cancelled.
    func pickSingleFolder(prompt: String?, initialDirectory: URL?) async -> URL?

    /// Prompts the user to pick an output directory.
    ///
    /// - Parameters:
    ///   - prompt: Custom button title (e.g. "Select Output").
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: The selected output directory URL, or `nil` if cancelled.
    func pickOutputDirectory(prompt: String?, initialDirectory: URL?) async -> URL?
}

#if canImport(AppKit)
/// Default implementation of `BatchDocumentPickerProtocol` and `DirectoryPickerProtocol`
/// using macOS `NSOpenPanel`.
final class OpenPanelDocumentPicker: BatchDocumentPickerProtocol, DirectoryPickerProtocol, @unchecked Sendable {

    @MainActor
    func pickMultipleAudioFiles(
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = AudioTypeCatalog.allowedUTTypes
        if let prompt = prompt {
            panel.prompt = prompt
        }
        if let initialDirectory = initialDirectory {
            panel.directoryURL = initialDirectory
        }

        let response = panel.runModal()
        if response == .OK {
            return panel.urls
        }
        return nil
    }

    @MainActor
    func pickSingleFolder(
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
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

    @MainActor
    func pickOutputDirectory(
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> URL? {
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

    @MainActor
    func pickDirectory(
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> URL? {
        await pickOutputDirectory(prompt: prompt, initialDirectory: initialDirectory)
    }
}
#endif

/// Result of ingesting candidate audio files or folders for batch processing.
struct BatchIngestionResult: Equatable, Sendable {
    /// Ingestion source type (single folder grant, collection of files, or empty).
    let source: BatchInputSource
    /// Filtered, deduplicated, and sorted batch items ready for execution.
    let items: [BatchItem]
    /// Security scope token held for the duration of the batch operation (if acquired).
    let securityToken: SecurityScopeToken?

    init(
        source: BatchInputSource,
        items: [BatchItem],
        securityToken: SecurityScopeToken? = nil
    ) {
        self.source = source
        self.items = items
        self.securityToken = securityToken
    }

    /// Number of collected batch items.
    var count: Int { items.count }

    /// Whether no valid batch items were collected.
    var isEmpty: Bool { items.isEmpty }

    /// Array of standardized source audio URLs.
    var audioURLs: [URL] { items.map(\.sourceURL) }

    static func == (lhs: BatchIngestionResult, rhs: BatchIngestionResult) -> Bool {
        lhs.source == rhs.source && lhs.items == rhs.items
    }
}

/// Helper coordinating document and folder picker interactions, audio-type filtering,
/// source detection, and batch queue ingestion.
final class DocumentPickerHelper: @unchecked Sendable {
    let picker: BatchDocumentPickerProtocol?
    private let fileManager: FileManager
    private let outputPolicy: BatchOutputPolicy

    #if canImport(AppKit)
    /// Initializes a `DocumentPickerHelper` with injectable dependencies.
    ///
    /// - Parameters:
    ///   - picker: An optional picker conforming to `BatchDocumentPickerProtocol` (defaults to `OpenPanelDocumentPicker()` under AppKit).
    ///   - fileManager: The `FileManager` instance for filesystem inspections.
    ///   - outputPolicy: The `BatchOutputPolicy` used for destination directory validation and overrides.
    init(
        picker: BatchDocumentPickerProtocol? = OpenPanelDocumentPicker(),
        fileManager: FileManager = .default,
        outputPolicy: BatchOutputPolicy = BatchOutputPolicy()
    ) {
        self.picker = picker
        self.fileManager = fileManager
        self.outputPolicy = outputPolicy
    }
    #else
    /// Initializes a `DocumentPickerHelper` with injectable dependencies.
    ///
    /// - Parameters:
    ///   - picker: An optional picker conforming to `BatchDocumentPickerProtocol`.
    ///   - fileManager: The `FileManager` instance for filesystem inspections.
    ///   - outputPolicy: The `BatchOutputPolicy` used for destination directory validation and overrides.
    init(
        picker: BatchDocumentPickerProtocol? = nil,
        fileManager: FileManager = .default,
        outputPolicy: BatchOutputPolicy = BatchOutputPolicy()
    ) {
        self.picker = picker
        self.fileManager = fileManager
        self.outputPolicy = outputPolicy
    }
    #endif

    // MARK: - Static Non-UI Logic Primitives

    /// Filters candidate file URLs down to supported audio types (via `AudioTypeCatalog`),
    /// standardizing URLs, verifying existence and non-directory status on disk, and deduplicating
    /// while preserving initial ordering.
    ///
    /// - Parameters:
    ///   - urls: Candidate file URLs.
    ///   - fileManager: The `FileManager` to inspect file existence and directory status.
    /// - Returns: Array of valid, standardized audio file URLs.
    static func filterAudioFiles(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var seenPaths = Set<String>()
        var validURLs: [URL] = []

        for url in urls {
            let standardURL = url.standardizedFileURL
            guard AudioTypeCatalog.isSupported(url: standardURL) else { continue }

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: standardURL.path, isDirectory: &isDirectory)
            guard exists, !isDirectory.boolValue else { continue }

            if seenPaths.insert(standardURL.path).inserted {
                validURLs.append(standardURL)
            }
        }

        return validURLs
    }

    /// Detects whether candidate URLs represent a single top-level folder grant or a collection of files.
    ///
    /// - Parameters:
    ///   - urls: Input candidate URLs.
    ///   - fileManager: The `FileManager` instance.
    /// - Returns: The detected `BatchInputSource`.
    static func detectInputSource(
        from urls: [URL],
        fileManager: FileManager = .default
    ) -> BatchInputSource {
        guard !urls.isEmpty else {
            return .empty
        }

        if urls.count == 1, let firstURL = urls.first {
            let standardURL = firstURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: standardURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return .folder(standardURL)
            }
            return .files([standardURL])
        }

        return .files(urls.map(\.standardizedFileURL))
    }

    /// Ingests audio files from a single explicitly-chosen folder grant (non-recursive, D020),
    /// scoping resource access with `SecurityScopeHelper` (D023) and collecting items via `BatchFileCollector`.
    ///
    /// - Parameter folderURL: The selected folder URL.
    /// - Returns: A `BatchIngestionResult` containing `.folder(URL)` source and collected items.
    static func processFolder(_ folderURL: URL) -> BatchIngestionResult {
        let standardFolder = folderURL.standardizedFileURL
        let items = BatchFileCollector.collectTopLevel(fromFolder: standardFolder)
        let token = SecurityScopeHelper.acquireScope(for: standardFolder)
        return BatchIngestionResult(
            source: .folder(standardFolder),
            items: items,
            securityToken: token.hasActiveScope ? token : nil
        )
    }

    /// Ingests a collection of individual candidate file URLs, filtering, deduplicating,
    /// and sorting them via `BatchFileCollector`.
    ///
    /// - Parameter urls: Candidate file URLs.
    /// - Returns: A `BatchIngestionResult` containing `.files([URL])` source and collected items.
    static func processFiles(_ urls: [URL]) -> BatchIngestionResult {
        let items = BatchFileCollector.collect(from: urls)
        let audioURLs = items.map(\.sourceURL)
        return BatchIngestionResult(
            source: .files(audioURLs),
            items: items,
            securityToken: nil
        )
    }

    /// Processes arbitrary candidate URLs (e.g. from picker or drag-and-drop), routing single folders
    /// to folder ingestion and file lists to multi-file ingestion.
    ///
    /// - Parameters:
    ///   - urls: Candidate URLs.
    ///   - fileManager: The `FileManager` instance.
    /// - Returns: A `BatchIngestionResult`.
    static func processCandidateURLs(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) -> BatchIngestionResult {
        guard !urls.isEmpty else {
            return BatchIngestionResult(source: .empty, items: [], securityToken: nil)
        }

        let detectedSource = detectInputSource(from: urls, fileManager: fileManager)
        switch detectedSource {
        case .folder(let folderURL):
            return processFolder(folderURL)
        case .files:
            return processFiles(urls)
        case .empty:
            return BatchIngestionResult(source: .empty, items: [], securityToken: nil)
        }
    }

    // MARK: - Instance Helper Operations

    /// Prompts the user to pick multiple audio files using the injected or provided picker,
    /// and processes them into a `BatchIngestionResult`.
    ///
    /// - Parameters:
    ///   - pickerOverride: Optional custom picker.
    ///   - prompt: Button prompt text.
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: `BatchIngestionResult` if files were picked, or `nil` if cancelled or no picker available.
    func promptAndIngestMultipleFiles(
        picker pickerOverride: BatchDocumentPickerProtocol? = nil,
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> BatchIngestionResult? {
        guard let activePicker = pickerOverride ?? picker else {
            return nil
        }

        guard let pickedURLs = await activePicker.pickMultipleAudioFiles(
            prompt: prompt,
            initialDirectory: initialDirectory
        ) else {
            return nil
        }

        return Self.processFiles(pickedURLs)
    }

    /// Prompts the user to pick a top-level audio folder using the injected or provided picker,
    /// and processes its top-level contents into a `BatchIngestionResult`.
    ///
    /// - Parameters:
    ///   - pickerOverride: Optional custom picker.
    ///   - prompt: Button prompt text.
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: `BatchIngestionResult` if a folder was picked, or `nil` if cancelled or no picker available.
    func promptAndIngestFolder(
        picker pickerOverride: BatchDocumentPickerProtocol? = nil,
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async -> BatchIngestionResult? {
        guard let activePicker = pickerOverride ?? picker else {
            return nil
        }

        guard let pickedFolder = await activePicker.pickSingleFolder(
            prompt: prompt,
            initialDirectory: initialDirectory
        ) else {
            return nil
        }

        return Self.processFolder(pickedFolder)
    }

    /// Prompts the user to pick and save a batch output directory override.
    ///
    /// - Parameters:
    ///   - pickerOverride: Optional custom picker.
    ///   - prompt: Button prompt text.
    ///   - initialDirectory: Initial directory to display.
    /// - Returns: Validated and saved output directory `URL`, or `nil` if cancelled or no picker available.
    /// - Throws: `BatchOutputDirectoryValidationError` or bookmark error if saving fails.
    func promptAndSelectOutputDirectory(
        picker pickerOverride: BatchDocumentPickerProtocol? = nil,
        prompt: String? = nil,
        initialDirectory: URL? = nil
    ) async throws -> URL? {
        guard let activePicker = pickerOverride ?? picker else {
            return nil
        }

        guard let selectedURL = await activePicker.pickOutputDirectory(
            prompt: prompt,
            initialDirectory: initialDirectory
        ) else {
            return nil
        }

        return try outputPolicy.saveUserOverride(directory: selectedURL)
    }
}
