//
//  BatchOutputPlanner.swift
//  OrangeNote
//
//  Plans output destination paths matching <outputDirectory>/<audio-basename>.json
//  (Task 3.6 / D017) and detects existing output files on disk to mark items as
//  skipped without overwriting (Task 3.6 / D018). Integrates with BatchOutputPolicy (Task 3.12).
//

import Foundation

/// Service that computes deterministic destination file paths for batch transcription
/// items and detects already-existing output files to skip them.
///
/// This enum has no instances; it exposes only static planning functions.
enum BatchOutputPlanner {
    /// Computes the destination JSON file URL for a given source audio URL
    /// in the specified destination directory.
    ///
    /// The output filename strictly matches `<audio-basename>.json` (D017),
    /// preserving the exact base name without extra sanitization.
    ///
    /// - Parameters:
    ///   - sourceURL: The source audio file URL.
    ///   - destinationDirectory: The destination folder where transcripts will be written.
    /// - Returns: The computed output file URL.
    static func computeOutputURL(for sourceURL: URL, in destinationDirectory: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return destinationDirectory
            .standardizedFileURL
            .appendingPathComponent(baseName)
            .appendingPathExtension("json")
    }

    /// Plans output paths for an array of `BatchItem`s in the given destination directory,
    /// checking for existing files on disk and marking existing items as `.skipped` (D018).
    ///
    /// For each item:
    /// 1. Computes `outputURL = computeOutputURL(for: item.sourceURL, in: destinationDirectory)`.
    /// 2. If a file already exists at `outputURL.path`, sets `item.status = .skipped`.
    /// 3. If no file exists at `outputURL.path` and the item was previously `.skipped` or `.queued`,
    ///    sets `item.status = .queued`.
    ///
    /// - Parameters:
    ///   - items: The batch items to plan output paths for.
    ///   - destinationDirectory: The folder where JSON transcripts will be stored.
    ///   - fileManager: The `FileManager` instance used to check disk existence (defaults to `.default`).
    /// - Returns: Updated batch items with computed `outputURL`s and updated `.skipped` / `.queued` statuses.
    static func plan(
        items: [BatchItem],
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) -> [BatchItem] {
        items.map { item in
            var updatedItem = item
            let outputURL = computeOutputURL(for: item.sourceURL, in: destinationDirectory)
            updatedItem.outputURL = outputURL

            if fileManager.fileExists(atPath: outputURL.path) {
                if updatedItem.status == .queued || updatedItem.status == .skipped {
                    updatedItem.status = .skipped
                }
            } else {
                if updatedItem.status == .skipped {
                    updatedItem.status = .queued
                }
            }

            return updatedItem
        }
    }

    /// Plans output paths for an array of `BatchItem`s by resolving the destination directory
    /// using `BatchOutputPolicy` for the given `BatchInputSource` (Task 3.12).
    ///
    /// - Parameters:
    ///   - items: The batch items to plan output paths for.
    ///   - source: The input source (e.g. `.folder(URL)` or `.files([URL])`).
    ///   - policy: The `BatchOutputPolicy` used to resolve the destination directory.
    ///   - fileManager: The `FileManager` instance used for filesystem checks.
    /// - Returns: A tuple containing the planned batch items and the resolved destination directory URL.
    /// - Throws: `BatchOutputDirectoryValidationError` if output directory resolution fails.
    static func plan(
        items: [BatchItem],
        source: BatchInputSource,
        policy: BatchOutputPolicy = BatchOutputPolicy(),
        fileManager: FileManager = .default
    ) throws -> (items: [BatchItem], resolvedDirectory: URL) {
        let resolution = try policy.resolveOutputDirectory(for: source).get()
        let plannedItems = plan(items: items, destinationDirectory: resolution.url, fileManager: fileManager)
        return (plannedItems, resolution.url)
    }
}
