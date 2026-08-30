//
//  BatchTranscriptionViewModelTests.swift
//  OrangeNoteTests
//
//  Unit tests for BatchTranscriptionViewModel (Task 3.15 / D010 / D015–D023).
//

import XCTest
@testable import OrangeNote

final class MockBatchTranscriptionCoordinator: BatchTranscriptionCoordinatorProtocol, @unchecked Sendable {
    var cancelCalled = false
    var resetCancellationCalled = false
    var processBatchCalled = false
    var lastItems: [BatchItem]?
    var lastDestinationDirectory: URL?
    var lastConfiguration: BatchTranscriptionConfiguration?

    var onProcessBatch: (([BatchItem], URL?, BatchTranscriptionConfiguration, (@Sendable (BatchItem) -> Void)?) async -> BatchTranscriptionProcessResult)?

    func cancel() async {
        cancelCalled = true
    }

    func resetCancellation() async {
        resetCancellationCalled = true
    }

    func processBatch(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> [BatchItem] {
        let result = await processBatchWithSummary(
            items: items,
            destinationDirectory: destinationDirectory,
            configuration: configuration,
            onItemUpdated: onItemUpdated
        )
        return result.items
    }

    func processBatchWithSummary(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> BatchTranscriptionProcessResult {
        processBatchCalled = true
        lastItems = items
        lastDestinationDirectory = destinationDirectory
        lastConfiguration = configuration

        if let onProcessBatch = onProcessBatch {
            return await onProcessBatch(items, destinationDirectory, configuration, onItemUpdated)
        }

        var processed: [BatchItem] = []
        for item in items {
            var updated = item
            if updated.status == .skipped || updated.status == .cancelled {
                processed.append(updated)
                onItemUpdated?(updated)
                continue
            }
            updated.status = .transcribing
            updated.progress = 0.5
            onItemUpdated?(updated)

            updated.status = .saving
            updated.progress = 1.0
            onItemUpdated?(updated)

            let outURL = updated.outputURL ?? destinationDirectory?.appendingPathComponent("\(item.sourceURL.deletingPathExtension().lastPathComponent).json")
            updated.status = .succeeded
            updated.outputURL = outURL
            updated.result = TranscriptionResult(segments: [], fullText: "Mock text for \(item.sourceURL.lastPathComponent)", language: "en", duration: 5.0)
            onItemUpdated?(updated)
            processed.append(updated)
        }
        return BatchTranscriptionProcessResult(items: processed)
    }
}

final class MockBatchDocumentPicker: BatchDocumentPickerProtocol, DirectoryPickerProtocol, @unchecked Sendable {
    var filesToReturn: [URL]?
    var folderToReturn: URL?
    var outputDirectoryToReturn: URL?

    func pickMultipleAudioFiles(prompt: String?, initialDirectory: URL?) async -> [URL]? {
        filesToReturn
    }

    func pickSingleFolder(prompt: String?, initialDirectory: URL?) async -> URL? {
        folderToReturn
    }

    func pickOutputDirectory(prompt: String?, initialDirectory: URL?) async -> URL? {
        outputDirectoryToReturn
    }

    func pickDirectory(prompt: String?, initialDirectory: URL?) async -> URL? {
        outputDirectoryToReturn
    }
}

@MainActor
final class BatchTranscriptionViewModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var mockCoordinator: MockBatchTranscriptionCoordinator!
    private var mockPicker: MockBatchDocumentPicker!
    private var userDefaults: UserDefaults!
    private var outputPolicy: BatchOutputPolicy!
    private var pickerHelper: DocumentPickerHelper!
    private var viewModel: BatchTranscriptionViewModel!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BatchVMTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let suiteName = "com.orangenote.tests.batchvm.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        mockCoordinator = MockBatchTranscriptionCoordinator()
        mockPicker = MockBatchDocumentPicker()
        outputPolicy = BatchOutputPolicy(userDefaults: userDefaults, fileManager: .default, directoryPicker: mockPicker)
        pickerHelper = DocumentPickerHelper(picker: mockPicker, fileManager: .default, outputPolicy: outputPolicy)
        viewModel = BatchTranscriptionViewModel(
            coordinator: mockCoordinator,
            outputPolicy: outputPolicy,
            documentPickerHelper: pickerHelper,
            fileManager: .default,
            isSingleFileBusy: nil
        )
    }

