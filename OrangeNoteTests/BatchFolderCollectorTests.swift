//
//  BatchFolderCollectorTests.swift
//  OrangeNoteTests
//
//  Unit tests for top-level (non-recursive) folder ingestion (Task 3.4 / D020).
//

import XCTest
@testable import OrangeNote

final class BatchFolderCollectorTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchFolderCollectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    private func makeSubdirectory(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Top-level mixed audio/non-audio

    func testCollectTopLevel_mixedAudioAndNonAudio_keepsOnlyAudio() throws {
        let mp3 = try makeFile(named: "one.mp3", in: tempDirectory)
        let wav = try makeFile(named: "two.wav", in: tempDirectory)
        _ = try makeFile(named: "notes.txt", in: tempDirectory)

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)

        XCTAssertEqual(Set(items.map(\.sourceURL)), Set([mp3, wav]))
    }

    // MARK: - Nested subfolder is not traversed

    func testCollectTopLevel_nestedSubfolder_isNotTraversed() throws {
        let topAudio = try makeFile(named: "top.mp3", in: tempDirectory)
        let subDir = try makeSubdirectory(named: "nested", in: tempDirectory)
        let nestedAudio = try makeFile(named: "nested.mp3", in: subDir)

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)

        XCTAssertEqual(items.map(\.sourceURL), [topAudio])
        XCTAssertFalse(items.contains { $0.sourceURL == nestedAudio })
    }

    // MARK: - Hidden file exclusion

    func testCollectTopLevel_hiddenAudioFile_isExcluded() throws {
        let visible = try makeFile(named: "visible.mp3", in: tempDirectory)
        _ = try makeFile(named: ".hidden.mp3", in: tempDirectory)

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)

        XCTAssertEqual(items.map(\.sourceURL), [visible])
    }

    // MARK: - Empty folder

    func testCollectTopLevel_emptyFolder_returnsEmptyArray() {
        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Non-existent folder

    func testCollectTopLevel_nonExistentFolder_returnsEmptyArray() {
        let missing = tempDirectory.appendingPathComponent("does-not-exist", isDirectory: true)
        let items = BatchFileCollector.collectTopLevel(fromFolder: missing)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Resulting item shape

    func testCollectTopLevel_resultingItems_areQueuedWithCorrectSourceURL() throws {
        let mp3 = try makeFile(named: "one.mp3", in: tempDirectory)

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].sourceURL, mp3)
        XCTAssertEqual(items[0].status, .queued)
    }
}
