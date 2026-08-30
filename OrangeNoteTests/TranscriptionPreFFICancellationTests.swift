//
//  TranscriptionPreFFICancellationTests.swift
//  OrangeNoteTests
//
//  Unit tests for Task 1.13 remediation:
//    - HIGH B: immediate cancellation before the native engine call is invoked must halt
//      without ever entering FFI, and must reflect truthful "cancelled" state.
//    - MEDIUM C: `finishNativeOperation` must be identity-bound to the execution
//      token/jobID it completes, so a stale/superseded operation's completion cannot
//      incorrectly clear busy state that now belongs to a newer operation.
//    - MEDIUM E: `TranscriptionView.handlePageDrop` must recheck busy state at commit
//      time after async provider resolution and surface rejection feedback instead of
//      silently ignoring a resolved drop. This is exercised here at the `DropResolution`
//      + `TranscriptionViewModel` integration-point level, since `handlePageDrop` itself
//      is a private view method (see also `DropItemResolverRemediationTests` for the
//      resolver-only dispatch normalization tests, MEDIUM D).
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionPreFFICancellationTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionPreFFICancellationTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: (a) HIGH B — immediate cancellation before engine entry halts truthfully.

    func testPreFFICheckpointHaltsWithoutEnteringEngineWhenCancelledBeforeEntry() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "a.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let jobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        // Simulate the user cancelling before the background Task's checkpoint runs
        // (D011: logical cancellation moves state out of `.running` immediately, while
        // `isNativeBusy` remains true until the native operation is confirmed drained).
        viewModel.cancelTranscription()
        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertTrue(viewModel.isNativeBusy, "Native-busy must remain true until the checkpoint/drain resolves it")
        XCTAssertTrue(viewModel.isCancelling)

        // The pre-FFI checkpoint must observe the job is no longer active and halt,
        // never "entering" the native engine call.
        let proceeded = viewModel.simulatePreFFICheckpointForTesting(jobID: jobID)
        XCTAssertFalse(proceeded, "Checkpoint must halt before invoking the native engine call")

        // Halting at the checkpoint must truthfully finalize busy/cancelling state exactly
        // as if the (never-invoked) native call had drained.
        XCTAssertFalse(viewModel.isNativeBusy)
        XCTAssertFalse(viewModel.isCancelling)
        XCTAssertEqual(viewModel.state, .ready(file: fileURL), "State must remain unaffected by the halted job")
        XCTAssertTrue(viewModel.canStartTranscription, "A new start must be permitted immediately after pre-FFI halt")
    }

    // MARK: (b) HIGH B — checkpoint proceeds normally for a still-active job.

    func testPreFFICheckpointProceedsWhenJobStillActive() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "b.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let jobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        let proceeded = viewModel.simulatePreFFICheckpointForTesting(jobID: jobID)
        XCTAssertTrue(proceeded, "Checkpoint must proceed to the native engine call for a still-active job")

        // Proceeding must not have altered busy/running state.
        XCTAssertTrue(viewModel.isNativeBusy)
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.state.activeJobID, jobID)
    }

    // MARK: (c) HIGH B — checkpoint halts when superseded by a newer job (defensive case).

    func testPreFFICheckpointHaltsForSupersededJobID() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "c.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let staleJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        // A stale jobID (not the current active job) must never be treated as proceeding.
        let unrelatedJobID = UUID()
        XCTAssertNotEqual(staleJobID, unrelatedJobID)
        let proceeded = viewModel.simulatePreFFICheckpointForTesting(jobID: unrelatedJobID)
        XCTAssertFalse(proceeded)

        // The genuinely active job's busy state must be untouched by the stale checkpoint.
        XCTAssertTrue(viewModel.isNativeBusy)
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.state.activeJobID, staleJobID)
    }

    // MARK: (d) MEDIUM C — a stale native completion cannot clear a newer job's busy state.

    func testStaleNativeCompletionCannotClearNewerJobsBusyState() throws {
        let viewModel = TranscriptionViewModel()
        let fileA = try makeAudioFile(named: "d-a.wav")
        let fileB = try makeAudioFile(named: "d-b.wav")

        viewModel.handleDroppedFile(fileA)
        viewModel.startTranscriptionForTesting(fileURL: fileA)
        guard let jobA = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID for job A")
            return
        }

        // Job A is cancelled and then genuinely drains (its native operation completes).
        viewModel.cancelTranscription()
        viewModel.completeNativeOperationForTesting()
        XCTAssertFalse(viewModel.isNativeBusy)

        // A new job B starts, becoming the current native operation.
        viewModel.handleDroppedFile(fileB)
        viewModel.startTranscriptionForTesting(fileURL: fileB)
        guard let jobB = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID for job B")
            return
        }
        XCTAssertNotEqual(jobA, jobB)
        XCTAssertTrue(viewModel.isNativeBusy)
        XCTAssertTrue(viewModel.isTranscribing)

        // A stale/duplicate late completion for job A arrives after job B has already
        // started. It must be ignored: job B's busy/running state must remain untouched.
        viewModel.completeNativeOperationForTesting(token: jobA)

        XCTAssertTrue(viewModel.isNativeBusy, "Stale completion for job A must not clear job B's busy state")
        XCTAssertTrue(viewModel.isTranscribing, "Stale completion for job A must not affect job B's running state")
        XCTAssertEqual(viewModel.state.activeJobID, jobB)

        // The genuine completion for job B must still correctly clear native-busy state.
        // (`isTranscribing` reflects the logical `.running` lifecycle state, which is only
        // exited via cancellation or a delivered completion outcome — not by this native
        // drain simulation alone — so only `isNativeBusy` is asserted here.)
        viewModel.completeNativeOperationForTesting(token: jobB)
        XCTAssertFalse(viewModel.isNativeBusy)
    }

    // MARK: (e) MEDIUM E — busy-state recheck at drop commit time surfaces rejection
    // feedback instead of silently ignoring an accepted resolution.

    func testDroppedFileIsRejectedWithFeedbackWhenBusyStateChangedDuringResolution() throws {
        let viewModel = TranscriptionViewModel()
        let runningFile = try makeAudioFile(named: "e-running.wav")
        let droppedFile = try makeAudioFile(named: "e-dropped.wav")

        // Simulate: at the time `extractAndResolve` was dispatched, the view captured
        // `isBusy == false`; by the time the async resolution completes and reaches the
        // commit point, a transcription has started (`isBusy` is now `true`). This
        // reproduces the exact commit-time recheck `TranscriptionView.handlePageDrop`
        // must perform (MEDIUM E) — modeled here directly against the view model, since
        // `handlePageDrop` itself is a private view method.
        viewModel.handleDroppedFile(runningFile)
        viewModel.startTranscriptionForTesting(fileURL: runningFile)
        XCTAssertTrue(viewModel.isBusy)

        let resolution = DropResolution.accepted(droppedFile)

        // This mirrors the exact commit-time logic added to `handlePageDrop`.
        switch resolution {
        case .accepted(let url):
            if viewModel.isBusy {
                if let message = DropResolution.rejectedTranscribing.localizedMessage {
                    viewModel.reportDropRejection(message)
                }
            } else {
                viewModel.handleDroppedFile(url)
            }
        default:
            XCTFail("Expected .accepted resolution")
        }

        // The already-running job's file selection must remain untouched...
        XCTAssertEqual(viewModel.selectedFileURL, runningFile)
        // ...and the user must receive explicit rejection feedback rather than a silent
        // no-op.
        XCTAssertEqual(viewModel.errorMessage, L10n.localizedString("error.dropRejectedTranscribing"))
    }

    func testDroppedFileIsAcceptedWhenStillIdleAtCommitTime() throws {
        let viewModel = TranscriptionViewModel()
        let droppedFile = try makeAudioFile(named: "f-dropped.wav")

        XCTAssertFalse(viewModel.isBusy)

        let resolution = DropResolution.accepted(droppedFile)
        switch resolution {
        case .accepted(let url):
            if viewModel.isBusy {
                if let message = DropResolution.rejectedTranscribing.localizedMessage {
                    viewModel.reportDropRejection(message)
                }
            } else {
                viewModel.handleDroppedFile(url)
            }
        default:
            XCTFail("Expected .accepted resolution")
        }

        XCTAssertEqual(viewModel.selectedFileURL, droppedFile)
        XCTAssertNil(viewModel.errorMessage)
    }
}
