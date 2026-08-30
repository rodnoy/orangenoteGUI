//
//  BatchIntegrationPipelineTests.swift
//  OrangeNoteTests
//
//  End-to-end integration test suite for the complete batch transcription pipeline (Task 3.18 / Chunk R).
//  Wires real BatchFileCollector, BatchOutputPolicy, BatchOutputPlanner, AtomicFileWriter,
//  BatchTranscriptionCoordinator, and BatchTranscriptionViewModel with a controllable MockTranscriptionEngine.
//

import XCTest
@testable import OrangeNote

@MainActor
final class BatchIntegrationPipelineTests: XCTestCase {
    private var tempDirectory: URL!
    private var mockUserDefaults: UserDefaults!
    private var userDefaultsSuite: String!
    private var fileManager: FileManager { .default }

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaultsSuite = "BatchIntegrationPipelineTests-\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: userDefaultsSuite)!
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchIntegrationPipelineTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let mockUserDefaults, let userDefaultsSuite {
            mockUserDefaults.removePersistentDomain(forName: userDefaultsSuite)
        }
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func createDummyAudioFile(name: String, directory: URL? = nil) throws -> URL {
        let dir = directory ?? tempDirectory!
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        let dummyData = "dummy-audio-content-\(name)".data(using: .utf8)!
        try dummyData.write(to: fileURL)
        return fileURL
    }

