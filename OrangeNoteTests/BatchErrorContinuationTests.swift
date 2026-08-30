//
//  BatchErrorContinuationTests.swift
//  OrangeNoteTests
//
//  Unit tests for Task 3.9 (Per-Item Failure Isolation & Continuation / D016),
//  verifying continue-on-failure guarantees, structured error recording,
//  aggregated batch summary correctness, mixed outcomes ordering, and cancellation interplay.
//

import XCTest
@testable import OrangeNote

final class BatchErrorContinuationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchErrorContinuationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func makeDummyResult(text: String = "Transcribed text") -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 3.0, text: text)
            ],
            fullText: text,
            language: "en",
            duration: 3.0
        )
    }

    private func createDummyAudioFile(name: String) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        let dummyData = "dummy-audio-content".data(using: .utf8)!
        try dummyData.write(to: fileURL)
        return fileURL
    }

    // MARK: - 1. Transient Engine Failures in Middle of Queue

    func testProcessBatch_transientEngineFailure_isolatesFailureAndContinuesQueue() async throws {
        let audio1 = try createDummyAudioFile(name: "file1.mp3")
        let audio2 = try createDummyAudioFile(name: "file2_transient_error.mp3")
        let audio3 = try createDummyAudioFile(name: "file3.mp3")
        let audio4 = try createDummyAudioFile(name: "file4.mp3")

        let result1 = makeDummyResult(text: "Result 1")
        let result3 = makeDummyResult(text: "Result 3")
        let result4 = makeDummyResult(text: "Result 4")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            resultsSequence: [result1, result3, result4],
            errorsSequence: [
                nil,
                MockTranscriptionEngineError(message: "Transient Metal GPU timeout"),
                nil,
                nil
            ]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3),
            BatchItem(sourceURL: audio4)
        ]

        let processResult = await coordinator.processBatchWithSummary(
            items: items,
            destinationDirectory: tempDirectory
        )

        let processedItems = processResult.items
        XCTAssertEqual(processedItems.count, 4)

        // Item 1: Succeeded
        XCTAssertEqual(processedItems[0].status, .succeeded)
        XCTAssertEqual(processedItems[0].result?.fullText, "Result 1")
        XCTAssertNil(processedItems[0].errorMessage)
        XCTAssertEqual(processedItems[0].progress, 1.0)

        // Item 2: Failed with structured error
        XCTAssertEqual(processedItems[1].status, .failed)
        XCTAssertNil(processedItems[1].result)
        XCTAssertEqual(processedItems[1].progress, 0.0)
        XCTAssertEqual(processedItems[1].errorMessage, "Transient Metal GPU timeout")

        // Item 3: Succeeded (queue did NOT abort!)
        XCTAssertEqual(processedItems[2].status, .succeeded)
        XCTAssertEqual(processedItems[2].result?.fullText, "Result 3")
        XCTAssertNil(processedItems[2].errorMessage)

        // Item 4: Succeeded
        XCTAssertEqual(processedItems[3].status, .succeeded)
        XCTAssertEqual(processedItems[3].result?.fullText, "Result 4")
        XCTAssertNil(processedItems[3].errorMessage)

        // Summary verification
        let summary = processResult.summary
        XCTAssertEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.succeededCount, 3)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertFalse(summary.isAllSucceeded)
        XCTAssertTrue(summary.hasFailures)
        XCTAssertEqual(summary.completedCount, 4)

        let totalInvocations = await mockEngine.invocationCount
        XCTAssertEqual(totalInvocations, 4)
    }

    // MARK: - 2. Permanent Failures & Multiple Consecutive Failures

    func testProcessBatch_consecutiveFailures_processesAllItemsToCompletion() async throws {
        let audio1 = try createDummyAudioFile(name: "bad1.mp3")
        let audio2 = try createDummyAudioFile(name: "bad2.mp3")
        let audio3 = try createDummyAudioFile(name: "good3.mp3")

        let goodResult = makeDummyResult(text: "Recovered in item 3")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: goodResult,
            resultsSequence: [goodResult],
            errorsSequence: [
                MockTranscriptionEngineError(message: "Corrupted header"),
                MockTranscriptionEngineError(message: "Unsupported sample rate"),
                nil
            ]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].errorMessage, "Corrupted header")
        XCTAssertEqual(results[1].status, .failed)
        XCTAssertEqual(results[1].errorMessage, "Unsupported sample rate")
        XCTAssertEqual(results[2].status, .succeeded)
        XCTAssertEqual(results[2].result?.fullText, "Recovered in item 3")

        let summary = results.batchSummary
        XCTAssertEqual(summary.succeededCount, 1)
        XCTAssertEqual(summary.failedCount, 2)
        XCTAssertTrue(summary.hasFailures)
    }

    // MARK: - 3. Write / Persistence Failure Isolation

    func testProcessBatch_persistenceFailure_marksItemFailedWithoutAbortingSubsequentItems() async throws {
        let audio1 = try createDummyAudioFile(name: "write_fail.mp3")
        let audio2 = try createDummyAudioFile(name: "write_success.mp3")

        let result1 = makeDummyResult(text: "Text 1")
        let result2 = makeDummyResult(text: "Text 2")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            resultsSequence: [result1, result2]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        // Give audio1 an invalid output path that points inside a non-directory file
        let blockerFile = tempDirectory.appendingPathComponent("blocker_file")
        try "blocker".data(using: .utf8)!.write(to: blockerFile)
        let impossibleOutputURL = blockerFile.appendingPathComponent("sub_dir").appendingPathComponent("write_fail.json")

        var item1 = BatchItem(sourceURL: audio1)
        item1.outputURL = impossibleOutputURL
        let item2 = BatchItem(sourceURL: audio2)

        let results = await coordinator.processBatch(items: [item1, item2], destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 2)
        // Item 1 fails during atomic save
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertNotNil(results[0].errorMessage)
        XCTAssertEqual(results[0].progress, 0.0)

        // Item 2 succeeds normally
        XCTAssertEqual(results[1].status, .succeeded)
        XCTAssertEqual(results[1].result?.fullText, "Text 2")

        let summary = results.batchSummary
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.succeededCount, 1)
    }

    // MARK: - 4. Mixed Outcomes (Succeeded, Failed, Skipped) Exact Order

    func testProcessBatch_mixedOutcomes_preservesExactInputOrderAndReportsAccurateSummary() async throws {
        let audio1 = try createDummyAudioFile(name: "item1_ok.mp3")
        let audio2 = try createDummyAudioFile(name: "item2_fail.mp3")
        let audio3 = try createDummyAudioFile(name: "item3_skip.mp3")
        let audio4 = try createDummyAudioFile(name: "item4_ok.mp3")

        // Pre-create output for item 3 so it gets skipped
        let skipOutput = tempDirectory.appendingPathComponent("item3_skip.json")
        try "{}".data(using: .utf8)!.write(to: skipOutput)

        let result1 = makeDummyResult(text: "Item 1 text")
        let result4 = makeDummyResult(text: "Item 4 text")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            resultsSequence: [result1, result4],
            errorsSequence: [
                nil,
                MockTranscriptionEngineError(message: "Decode error"),
                nil // Not called for skip
            ]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3),
            BatchItem(sourceURL: audio4)
        ]

        let processResult = await coordinator.processBatchWithSummary(
            items: items,
            destinationDirectory: tempDirectory
        )

        let processed = processResult.items
        XCTAssertEqual(processed.count, 4)

        // Check index preservation and exact status
        XCTAssertEqual(processed[0].sourceURL, audio1)
        XCTAssertEqual(processed[0].status, .succeeded)

        XCTAssertEqual(processed[1].sourceURL, audio2)
        XCTAssertEqual(processed[1].status, .failed)
        XCTAssertEqual(processed[1].errorMessage, "Decode error")

        XCTAssertEqual(processed[2].sourceURL, audio3)
        XCTAssertEqual(processed[2].status, .skipped)

        XCTAssertEqual(processed[3].sourceURL, audio4)
        XCTAssertEqual(processed[3].status, .succeeded)

        // Check summary metrics
        let summary = processResult.summary
        XCTAssertEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertFalse(summary.isAllSucceeded)
        XCTAssertTrue(summary.hasFailures)
        XCTAssertEqual(summary.completedCount, 4)
    }

    // MARK: - 5. Summary Metrics Consistency Tests

    func testBatchSummary_allSucceeded() {
        let dummy = makeDummyResult()
        let items = [
            BatchItem(sourceURL: URL(fileURLWithPath: "/a.mp3"), status: .succeeded, result: dummy),
            BatchItem(sourceURL: URL(fileURLWithPath: "/b.mp3"), status: .succeeded, result: dummy)
        ]
        let summary = BatchTranscriptionSummary(items: items)

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertTrue(summary.isAllSucceeded)
        XCTAssertFalse(summary.hasFailures)
        XCTAssertEqual(summary.completedCount, 2)
    }

    func testBatchSummary_allFailed() {
        let items = [
            BatchItem(sourceURL: URL(fileURLWithPath: "/a.mp3"), status: .failed, errorMessage: "Err1"),
            BatchItem(sourceURL: URL(fileURLWithPath: "/b.mp3"), status: .failed, errorMessage: "Err2")
        ]
        let summary = items.batchSummary

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertFalse(summary.isAllSucceeded)
        XCTAssertTrue(summary.hasFailures)
        XCTAssertEqual(summary.completedCount, 2)
    }

    func testBatchSummary_emptyItems() {
        let summary = BatchTranscriptionSummary(items: [])

        XCTAssertEqual(summary.totalCount, 0)
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.cancelledCount, 0)
        XCTAssertFalse(summary.isAllSucceeded)
        XCTAssertFalse(summary.hasFailures)
        XCTAssertEqual(summary.completedCount, 0)
    }

    // MARK: - 6. Cancellation Interplay with Failures

    func testProcessBatch_cancellationDuringFailingItem_recordsFailureAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "f1_fail.mp3")
        let audio2 = try createDummyAudioFile(name: "f2_queued.mp3")
        let audio3 = try createDummyAudioFile(name: "f3_queued.mp3")

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(),
            completionGate: completionGate,
            errorsSequence: [MockTranscriptionEngineError(message: "Item 1 engine error")]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        // Start processing batch in background task
        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        // Wait a small duration so item 1 enters transcribe and suspends on gate
        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel the coordinator while item 1 is active
        await coordinator.cancel()

        // Open the gate to let item 1 finish (and throw its configured error)
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 3)

        // Item 1 was actively running and threw an error: records failure
        XCTAssertEqual(processed[0].status, .failed)
        XCTAssertEqual(processed[0].errorMessage, "Item 1 engine error")

        // Items 2 and 3 were queued and are cancelled
        XCTAssertEqual(processed[1].status, .cancelled)
        XCTAssertEqual(processed[2].status, .cancelled)

        let summary = processResult.summary
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.cancelledCount, 2)
        XCTAssertTrue(summary.hasFailures)
        XCTAssertFalse(summary.isAllSucceeded)
        XCTAssertEqual(summary.completedCount, 3)
    }

    // MARK: - 7. No Early Abort on First Item Failure

    func testProcessBatch_firstItemFails_allRemainingItemsStillProcess() async throws {
        let audio1 = try createDummyAudioFile(name: "first_fails.mp3")
        let audio2 = try createDummyAudioFile(name: "second_succeeds.mp3")

        let result2 = makeDummyResult(text: "Second item succeeded")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result2,
            resultsSequence: [result2],
            errorsSequence: [
                MockTranscriptionEngineError(message: "Immediate failure on item 1"),
                nil
            ]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].errorMessage, "Immediate failure on item 1")

        XCTAssertEqual(results[1].status, .succeeded)
        XCTAssertEqual(results[1].result?.fullText, "Second item succeeded")

        let invocations = await mockEngine.invocationCount
        XCTAssertEqual(invocations, 2)
    }
}
