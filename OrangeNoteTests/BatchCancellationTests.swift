//
//  BatchCancellationTests.swift
//  OrangeNoteTests
//
//  Unit tests for Task 3.10: Stop-After-Current Cancellation Policy (D021, D022),
//  verifying cancellation before start, during first item, during subsequent items,
//  mid-transcription with success/failure, double-cancel idempotence, empty queue handling,
//  state observability, file retention, and callback semantics.
//

import XCTest
@testable import OrangeNote

final class BatchCancellationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchCancellationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func makeDummyResult(text: String = "Transcription result") -> TranscriptionResult {
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

    // MARK: - 1. Cancel Before Start

    func testCancel_beforeStart_marksAllItemsCancelledAndDoesNotInvokeEngine() async throws {
        let audio1 = try createDummyAudioFile(name: "file1.mp3")
        let audio2 = try createDummyAudioFile(name: "file2.mp3")
        let audio3 = try createDummyAudioFile(name: "file3.mp3")

        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        // Cancel before batch execution starts
        await coordinator.cancel()
        let isCancelled = await coordinator.isCancelled
        XCTAssertTrue(isCancelled, "Coordinator should observe cancellation before batch starts")

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let processResult = await coordinator.processBatchWithSummary(
            items: items,
            destinationDirectory: tempDirectory
        )

        let processed = processResult.items
        XCTAssertEqual(processed.count, 3)
        for item in processed {
            XCTAssertEqual(item.status, BatchItemStatus.cancelled)
            XCTAssertNil(item.result)
            XCTAssertNil(item.errorMessage)
            XCTAssertEqual(item.progress, 0.0)
        }

        // Summary verification
        let summary = processResult.summary
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.cancelledCount, 3)
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 0)

        // Engine must never have been called
        let invocations = await mockEngine.invocationCount
        XCTAssertEqual(invocations, 0)

        // Zero output files should exist
        let output1 = tempDirectory.appendingPathComponent("file1.json")
        let output2 = tempDirectory.appendingPathComponent("file2.json")
        let output3 = tempDirectory.appendingPathComponent("file3.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output2.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output3.path))
    }

    // MARK: - 2. Cancel During First Item (Stop-After-Current)

    func testCancel_duringFirstItem_completesFirstItemAndCancelsSubsequent() async throws {
        let audio1 = try createDummyAudioFile(name: "first_active.mp3")
        let audio2 = try createDummyAudioFile(name: "second_queued.mp3")
        let audio3 = try createDummyAudioFile(name: "third_queued.mp3")

        let completionGate = CompletionGate()
        let result1 = makeDummyResult(text: "First item completed")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            completionGate: completionGate
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        // Wait until item 1 is active inside transcribe
        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel while item 1 is active
        await coordinator.cancel()

        // Release item 1
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 3)

        // Item 1 succeeded and wrote file
        XCTAssertEqual(processed[0].status, BatchItemStatus.succeeded)
        XCTAssertEqual(processed[0].result?.fullText, "First item completed")
        let output1 = tempDirectory.appendingPathComponent("first_active.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path))

        // Items 2 & 3 cancelled without ever running engine
        XCTAssertEqual(processed[1].status, BatchItemStatus.cancelled)
        XCTAssertEqual(processed[2].status, BatchItemStatus.cancelled)

        let summary = processResult.summary
        XCTAssertEqual(summary.succeededCount, 1)
        XCTAssertEqual(summary.cancelledCount, 2)
        XCTAssertEqual(summary.failedCount, 0)

        let invocations = await mockEngine.invocationCount
        XCTAssertEqual(invocations, 1)
    }

    // MARK: - 3. Cancel During Subsequent Item in Middle of Queue

    func testCancel_duringMiddleItem_completesPriorAndActiveItemAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "item1_done.mp3")
        let audio2 = try createDummyAudioFile(name: "item2_active.mp3")
        let audio3 = try createDummyAudioFile(name: "item3_pending.mp3")

        let gate1 = CompletionGate()
        let gate2 = CompletionGate()
        // Open gate 1 immediately so item 1 runs through
        await gate1.open()

        let result1 = makeDummyResult(text: "Item 1 text")
        let result2 = makeDummyResult(text: "Item 2 text")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            resultsSequence: [result1, result2],
            completionGatesSequence: [gate1, gate2]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        // Wait until item 2 has started and suspended on gate2
        try await Task.sleep(nanoseconds: 60_000_000)

        // Cancel while item 2 is in-flight
        await coordinator.cancel()

        // Open gate2 to let item 2 finish
        await gate2.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 3)

        // Item 1 succeeded
        XCTAssertEqual(processed[0].status, BatchItemStatus.succeeded)
        let output1 = tempDirectory.appendingPathComponent("item1_done.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path))

        // Item 2 succeeded (active item finishes, D021)
        XCTAssertEqual(processed[1].status, BatchItemStatus.succeeded)
        let output2 = tempDirectory.appendingPathComponent("item2_active.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output2.path))

        // Item 3 cancelled
        XCTAssertEqual(processed[2].status, BatchItemStatus.cancelled)
        let output3 = tempDirectory.appendingPathComponent("item3_pending.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output3.path))

        let summary = processResult.summary
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.cancelledCount, 1)
        XCTAssertEqual(summary.failedCount, 0)

        let invocations = await mockEngine.invocationCount
        XCTAssertEqual(invocations, 2)
    }

    // MARK: - 4. Cancel Mid-Transcription with Canonical Document Verification

    func testCancel_midTranscription_completesAndSavesActiveItemAtomicallyAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "active_save.mp3")
        let audio2 = try createDummyAudioFile(name: "queued1.mp3")
        let audio3 = try createDummyAudioFile(name: "queued2.mp3")

        let completionGate = CompletionGate()
        let result1 = makeDummyResult(text: "Active file transcription completed")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            completionGate: completionGate,
            engineID: "whisper-test-local"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory,
                configuration: BatchTranscriptionConfiguration(modelName: "small")
            )
        }

        // Wait for item 1 to enter transcription and suspend on the gate
        try await Task.sleep(nanoseconds: 50_000_000)

        // Trigger cancellation while item 1 is active in transcribe
        await coordinator.cancel()

        // Open the completion gate
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 3)

        // Active item 1 must complete and save atomically (D021)
        XCTAssertEqual(processed[0].status, BatchItemStatus.succeeded)
        XCTAssertEqual(processed[0].result?.fullText, "Active file transcription completed")
        XCTAssertEqual(processed[0].progress, 1.0)
        XCTAssertNil(processed[0].errorMessage)

        let output1 = tempDirectory.appendingPathComponent("active_save.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path), "Output file for active item must be saved (D022)")

        let fileData = try Data(contentsOf: output1)
        let canonicalDoc = try CanonicalTranscriptionSerializer.decode(fileData)
        XCTAssertEqual(canonicalDoc.schemaVersion, 1)
        XCTAssertEqual(canonicalDoc.source.fileName, "active_save.mp3")
        XCTAssertEqual(canonicalDoc.engine.id, "whisper-test-local")
        XCTAssertEqual(canonicalDoc.transcription.fullText, "Active file transcription completed")

        // Remaining queued items must be marked as cancelled
        XCTAssertEqual(processed[1].status, BatchItemStatus.cancelled)
        XCTAssertEqual(processed[1].progress, 0.0)
        XCTAssertNil(processed[1].result)

        XCTAssertEqual(processed[2].status, BatchItemStatus.cancelled)
        XCTAssertEqual(processed[2].progress, 0.0)
        XCTAssertNil(processed[2].result)

        // Summary
        let summary = processResult.summary
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.succeededCount, 1)
        XCTAssertEqual(summary.cancelledCount, 2)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.completedCount, 3)

        let invocations = await mockEngine.invocationCount
        XCTAssertEqual(invocations, 1)
    }

    // MARK: - 5. Cancel Mid-Transcription with Failure of Current

    func testCancel_midTranscription_activeItemEngineFails_recordsFailureAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "active_error.mp3")
        let audio2 = try createDummyAudioFile(name: "queued_after_error.mp3")

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(),
            completionGate: completionGate,
            errorsSequence: [MockTranscriptionEngineError(message: "Mid-cancellation engine error")]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2)
        ]

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel while item 1 is active
        await coordinator.cancel()

        // Release gate to let item 1 throw error
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 2)

        // Active item 1 recorded failure
        XCTAssertEqual(processed[0].status, BatchItemStatus.failed)
        XCTAssertEqual(processed[0].errorMessage, "Mid-cancellation engine error")
        XCTAssertEqual(processed[0].progress, 0.0)

        // Item 2 cancelled
        XCTAssertEqual(processed[1].status, BatchItemStatus.cancelled)
        XCTAssertNil(processed[1].errorMessage)

        let summary = processResult.summary
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.cancelledCount, 1)
        XCTAssertEqual(summary.succeededCount, 0)
    }

    // MARK: - 6. Cancel Mid-Transcription with Persistence Failure

    func testCancel_midTranscription_activeItemPersistenceFails_recordsFailureAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "active_bad_save.mp3")
        let audio2 = try createDummyAudioFile(name: "queued_after_save_fail.mp3")

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(text: "Good text"),
            completionGate: completionGate
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        // Provide an impossible output path for audio1
        let blockerFile = tempDirectory.appendingPathComponent("blocker_file")
        try "blocker".data(using: .utf8)!.write(to: blockerFile)
        let impossibleOutput = blockerFile.appendingPathComponent("sub").appendingPathComponent("active_bad_save.json")

        var item1 = BatchItem(sourceURL: audio1)
        item1.outputURL = impossibleOutput
        let item2 = BatchItem(sourceURL: audio2)

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: [item1, item2],
                destinationDirectory: tempDirectory
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await coordinator.cancel()
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items
        XCTAssertEqual(processed.count, 2)

        // Item 1 failed on atomic write
        XCTAssertEqual(processed[0].status, BatchItemStatus.failed)
        XCTAssertNotNil(processed[0].errorMessage)

        // Item 2 cancelled
        XCTAssertEqual(processed[1].status, BatchItemStatus.cancelled)

        let summary = processResult.summary
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.cancelledCount, 1)
    }

    // MARK: - 7. Double-Cancel Idempotence & Thread/Actor Safety

    func testCancel_doubleCancel_isIdempotentAndThreadSafe() async throws {
        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        // Multiple concurrent calls to cancel()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await coordinator.cancel()
                }
            }
        }

        let isCancelled = await coordinator.isCancelled
        XCTAssertTrue(isCancelled)
    }

    // MARK: - 8. Cancel of Empty Queue

    func testCancel_emptyQueue_returnsEmptyArrayAndMaintainsState() async {
        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        await coordinator.cancel()
        let results = await coordinator.processBatch(items: [], destinationDirectory: tempDirectory)
        XCTAssertTrue(results.isEmpty)

        let isCancelled = await coordinator.isCancelled
        XCTAssertTrue(isCancelled)
    }

    // MARK: - 9. State Observable and Reset Allows Coordinator Reuse

    func testCancel_observableStateAndReset_allowsCoordinatorReuse() async throws {
        let audio1 = try createDummyAudioFile(name: "run1.mp3")
        let audio2 = try createDummyAudioFile(name: "run2.mp3")

        let result1 = makeDummyResult(text: "Run 2 text")
        let mockEngine = MockTranscriptionEngine(resultToReturn: result1)
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        // Run 1: Cancel before start
        await coordinator.cancel()
        let isCancelledRun1 = await coordinator.isCancelled
        XCTAssertTrue(isCancelledRun1)

        let run1Results = await coordinator.processBatch(
            items: [BatchItem(sourceURL: audio1)],
            destinationDirectory: tempDirectory
        )
        XCTAssertEqual(run1Results[0].status, BatchItemStatus.cancelled)

        // Reset cancellation flag
        await coordinator.resetCancellation()
        let isCancelledAfterReset = await coordinator.isCancelled
        XCTAssertFalse(isCancelledAfterReset)

        // Run 2: Should succeed normally
        let run2Results = await coordinator.processBatch(
            items: [BatchItem(sourceURL: audio2)],
            destinationDirectory: tempDirectory
        )
        XCTAssertEqual(run2Results[0].status, BatchItemStatus.succeeded)
        XCTAssertEqual(run2Results[0].result?.fullText, "Run 2 text")
    }

    // MARK: - 10. Swift Task.cancel() Cooperation

    func testCancel_taskCancelCooperation_setsIsCancelledAndCancelsSubsequentItems() async throws {
        let audio1 = try createDummyAudioFile(name: "task_active.mp3")
        let audio2 = try createDummyAudioFile(name: "task_queued.mp3")

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(text: "Task cancel current item completed"),
            completionGate: completionGate
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2)
        ]

        let task = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel via Swift standard Task.cancel()
        task.cancel()

        await completionGate.open()

        let processResult = await task.value
        let processed = processResult.items

        XCTAssertEqual(processed.count, 2)
        XCTAssertEqual(processed[0].status, BatchItemStatus.succeeded)
        XCTAssertEqual(processed[1].status, BatchItemStatus.cancelled)

        let isCoordinatorCancelled = await coordinator.isCancelled
        XCTAssertTrue(isCoordinatorCancelled)
    }

    // MARK: - 11. Retain Successfully Written Files on Disk (D022)

    func testCancel_retainsPreExistingAndNewlyWrittenFilesOnDisk() async throws {
        let audio1 = try createDummyAudioFile(name: "pre_existing.mp3")
        let audio2 = try createDummyAudioFile(name: "active_write.mp3")
        let audio3 = try createDummyAudioFile(name: "cancelled_queued.mp3")

        // Pre-create output for item 1
        let output1 = tempDirectory.appendingPathComponent("pre_existing.json")
        try "{\"pre\": true}".data(using: .utf8)!.write(to: output1)

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(text: "Active write result"),
            completionGate: completionGate
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let batchTask = Task {
            await coordinator.processBatchWithSummary(
                items: items,
                destinationDirectory: tempDirectory
            )
        }

        // Wait for item 2 to enter transcription
        try await Task.sleep(nanoseconds: 50_000_000)
        await coordinator.cancel()
        await completionGate.open()

        let processResult = await batchTask.value
        let processed = processResult.items

        // Item 1: skipped (pre-existing output file remains on disk)
        XCTAssertEqual(processed[0].status, BatchItemStatus.skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path))

        // Item 2: succeeded (new output file remains on disk)
        XCTAssertEqual(processed[1].status, BatchItemStatus.succeeded)
        let output2 = tempDirectory.appendingPathComponent("active_write.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output2.path))

        // Item 3: cancelled (no output file created)
        XCTAssertEqual(processed[2].status, BatchItemStatus.cancelled)
        let output3 = tempDirectory.appendingPathComponent("cancelled_queued.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output3.path))
    }

    // MARK: - 12. Event Callbacks Emitted for Cancelled Items in Order

    func testCancel_eventCallbacksEmittedForCancelledItemsInOrder() async throws {
        let audio1 = try createDummyAudioFile(name: "ev1.mp3")
        let audio2 = try createDummyAudioFile(name: "ev2.mp3")
        let audio3 = try createDummyAudioFile(name: "ev3.mp3")

        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        await coordinator.cancel()

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let eventRecorder = CancelEventRecorder()

        _ = await coordinator.processBatch(
            items: items,
            destinationDirectory: tempDirectory
        ) { updatedItem in
            Task {
                await eventRecorder.record(id: updatedItem.id, sourceURL: updatedItem.sourceURL, status: updatedItem.status)
            }
        }

        try await Task.sleep(nanoseconds: 30_000_000)

        let events = await eventRecorder.records
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].sourceURL, audio1)
        XCTAssertEqual(events[0].status, BatchItemStatus.cancelled)
        XCTAssertEqual(events[1].sourceURL, audio2)
        XCTAssertEqual(events[1].status, BatchItemStatus.cancelled)
        XCTAssertEqual(events[2].sourceURL, audio3)
        XCTAssertEqual(events[2].status, BatchItemStatus.cancelled)
    }
}

// MARK: - Helper Actor for Events

private actor CancelEventRecorder {
    struct Event: Equatable {
        let id: UUID
        let sourceURL: URL
        let status: BatchItemStatus
    }

    var records: [Event] = []

    func record(id: UUID, sourceURL: URL, status: BatchItemStatus) {
        records.append(Event(id: id, sourceURL: sourceURL, status: status))
    }
}
