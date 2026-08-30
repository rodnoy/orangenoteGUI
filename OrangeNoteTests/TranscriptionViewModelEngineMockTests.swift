//
//  TranscriptionViewModelEngineMockTests.swift
//  OrangeNoteTests
//
//  Unit tests for `TranscriptionViewModel` (Task 2.9) exercising the real
//  `startTranscription(settings:)` path through an injected mock
//  `TranscriptionEngineProtocol`, demonstrating that the view model is now
//  fully testable without invoking the native Rust FFI binaries.
//
//  The mock conformer (`MockTranscriptionEngine`, defined in
//  `Helpers/MockTranscriptionEngine.swift`) is an `actor`, ensuring all
//  mutable state accessed across the test/async boundary is synchronized by
//  the Swift runtime rather than relying on an unsynchronized
//  `@unchecked Sendable` class (Task 2.11 / Finding B4).
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionViewModelEngineMockTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionViewModelEngineMockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeAudioFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    private func makeResult(fullText: String = "hello") -> TranscriptionResult {
        TranscriptionResult(
            segments: [],
            fullText: fullText,
            language: "en",
            duration: 1.0
        )
    }

    /// Polls `condition` until it becomes true or a timeout elapses, yielding to the
    /// run loop between checks so background `Task`s can make progress.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: (a) Successful transcription flow via injected mock engine.

    func testStartTranscription_successUpdatesStateAndResultViaMockEngine() async throws {
        let expectedResult = makeResult(fullText: "mock transcript")
        let mockEngine = MockTranscriptionEngine(resultToReturn: expectedResult)
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let fileURL = try makeAudioFile(named: "a.wav")
        let settings = AppSettings()

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: settings)

        await waitUntil { viewModel.result != nil || viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.result?.fullText, "mock transcript")
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertNil(viewModel.errorMessage)
        let received = await mockEngine.receivedRequest
        XCTAssertEqual(received?.sourceURL, fileURL)
        XCTAssertEqual(received?.modelName, settings.selectedModel)
    }

    // MARK: (b) Progress updates from the mock propagate to `progress`.

    func testStartTranscription_progressUpdatesPropagateFromMockEngine() async throws {
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(),
            progressValuesToEmit: [0.25, 0.5, 0.9],
            delaySeconds: 0.2
        )
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let fileURL = try makeAudioFile(named: "b.wav")

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())

        // Assert the intermediate progress value is observed before completion sets
        // progress to 1.0 (the mock's `delaySeconds` guarantees a window between the
        // last progress emission and the final result being returned).
        await waitUntil { viewModel.progress == 0.9 }
        XCTAssertEqual(viewModel.progress, 0.9)

        await waitUntil { viewModel.result != nil || viewModel.errorMessage != nil }
        XCTAssertEqual(viewModel.result?.fullText, "hello")
    }

    // MARK: (c) Engine throwing an error transitions to `.failed` with errorMessage set.

    func testStartTranscription_engineErrorTransitionsToFailedState() async throws {
        let expectedError = MockTranscriptionEngineError(message: "mock transcription failed")
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(),
            errorToThrow: expectedError
        )
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let fileURL = try makeAudioFile(named: "c.wav")

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())

        await waitUntil { viewModel.errorMessage != nil }

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.result)
        XCTAssertFalse(viewModel.isTranscribing)
        if case .failed(let file, _) = viewModel.state {
            XCTAssertEqual(file, fileURL)
        } else {
            XCTFail("Expected .failed state, got \(viewModel.state)")
        }
    }

    // MARK: (d) Stale/superseded job guard remains enforced through the real path.

    func testStartTranscription_staleCompletionAfterCancellationIsDiscarded() async throws {
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(fullText: "late result after cancel"),
            delaySeconds: 0.3
        )
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let fileURL = try makeAudioFile(named: "d.wav")

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())

        // Cancel logically while the mock engine's "FFI call" is still draining
        // (simulating D011: Task.cancel() does not stop an in-flight blocking call).
        await waitUntil { viewModel.isTranscribing }
        viewModel.cancelTranscription()

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertTrue(viewModel.isNativeBusy, "Native busy guard should remain set until the mock engine drains")

        // Wait for the mock engine's delayed completion to arrive and be discarded.
        await waitUntil(timeout: 2.0) { !viewModel.isNativeBusy }

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertNil(viewModel.result)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertFalse(viewModel.isNativeBusy)
    }

    // MARK: (e) Dynamic engine identity snapshot (Finding R3).

    /// `TranscriptionViewModel` must snapshot the actual injected engine's
    /// `engineID` into `executionProvenance`/`displayedTranscription` rather
    /// than hardcoding `WhisperTranscriptionEngine.stableEngineID`. Verified
    /// here with a non-Whisper mock engine carrying a distinct identifier.
    func testStartTranscription_snapshotsInjectedEngineIDDynamically() async throws {
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(fullText: "custom engine transcript"),
            engineID: "custom-cloud-engine"
        )
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let fileURL = try makeAudioFile(named: "e.wav")

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())

        await waitUntil { viewModel.result != nil || viewModel.errorMessage != nil }

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.executionProvenance?.engineID, "custom-cloud-engine")
        XCTAssertNotEqual(viewModel.executionProvenance?.engineID, WhisperTranscriptionEngine.stableEngineID)
        XCTAssertEqual(viewModel.displayedTranscription?.provenance?.engineID, "custom-cloud-engine")
    }
}
