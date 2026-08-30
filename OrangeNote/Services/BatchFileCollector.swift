//
//  BatchFileCollector.swift
//  OrangeNote
//
//  Builds the initial in-memory batch queue from an array of dropped or
//  picked file URLs (Task 3.3 / D019 — in-memory only, no persistence).
//  Supports top-level folder ingestion (Task 3.4 / D020) and deterministic
//  URL normalization, deduplication, and full-path sorting (Task 3.5).
//  Protects folder reads with security-scoped resource access (Task 3.11 / D023).
//

import Foundation

/// Collects a flat array of candidate file URLs into a queue of `BatchItem`s,
/// filtering out non-audio, directory, and inaccessible entries, standardizing
/// URLs, removing duplicates by standardized path, and sorting by normalized
/// full path using natural string comparison.
///
/// This enum has no instances; it exposes only static members.
enum BatchFileCollector {
    /// Filters the given `urls` down to valid, accessible audio files,
    /// standardizes URLs, deduplicates by standardized path, and sorts by
    /// normalized full path using `localizedStandardCompare` with a literal
    /// full-path tie-breaker.
    ///
    /// Processing pipeline, applied in order:
    /// 1. Standardize URL (`url.standardizedFileURL`).
    /// 2. Validate supported audio type (`AudioTypeCatalog.isSupported(url:)`).
    /// 3. Verify file existence and non-directory status on disk
    ///    (`FileManager.default.fileExists(atPath:isDirectory:)`).
    /// 4. Deduplicate based on standardized path string.
    /// 5. Sort by normalized full path using `localizedStandardCompare`
    ///    with a literal string comparison tie-breaker.
    ///
    /// - Parameter urls: Candidate file URLs, e.g. from a drop or open panel.
    /// - Returns: Unique `BatchItem`s in deterministic natural full-path order.
    static func collect(from urls: [URL]) -> [BatchItem] {
        var seenPaths = Set<String>()
        var items: [BatchItem] = []

        for url in urls {
            let standardURL = url.standardizedFileURL
            guard AudioTypeCatalog.isSupported(url: standardURL) else { continue }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: standardURL.path, isDirectory: &isDirectory)
            guard exists, !isDirectory.boolValue else { continue }

            if seenPaths.insert(standardURL.path).inserted {
                items.append(BatchItem(sourceURL: standardURL))
            }
        }

        return sort(items: items)
    }

    /// Collects audio files located directly inside `folderURL`'s top level,
    /// non-recursively (D020 — subdirectory contents are never traversed),
    /// returning standardized, deduplicated, and sorted `BatchItem`s.
    /// Uses `SecurityScopeHelper` to ensure access within sandboxed environments (D023).
    ///
    /// - Parameter folderURL: The folder whose top-level contents should be scanned.
    /// - Returns: `BatchItem`s for the surviving top-level audio files.
    static func collectTopLevel(fromFolder folderURL: URL) -> [BatchItem] {
        SecurityScopeHelper.withSecurityScope(for: folderURL) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            ) else {
                return []
            }

            return collect(from: contents)
        }
    }

    /// Normalizes and deduplicates an existing array of `BatchItem`s, standardizing
    /// their `sourceURL`s, removing duplicates by standardized path, and sorting
    /// by normalized full path.
    ///
    /// - Parameter items: The batch items to normalize, deduplicate, and sort.
    /// - Returns: Normalized unique items in deterministic natural full-path order.
    static func normalize(items: [BatchItem]) -> [BatchItem] {
        var seenPaths = Set<String>()
        var uniqueItems: [BatchItem] = []

        for item in items {
            let standardURL = item.sourceURL.standardizedFileURL
            if seenPaths.insert(standardURL.path).inserted {
                let normalizedItem: BatchItem
                if item.sourceURL != standardURL {
                    normalizedItem = BatchItem(
                        id: item.id,
                        sourceURL: standardURL,
                        outputURL: item.outputURL,
                        status: item.status,
                        progress: item.progress,
                        errorMessage: item.errorMessage,
                        result: item.result
                    )
                } else {
                    normalizedItem = item
                }
                uniqueItems.append(normalizedItem)
            }
        }

        return sort(items: uniqueItems)
    }

    // MARK: - Private Helpers

    /// Sorts an array of `BatchItem`s by normalized full path using `localizedStandardCompare`
    /// with a literal string comparison tie-breaker.
    private static func sort(items: [BatchItem]) -> [BatchItem] {
        items.sorted { lhs, rhs in
            let lhsPath = lhs.sourceURL.path
            let rhsPath = rhs.sourceURL.path
            let comparison = lhsPath.localizedStandardCompare(rhsPath)
            if comparison == .orderedSame {
                return lhsPath < rhsPath
            }
            return comparison == .orderedAscending
        }
    }
}
