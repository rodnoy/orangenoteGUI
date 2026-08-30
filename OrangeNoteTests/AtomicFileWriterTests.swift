//
//  AtomicFileWriterTests.swift
//  OrangeNoteTests
//
//  Unit tests for AtomicFileWriter verifying atomic non-overwriting writes,
//  refuse-overwrite semantics, temp file cleanup, error paths, and Unicode paths.
//

import XCTest
@testable import OrangeNote

final class AtomicFileWriterTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let uniqueFolder = "AtomicFileWriterTests_\(UUID().uuidString)"
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Fresh Write Success

    func testWriteData_freshFile_writesSuccessfullyAndReturnsWritten() throws {
        let destination = tempDirectory.appendingPathComponent("output.json")
        let data = "{\"test\": true}".data(using: .utf8)!

        let result = try AtomicFileWriter.write(data: data, to: destination)

        XCTAssertEqual(result, .written(destination.standardizedFileURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let readData = try Data(contentsOf: destination)
        XCTAssertEqual(readData, data)

        // Verify no leftover temporary files in directory
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(files, ["output.json"])
    }

    func testWriteData_emptyData_writesSuccessfully() throws {
        let destination = tempDirectory.appendingPathComponent("empty.json")
        let data = Data()

        let result = try AtomicFileWriter.write(data: data, to: destination)

        XCTAssertEqual(result, .written(destination.standardizedFileURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let readData = try Data(contentsOf: destination)
        XCTAssertEqual(readData, data)
    }

    // MARK: - Refuse Overwrite Semantics (D018)

    func testWriteData_destinationAlreadyExists_returnsSkippedAndDoesNotOverwrite() throws {
        let destination = tempDirectory.appendingPathComponent("existing.json")
        let originalData = "original-content".data(using: .utf8)!
        try originalData.write(to: destination)

        let newData = "new-content-that-should-be-refused".data(using: .utf8)!
        let result = try AtomicFileWriter.write(data: newData, to: destination)

        XCTAssertEqual(result, .skippedAlreadyExists(destination.standardizedFileURL))

        // Existing file must NOT have been modified
        let currentData = try Data(contentsOf: destination)
        XCTAssertEqual(currentData, originalData)

        // No leftover temporary files
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(files, ["existing.json"])
    }

    // MARK: - Document Serialization & Atomic Write

    func testWriteDocument_validCanonicalDocument_writesFormattedJsonSuccessfully() throws {
        let destination = tempDirectory.appendingPathComponent("document.json")
        let sampleResult = TranscriptionResult(
            segments: [
                TranscriptionSegment(
                    id: UUID(),
                    startTime: 0.0,
                    endTime: 1.5,
                    text: "Hello world"
                )
            ],
            fullText: "Hello world",
            language: "en",
            duration: 1.5
        )

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: sampleResult,
            sourceFileName: "audio.mp3",
            sourceURL: URL(fileURLWithPath: "/path/to/audio.mp3"),
            modelName: "ggml-base.bin",
            engineID: "whisper-local"
        )

        let result = try AtomicFileWriter.write(document: document, to: destination)

        XCTAssertEqual(result, .written(destination.standardizedFileURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let writtenData = try Data(contentsOf: destination)
        let decodedDocument = try CanonicalTranscriptionSerializer.decode(writtenData)

        XCTAssertEqual(decodedDocument.schemaVersion, 1)
        XCTAssertEqual(decodedDocument.source.fileName, "audio.mp3")
        XCTAssertEqual(decodedDocument.engine.model, "ggml-base.bin")
        XCTAssertEqual(decodedDocument.engine.id, "whisper-local")
        XCTAssertEqual(decodedDocument.transcription.fullText, "Hello world")
        XCTAssertEqual(decodedDocument.transcription.segments.count, 1)
        XCTAssertEqual(decodedDocument.transcription.segments[0].text, "Hello world")
    }

    func testWriteDocument_destinationAlreadyExists_returnsSkippedWithoutModifying() throws {
        let destination = tempDirectory.appendingPathComponent("document_existing.json")
        let initialData = "{\"preserved\": true}".data(using: .utf8)!
        try initialData.write(to: destination)

        let sampleResult = TranscriptionResult(
            segments: [],
            fullText: "Fresh text",
            language: "en",
            duration: 0.0
        )
        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: sampleResult,
            sourceFileName: "audio.mp3",
            modelName: "ggml-base.bin",
            engineID: "whisper-local"
        )

        let result = try AtomicFileWriter.write(document: document, to: destination)

        XCTAssertEqual(result, .skippedAlreadyExists(destination.standardizedFileURL))
        let readData = try Data(contentsOf: destination)
        XCTAssertEqual(readData, initialData)
    }

    // MARK: - Paths with Unicode, Spaces, and Emoji

    func testWriteData_unicodeSpacesAndEmoji_writesSuccessfully() throws {
        let subfolder = tempDirectory.appendingPathComponent("Тестовая Папка 📁 2026/Подпапка с пробелами", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)

        let destination = subfolder.appendingPathComponent("файл с пробелами и эмодзи 🎙️.json")
        let data = "{\"unicode\": \"тест\"}".data(using: .utf8)!

        let result = try AtomicFileWriter.write(data: data, to: destination)

        XCTAssertEqual(result, .written(destination.standardizedFileURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let readData = try Data(contentsOf: destination)
        XCTAssertEqual(readData, data)
    }

    // MARK: - Error Handling Paths

    func testWriteData_nonExistentDirectory_throwsDestinationDirectoryNotFound() {
        let nonExistentDir = tempDirectory.appendingPathComponent("does_not_exist_\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        let destination = nonExistentDir.appendingPathComponent("output.json")
        let data = "data".data(using: .utf8)!

        XCTAssertThrowsError(try AtomicFileWriter.write(data: data, to: destination)) { error in
            guard let writerError = error as? AtomicFileWriterError else {
                XCTFail("Expected AtomicFileWriterError, got \(error)")
                return
            }
            XCTAssertEqual(writerError, .destinationDirectoryNotFound(nonExistentDir))
        }
    }

    func testWriteData_destinationIsDirectory_throwsDestinationIsDirectory() throws {
        let dirDestination = tempDirectory.appendingPathComponent("existing_folder", isDirectory: true)
        try FileManager.default.createDirectory(at: dirDestination, withIntermediateDirectories: true)
        let data = "data".data(using: .utf8)!

        XCTAssertThrowsError(try AtomicFileWriter.write(data: data, to: dirDestination)) { error in
            guard let writerError = error as? AtomicFileWriterError else {
                XCTFail("Expected AtomicFileWriterError, got \(error)")
                return
            }
            XCTAssertEqual(writerError, .destinationIsDirectory(dirDestination.standardizedFileURL))
        }
    }

    func testWriteData_readOnlyDirectory_throwsWriteFailedAndCleansUpTemp() throws {
        let readOnlyDir = tempDirectory.appendingPathComponent("read_only_dir", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)

        // Set directory permissions to read-only (0555)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)

        defer {
            // Restore write permissions so tearDown can delete the folder
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        }

        let destination = readOnlyDir.appendingPathComponent("output.json")
        let data = "sample".data(using: .utf8)!

        XCTAssertThrowsError(try AtomicFileWriter.write(data: data, to: destination)) { error in
            guard let writerError = error as? AtomicFileWriterError else {
                XCTFail("Expected AtomicFileWriterError, got \(error)")
                return
            }
            if case .writeFailed = writerError {
                // Success - write failed as expected
            } else {
                XCTFail("Expected writeFailed, got \(writerError)")
            }
        }

        // Restore permissions to inspect contents
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: readOnlyDir.path)
        XCTAssertTrue(remainingFiles.isEmpty, "Temporary file should have been cleaned up on write failure")
    }

    func testAtomicFileWriterError_descriptions_returnExpectedMessages() {
        let sampleURL = URL(fileURLWithPath: "/path/to/item")
        let sampleDestURL = URL(fileURLWithPath: "/path/to/dest")

        let dirNotFoundError = AtomicFileWriterError.destinationDirectoryNotFound(sampleURL)
        XCTAssertTrue(dirNotFoundError.errorDescription?.contains("Destination directory does not exist") == true)

        let isDirError = AtomicFileWriterError.destinationIsDirectory(sampleURL)
        XCTAssertTrue(isDirError.errorDescription?.contains("Destination path is a directory") == true)

        let writeError = AtomicFileWriterError.writeFailed(sampleURL, "disk full")
        XCTAssertTrue(writeError.errorDescription?.contains("Failed to write temporary file") == true)
        XCTAssertTrue(writeError.errorDescription?.contains("disk full") == true)

        let moveError = AtomicFileWriterError.moveFailed(source: sampleURL, destination: sampleDestURL, errorDescription: "permission denied")
        XCTAssertTrue(moveError.errorDescription?.contains("Failed to move temporary file") == true)
        XCTAssertTrue(moveError.errorDescription?.contains("permission denied") == true)
    }
}
