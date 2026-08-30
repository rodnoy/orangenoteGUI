//
//  AtomicFileWriter.swift
//  OrangeNote
//
//  Safely writes Canonical JSON documents and data to disk using unique temporary files
//  in the destination directory and atomic non-overwriting rename semantics (Task 3.7 / D018).
//

import Foundation
import Darwin

/// Outcome of an atomic write operation.
enum AtomicWriteResult: Equatable, Sendable {
    /// File was successfully written to the destination URL.
    case written(URL)
    /// Destination file already exists; writing was skipped without overwriting existing data.
    case skippedAlreadyExists(URL)
}

/// Errors that can occur during atomic file writing.
enum AtomicFileWriterError: Error, LocalizedError, Equatable {
    /// Destination parent directory does not exist or is not a directory.
    case destinationDirectoryNotFound(URL)
    /// Destination path itself is a directory.
    case destinationIsDirectory(URL)
    /// Failed to write data to temporary file.
    case writeFailed(URL, String)
    /// Failed to atomically move/rename the temporary file to the destination path.
    case moveFailed(source: URL, destination: URL, errorDescription: String)

    var errorDescription: String? {
        switch self {
        case .destinationDirectoryNotFound(let url):
            return "Destination directory does not exist: \(url.path)"
        case .destinationIsDirectory(let url):
            return "Destination path is a directory: \(url.path)"
        case .writeFailed(let url, let reason):
            return "Failed to write temporary file at \(url.path): \(reason)"
        case .moveFailed(let src, let dst, let reason):
            return "Failed to move temporary file from \(src.path) to \(dst.path): \(reason)"
        }
    }
}

/// Provides atomic, non-overwriting file writing to disk.
///
/// Ensures:
/// 1. Data is written to a unique temporary file in the destination directory (ensuring same-filesystem semantics).
/// 2. Atomic rename using Darwin `renamex_np` with `RENAME_EXCL` guarantees the destination is never overwritten.
/// 3. If the destination already exists (pre-check or concurrent collision), the temporary file is deleted and
///    `.skippedAlreadyExists` is returned.
/// 4. Temporary files are always cleaned up on write errors, collisions, or rename failures.
enum AtomicFileWriter {

    /// Atomically writes a `CanonicalTranscriptionDocument` to the destination URL.
    ///
    /// The document is encoded into formatted JSON `Data` via `CanonicalTranscriptionSerializer`
    /// and written atomically without overwriting existing files.
    ///
    /// - Parameters:
    ///   - document: The canonical transcription document to serialize and write.
    ///   - destinationURL: The target destination file URL.
    ///   - fileManager: The `FileManager` instance to use (defaults to `.default`).
    /// - Returns: `.written(destinationURL)` on success, or `.skippedAlreadyExists(destinationURL)` if a file exists.
    /// - Throws: `CanonicalTranscriptionSerializerError` if serialization fails, or `AtomicFileWriterError` on I/O failure.
    static func write(
        document: CanonicalTranscriptionDocument,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> AtomicWriteResult {
        let data = try CanonicalTranscriptionSerializer.encode(document)
        return try write(data: data, to: destinationURL, fileManager: fileManager)
    }

    /// Atomically writes `Data` to the destination URL using a temporary file and non-overwriting rename.
    ///
    /// - Parameters:
    ///   - data: The raw data bytes to write.
    ///   - destinationURL: The target destination file URL.
    ///   - fileManager: The `FileManager` instance to use (defaults to `.default`).
    /// - Returns: `.written(destinationURL)` on success, or `.skippedAlreadyExists(destinationURL)` if a file exists.
    /// - Throws: `AtomicFileWriterError` if the directory does not exist, destination is a directory,
    ///   or I/O fails.
    static func write(
        data: Data,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> AtomicWriteResult {
        let destination = destinationURL.standardizedFileURL
        let directory = destination.deletingLastPathComponent().standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AtomicFileWriterError.destinationDirectoryNotFound(directory)
        }

        var isDestDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDestDirectory) {
            if isDestDirectory.boolValue {
                throw AtomicFileWriterError.destinationIsDirectory(destination)
            }
            return .skippedAlreadyExists(destination)
        }

        let tempFilename = ".\(destination.lastPathComponent).tmp.\(UUID().uuidString)"
        let tempURL = directory.appendingPathComponent(tempFilename)

        var successfullyRenamed = false
        defer {
            if !successfullyRenamed {
                try? fileManager.removeItem(at: tempURL)
            }
        }

        do {
            try data.write(to: tempURL, options: .withoutOverwriting)
        } catch {
            throw AtomicFileWriterError.writeFailed(tempURL, error.localizedDescription)
        }

        let ret = renamex_np(tempURL.path, destination.path, UInt32(RENAME_EXCL))
        if ret == 0 {
            successfullyRenamed = true
            return .written(destination)
        }

        let moveErrno = errno
        if moveErrno == EEXIST {
            return .skippedAlreadyExists(destination)
        }

        if moveErrno == ENOTSUP {
            // Fallback for filesystems that do not support RENAME_EXCL
            let linkRet = link(tempURL.path, destination.path)
            if linkRet == 0 {
                _ = unlink(tempURL.path)
                successfullyRenamed = true
                return .written(destination)
            } else if errno == EEXIST {
                return .skippedAlreadyExists(destination)
            }
        }

        let errorMessage = String(cString: strerror(moveErrno))
        throw AtomicFileWriterError.moveFailed(source: tempURL, destination: destination, errorDescription: errorMessage)
    }
}
