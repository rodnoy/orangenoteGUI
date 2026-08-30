//
//  DropItemResolverTests.swift
//  OrangeNoteTests
//
//  Unit tests for the pure resolution logic in DropItemResolver.
//

import XCTest
@testable import OrangeNote

final class DropItemResolverTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropItemResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    private func makeFolder(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Single valid file

    func testResolve_singleValidAudioFile_isAccepted() throws {
        let url = try makeFile(named: "song.mp3")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: false)

        XCTAssertEqual(resolution, .accepted(url))
        XCTAssertEqual(resolution.singleFileURL, url)
        XCTAssertNotNil(resolution.batchIngestionResult)
    }

    // MARK: - Non-audio single file rejection

    func testResolve_singleNonAudioFile_isRejectedAsInvalid() throws {
        let url = try makeFile(named: "notes.txt")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: false)

        guard case .invalidFile(let error) = resolution else {
            return XCTFail("Expected .invalidFile, got \(resolution)")
        }
        XCTAssertEqual(error, .unsupportedFormat("txt"))
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Multi-file drop (Phase 3 Evolution)

    func testResolve_multipleAudioFiles_resolvesToBatch() throws {
        let first = try makeFile(named: "a.mp3")
        let second = try makeFile(named: "b.wav")

        let resolution = DropItemResolver.resolve(urls: [first, second], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 2)
        XCTAssertEqual(ingestion.items.map(\.sourceURL.lastPathComponent), ["a.mp3", "b.wav"])
        XCTAssertNil(resolution.localizedMessage)
    }

    func testResolveSingleFileOnly_multipleFilesDropped_isRejectedWithCount() throws {
        let first = try makeFile(named: "a.mp3")
        let second = try makeFile(named: "b.wav")

        let resolution = DropItemResolver.resolveSingleFileOnly(urls: [first, second], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMultipleItems(count: 2))
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_zeroFilesResolved_isRejectedWithZeroCount() {
        let resolution = DropItemResolver.resolve(urls: [], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMultipleItems(count: 0))
    }

    // MARK: - Single Top-Level Folder

    func testResolve_singleFolderWithAudio_resolvesToBatch() throws {
        let folder = try makeFolder(named: "AudioFolder")
        let file1 = folder.appendingPathComponent("track1.mp3")
        let file2 = folder.appendingPathComponent("track2.wav")
        try Data("audio1".utf8).write(to: file1)
        try Data("audio2".utf8).write(to: file2)

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 2)
        XCTAssertEqual(ingestion.source, .folder(folder.standardizedFileURL))
    }

    func testResolve_singleFolderWithNoAudio_reportsNoAudioFilesFound() throws {
        let folder = try makeFolder(named: "EmptyFolder")
        let txt = folder.appendingPathComponent("notes.txt")
        try Data("text".utf8).write(to: txt)

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: false)

        XCTAssertEqual(resolution, .noAudioFilesFound)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Mixed drops and multi-folders (D029)

    func testResolve_folderAndFileTogether_isRejectedAsMixedItems() throws {
        let folder = try makeFolder(named: "AudioFolder")
        let file = try makeFile(named: "extra.mp3")

        let resolution = DropItemResolver.resolve(urls: [folder, file], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMixedItems)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_multipleFoldersTogether_isRejectedAsMixedItems() throws {
        let folder1 = try makeFolder(named: "Folder1")
        let folder2 = try makeFolder(named: "Folder2")

        let resolution = DropItemResolver.resolve(urls: [folder1, folder2], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMixedItems)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Reject while transcribing (D010)

    func testResolve_whileTranscribing_rejectsEvenValidSingleFile() throws {
        let url = try makeFile(named: "song.mp3")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: true)

        XCTAssertEqual(resolution, .rejectedTranscribing)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_whileTranscribing_rejectsMultipleFilesAsTranscribingNotMultiple() throws {
        let first = try makeFile(named: "a.mp3")
        let second = try makeFile(named: "b.wav")

        let resolution = DropItemResolver.resolve(urls: [first, second], isTranscribing: true)

        // Active-transcription rejection takes precedence over the multi-item check.
        XCTAssertEqual(resolution, .rejectedTranscribing)
    }

    // MARK: - Accepted case has no message

    func testAccepted_hasNoLocalizedMessage() throws {
        let url = try makeFile(named: "song.mp3")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: false)

        XCTAssertNil(resolution.localizedMessage)
    }
}