    private func makeResult(text: String, duration: Double = 3.0, language: String = "en") -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: duration, text: text)
            ],
            fullText: text,
            language: language,
            duration: duration
        )
    }

    private func waitForViewModelCompletion(
        _ viewModel: BatchTranscriptionViewModel,
        timeoutSeconds: Double = 5.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while viewModel.isBusy {
            if Date() > deadline {
                XCTFail("Timed out waiting for BatchTranscriptionViewModel to finish execution")
                return
            }
            try await Task.sleep(nanoseconds: 15_000_000) // 15ms
        }
    }

    // MARK: - 1. Folder Ingest → Run → Per-File JSON on Disk

    func testPipeline_folderIngestion_runsToCompletion_writesCanonicalJsonDocumentsOnDisk() async throws {
        let folderURL = tempDirectory.appendingPathComponent("AudioFolder")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "meeting1.mp3", directory: folderURL)
        try createDummyAudioFile(name: "meeting2.wav", directory: folderURL)
        try createDummyAudioFile(name: "notes.m4a", directory: folderURL)

        // Non-audio files, nested directories, and hidden files must be filtered out
        let txtFile = folderURL.appendingPathComponent("notes.txt")
        try "ignore me".data(using: .utf8)!.write(to: txtFile)
        let subDir = folderURL.appendingPathComponent("Subfolder")
        try fileManager.createDirectory(at: subDir, withIntermediateDirectories: true)
        let nestedAudio = subDir.appendingPathComponent("nested.mp3")
        try "nested audio".data(using: .utf8)!.write(to: nestedAudio)
        let hiddenAudio = folderURL.appendingPathComponent(".hidden.wav")
        try "hidden".data(using: .utf8)!.write(to: hiddenAudio)

        let resultsSequence = [
            makeResult(text: "Transcript for meeting 1", duration: 10.0),
            makeResult(text: "Transcript for meeting 2", duration: 15.0),
            makeResult(text: "Transcript for notes", duration: 5.0)
        ]

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Fallback"),
            engineID: "whisper-mock-engine",
            resultsSequence: resultsSequence
        )

        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(folderURL)

        XCTAssertEqual(viewModel.items.count, 3)
        XCTAssertEqual(viewModel.outputResolutionSource, .sourceFolder)
        XCTAssertEqual(viewModel.outputDirectory?.standardizedFileURL.path, folderURL.standardizedFileURL.path)
        XCTAssertEqual(viewModel.lifecycleState, .ready)
        XCTAssertTrue(viewModel.canStart)

        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.lifecycleState, .completed)
        XCTAssertEqual(viewModel.overallProgress, 1.0)
        XCTAssertEqual(viewModel.summary.succeededCount, 3)
        XCTAssertEqual(viewModel.summary.failedCount, 0)
        XCTAssertEqual(viewModel.summary.skippedCount, 0)

        // Verify JSON files on disk
        let expectedJSON1 = folderURL.appendingPathComponent("meeting1.json")
        let expectedJSON2 = folderURL.appendingPathComponent("meeting2.json")
        let expectedJSON3 = folderURL.appendingPathComponent("notes.json")

        XCTAssertTrue(fileManager.fileExists(atPath: expectedJSON1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: expectedJSON2.path))
        XCTAssertTrue(fileManager.fileExists(atPath: expectedJSON3.path))

        // Verify decoded Canonical JSON v1 documents
        let doc1Data = try Data(contentsOf: expectedJSON1)
        let doc1 = try CanonicalTranscriptionSerializer.decode(doc1Data)
        XCTAssertEqual(doc1.schemaVersion, 1)
        XCTAssertEqual(doc1.source.fileName, "meeting1.mp3")
        XCTAssertEqual(doc1.transcription.fullText, "Transcript for meeting 1")
        XCTAssertEqual(doc1.transcription.durationSeconds, 10.0)

        let doc2Data = try Data(contentsOf: expectedJSON2)
        let doc2 = try CanonicalTranscriptionSerializer.decode(doc2Data)
        XCTAssertEqual(doc2.schemaVersion, 1)
        XCTAssertEqual(doc2.source.fileName, "meeting2.wav")
        XCTAssertEqual(doc2.transcription.fullText, "Transcript for meeting 2")

        let doc3Data = try Data(contentsOf: expectedJSON3)
        let doc3 = try CanonicalTranscriptionSerializer.decode(doc3Data)
        XCTAssertEqual(doc3.schemaVersion, 1)
        XCTAssertEqual(doc3.source.fileName, "notes.m4a")
        XCTAssertEqual(doc3.transcription.fullText, "Transcript for notes")

        let engineCalls = await mockEngine.invocationCount
        XCTAssertEqual(engineCalls, 3)
    }

    // MARK: - 2. Files Ingest with Skips (Pre-Existing Outputs)

    func testPipeline_filesIngestion_withPreExistingOutputs_skipsExistingAndWritesMissingWithoutOverwriting() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("Sources")
        let outputDir = tempDirectory.appendingPathComponent("Outputs")
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let fileA = try createDummyAudioFile(name: "audioA.mp3", directory: sourceDir)
        let fileB = try createDummyAudioFile(name: "audioB.mp3", directory: sourceDir)
        let fileC = try createDummyAudioFile(name: "audioC.mp3", directory: sourceDir)

        // Pre-create output for audioB with distinct non-canonical content
        let preExistingB = outputDir.appendingPathComponent("audioB.json")
        let preExistingContent = "{\"custom_precious_data\": \"do_not_overwrite_me\"}"
        try preExistingContent.data(using: .utf8)!.write(to: preExistingB)

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Fresh result"),
            engineID: "whisper-mock-engine"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFiles([fileA, fileB, fileC])
        viewModel.setOutputDirectory(outputDir)

        XCTAssertEqual(viewModel.items.count, 3)
        let itemB = viewModel.items.first { $0.sourceURL == fileB }
        XCTAssertEqual(itemB?.status, .skipped)

        let itemA = viewModel.items.first { $0.sourceURL == fileA }
        XCTAssertEqual(itemA?.status, .queued)

        let itemC = viewModel.items.first { $0.sourceURL == fileC }
        XCTAssertEqual(itemC?.status, .queued)

        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.summary.succeededCount, 2)
        XCTAssertEqual(viewModel.summary.skippedCount, 1)

        // audioA and audioC should be written
        let outputA = outputDir.appendingPathComponent("audioA.json")
        let outputC = outputDir.appendingPathComponent("audioC.json")
        XCTAssertTrue(fileManager.fileExists(atPath: outputA.path))
        XCTAssertTrue(fileManager.fileExists(atPath: outputC.path))

        // audioB must remain untouched (D018)
        let postRunContentB = try String(contentsOf: preExistingB, encoding: .utf8)
        XCTAssertEqual(postRunContentB, preExistingContent)

        // Engine must only have been invoked for audioA and audioC
        let invocationCount = await mockEngine.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    // MARK: - 3. Cancellation Stop-After-Current with Correct Disk State

    func testPipeline_cancellation_stopAfterCurrent_preservesWrittenFilesAndMarksRemainingCancelled() async throws {
        let workDir = tempDirectory.appendingPathComponent("Cancellation")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "file1.mp3", directory: workDir)
        try createDummyAudioFile(name: "file2.mp3", directory: workDir)
        try createDummyAudioFile(name: "file3.mp3", directory: workDir)

        let openGate1 = CompletionGate()
        await openGate1.open() // Invocation 1 proceeds immediately

        let gate2 = CompletionGate() // Invocation 2 pauses until explicitly opened

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Processed"),
            engineID: "whisper-mock-engine",
            completionGatesSequence: [openGate1, gate2]
        )

        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(workDir)
        viewModel.start()

        // Wait until 2nd item is actively transcribing
        let startWait = Date()
        while viewModel.activeIndex != 1 {
            if Date().timeIntervalSince(startWait) > 5.0 {
                XCTFail("Timed out waiting for item 2 to become active")
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.activeIndex, 1)
        XCTAssertTrue(viewModel.isRunning)

        // Request cancellation (stop-after-current, D021)
        viewModel.cancel()
        XCTAssertTrue(viewModel.isCancelling)

        // Open gate to let item 2 complete its transcription and atomic write
        await gate2.open()

        try await waitForViewModelCompletion(viewModel)

        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.summary.succeededCount, 2)
        XCTAssertEqual(viewModel.summary.cancelledCount, 1)

        // Check disk state: file1.json and file2.json must exist (D022)
        let out1 = workDir.appendingPathComponent("file1.json")
        let out2 = workDir.appendingPathComponent("file2.json")
        let out3 = workDir.appendingPathComponent("file3.json")

        XCTAssertTrue(fileManager.fileExists(atPath: out1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: out2.path))
        XCTAssertFalse(fileManager.fileExists(atPath: out3.path))

        // Verify engine was invoked exactly twice
        let invocationCount = await mockEngine.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    // MARK: - 4. Failure Isolation with Correct Disk State

    func testPipeline_failureIsolation_recordsErrorAndContinuesProcessingRemainingQueue() async throws {
        let workDir = tempDirectory.appendingPathComponent("FailureIsolation")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "alpha.mp3", directory: workDir)
        try createDummyAudioFile(name: "corrupt.mp3", directory: workDir)
        try createDummyAudioFile(name: "gamma.mp3", directory: workDir)

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Good transcript"),
            engineID: "whisper-mock-engine",
            errorsSequence: [
                nil,
                MockTranscriptionEngineError(message: "Corrupt audio stream header"),
                nil
            ]
        )

        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(workDir)
        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.lifecycleState, .completed)
        XCTAssertEqual(viewModel.summary.succeededCount, 2)
        XCTAssertEqual(viewModel.summary.failedCount, 1)

        XCTAssertEqual(viewModel.items[0].status, .succeeded)
        XCTAssertEqual(viewModel.items[1].status, .failed)
        XCTAssertEqual(viewModel.items[1].errorMessage, "Corrupt audio stream header")
        XCTAssertEqual(viewModel.items[2].status, .succeeded)

        // Disk state: alpha.json and gamma.json exist; corrupt.json does not
        let outAlpha = workDir.appendingPathComponent("alpha.json")
        let outCorrupt = workDir.appendingPathComponent("corrupt.json")
        let outGamma = workDir.appendingPathComponent("gamma.json")

        XCTAssertTrue(fileManager.fileExists(atPath: outAlpha.path))
        XCTAssertFalse(fileManager.fileExists(atPath: outCorrupt.path))
        XCTAssertTrue(fileManager.fileExists(atPath: outGamma.path))

        let docGamma = try CanonicalTranscriptionSerializer.decode(try Data(contentsOf: outGamma))
        XCTAssertEqual(docGamma.source.fileName, "gamma.mp3")
    }

    // MARK: - 5. Large Queue Ordering

    func testPipeline_largeQueue_processesAllItemsInDeterministicNormalizedOrder() async throws {
        let workDir = tempDirectory.appendingPathComponent("LargeQueue")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        // Create 25 files with numerical naming out of order
        let numbers = Array(1...25).shuffled()
        for n in numbers {
            try createDummyAudioFile(name: "track_\(n).mp3", directory: workDir)
        }

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Large queue item"),
            engineID: "whisper-mock-engine"
        )

        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(workDir)

        XCTAssertEqual(viewModel.items.count, 25)

        // Verify natural numeric sort order: track_1.mp3, track_2.mp3, ..., track_10.mp3, ..., track_25.mp3
        for i in 0..<25 {
            let expectedName = "track_\(i + 1).mp3"
            XCTAssertEqual(viewModel.items[i].sourceURL.lastPathComponent, expectedName)
        }

        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.summary.succeededCount, 25)
        XCTAssertEqual(viewModel.overallProgress, 1.0)

        // Verify all 25 output JSON files exist on disk
        for i in 1...25 {
            let jsonURL = workDir.appendingPathComponent("track_\(i).json")
            XCTAssertTrue(fileManager.fileExists(atPath: jsonURL.path))
        }

        // Verify engine received requests in exact natural order
        let receivedRequests = await mockEngine.receivedRequests
        XCTAssertEqual(receivedRequests.count, 25)
        for (idx, req) in receivedRequests.enumerated() {
            let expectedName = "track_\(idx + 1).mp3"
            XCTAssertEqual(req.sourceURL.lastPathComponent, expectedName)
        }
    }

    // MARK: - 6. Unicode and Space Paths

    func testPipeline_unicodeAndSpacePaths_preservesExactBaseNamesAndSerializesCanonicalDocuments() async throws {
        let workDir = tempDirectory.appendingPathComponent("Dossier Conférence 2026 🎙️")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "Présentation de l'équipe (été 2026).mp3", directory: workDir)
        try createDummyAudioFile(name: "Отчёт и запись — встреча #1.wav", directory: workDir)
        try createDummyAudioFile(name: "音声テスト [東京].m4a", directory: workDir)

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Unicode transcript"),
            engineID: "whisper-mock-engine"
        )

        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(workDir)
        XCTAssertEqual(viewModel.items.count, 3)

        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.summary.succeededCount, 3)

        let out1 = workDir.appendingPathComponent("Présentation de l'équipe (été 2026).json")
        let out2 = workDir.appendingPathComponent("Отчёт и запись — встреча #1.json")
        let out3 = workDir.appendingPathComponent("音声テスト [東京].json")

        XCTAssertTrue(fileManager.fileExists(atPath: out1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: out2.path))
        XCTAssertTrue(fileManager.fileExists(atPath: out3.path))

        let doc1 = try CanonicalTranscriptionSerializer.decode(try Data(contentsOf: out1))
        XCTAssertEqual(doc1.source.fileName, "Présentation de l'équipe (été 2026).mp3")

        let doc2 = try CanonicalTranscriptionSerializer.decode(try Data(contentsOf: out2))
        XCTAssertEqual(doc2.source.fileName, "Отчёт и запись — встреча #1.wav")

        let doc3 = try CanonicalTranscriptionSerializer.decode(try Data(contentsOf: out3))
        XCTAssertEqual(doc3.source.fileName, "音声テスト [東京].m4a")
    }

    // MARK: - 7. D010 Gating with Single-File Mock / Busy State

    func testPipeline_d010Gating_rejectsStartWhenSingleFileIsBusy_andRejectsIngestionWhenBatchIsRunning() async throws {
        let workDir = tempDirectory.appendingPathComponent("D010Gating")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "clip1.mp3", directory: workDir)
        try createDummyAudioFile(name: "clip2.mp3", directory: workDir)

        var isSingleBusy = true
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Test"),
            engineID: "whisper-mock-engine"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager,
            isSingleFileBusy: { isSingleBusy }
        )

        viewModel.ingestFolder(workDir)
        XCTAssertFalse(viewModel.canStart)

        // Attempt start while single file is busy
        viewModel.start()
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.errorMessage, L10n.localizedString("batch.error.singleFileBusy"))

        let countBefore = await mockEngine.invocationCount
        XCTAssertEqual(countBefore, 0)

        // Clear single-file busy flag and use gate to pause batch during execution
        isSingleBusy = false
        XCTAssertTrue(viewModel.canStart)

        let gate = CompletionGate()
        let pausedEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Paused test"),
            completionGate: gate,
            engineID: "whisper-mock-engine"
        )
        let pausedCoordinator = BatchTranscriptionCoordinator(engine: pausedEngine)
        let activeViewModel = BatchTranscriptionViewModel(
            coordinator: pausedCoordinator,
            outputPolicy: policy,
            fileManager: fileManager,
            isSingleFileBusy: { false }
        )

        activeViewModel.ingestFolder(workDir)
        activeViewModel.start()

        // Wait for running state
        let startWait = Date()
        while !activeViewModel.isRunning {
            if Date().timeIntervalSince(startWait) > 2.0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(activeViewModel.isRunning)

        // Ingestion during active batch must be rejected (D010)
        let extraAudio = try createDummyAudioFile(name: "extra.wav", directory: tempDirectory)
        activeViewModel.ingestFiles([extraAudio])
        XCTAssertEqual(activeViewModel.errorMessage, L10n.localizedString("error.dropRejectedTranscribing"))

        activeViewModel.ingestFolder(tempDirectory)
        XCTAssertEqual(activeViewModel.errorMessage, L10n.localizedString("error.dropRejectedTranscribing"))

        // Release gate and wait for completion
        await gate.open()
        try await waitForViewModelCompletion(activeViewModel)

        XCTAssertFalse(activeViewModel.isBusy)
        XCTAssertEqual(activeViewModel.summary.succeededCount, 2)
    }

    // MARK: - 8. Policy Fallback When User Override Removed

    func testPipeline_outputPolicy_resolvesSourceFolder_supportsUserOverride_andFallsBackWhenOverrideReset() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("SourceDir")
        let overrideFolder = tempDirectory.appendingPathComponent("OverrideDir")
        try fileManager.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: overrideFolder, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "speech.mp3", directory: sourceFolder)

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(text: "Policy speech"),
            engineID: "whisper-mock-engine"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)

        // Step 1: Initial resolution with single folder grant proposes sourceFolder
        let res1 = policy.resolveOutputDirectory(for: .folder(sourceFolder))
        guard case .success(let resolution1) = res1 else {
            XCTFail("Expected successful resolution for sourceFolder")
            return
        }
        XCTAssertEqual(resolution1.source, .sourceFolder)
        XCTAssertEqual(resolution1.url.standardizedFileURL.path, sourceFolder.standardizedFileURL.path)

        // Step 2: Save user override in policy
        try policy.saveUserOverride(directory: overrideFolder)
        let res2 = policy.resolveOutputDirectory(for: .folder(sourceFolder))
        guard case .success(let resolution2) = res2 else {
            XCTFail("Expected successful resolution for userOverride")
            return
        }
        XCTAssertEqual(resolution2.source, .userOverride)
        XCTAssertEqual(resolution2.url.standardizedFileURL.path, overrideFolder.standardizedFileURL.path)

        // Step 3: Clear user override -> falls back cleanly to sourceFolder
        policy.clearUserOverride()
        let res3 = policy.resolveOutputDirectory(for: .folder(sourceFolder))
        guard case .success(let resolution3) = res3 else {
            XCTFail("Expected successful resolution for fallback to sourceFolder")
            return
        }
        XCTAssertEqual(resolution3.source, .sourceFolder)
        XCTAssertEqual(resolution3.url.standardizedFileURL.path, sourceFolder.standardizedFileURL.path)

        // Step 4: Run batch through ViewModel with this policy to verify disk write at fallback location
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        viewModel.ingestFolder(sourceFolder)
        XCTAssertEqual(viewModel.outputResolutionSource, .sourceFolder)
        XCTAssertEqual(viewModel.outputDirectory?.standardizedFileURL.path, sourceFolder.standardizedFileURL.path)
        XCTAssertEqual(viewModel.items[0].outputURL?.standardizedFileURL.path, sourceFolder.appendingPathComponent("speech.json").standardizedFileURL.path)

        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.summary.succeededCount, 1)
        let expectedFile = sourceFolder.appendingPathComponent("speech.json")
        let wrongFile = overrideFolder.appendingPathComponent("speech.json")

        XCTAssertTrue(fileManager.fileExists(atPath: expectedFile.path))
        XCTAssertFalse(fileManager.fileExists(atPath: wrongFile.path))
    }

    // MARK: - 9. End-to-End Pipeline with AppState Results Routing (Task 3.17 / D031)

    func testPipeline_endToEndWithAppStateRouting_allowsNavigatingToCompletedResult() async throws {
        let workDir = tempDirectory.appendingPathComponent("Routing")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        try createDummyAudioFile(name: "keynote.mp3", directory: workDir)
        let expectedResult = makeResult(text: "Keynote presentation transcript", duration: 42.0)

        let mockEngine = MockTranscriptionEngine(
            resultToReturn: expectedResult,
            engineID: "whisper-mock-engine"
        )
        let coordinator = BatchTranscriptionCoordinator(engine: mockEngine)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, fileManager: fileManager)
        let viewModel = BatchTranscriptionViewModel(
            coordinator: coordinator,
            outputPolicy: policy,
            fileManager: fileManager
        )

        let appState = AppState()
        XCTAssertEqual(appState.selectedNavigationItem, .transcribe)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertNil(appState.displayedTranscription)

        viewModel.ingestFolder(workDir)
        viewModel.start()
        try await waitForViewModelCompletion(viewModel)

        XCTAssertEqual(viewModel.summary.succeededCount, 1)
        let completedItem = viewModel.items[0]
        XCTAssertEqual(completedItem.status, .succeeded)

        // Route to AppState (D031)
        appState.routeToBatchItemResult(
            completedItem,
            modelName: viewModel.configuration.modelName,
            engineID: "whisper-mock-engine"
        )

        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertEqual(appState.selectedBatchItemID, completedItem.id)
        XCTAssertEqual(appState.displayedTranscription?.result, expectedResult)
        XCTAssertEqual(appState.displayedTranscription?.provenance?.sourceFileName, "keynote.mp3")
        XCTAssertEqual(appState.displayedTranscription?.provenance?.modelName, "base")
        XCTAssertEqual(appState.displayedTranscription?.provenance?.engineID, "whisper-mock-engine")
    }
}
