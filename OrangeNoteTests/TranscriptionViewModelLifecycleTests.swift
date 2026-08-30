//
//  TranscriptionViewModelLifecycleTests.swift
//  OrangeNoteTests
//
//  Unit tests for the TranscriptionViewModel conceptual lifecycle states.
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionViewModelLifecycleTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionViewModelLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeAudioFile(named name: String = "sample.wav") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    func testInitialStateIsEmpty() {
        let viewModel = TranscriptionViewModel()
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.selectedFileURL)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertNil(viewModel.result)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleDroppedFileTransitionsToReady() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()

        viewModel.handleDroppedFile(fileURL)

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertEqual(viewModel.selectedFileURL, fileURL)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertNil(viewModel.result)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleDroppedInvalidFileDoesNotChangeState() throws {
        let viewModel = TranscriptionViewModel()
        let invalidURL = tempDirectory.appendingPathComponent("notaudio.txt")
        try Data("not audio".utf8).write(to: invalidURL)

        viewModel.handleDroppedFile(invalidURL)

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testReplacingFileClearsPriorErrorAndResult() throws {
        let viewModel = TranscriptionViewModel()
        let firstFile = try makeAudioFile(named: "first.wav")
        let secondFile = try makeAudioFile(named: "second.wav")

        viewModel.handleDroppedFile(firstFile)
        // Simulate a prior job on the first file using the deterministic testing seam
        // (Task 1.9: real `startTranscription` now blocks file changes via the native-busy
        // guard while a job is running/draining, so it cannot be used here to reach a
        // non-ready state before replacement).
        viewModel.startTranscriptionForTesting(fileURL: firstFile)
        viewModel.cancelTranscription()
        viewModel.completeNativeOperationForTesting()

        viewModel.handleDroppedFile(secondFile)

        XCTAssertEqual(viewModel.state, .ready(file: secondFile))
        XCTAssertEqual(viewModel.selectedFileURL, secondFile)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.result)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertFalse(viewModel.isTranscribing)
    }

    func testStartTranscriptionTransitionsToRunning() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)

        viewModel.startTranscription(settings: AppSettings())

        if case .running(let file, _) = viewModel.state {
            XCTAssertEqual(file, fileURL)
        } else {
            XCTFail("Expected running state, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertNil(viewModel.result)
        XCTAssertNil(viewModel.errorMessage)

        // Clean up background task to avoid leaking into other tests.
        viewModel.cancelTranscription()
    }

    func testCancelTranscriptionReturnsToReadyWithSelectedFile() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())

        viewModel.cancelTranscription()

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.progress, 0.0)
    }

    func testClearResultWithNoFileReturnsToEmpty() {
        let viewModel = TranscriptionViewModel()

        viewModel.clearResult()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.selectedFileURL)
    }

    func testClearResultWithSelectedFileReturnsToReady() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)

        viewModel.clearResult()

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
    }

    func testClearResultIsNoOpWhileTranscribing() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        XCTAssertTrue(viewModel.isTranscribing)

        viewModel.clearResult()

        // clearResult() must be rejected (no-op) while a job is logically running (D011),
        // since transitioning to `.ready`/`.empty` would corrupt the active lifecycle
        // state while native Whisper execution is still ongoing.
        if case .running(let file, _) = viewModel.state {
            XCTAssertEqual(file, fileURL)
        } else {
            XCTFail("Expected clearResult() to be rejected, leaving state as .running, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.selectedFileURL, fileURL)

        viewModel.cancelTranscription()
        viewModel.completeNativeOperationForTesting()
    }

    func testClearResultIsNoOpWhileNativeBusyDraining() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        viewModel.cancelTranscription()

        // Logical cancellation moves state to `.ready`, but the native FFI call is still
        // considered draining (`isNativeBusy == true`) until `finishNativeOperation` runs.
        XCTAssertTrue(viewModel.isNativeBusy)
        XCTAssertFalse(viewModel.isTranscribing)

        viewModel.clearResult()

        // clearResult() must remain rejected (no-op) while `isNativeBusy` is still true,
        // even though `isTranscribing` has already returned to `false`.
        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertEqual(viewModel.selectedFileURL, fileURL)

        viewModel.completeNativeOperationForTesting()
        XCTAssertFalse(viewModel.isNativeBusy)
    }

    func testStartTranscriptionWithNoFileSetsErrorWithoutChangingState() {
        let viewModel = TranscriptionViewModel()

        viewModel.startTranscription(settings: AppSettings())

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDismissErrorClearsErrorMessageWithoutChangingOtherState() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscription(settings: AppSettings())
        viewModel.cancelTranscription()

        // Manually drive into a deterministic error state via the drop-rejection intent,
        // which is the only production entry point that sets `errorMessage` without
        // requiring the real FFI.
        viewModel.reportDropRejection("Simulated error")
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.dismissError()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFileURL, fileURL)
    }

    func testFailedTransitionResetsProgressAndResultDeterministically() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile()
        viewModel.handleDroppedFile(fileURL)

        // Reach `.running` and simulate progress advancing before failure, using the
        // deterministic testing seam (Task 1.9) so this test does not depend on the real
        // Rust FFI or model resources.
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        guard case .running(_, let jobID) = viewModel.state else {
            XCTFail("Expected running state")
            return
        }
        viewModel.handleProgressUpdate(jobID: jobID, progressValue: 0.75)
        XCTAssertEqual(viewModel.progress, 0.75)

        struct SimulatedError: Error, LocalizedError {
            var errorDescription: String? { "Simulated failure" }
        }
        viewModel.handleTranscriptionCompletion(
            jobID: jobID,
            fileURL: fileURL,
            outcome: .failure(SimulatedError())
        )

        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertNil(viewModel.result)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTranscribing)

        viewModel.completeNativeOperationForTesting()
    }
}
