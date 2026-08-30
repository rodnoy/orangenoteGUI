//
//  TranscriptionNativeBusyTests.swift
//  OrangeNoteTests
//
//  Unit tests guarding TranscriptionViewModel against overlapping native Whisper FFI
//  operations (Task 1.9). Verifies that `isNativeBusy` enforces at most one active native
//  call, that cancellation is a logical-only operation which keeps `isNativeBusy == true`
//  until the background FFI thread drains, and that late completions from cancelled runs
//  remain suppressed while the busy guard blocks re-triggering and file/drop changes.
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionNativeBusyTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionNativeBusyTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: (a) Starting a job marks the native-busy guard, and re-triggering is rejected.

    func testStartingJobSetsNativeBusyAndBlocksReTrigger() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "a.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        XCTAssertTrue(viewModel.isNativeBusy)
        XCTAssertTrue(viewModel.isBusy)

        guard let firstJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        // Re-triggering while native-busy must not spawn a new job.
        viewModel.startTranscription(settings: AppSettings())
        XCTAssertEqual(viewModel.state.activeJobID, firstJobID, "startTranscription must be rejected while native-busy")
    }

    // MARK: (b) File selection and drop ingestion are blocked while native-busy.

    func testFileChangeIsBlockedWhileNativeBusy() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "b.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        let replacementFile = try makeAudioFile(named: "b-replacement.wav")

        // Cancel logically, but native-busy remains true until the FFI thread drains.
        viewModel.cancelTranscription()
        XCTAssertTrue(viewModel.isNativeBusy, "isNativeBusy must remain true until the native thread drains")

        viewModel.handleDroppedFile(replacementFile)

        XCTAssertEqual(
            viewModel.selectedFileURL,
            fileURL,
            "Drop ingestion must be blocked while a prior job's native call is still draining"
        )
    }

    // MARK: (c) Cancellation suppresses result delivery while holding busy state until drain.

    func testCancellationSuppressesResultUntilNativeDrains() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "c.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let cancelledJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        viewModel.cancelTranscription()

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertTrue(viewModel.isNativeBusy, "Native-busy must remain true immediately after logical cancellation")
        XCTAssertTrue(viewModel.isCancelling)

        // A late completion for the cancelled job must still be discarded while draining.
        let lateResult = makeResult(fullText: "late result while draining")
        viewModel.handleTranscriptionCompletion(jobID: cancelledJobID, fileURL: fileURL, outcome: .success(lateResult))

        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertNil(viewModel.result)

        // While draining, starting a new transcription and changing files remain rejected.
        XCTAssertFalse(viewModel.canStartTranscription)
        viewModel.startTranscription(settings: AppSettings())
        XCTAssertEqual(viewModel.state, .ready(file: fileURL), "startTranscription must be rejected while draining")

        // Once the background FFI thread actually drains, native-busy clears and a truthful
        // "cancelled" status is finalized, and new starts/file changes become permitted again.
        viewModel.completeNativeOperationForTesting()

        XCTAssertFalse(viewModel.isNativeBusy)
        XCTAssertFalse(viewModel.isCancelling)
        XCTAssertTrue(viewModel.canStartTranscription)

        let replacementFile = try makeAudioFile(named: "c-replacement.wav")
        viewModel.handleDroppedFile(replacementFile)
        XCTAssertEqual(viewModel.selectedFileURL, replacementFile, "File changes are permitted once native-busy clears")
    }

    // MARK: (d) At most one native operation: starting after full drain is permitted.

    func testNewStartPermittedOnlyAfterNativeDrains() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "d.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        viewModel.cancelTranscription()

        // Still draining: rejected.
        viewModel.startTranscription(settings: AppSettings())
        XCTAssertFalse(viewModel.isTranscribing, "No new job should start while the prior native call is still draining")

        viewModel.completeNativeOperationForTesting()

        // Now permitted: startTranscriptionForTesting models a fresh job acceptance.
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertTrue(viewModel.isNativeBusy)
    }
}