    override func tearDown() {
        viewModel = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        mockCoordinator = nil
        mockPicker = nil
        outputPolicy = nil
        pickerHelper = nil
        userDefaults = nil
        super.tearDown()
    }

    private func createTestAudioFile(named filename: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? tempDirectory!
        let fileURL = dir.appendingPathComponent(filename)
        try! "RIFFtestWAVEfmt data".data(using: .utf8)!.write(to: fileURL)
        return fileURL
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.inputSource, .empty)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isCancelling)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.overallProgress, 0.0)
        XCTAssertNil(viewModel.activeIndex)
        XCTAssertNil(viewModel.activeItemID)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.lifecycleState, .empty)
        XCTAssertFalse(viewModel.hasItems)
        XCTAssertEqual(viewModel.itemCount, 0)
        XCTAssertFalse(viewModel.canStart)
    }

    // MARK: - Ingestion Tests

    func testIngestFilesSuccess() {
        let fileA = createTestAudioFile(named: "trackA.wav")
        let fileB = createTestAudioFile(named: "trackB.mp3")

        viewModel.ingestFiles([fileA, fileB])

        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.itemCount, 2)
        XCTAssertTrue(viewModel.hasItems)
        XCTAssertEqual(viewModel.lifecycleState, .ready)
        XCTAssertEqual(viewModel.summary.totalCount, 2)
        XCTAssertEqual(viewModel.summary.succeededCount, 0)
        XCTAssertNotNil(viewModel.outputDirectory)
        XCTAssertEqual(viewModel.items[0].sourceURL, fileA.standardizedFileURL)
        XCTAssertEqual(viewModel.items[1].sourceURL, fileB.standardizedFileURL)
        XCTAssertEqual(viewModel.items[0].status, .queued)
        XCTAssertEqual(viewModel.items[1].status, .queued)
    }

    func testIngestFilesFiltersNonAudioAndDeduplicates() {
        let fileA = createTestAudioFile(named: "song.mp3")
        let textFile = tempDirectory.appendingPathComponent("notes.txt")
        try! "text".data(using: .utf8)!.write(to: textFile)

        viewModel.ingestFiles([fileA, fileA, textFile])

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL, fileA.standardizedFileURL)
    }

    func testIngestFolderSuccess() {
        let folder = tempDirectory.appendingPathComponent("Album")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file1 = createTestAudioFile(named: "01.flac", in: folder)
        let file2 = createTestAudioFile(named: "02.flac", in: folder)

        viewModel.ingestFolder(folder)

        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.inputSource, .folder(folder.standardizedFileURL))
        XCTAssertEqual(viewModel.outputDirectory, folder.standardizedFileURL)
        XCTAssertEqual(viewModel.outputResolutionSource, .sourceFolder)
        XCTAssertEqual(viewModel.items[0].sourceURL, file1.standardizedFileURL)
        XCTAssertEqual(viewModel.items[1].sourceURL, file2.standardizedFileURL)
        XCTAssertEqual(viewModel.items[0].outputURL, folder.standardizedFileURL.appendingPathComponent("01.json"))
    }

    func testIngestResultDirectly() {
        let file = createTestAudioFile(named: "audio.m4a")
        let ingestion = DocumentPickerHelper.processFiles([file])

        viewModel.ingestResult(ingestion)

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL, file.standardizedFileURL)
        XCTAssertEqual(viewModel.lifecycleState, .ready)
    }

    func testPromptAndIngestFiles() async {
        let file = createTestAudioFile(named: "picked.wav")
        mockPicker.filesToReturn = [file]

        await viewModel.promptAndIngestFiles()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL, file.standardizedFileURL)
    }

    func testPromptAndIngestFolder() async {
        let folder = tempDirectory.appendingPathComponent("Folder")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = createTestAudioFile(named: "sound.ogg", in: folder)
        mockPicker.folderToReturn = folder

        await viewModel.promptAndIngestFolder()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.outputDirectory, folder.standardizedFileURL)
    }

    // MARK: - Output Directory & Policy Tests

    func testSetOutputDirectoryCustom() {
        let customOut = tempDirectory.appendingPathComponent("CustomOut")
        try! FileManager.default.createDirectory(at: customOut, withIntermediateDirectories: true)
        let file = createTestAudioFile(named: "audio.wav")
        viewModel.ingestFiles([file])

        viewModel.setOutputDirectory(customOut)

        XCTAssertEqual(viewModel.outputDirectory, customOut.standardizedFileURL)
        XCTAssertEqual(viewModel.outputResolutionSource, .custom)
        XCTAssertEqual(viewModel.items[0].outputURL, customOut.standardizedFileURL.appendingPathComponent("audio.json"))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSetOutputDirectoryInvalidSetsError() {
        let invalidURL = tempDirectory.appendingPathComponent("NonExistentDir")
        let file = createTestAudioFile(named: "audio.wav")
        viewModel.ingestFiles([file])
        let originalOutput = viewModel.outputDirectory

        viewModel.setOutputDirectory(invalidURL)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.outputDirectory, originalOutput)
    }

    func testPromptAndSelectOutputDirectory() async {
        let outDir = tempDirectory.appendingPathComponent("UserSelectedOut")
        try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        mockPicker.outputDirectoryToReturn = outDir

        let file = createTestAudioFile(named: "audio.wav")
        viewModel.ingestFiles([file])

        await viewModel.promptAndSelectOutputDirectory()

        XCTAssertEqual(viewModel.outputDirectory, outDir.standardizedFileURL)
        XCTAssertEqual(viewModel.outputResolutionSource, .userOverride)
        XCTAssertEqual(viewModel.items[0].outputURL, outDir.standardizedFileURL.appendingPathComponent("audio.json"))
    }

    // MARK: - Execution Lifecycle Tests

    func testStartBatchExecutionSuccess() async {
        let file1 = createTestAudioFile(named: "01.wav")
        let file2 = createTestAudioFile(named: "02.wav")
        viewModel.ingestFiles([file1, file2])

        let exp = expectation(description: "Batch complete")
        var recordedStates: [BatchLifecycleState] = []

        viewModel.start()
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(viewModel.lifecycleState, .running)

        // Poll for completion
        Task {
            while viewModel.isRunning {
                recordedStates.append(viewModel.lifecycleState)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 5.0)

        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isCancelling)
        XCTAssertEqual(viewModel.lifecycleState, .completed)
        XCTAssertEqual(viewModel.overallProgress, 1.0)
        XCTAssertEqual(viewModel.summary.totalCount, 2)
        XCTAssertEqual(viewModel.summary.succeededCount, 2)
        XCTAssertEqual(viewModel.summary.failedCount, 0)
        XCTAssertTrue(viewModel.summary.isAllSucceeded)
        XCTAssertNil(viewModel.activeIndex)
        XCTAssertNil(viewModel.activeItemID)
        XCTAssertEqual(viewModel.items[0].status, .succeeded)
        XCTAssertEqual(viewModel.items[1].status, .succeeded)
        XCTAssertNotNil(viewModel.items[0].result)
    }

    func testLiveItemUpdatesAndProgressCalculation() async {
        let file1 = createTestAudioFile(named: "track1.wav")
        let file2 = createTestAudioFile(named: "track2.wav")
        viewModel.ingestFiles([file1, file2])

        mockCoordinator.onProcessBatch = { items, destinationDirectory, configuration, onItemUpdated in
            // Step 1: file 1 transcribing 50%
            var item1 = items[0]
            item1.status = .transcribing
            item1.progress = 0.5
            onItemUpdated?(item1)
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Step 2: file 1 succeeded
            item1.status = .succeeded
            item1.progress = 1.0
            item1.result = TranscriptionResult(segments: [], fullText: "Done 1", language: "en", duration: 2.0)
            onItemUpdated?(item1)
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Step 3: file 2 transcribing 80%
            var item2 = items[1]
            item2.status = .transcribing
            item2.progress = 0.8
            onItemUpdated?(item2)
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Step 4: file 2 succeeded
            item2.status = .succeeded
            item2.progress = 1.0
            item2.result = TranscriptionResult(segments: [], fullText: "Done 2", language: "en", duration: 3.0)
            onItemUpdated?(item2)

            return BatchTranscriptionProcessResult(items: [item1, item2])
        }

        let exp = expectation(description: "Batch complete with progress")
        viewModel.start()

        Task {
            while viewModel.isRunning {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 5.0)

        XCTAssertEqual(viewModel.summary.succeededCount, 2)
        XCTAssertEqual(viewModel.overallProgress, 1.0)
    }

    func testCancelBatchExecution() async {
        let file1 = createTestAudioFile(named: "slow1.wav")
        let file2 = createTestAudioFile(named: "slow2.wav")
        viewModel.ingestFiles([file1, file2])

        mockCoordinator.onProcessBatch = { items, destinationDirectory, configuration, onItemUpdated in
            var item1 = items[0]
            item1.status = .transcribing
            item1.progress = 0.2
            onItemUpdated?(item1)

            // Wait for cancel to be triggered
            try? await Task.sleep(nanoseconds: 100_000_000)

            item1.status = .succeeded
            item1.progress = 1.0
            item1.result = TranscriptionResult(segments: [], fullText: "Item 1 finished before cancel", language: "en", duration: 1.0)
            onItemUpdated?(item1)

            var item2 = items[1]
            item2.status = .cancelled
            item2.progress = 0.0
            onItemUpdated?(item2)

            return BatchTranscriptionProcessResult(items: [item1, item2])
        }

        viewModel.start()
        XCTAssertTrue(viewModel.isRunning)

        try? await Task.sleep(nanoseconds: 30_000_000)
        viewModel.cancel()
        XCTAssertTrue(viewModel.isCancelling)

        let exp = expectation(description: "Cancelled batch completes")
        Task {
            while viewModel.isRunning {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 5.0)

        XCTAssertTrue(mockCoordinator.cancelCalled)

        XCTAssertFalse(viewModel.isRunning)
        XCTAssertFalse(viewModel.isCancelling)
        XCTAssertEqual(viewModel.items[0].status, .succeeded)
        XCTAssertEqual(viewModel.items[1].status, .cancelled)
        XCTAssertEqual(viewModel.summary.succeededCount, 1)
        XCTAssertEqual(viewModel.summary.cancelledCount, 1)
    }

    // MARK: - Failure Isolation & Continuation Tests (D016)

    func testFailureIsolationContinuesQueue() async {
        let file1 = createTestAudioFile(named: "bad.wav")
        let file2 = createTestAudioFile(named: "good.wav")
        viewModel.ingestFiles([file1, file2])

        mockCoordinator.onProcessBatch = { items, destinationDirectory, configuration, onItemUpdated in
            var item1 = items[0]
            item1.status = .failed
            item1.errorMessage = "Corrupt audio format"
            onItemUpdated?(item1)

            var item2 = items[1]
            item2.status = .succeeded
            item2.result = TranscriptionResult(segments: [], fullText: "Good transcript", language: "en", duration: 10.0)
            onItemUpdated?(item2)

            return BatchTranscriptionProcessResult(items: [item1, item2])
        }

        let exp = expectation(description: "Batch finished with failure isolation")
        viewModel.start()

        Task {
            while viewModel.isRunning {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 5.0)

        XCTAssertEqual(viewModel.summary.failedCount, 1)
        XCTAssertEqual(viewModel.summary.succeededCount, 1)
        XCTAssertTrue(viewModel.summary.hasFailures)
        XCTAssertFalse(viewModel.summary.isAllSucceeded)
        XCTAssertEqual(viewModel.items[0].status, .failed)
        XCTAssertEqual(viewModel.items[0].errorMessage, "Corrupt audio format")
        XCTAssertEqual(viewModel.items[1].status, .succeeded)
    }

    // MARK: - Guard & D010 Gating Tests

    func testStartWithEmptyQueueSetsErrorMessage() {
        viewModel.start()

        XCTAssertFalse(viewModel.isRunning)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(mockCoordinator.processBatchCalled)
    }

    func testD010SingleFileBusyRejectsStart() {
        let busyVM = BatchTranscriptionViewModel(
            coordinator: mockCoordinator,
            outputPolicy: outputPolicy,
            documentPickerHelper: pickerHelper,
            fileManager: .default,
            isSingleFileBusy: { true }
        )

        let file = createTestAudioFile(named: "track.wav")
        busyVM.ingestFiles([file])

        busyVM.start()

        XCTAssertFalse(busyVM.isRunning)
        XCTAssertNotNil(busyVM.errorMessage)
        XCTAssertFalse(mockCoordinator.processBatchCalled)
    }

    func testIngestWhileBusyRejects() {
        let file1 = createTestAudioFile(named: "file1.wav")
        let file2 = createTestAudioFile(named: "file2.wav")
        viewModel.ingestFiles([file1])

        mockCoordinator.onProcessBatch = { items, _, _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return BatchTranscriptionProcessResult(items: items)
        }

        viewModel.start()
        XCTAssertTrue(viewModel.isBusy)

        viewModel.ingestFiles([file2])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.items.count, 1)
    }

    // MARK: - Queue Pruning & Clear Tests

    func testClearQueueResetsAllState() {
        let file = createTestAudioFile(named: "audio.wav")
        viewModel.ingestFiles([file])
        XCTAssertEqual(viewModel.items.count, 1)

        viewModel.clear()

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.inputSource, .empty)
        XCTAssertEqual(viewModel.summary.totalCount, 0)
        XCTAssertEqual(viewModel.overallProgress, 0.0)
        XCTAssertEqual(viewModel.lifecycleState, .empty)
    }

    func testRemoveItemByID() {
        let file1 = createTestAudioFile(named: "one.wav")
        let file2 = createTestAudioFile(named: "two.wav")
        viewModel.ingestFiles([file1, file2])
        let idToRemove = viewModel.items[0].id

        viewModel.removeItem(id: idToRemove)

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL, file2.standardizedFileURL)
        XCTAssertEqual(viewModel.summary.totalCount, 1)
    }

    func testRemoveItemsAtIndexSet() {
        let file1 = createTestAudioFile(named: "a.wav")
        let file2 = createTestAudioFile(named: "b.wav")
        let file3 = createTestAudioFile(named: "c.wav")
        viewModel.ingestFiles([file1, file2, file3])

        viewModel.removeItems(at: IndexSet(integer: 1))

        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.items[0].sourceURL, file1.standardizedFileURL)
        XCTAssertEqual(viewModel.items[1].sourceURL, file3.standardizedFileURL)
        XCTAssertEqual(viewModel.summary.totalCount, 2)
    }

    func testDismissError() {
        viewModel.start()
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.dismissError()
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Pre-existing Output Files (D018)

    func testPreExistingOutputFilesSkipped() {
        let folder = tempDirectory.appendingPathComponent("SkipFolder")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = createTestAudioFile(named: "first.wav", in: folder)
        _ = createTestAudioFile(named: "second.wav", in: folder)

        // Create pre-existing output file for first.wav
        let existingJSON = folder.appendingPathComponent("first.json")
        try! "{}".data(using: .utf8)!.write(to: existingJSON)

        viewModel.ingestFolder(folder)

        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.items[0].status, .skipped)
        XCTAssertEqual(viewModel.items[1].status, .queued)
        XCTAssertEqual(viewModel.summary.skippedCount, 1)
    }
}
