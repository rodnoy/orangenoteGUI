//
//  DropItemResolver.swift
//  OrangeNote
//
//  Resolves drag-and-drop `NSItemProvider` payloads into validated single audio
//  file URLs or multi-file / top-level folder batch ingestion results for the
//  transcription workflow. Enforces D010 (no drops while transcribing), D020
//  (top-level folder ingestion only), D023 (security-scoped folder access),
//  and D029 (rejection of mixed folder+files or multiple folders).
//

import Foundation
import UniformTypeIdentifiers

/// Outcome of resolving a drag-and-drop payload against transcription drop rules.
enum DropResolution: Equatable {
    /// Exactly one item was dropped and it is a valid, supported audio file.
    case accepted(URL)
    /// Multiple audio files or a single top-level folder was dropped and collected into a batch.
    case batch(BatchIngestionResult)
    /// The drop was ignored because a transcription job or batch is currently running (D010).
    case rejectedTranscribing
    /// Dropped items contained mixed folders and files, or multiple folders (D029).
    case rejectedMixedItems
    /// More (or fewer) than one item was dropped in single-file-only resolution mode.
    case rejectedMultipleItems(count: Int)
    /// Exactly one item was dropped but it failed audio validation.
    case invalidFile(AudioValidationError)
    /// A dropped folder contained no supported audio files at its top level, or a dropped list of files contained no supported audio files.
    case noAudioFilesFound
    /// Item URL(s) could not be extracted from the `NSItemProvider`s.
    case extractionFailed

    /// A user-facing localized explanation for non-accepted outcomes, or `nil` when accepted.
    var localizedMessage: String? {
        switch self {
        case .accepted, .batch:
            return nil
        case .rejectedTranscribing:
            return L10n.localizedString("error.dropRejectedTranscribing")
        case .rejectedMixedItems:
            return L10n.localizedString("error.dropMixedItemsRejected")
        case .rejectedMultipleItems:
            return L10n.localizedString("error.dropMultipleFilesRejected")
        case .invalidFile(let validationError):
            return validationError.errorDescription
        case .noAudioFilesFound:
            return L10n.localizedString("error.dropNoAudioFiles")
        case .extractionFailed:
            return L10n.localizedString("error.dropExtractionFailed")
        }
    }

    /// Extracted single audio file URL if this resolution accepted a single file.
    var singleFileURL: URL? {
        if case .accepted(let url) = self {
            return url
        }
        return nil
    }

    /// Batch ingestion result if this resolution represents a batch or single file.
    var batchIngestionResult: BatchIngestionResult? {
        switch self {
        case .batch(let result):
            return result
        case .accepted(let url):
            return BatchIngestionResult(source: .files([url]), items: [BatchItem(sourceURL: url)])
        default:
            return nil
        }
    }
}

