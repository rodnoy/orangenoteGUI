//
//  TranscriptionJobConcurrencyTests.swift
//  OrangeNoteTests
//
//  Unit tests guarding TranscriptionViewModel against stale asynchronous job completions
//  (Task 1.4). Verifies that completion/progress events tagged with an outdated `jobID`
//  are discarded rather than corrupting the active state, per D011.
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionJobConcurrencyTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionJobConcurrencyTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: (a) Normal completion updates state.

    func testActiveJobCompletionUpdatesState() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "a.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let activeJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID after starting transcription")
            return
        }

        let result = makeResult(fullText: "final transcript")
        viewModel.handleTranscriptionCompletion(jobID: activeJobID, fileURL: fileURL, outcome: .success(result))

        XCTAssertEqual(viewModel.state, .completed(file: fileURL, result: result))
        XCTAssertEqual(viewModel.result?.fullText, "final transcript")
        XCTAssertFalse(viewModel.isTranscribing)
    }

    func testActiveJobProgressUpdateAppliesValue() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "b.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let activeJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        viewModel.handleProgressUpdate(jobID: activeJobID, progressValue: 0.42)

        XCTAssertEqual(viewModel.progress, 0.42)
    }

    // MARK: (b) Stale job completing after a newer job has started must be discarded.

    func testStaleJobCompletionAfterNewerJobIsDiscarded() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "c.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let staleJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        // A newer job supersedes the stale one (e.g. user replaced the file and restarted).
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        guard let newerJobID = viewModel.state.activeJobID, newerJobID != staleJobID else {
            XCTFail("Expected a distinct newer active jobID")
            return
        }

        // Advance the newer job's progress to a known value.
        viewModel.handleProgressUpdate(jobID: newerJobID, progressValue: 0.75)
        XCTAssertEqual(viewModel.progress, 0.75)

        // The stale job's late completion must be discarded and must NOT overwrite state.
        let staleResult = makeResult(fullText: "stale result")
        viewModel.handleTranscriptionCompletion(jobID: staleJobID, fileURL: fileURL, outcome: .success(staleResult))

        XCTAssertEqual(viewModel.state, .running(file: fileURL, jobID: newerJobID))
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertNil(viewModel.result)
        XCTAssertEqual(viewModel.progress, 0.75, "Stale completion must not reset newer job's progress")

        // The stale job's late progress update must also be discarded.
        viewModel.handleProgressUpdate(jobID: staleJobID, progressValue: 0.01)
        XCTAssertEqual(viewModel.progress, 0.75, "Stale progress update must not overwrite newer job's progress")
    }

    // MARK: (c) Job completing after cancellation must be discarded.

    func testJobCompletionAfterCancellationIsDiscarded() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "d.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        guard let cancelledJobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        viewModel.cancelTranscription()
        XCTAssertEqual(viewModel.state, .ready(file: fileURL))

        let lateResult = makeResult(fullText: "late result after cancel")
        viewModel.handleTranscriptionCompletion(jobID: cancelledJobID, fileURL: fileURL, outcome: .success(lateResult))

        // The cancelled job's late completion must not resurrect `.completed` state.
        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertNil(viewModel.result)
        XCTAssertFalse(viewModel.isTranscribing)

        // A late failure for the same cancelled job must also be discarded.
        viewModel.handleTranscriptionCompletion(
            jobID: cancelledJobID,
            fileURL: fileURL,
            outcome: .failure(NSError(domain: "test", code: 1))
        )
        XCTAssertEqual(viewModel.state, .ready(file: fileURL))
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: (d) Production-representative replacement: a completed result followed by a
    // new file selection and transcription updates context deterministically
    // (Task 2.21 / Finding F5).
    //
    // The previous version of this test (`testJobReplacement_realActiveJobReplacedBeforeCompletion_...`)
    // replaced an *active, still-running* job by calling `startTranscriptionForTesting`
    // twice in a row without ever cancelling or completing the first job. That sequence
    // is impossible in production: real `startTranscription(settings:)` rejects
    // re-triggering via the `isBusy` guard while a job is logically running or the
    // native FFI call is still draining (D011), so an active job can never be silently
    // replaced by a second `startTranscription` call. This test instead drives the
    // exact production-valid sequence — job A fully completes via the real
    // `startTranscription(settings:)` path (through an injected `MockTranscriptionEngine`,
    // no test-only seam bypassing lifecycle guards), the user then selects a new file
    // (`handleDroppedFile`), and job B is started and completed — asserting the final
    // atomic `displayedTranscription` deterministically reflects only job B's result and
    // provenance, with job A's now-superseded context fully replaced.
    func testJobReplacement_completedResultFollowedByNewFileSelectionAndTranscription_updatesContextDeterministically() async throws {
        let fileA = try makeAudioFile(named: "replace-a.wav")
        let fileB = try makeAudioFile(named: "replace-b.wav")

        // A single injected mock engine serves both runs via `resultsSequence`,
        // returning "job A result" for the first invocation and "job B result" for the
        // second — modeling the same engine instance handling two successive,
        // non-overlapping transcription runs (D027: explicit, non-swappable engine
        // selection; there is no production API to hot-swap the injected engine).
        let mockEngine = MockTranscriptionEngine(
            resultToReturn: makeResult(fullText: "job A result"),
            engineID: "mock-engine",
            resultsSequence: [makeResult(fullText: "job A result"), makeResult(fullText: "job B result")]
        )
        let viewModel = TranscriptionViewModel(engine: mockEngine)
        let settingsA = AppSettings()
        settingsA.selectedModel = "base"

        viewModel.handleDroppedFile(fileA)
        viewModel.startTranscription(settings: settingsA)

        try await waitUntil { viewModel.result != nil || viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.displayedTranscription?.result.fullText, "job A result")
        XCTAssertEqual(viewModel.executionProvenance?.sourceURL, fileA)
        XCTAssertEqual(viewModel.executionProvenance?.modelName, "base")

        // The user now selects a new file, superseding job A's now-completed context
        // through the real, public `handleDroppedFile` entry point.
        viewModel.handleDroppedFile(fileB)
        XCTAssertNil(viewModel.displayedTranscription, "Selecting a new file must clear the prior completed context")
        XCTAssertNil(viewModel.executionProvenance)

        // Job B runs against the same engine (returning its second queued result) with
        // a distinct model setting, exactly as if the user changed settings between runs.
        let settingsB = AppSettings()
        settingsB.selectedModel = "large-v3"

        viewModel.startTranscription(settings: settingsB)
        try await waitUntil { viewModel.result != nil || viewModel.errorMessage != nil }

        let displayed = try XCTUnwrap(viewModel.displayedTranscription)
        XCTAssertEqual(displayed.result.fullText, "job B result")
        XCTAssertEqual(displayed.provenance?.sourceURL, fileB)
        XCTAssertEqual(displayed.provenance?.modelName, "large-v3")
    }

    // MARK: (e) Job-owned provenance terminal transfer (Task 2.23 / Finding G1).

    /// Successful completion must atomically transfer `executionProvenance` into
    /// `displayedTranscription` and clear running job ownership (`runningJobIDForTesting`)
    /// in the same synchronous transition, since the job is no longer "running" once it
    /// has reached a terminal `.completed` state.
    func testSuccessfulCompletion_atomicallySetsDisplayedTranscriptionAndClearsRunningJobOwnership() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "e.wav")
        viewModel.handleDroppedFile(fileURL)

        let provenance = ExecutionProvenance(sourceURL: fileURL, modelName: "base", engineID: "whisper-local")
        viewModel.startTranscriptionForTesting(fileURL: fileURL, provenance: provenance)

        guard let jobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }
        XCTAssertEqual(viewModel.runningJobIDForTesting, jobID)

        let result = makeResult(fullText: "owned completion")
        viewModel.handleTranscriptionCompletion(jobID: jobID, fileURL: fileURL, outcome: .success(result))

        XCTAssertEqual(viewModel.displayedTranscription?.result.fullText, "owned completion")
        XCTAssertEqual(viewModel.displayedTranscription?.provenance, provenance)
        XCTAssertNil(
            viewModel.runningJobIDForTesting,
            "runningJobID must be cleared once the job reaches a terminal completed state"
        )
    }

    /// Failure must clear both running provenance and job ownership.
    func testFailedCompletion_clearsRunningProvenanceAndJobOwnership() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "f.wav")
        viewModel.handleDroppedFile(fileURL)

        let provenance = ExecutionProvenance(sourceURL: fileURL, modelName: "base", engineID: "whisper-local")
        viewModel.startTranscriptionForTesting(fileURL: fileURL, provenance: provenance)

        guard let jobID = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID")
            return
        }

        viewModel.handleTranscriptionCompletion(
            jobID: jobID,
            fileURL: fileURL,
            outcome: .failure(NSError(domain: "test", code: 1))
        )

        XCTAssertNil(viewModel.executionProvenance)
        XCTAssertNil(viewModel.runningJobIDForTesting)
        XCTAssertNil(viewModel.displayedTranscription)
    }

    /// Cancellation must clear both running provenance and job ownership.
    func testCancellation_clearsRunningProvenanceAndJobOwnership() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "g.wav")
        viewModel.handleDroppedFile(fileURL)

        let provenance = ExecutionProvenance(sourceURL: fileURL, modelName: "base", engineID: "whisper-local")
        viewModel.startTranscriptionForTesting(fileURL: fileURL, provenance: provenance)

        XCTAssertNotNil(viewModel.runningJobIDForTesting)

        viewModel.cancelTranscription()

        XCTAssertNil(viewModel.executionProvenance)
        XCTAssertNil(viewModel.runningJobIDForTesting)
    }

    /// A stale job's leftover provenance/ownership must never attach to a different,
    /// currently active job's terminal result (Task 2.23 / Finding G1). This models the
    /// exact defect the ownership validation in `handleTranscriptionCompletion` guards
    /// against: `runningJobID` desynchronized from the currently active job.
    func testWrongJobProvenanceCannotAttachToActiveResult() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "h.wav")
        viewModel.handleDroppedFile(fileURL)

        let provenanceA = ExecutionProvenance(sourceURL: fileURL, modelName: "job-a-model", engineID: "engine-a")
        viewModel.startTranscriptionForTesting(fileURL: fileURL, provenance: provenanceA)
        guard let jobA = viewModel.state.activeJobID else {
            XCTFail("Expected .running state with an active jobID for job A")
            return
        }
        XCTAssertEqual(viewModel.runningJobIDForTesting, jobA)

        // A newer job (job B) becomes active without supplying its own provenance,
        // leaving `executionProvenance`/`runningJobID` stale and still pointing at job
        // A — the desynchronized scenario this ownership check guards against.
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        guard let jobB = viewModel.state.activeJobID, jobB != jobA else {
            XCTFail("Expected a distinct newer active jobID for job B")
            return
        }
        XCTAssertEqual(viewModel.runningJobIDForTesting, jobA, "Precondition: ownership is stale, still pointing at job A")

        let resultB = makeResult(fullText: "job B result")
        viewModel.handleTranscriptionCompletion(jobID: jobB, fileURL: fileURL, outcome: .success(resultB))

        XCTAssertEqual(viewModel.displayedTranscription?.result.fullText, "job B result")
        XCTAssertNil(
            viewModel.displayedTranscription?.provenance,
            "Stale job A provenance must not attach to job B's terminal result"
        )
        XCTAssertNil(viewModel.runningJobIDForTesting, "Ownership must be cleared after terminal completion")
    }

    /// Polls `condition` until it becomes true or a timeout elapses, yielding to the run
    /// loop between checks so background `Task`s driven by the real `startTranscription`
    /// path can make progress.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
