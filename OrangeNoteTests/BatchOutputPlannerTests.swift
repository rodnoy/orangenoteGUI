//
//  BatchOutputPlannerTests.swift
//  OrangeNoteTests
//
//  Unit tests for BatchOutputPlanner (Task 3.6 / D017 / D018).
//

import XCTest
@testable import OrangeNote

final class BatchOutputPlannerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchOutputPlannerTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL = temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        try super.tearDownWithError()
    }

    // MARK: - Path Computation Tests (D017)

    func testComputeOutputURL_standardFilename_producesBasenameDotJson() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/Audio/interview.mp3")
        let outputDir = URL(fileURLWithPath: "/Users/test/Transcripts")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Users/test/Transcripts/interview.json")
        XCTAssertEqual(outputURL.lastPathComponent, "interview.json")
    }

    func testComputeOutputURL_filenameWithMultipleDots_preservesFullBasename() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/Audio/meeting.01.2026.final.wav")
        let outputDir = URL(fileURLWithPath: "/Users/test/Transcripts")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Users/test/Transcripts/meeting.01.2026.final.json")
        XCTAssertEqual(outputURL.lastPathComponent, "meeting.01.2026.final.json")
    }

    func testComputeOutputURL_filenameWithSpacesAndUnicode_preservesExactBasename() {
        let sourceURL = URL(fileURLWithPath: "/Audio/Запись встречи 2026.m4a")
        let outputDir = URL(fileURLWithPath: "/Users/test/Transcripts")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Users/test/Transcripts/Запись встречи 2026.json")
    }

    func testComputeOutputURL_specialCharactersAndEmoji_preservesExactBasename() {
        let sourceURL = URL(fileURLWithPath: "/Audio/🎵 track #1 (live).flac")
        let outputDir = URL(fileURLWithPath: "/Transcripts")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Transcripts/🎵 track #1 (live).json")
    }

    func testComputeOutputURL_uppercaseExtension_producesJsonExtension() {
        let sourceURL = URL(fileURLWithPath: "/Audio/RECORDING.WAV")
        let outputDir = URL(fileURLWithPath: "/Transcripts")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Transcripts/RECORDING.json")
    }

    func testComputeOutputURL_destinationWithRelativeSegments_standardizesCleanly() {
        let sourceURL = URL(fileURLWithPath: "/Audio/test.opus")
        let outputDir = URL(fileURLWithPath: "/Users/test/Transcripts/sub/../")

        let outputURL = BatchOutputPlanner.computeOutputURL(for: sourceURL, in: outputDir)

        XCTAssertEqual(outputURL.path, "/Users/test/Transcripts/test.opus.json" == outputURL.path ? "" : "/Users/test/Transcripts/test.json")
        XCTAssertEqual(outputURL.path, "/Users/test/Transcripts/test.json")
    }

    // MARK: - Batch Planning and Skip Detection Tests (D018)

    func testPlan_whenOutputFileDoesNotExist_assignsOutputURLAndRetainsQueuedStatus() {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("audio1.mp3")
        let item = BatchItem(sourceURL: sourceURL)

        let plannedItems = BatchOutputPlanner.plan(items: [item], destinationDirectory: temporaryDirectoryURL)

        XCTAssertEqual(plannedItems.count, 1)
        XCTAssertEqual(plannedItems[0].status, .queued)
        XCTAssertEqual(plannedItems[0].outputURL?.path, temporaryDirectoryURL.appendingPathComponent("audio1.json").path)
    }

    func testPlan_whenOutputFileAlreadyExists_assignsOutputURLAndMarksSkipped() throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("existing_audio.wav")
        let existingOutputURL = temporaryDirectoryURL.appendingPathComponent("existing_audio.json")

        // Pre-create the output JSON on disk
        try "{}".write(to: existingOutputURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingOutputURL.path))

        let item = BatchItem(sourceURL: sourceURL)
        let plannedItems = BatchOutputPlanner.plan(items: [item], destinationDirectory: temporaryDirectoryURL)

        XCTAssertEqual(plannedItems.count, 1)
        XCTAssertEqual(plannedItems[0].status, .skipped)
        XCTAssertEqual(plannedItems[0].outputURL?.path, existingOutputURL.path)
    }

    func testPlan_mixedExistingAndNonExistingFiles_marksOnlyExistingAsSkipped() throws {
        let source1 = temporaryDirectoryURL.appendingPathComponent("first.mp3")
        let source2 = temporaryDirectoryURL.appendingPathComponent("second.mp3")
        let source3 = temporaryDirectoryURL.appendingPathComponent("third.mp3")

        // Pre-create output JSON only for the second item
        let existingOutputURL2 = temporaryDirectoryURL.appendingPathComponent("second.json")
        try "{}".write(to: existingOutputURL2, atomically: true, encoding: .utf8)

        let items = [
            BatchItem(sourceURL: source1),
            BatchItem(sourceURL: source2),
            BatchItem(sourceURL: source3)
        ]

        let plannedItems = BatchOutputPlanner.plan(items: items, destinationDirectory: temporaryDirectoryURL)

        XCTAssertEqual(plannedItems.count, 3)

        XCTAssertEqual(plannedItems[0].status, .queued)
        XCTAssertEqual(plannedItems[0].outputURL?.path, temporaryDirectoryURL.appendingPathComponent("first.json").path)

        XCTAssertEqual(plannedItems[1].status, .skipped)
        XCTAssertEqual(plannedItems[1].outputURL?.path, temporaryDirectoryURL.appendingPathComponent("second.json").path)

        XCTAssertEqual(plannedItems[2].status, .queued)
        XCTAssertEqual(plannedItems[2].outputURL?.path, temporaryDirectoryURL.appendingPathComponent("third.json").path)
    }

    func testPlan_previouslySkippedItem_whenOutputFileDoesNotExist_resetsToQueued() {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("fresh.mp3")
        let item = BatchItem(sourceURL: sourceURL, status: .skipped)

        let plannedItems = BatchOutputPlanner.plan(items: [item], destinationDirectory: temporaryDirectoryURL)

        XCTAssertEqual(plannedItems.count, 1)
        XCTAssertEqual(plannedItems[0].status, .queued)
        XCTAssertEqual(plannedItems[0].outputURL?.path, temporaryDirectoryURL.appendingPathComponent("fresh.json").path)
    }

    func testPlan_emptyItemsArray_returnsEmptyArray() {
        let plannedItems = BatchOutputPlanner.plan(items: [], destinationDirectory: temporaryDirectoryURL)
        XCTAssertTrue(plannedItems.isEmpty)
    }
}
