//
//  BatchDropItemResolverTests.swift
//  OrangeNoteTests
//
//  Unit tests for Task 3.14 (Multi-File / Folder Drag & Drop Evolution).
//  Tests pure resolution logic, folder-vs-files detection, audio type filtering,
//  deduplication, mixed-drop rejection (D029), and async NSItemProvider resolution.
//

import XCTest
import UniformTypeIdentifiers
@testable import OrangeNote

final class BatchDropItemResolverTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchDropItemResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String, content: String = "test") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func makeFolder(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Single Audio File Drops

    func testResolve_singleAudioFile_isAccepted() throws {
        let url = try makeFile(named: "interview.mp3")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: false)

        XCTAssertEqual(resolution, .accepted(url.standardizedFileURL))
        XCTAssertEqual(resolution.singleFileURL, url.standardizedFileURL)
        XCTAssertEqual(resolution.batchIngestionResult?.count, 1)
        XCTAssertEqual(resolution.batchIngestionResult?.source, .files([url.standardizedFileURL]))
        XCTAssertNil(resolution.localizedMessage)
    }

    func testResolve_singleNonAudioFile_isInvalidFile() throws {
        let url = try makeFile(named: "transcript.docx")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: false)

        guard case .invalidFile(let error) = resolution else {
            return XCTFail("Expected .invalidFile, got \(resolution)")
        }
        XCTAssertEqual(error, .unsupportedFormat("docx"))
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Multi-File Drops

    func testResolve_multipleAudioFiles_collectsAllIntoBatch() throws {
        let f1 = try makeFile(named: "track1.mp3")
        let f2 = try makeFile(named: "track2.wav")
        let f3 = try makeFile(named: "track3.flac")

        let resolution = DropItemResolver.resolve(urls: [f3, f1, f2], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 3)
        // Natural full-path sort order
        XCTAssertEqual(ingestion.items.map(\.sourceURL.lastPathComponent), ["track1.mp3", "track2.wav", "track3.flac"])
        XCTAssertEqual(ingestion.source, .files([f1.standardizedFileURL, f2.standardizedFileURL, f3.standardizedFileURL]))
        XCTAssertNil(resolution.localizedMessage)
    }

    func testResolve_multipleFilesWithDuplicates_deduplicatesByPath() throws {
        let f1 = try makeFile(named: "track1.mp3")
        let f2 = try makeFile(named: "track2.wav")

        let resolution = DropItemResolver.resolve(urls: [f1, f2, f1, f2], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 2)
    }

    func testResolve_mixedAudioAndNonAudioFiles_filtersNonAudio() throws {
        let audio1 = try makeFile(named: "song.m4a")
        let txt = try makeFile(named: "readme.txt")
        let audio2 = try makeFile(named: "podcast.ogg")
        let pdf = try makeFile(named: "notes.pdf")

        let resolution = DropItemResolver.resolve(urls: [audio1, txt, audio2, pdf], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 2)
        XCTAssertEqual(ingestion.items.map(\.sourceURL.lastPathComponent), ["podcast.ogg", "song.m4a"])
    }

    func testResolve_multipleFilesWithZeroSupportedAudio_reportsNoAudioFilesFound() throws {
        let f1 = try makeFile(named: "a.txt")
        let f2 = try makeFile(named: "b.pdf")
        let f3 = try makeFile(named: "c.png")

        let resolution = DropItemResolver.resolve(urls: [f1, f2, f3], isTranscribing: false)

        XCTAssertEqual(resolution, .noAudioFilesFound)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Folder Drops (Top-Level Ingestion per D020)

    func testResolve_singleFolderWithAudioFiles_collectsTopLevelBatch() throws {
        let folder = try makeFolder(named: "Session1")
        _ = try makeFile(named: "Session1/recording1.mp3")
        _ = try makeFile(named: "Session1/recording2.wav")
        _ = try makeFile(named: "Session1/notes.txt")

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 2)
        XCTAssertEqual(ingestion.items.map(\.sourceURL.lastPathComponent), ["recording1.mp3", "recording2.wav"])
        XCTAssertEqual(ingestion.source, .folder(folder.standardizedFileURL))
    }

    func testResolve_singleFolderNonRecursive_ignoresSubdirectoryAudio() throws {
        let folder = try makeFolder(named: "Session2")
        _ = try makeFile(named: "Session2/top.mp3")
        _ = try makeFolder(named: "Session2/Sub")
        _ = try makeFile(named: "Session2/Sub/nested.mp3")

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: false)

        guard case .batch(let ingestion) = resolution else {
            return XCTFail("Expected .batch, got \(resolution)")
        }
        XCTAssertEqual(ingestion.count, 1)
        XCTAssertEqual(ingestion.items.first?.sourceURL.lastPathComponent, "top.mp3")
    }

    func testResolve_singleFolderWithNoAudio_reportsNoAudioFilesFound() throws {
        let folder = try makeFolder(named: "EmptyFolder")
        _ = try makeFile(named: "EmptyFolder/notes.txt")

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: false)

        XCTAssertEqual(resolution, .noAudioFilesFound)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Mixed Item & Multi-Folder Rejection (D029)

    func testResolve_folderAndFileInOneDrop_isRejectedAsMixedItems() throws {
        let folder = try makeFolder(named: "AudioDir")
        let file = try makeFile(named: "track.mp3")

        let resolution = DropItemResolver.resolve(urls: [folder, file], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMixedItems)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_multipleFoldersInOneDrop_isRejectedAsMixedItems() throws {
        let folder1 = try makeFolder(named: "Dir1")
        let folder2 = try makeFolder(named: "Dir2")

        let resolution = DropItemResolver.resolve(urls: [folder1, folder2], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMixedItems)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Active Transcription Guard (D010)

    func testResolve_whileTranscribing_rejectsSingleAudioFile() throws {
        let url = try makeFile(named: "song.mp3")

        let resolution = DropItemResolver.resolve(urls: [url], isTranscribing: true)

        XCTAssertEqual(resolution, .rejectedTranscribing)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_whileTranscribing_rejectsMultipleAudioFiles() throws {
        let f1 = try makeFile(named: "a.mp3")
        let f2 = try makeFile(named: "b.wav")

        let resolution = DropItemResolver.resolve(urls: [f1, f2], isTranscribing: true)

        XCTAssertEqual(resolution, .rejectedTranscribing)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    func testResolve_whileTranscribing_rejectsFolderDrop() throws {
        let folder = try makeFolder(named: "AudioDir")

        let resolution = DropItemResolver.resolve(urls: [folder], isTranscribing: true)

        XCTAssertEqual(resolution, .rejectedTranscribing)
        XCTAssertNotNil(resolution.localizedMessage)
    }

    // MARK: - Empty URLs List

    func testResolve_emptyList_rejectsWithZeroCount() {
        let resolution = DropItemResolver.resolve(urls: [], isTranscribing: false)

        XCTAssertEqual(resolution, .rejectedMultipleItems(count: 0))
    }

    // MARK: - Async Provider Extraction (extractAndResolve)

    func testExtractAndResolve_singleAudioProvider_resolvesToAccepted() throws {
        let file = try makeFile(named: "solo.mp3")
        let provider = NSItemProvider(contentsOf: file)!

        let expectation = expectation(description: "single audio provider")

        DropItemResolver.extractAndResolve(from: [provider], isTranscribing: false) { resolution in
            XCTAssertEqual(resolution, .accepted(file.standardizedFileURL))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_multipleAudioProviders_resolvesToBatch() throws {
        let f1 = try makeFile(named: "part1.mp3")
        let f2 = try makeFile(named: "part2.wav")
        let providers = [NSItemProvider(contentsOf: f1)!, NSItemProvider(contentsOf: f2)!]

        let expectation = expectation(description: "multiple audio providers")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            guard case .batch(let ingestion) = resolution else {
                return XCTFail("Expected .batch, got \(resolution)")
            }
            XCTAssertEqual(ingestion.count, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_folderProvider_resolvesToBatch() throws {
        let folder = try makeFolder(named: "Album")
        _ = try makeFile(named: "Album/track1.mp3")
        _ = try makeFile(named: "Album/track2.aac")
        let provider = NSItemProvider(contentsOf: folder)!

        let expectation = expectation(description: "folder provider")

        DropItemResolver.extractAndResolve(from: [provider], isTranscribing: false) { resolution in
            guard case .batch(let ingestion) = resolution else {
                return XCTFail("Expected .batch, got \(resolution)")
            }
            XCTAssertEqual(ingestion.count, 2)
            XCTAssertEqual(ingestion.source, .folder(folder.standardizedFileURL))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_mixedFolderAndFileProviders_rejectsAsMixed() throws {
        let folder = try makeFolder(named: "Dir")
        let file = try makeFile(named: "song.mp3")
        let providers = [NSItemProvider(contentsOf: folder)!, NSItemProvider(contentsOf: file)!]

        let expectation = expectation(description: "mixed providers")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            XCTAssertEqual(resolution, .rejectedMixedItems)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_whileTranscribing_rejectsImmediately() throws {
        let file = try makeFile(named: "song.mp3")
        let provider = NSItemProvider(contentsOf: file)!

        let expectation = expectation(description: "transcribing rejection")

        DropItemResolver.extractAndResolve(from: [provider], isTranscribing: true) { resolution in
            XCTAssertEqual(resolution, .rejectedTranscribing)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
