//
//  BatchTranscriptionCoordinatorTests.swift
//  OrangeNoteTests
//
//  Unit tests for `BatchTranscriptionCoordinator` verifying sequential execution (D015),
//  status transitions (D019), non-overwriting skip handling (D018), error continuation (D016),
//  and stop-after-current cancellation semantics (D021).
//

import XCTest
@testable import OrangeNote

final class BatchTranscriptionCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchTranscriptionCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func makeDummyResult(text: String = "Hello batch world") -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.5, text: text)
            ],
            fullText: text,
            language: "en",
            duration: 2.5
        )
    }

    private func createDummyAudioFile(name: String) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        let dummyData = "dummy-audio-content".data(using: .utf8)!
        try dummyData.write(to: fileURL)
        return fileURL
    }

    // MARK: - 1. Empty Items

    func testProcessBatch_emptyItems_returnsEmptyArray() async {
        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let results = await coordinator.processBatch(items: [], destinationDirectory: tempDirectory)
        XCTAssertTrue(results.isEmpty)

        let invocationCount = await mockEngine.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    // MARK: - 2. Single Item Lifecycle Transitions & Canonical Write

    func testProcessBatch_singleItem_transitionsThroughQueuedTranscribingSavingSucceededAndWritesDocument() async throws {
        let audioURL = try createDummyAudioFile(name: "audio1.mp3")
        let dummyResult = makeDummyResult(text: "Transcribed audio 1")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: dummyResult,
            progressValuesToEmit: [0.5],
            engineID: "whisper-test-engine"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let item = BatchItem(sourceURL: audioURL)
        let observedStatuses = StateRecorder()

        let results = await coordinator.processBatch(
            items: [item],
            destinationDirectory: tempDirectory,
            configuration: BatchTranscriptionConfiguration(modelName: "small")
        ) { updatedItem in
            Task {
                await observedStatuses.record(status: updatedItem.status, progress: updatedItem.progress)
            }
        }

        XCTAssertEqual(results.count, 1)
        let processedItem = results[0]
        XCTAssertEqual(processedItem.status, .succeeded)
        XCTAssertEqual(processedItem.result?.fullText, "Transcribed audio 1")
        XCTAssertNil(processedItem.errorMessage)

        let expectedOutputURL = tempDirectory.appendingPathComponent("audio1.json")
        XCTAssertEqual(processedItem.outputURL, expectedOutputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOutputURL.path))

        // Verify the written document is valid Canonical JSON v1
        let writtenData = try Data(contentsOf: expectedOutputURL)
        let decodedDoc = try CanonicalTranscriptionSerializer.decode(writtenData)
        XCTAssertEqual(decodedDoc.schemaVersion, 1)
        XCTAssertEqual(decodedDoc.source.fileName, "audio1.mp3")
        XCTAssertEqual(decodedDoc.engine.id, "whisper-test-engine")
        XCTAssertEqual(decodedDoc.engine.model, "small")
        XCTAssertEqual(decodedDoc.transcription.fullText, "Transcribed audio 1")
    }

    // MARK: - 3. Multiple Items Sequential Execution

    func testProcessBatch_multipleItems_executesSequentiallyInOrder() async throws {
        let audio1 = try createDummyAudioFile(name: "audio1.wav")
        let audio2 = try createDummyAudioFile(name: "audio2.m4a")
        let audio3 = try createDummyAudioFile(name: "audio3.flac")

        let result1 = makeDummyResult(text: "Result 1")
        let result2 = makeDummyResult(text: "Result 2")
        let result3 = makeDummyResult(text: "Result 3")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: result1,
            resultsSequence: [result1, result2, result3]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].status, .succeeded)
        XCTAssertEqual(results[0].result?.fullText, "Result 1")
        XCTAssertEqual(results[1].status, .succeeded)
        XCTAssertEqual(results[1].result?.fullText, "Result 2")
        XCTAssertEqual(results[2].status, .succeeded)
        XCTAssertEqual(results[2].result?.fullText, "Result 3")

        let requests = await mockEngine.receivedRequests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].sourceURL, audio1)
        XCTAssertEqual(requests[1].sourceURL, audio2)
        XCTAssertEqual(requests[2].sourceURL, audio3)
    }

    // MARK: - 4. Skip Existing Output File

    func testProcessBatch_existingOutputFile_skipsItemWithoutInvokingEngine() async throws {
        let audio1 = try createDummyAudioFile(name: "already_done.mp3")
        let audio2 = try createDummyAudioFile(name: "needs_transcription.mp3")

        // Pre-create output for audio1
        let existingOutputURL = tempDirectory.appendingPathComponent("already_done.json")
        try "{}".data(using: .utf8)!.write(to: existingOutputURL)

        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult(text: "New audio result"))
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].status, .skipped)
        XCTAssertEqual(results[0].outputURL, existingOutputURL)

        XCTAssertEqual(results[1].status, .succeeded)
        XCTAssertEqual(results[1].result?.fullText, "New audio result")

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 1)

        let lastReq = await mockEngine.receivedRequest
        XCTAssertEqual(lastReq?.sourceURL, audio2)
    }

    // MARK: - 5. Already-Skipped Item

    func testProcessBatch_alreadySkippedItem_preservedAsSkipped() async throws {
        let audio1 = try createDummyAudioFile(name: "planned_skip.mp3")
        let audio2 = try createDummyAudioFile(name: "planned_work.mp3")

        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        var item1 = BatchItem(sourceURL: audio1)
        item1.status = .skipped
        let item2 = BatchItem(sourceURL: audio2)

        let results = await coordinator.processBatch(items: [item1, item2], destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].status, .skipped)
        XCTAssertEqual(results[1].status, .succeeded)

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - 6. Error Continuation (D016)

    func testProcessBatch_engineFails_marksFailedAndContinuesRemainingItems() async throws {
        let audio1 = try createDummyAudioFile(name: "track1.mp3")
        let audio2 = try createDummyAudioFile(name: "track2_corrupt.mp3")
        let audio3 = try createDummyAudioFile(name: "track3.mp3")

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(text: "Track result"),
            errorsSequence: [nil, MockTranscriptionEngineError(message: "Corrupted audio file"), nil]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].status, .succeeded)
        XCTAssertNil(results[0].errorMessage)

        XCTAssertEqual(results[1].status, .failed)
        XCTAssertNotNil(results[1].errorMessage)

        XCTAssertEqual(results[2].status, .succeeded)
        XCTAssertNil(results[2].errorMessage)

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 3)
    }

    // MARK: - 7. Missing Output Destination

    func testProcessBatch_missingOutputURLAndDestinationDirectory_marksFailed() async throws {
        let audio = try createDummyAudioFile(name: "orphan.mp3")
        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let item = BatchItem(sourceURL: audio, outputURL: nil)
        let results = await coordinator.processBatch(items: [item], destinationDirectory: nil)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].errorMessage, "Missing destination directory or output URL")

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - 8. Cancellation Before Start (D021)

    func testProcessBatch_cancellationBeforeStart_marksAllItemsCancelled() async throws {
        let audio1 = try createDummyAudioFile(name: "cancel1.mp3")
        let audio2 = try createDummyAudioFile(name: "cancel2.mp3")

        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        await coordinator.cancel()
        let isCancelled = await coordinator.isCancelled
        XCTAssertTrue(isCancelled)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2)
        ]

        let results = await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].status, .cancelled)
        XCTAssertEqual(results[1].status, .cancelled)

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - 9. Stop-After-Current Cancellation (D021 / D022)

    func testProcessBatch_cancellationDuringActiveItem_finishesActiveAndCancelsRemaining() async throws {
        let audio1 = try createDummyAudioFile(name: "active.mp3")
        let audio2 = try createDummyAudioFile(name: "waiting1.mp3")
        let audio3 = try createDummyAudioFile(name: "waiting2.mp3")

        let completionGate = CompletionGate()
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(text: "Active file completed"),
            completionGate: completionGate
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let items = [
            BatchItem(sourceURL: audio1),
            BatchItem(sourceURL: audio2),
            BatchItem(sourceURL: audio3)
        ]

        // Start processing batch in background task
        let batchTask = Task {
            await coordinator.processBatch(items: items, destinationDirectory: tempDirectory)
        }

        // Wait a tiny fraction so item 1 enters transcribe and suspends on gate
        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel the coordinator while item 1 is in-flight
        await coordinator.cancel()

        // Open the gate to let item 1 finish
        await completionGate.open()

        let results = await batchTask.value

        XCTAssertEqual(results.count, 3)
        // Item 1 finishes cleanly (stop-after-current, D021)
        XCTAssertEqual(results[0].status, .succeeded)
        XCTAssertEqual(results[0].result?.fullText, "Active file completed")

        // Output file for item 1 exists on disk (D022)
        let output1 = tempDirectory.appendingPathComponent("active.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output1.path))

        // Remaining queued items are marked cancelled
        XCTAssertEqual(results[1].status, .cancelled)
        XCTAssertEqual(results[2].status, .cancelled)

        let count = await mockEngine.invocationCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - 10. Progress Forwarding

    func testProcessBatch_progressForwarding_reportsPerItemProgress() async throws {
        let audio = try createDummyAudioFile(name: "progress_test.mp3")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeDummyResult(),
            progressValuesToEmit: [0.25, 0.5, 0.75, 1.0]
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let item = BatchItem(sourceURL: audio)
        let progressRecorder = ProgressRecorder()

        _ = await coordinator.processBatch(items: [item], destinationDirectory: tempDirectory) { updatedItem in
            Task {
                await progressRecorder.record(progress: updatedItem.progress, status: updatedItem.status)
            }
        }

        // Allow any background tasks to record
        try await Task.sleep(nanoseconds: 20_000_000)

        let recordedProgresses = await progressRecorder.progresses
        XCTAssertTrue(recordedProgresses.contains(0.25))
        XCTAssertTrue(recordedProgresses.contains(0.5))
        XCTAssertTrue(recordedProgresses.contains(0.75))
    }

    // MARK: - 11. Configuration Forwarding

    func testProcessBatch_customConfiguration_forwardsParametersToRequest() async throws {
        let audio = try createDummyAudioFile(name: "config_test.mp3")
        let mockEngine = MockTranscriptionEngine(resultToReturn: makeDummyResult())
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)

        let config = BatchTranscriptionConfiguration(
            modelName: "large-v3",
            language: "fr",
            translateToEnglish: true,
            chunkingEnabled: true,
            chunkDurationSeconds: 45.0,
            overlapDurationSeconds: 10.0,
            includeSourcePathInCanonicalDocument: true
        )

        let results = await coordinator.processBatch(
            items: [BatchItem(sourceURL: audio)],
            destinationDirectory: tempDirectory,
            configuration: config
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .succeeded)

        let receivedReq = await mockEngine.receivedRequest
        XCTAssertNotNil(receivedReq)
        XCTAssertEqual(receivedReq?.modelName, "large-v3")
        XCTAssertEqual(receivedReq?.language, "fr")
        XCTAssertEqual(receivedReq?.translateToEnglish, true)
        XCTAssertEqual(receivedReq?.chunkingEnabled, true)
        XCTAssertEqual(receivedReq?.chunkDurationSeconds, 45.0)
        XCTAssertEqual(receivedReq?.overlapDurationSeconds, 10.0)

        // Check that document embedded source path when configured
        let outputURL = tempDirectory.appendingPathComponent("config_test.json")
        let docData = try Data(contentsOf: outputURL)
        let doc = try CanonicalTranscriptionSerializer.decode(docData)
        XCTAssertEqual(doc.source.path, audio.path)
    }
}

// MARK: - Test Helpers

private actor StateRecorder {
    var records: [(status: BatchItemStatus, progress: Float)] = []

    func record(status: BatchItemStatus, progress: Float) {
        records.append((status: status, progress: progress))
    }
}

private actor ProgressRecorder {
    var progresses: [Float] = []
    var statuses: [BatchItemStatus] = []

    func record(progress: Float, status: BatchItemStatus) {
        progresses.append(progress)
        statuses.append(status)
    }
}