/// Resolves dropped items into a single validated audio file URL, a multi-item/folder
/// batch ingestion result, or a typed rejection reason with localized user feedback.
enum DropItemResolver {
    /// Pure resolution logic over already-extracted file URLs.
    ///
    /// Evaluates:
    /// 1. Active transcription status (D010).
    /// 2. Mixed folder+files or multiple folders rejection (D029).
    /// 3. Single top-level folder ingestion (D020 / D023).
    /// 4. Single audio file validation (`AudioFileValidator`).
    /// 5. Multi-file batch collection (`BatchFileCollector`).
    ///
    /// - Parameters:
    ///   - urls: Candidate file URLs.
    ///   - isTranscribing: Whether transcription or batch is currently active.
    ///   - fileManager: The `FileManager` instance for directory inspections.
    /// - Returns: The resolution outcome.
    static func resolve(
        urls: [URL],
        isTranscribing: Bool,
        fileManager: FileManager = .default
    ) -> DropResolution {
        if isTranscribing {
            return .rejectedTranscribing
        }

        guard !urls.isEmpty else {
            return .rejectedMultipleItems(count: 0)
        }

        var folderURLs: [URL] = []
        var fileURLs: [URL] = []

        for url in urls {
            let standardURL = url.standardizedFileURL
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: standardURL.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    folderURLs.append(standardURL)
                } else {
                    fileURLs.append(standardURL)
                }
            } else {
                // If not found on disk, classify by path syntax
                if standardURL.hasDirectoryPath {
                    folderURLs.append(standardURL)
                } else {
                    fileURLs.append(standardURL)
                }
            }
        }

        // D029: Reject mixed folder+files or multiple folders
        if folderURLs.count > 1 || (!folderURLs.isEmpty && !fileURLs.isEmpty) {
            return .rejectedMixedItems
        }

        // Single folder drop
        if folderURLs.count == 1 && fileURLs.isEmpty {
            let folderURL = folderURLs[0]
            let ingestion = DocumentPickerHelper.processFolder(folderURL)
            if ingestion.isEmpty {
                return .noAudioFilesFound
            }
            return .batch(ingestion)
        }

        // File(s) drop
        if fileURLs.count == 1 {
            let fileURL = fileURLs[0]
            switch AudioFileValidator.validate(fileURL) {
            case .success(let validURL):
                return .accepted(validURL)
            case .failure(let validationError):
                return .invalidFile(validationError)
            }
        } else {
            let ingestion = DocumentPickerHelper.processFiles(fileURLs)
            if ingestion.isEmpty {
                return .noAudioFilesFound
            }
            return .batch(ingestion)
        }
    }

    /// Single-file-only resolution helper for legacy single-file drop contexts.
    ///
    /// - Parameters:
    ///   - urls: File URLs extracted from the dropped `NSItemProvider`s.
    ///   - isTranscribing: Whether a transcription job is currently active (D010).
    /// - Returns: The resolution outcome.
    static func resolveSingleFileOnly(urls: [URL], isTranscribing: Bool) -> DropResolution {
        if isTranscribing {
            return .rejectedTranscribing
        }

        guard urls.count == 1, let url = urls.first else {
            return .rejectedMultipleItems(count: urls.count)
        }

        switch AudioFileValidator.validate(url) {
        case .success(let validURL):
            return .accepted(validURL)
        case .failure(let validationError):
            return .invalidFile(validationError)
        }
    }

    /// Resolves a drag-and-drop payload end-to-end: checks active transcription status,
    /// extracts URLs from all providers asynchronously without data races, and passes
    /// the extracted URLs to `resolve(urls:isTranscribing:fileManager:)`.
    ///
    /// - Parameters:
    ///   - providers: Providers supplied by SwiftUI's `onDrop`.
    ///   - isTranscribing: Whether a transcription job is currently active (D010).
    ///   - fileManager: The `FileManager` instance for directory inspections.
    ///   - completion: Called on the main queue with the final resolution.
    static func extractAndResolve(
        from providers: [NSItemProvider],
        isTranscribing: Bool,
        fileManager: FileManager = .default,
        completion: @escaping (DropResolution) -> Void
    ) {
        if isTranscribing {
            DispatchQueue.main.async {
                completion(.rejectedTranscribing)
            }
            return
        }

        guard !providers.isEmpty else {
            DispatchQueue.main.async {
                completion(.rejectedMultipleItems(count: 0))
            }
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loadedURLs: [URL] = []

        for provider in providers {
            group.enter()
            loadURL(from: provider) { url in
                if let url = url {
                    lock.lock()
                    loadedURLs.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if loadedURLs.isEmpty {
                completion(.extractionFailed)
                return
            }

            let resolution = resolve(urls: loadedURLs, isTranscribing: isTranscribing, fileManager: fileManager)
            completion(resolution)
        }
    }

    /// Loads a single file URL from a provider, preferring `loadObject(ofClass: URL.self)`
    /// and falling back to `loadItem(forTypeIdentifier: UTType.fileURL.identifier)` when
    /// the primary API is unavailable or fails to resolve a URL.
    private static func loadURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        guard provider.canLoadObject(ofClass: URL.self) else {
            loadURLFallback(from: provider, completion: completion)
            return
        }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url = url {
                completion(url)
            } else {
                loadURLFallback(from: provider, completion: completion)
            }
        }
    }

    /// Fallback extraction path using `UTType.fileURL` item loading, covering providers
    /// (or `loadObject` failures) where the typed URL API did not yield a usable URL.
    private static func loadURLFallback(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            completion(nil)
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                completion(url)
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                completion(url)
            } else {
                completion(nil)
            }
        }
    }
}
