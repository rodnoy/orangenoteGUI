//
//  BatchFileCollectorTests.swift
//  OrangeNoteTests
//
//  Unit tests for the batch queue file collector (Task 3.3).
//

import XCTest
@testable import OrangeNote

final class BatchFileCollectorTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchFileCollectorTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeDirectory(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Mixed valid/non-audio

    func testCollect_mixedAudioAndNonAudio_keepsOnlyAudioInOrder() throws {
        let mp3 = try makeFile(named: "one.mp3")
        let txt = try makeFile(named: "notes.txt")
        let wav = try makeFile(named: "two.wav")

        let items = BatchFileCollector.collect(from: [mp3, txt, wav])

        XCTAssertEqual(items.map(\.sourceURL), [mp3, wav])
        XCTAssertFalse(items.contains { $0.sourceURL == txt })
    }

    // MARK: - Directory skip

    func testCollect_directoryWithAudioExtension_isSkipped() throws {
        // Directory name deliberately has an audio-like extension to ensure
        // the directory check runs after the extension check.
        let dir = try makeDirectory(named: "folder.mp3")
        let realAudio = try makeFile(named: "real.mp3")

        let items = BatchFileCollector.collect(from: [dir, realAudio])

        XCTAssertEqual(items.map(\.sourceURL), [realAudio])
    }

    // MARK: - Inaccessible / non-existent

    func testCollect_nonExistentAudioFile_isSkipped() throws {
        let missing = tempDirectory.appendingPathComponent("missing.mp3")
        let existing = try makeFile(named: "existing.wav")

        let items = BatchFileCollector.collect(from: [missing, existing])

        XCTAssertEqual(items.map(\.sourceURL), [existing])
    }

    // MARK: - Empty input

    func testCollect_emptyArray_returnsEmptyArray() {
        let items = BatchFileCollector.collect(from: [])
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Resulting item shape

    func testCollect_resultingItems_areQueuedAndPreserveSourceURL() throws {
        let mp3 = try makeFile(named: "one.mp3")
        let wav = try makeFile(named: "two.wav")

        let items = BatchFileCollector.collect(from: [mp3, wav])

        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(item.status, .queued)
        }
        XCTAssertEqual(items[0].sourceURL, mp3)
        XCTAssertEqual(items[1].sourceURL, wav)
    }
}
