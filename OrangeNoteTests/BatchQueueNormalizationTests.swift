//
//  BatchQueueNormalizationTests.swift
//  OrangeNoteTests
//
//  Unit tests for URL normalization, deduplication, and full-path sorting (Task 3.5).
//

import XCTest
@testable import OrangeNote

final class BatchQueueNormalizationTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchQueueNormalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? tempDirectory!
        let url = dir.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    private func makeSubdirectory(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Deduplication

    func testDeduplication_identicalURLs_keepsSingleItem() throws {
        let file = try makeFile(named: "sample.mp3")

        let items = BatchFileCollector.collect(from: [file, file, file])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceURL, file.standardizedFileURL)
    }

    func testDeduplication_nonStandardizedPaths_deduplicatesToStandardizedURL() throws {
        let file = try makeFile(named: "track.mp3")
        _ = try makeSubdirectory(named: "sub")

        // Construct non-standardized URLs pointing to the same file on disk
        let nonStandardURL1 = tempDirectory.appendingPathComponent("sub/../track.mp3")
        let nonStandardURL2 = tempDirectory.appendingPathComponent("./track.mp3")

        let items = BatchFileCollector.collect(from: [nonStandardURL1, file, nonStandardURL2])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceURL.path, file.standardizedFileURL.path)
    }

    // MARK: - Natural Sorting (localizedStandardCompare)

    func testSorting_naturalOrder_sortsNumerically() throws {
        let track1 = try makeFile(named: "track1.mp3")
        let track2 = try makeFile(named: "track2.mp3")
        let track10 = try makeFile(named: "track10.mp3")
        let track20 = try makeFile(named: "track20.mp3")

        // Provide in reverse/mixed order
        let items = BatchFileCollector.collect(from: [track20, track10, track2, track1])

        XCTAssertEqual(items.map(\.sourceURL.path), [
            track1.standardizedFileURL.path,
            track2.standardizedFileURL.path,
            track10.standardizedFileURL.path,
            track20.standardizedFileURL.path
        ])
    }

    // MARK: - Full-Path Sorting (not filename only)

    func testSorting_fullPathHierarchy_sortsByFullPathNotFilenameOnly() throws {
        let dirA = try makeSubdirectory(named: "alpha")
        let dirB = try makeSubdirectory(named: "beta")

        let songInB = try makeFile(named: "song.mp3", in: dirB)
        let songInA = try makeFile(named: "song.mp3", in: dirA)

        // songInB is passed before songInA, but alpha/song.mp3 should sort before beta/song.mp3
        let items = BatchFileCollector.collect(from: [songInB, songInA])

        XCTAssertEqual(items.map(\.sourceURL.path), [
            songInA.standardizedFileURL.path,
            songInB.standardizedFileURL.path
        ])
    }

    // MARK: - Normalize BatchItems directly

    func testNormalize_batchItemsArray_standardizesDeduplicatesAndSorts() throws {
        let track1 = try makeFile(named: "track1.mp3")
        let track2 = try makeFile(named: "track2.mp3")
        let track10 = try makeFile(named: "track10.mp3")

        let nonStandardTrack1 = tempDirectory.appendingPathComponent("./track1.mp3")

        let rawItems = [
            BatchItem(sourceURL: track10),
            BatchItem(sourceURL: nonStandardTrack1),
            BatchItem(sourceURL: track1),
            BatchItem(sourceURL: track2),
            BatchItem(sourceURL: track10)
        ]

        let normalized = BatchFileCollector.normalize(items: rawItems)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized.map(\.sourceURL.path), [
            track1.standardizedFileURL.path,
            track2.standardizedFileURL.path,
            track10.standardizedFileURL.path
        ])
        for item in normalized {
            XCTAssertEqual(item.status, .queued)
        }
    }

    // MARK: - Empty Input

    func testNormalize_emptyArray_returnsEmpty() {
        let items = BatchFileCollector.normalize(items: [])
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Top-Level Folder Integration

    func testCollectTopLevel_appliesNaturalSortingAndDeduplication() throws {
        let file10 = try makeFile(named: "chapter10.mp3")
        let file1 = try makeFile(named: "chapter1.mp3")
        let file2 = try makeFile(named: "chapter2.mp3")

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)

        XCTAssertEqual(items.map(\.sourceURL.path), [
            file1.standardizedFileURL.path,
            file2.standardizedFileURL.path,
            file10.standardizedFileURL.path
        ])
    }
}
