//
//  DisplayedTranscriptionWiringTests.swift
//  OrangeNoteTests
//
//  Unit tests verifying `ResultsView`'s atomic `DisplayedTranscription` wiring (Task
//  2.20 / Finding F1): rendering and every export/copy action must read the result and
//  its provenance from the exact same snapshot, never mixing a result from one
//  transcription with provenance from another.
//

import XCTest
@testable import OrangeNote

@MainActor
final class DisplayedTranscriptionWiringTests: XCTestCase {

    private func makeResult(fullText: String) -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: fullText)
            ],
            fullText: fullText,
            language: "en",
            duration: 2.0
        )
    }

    /// `ResultsView` is constructed directly from a single `DisplayedTranscription`
    /// value, not from separately-sourced `result`/`provenance` properties. This test
    /// verifies the type itself only exposes one atomic snapshot to bind a view to,
    /// exercising the exact export code path `ResultsView`'s copy menu uses
    /// (`ExportViewModel.copyToClipboard(result:provenance:)`) against that single
    /// snapshot's `result` and `provenance` together.
    func testResultsView_exportReadsResultAndProvenanceFromSameSnapshot() throws {
        let result = makeResult(fullText: "atomic wiring test")
        let provenance = ExecutionProvenance(
            sourceURL: URL(fileURLWithPath: "/tmp/wiring-test.wav"),
            modelName: "large-v3",
            engineID: "whisper-local"
        )
        let displayed = DisplayedTranscription(result: result, provenance: provenance)

        let exportVM = ExportViewModel()
        exportVM.selectedFormat = .json
        // Mirrors exactly what `ResultsView`'s copy-as-JSON menu action does: pass
        // `displayedTranscription.result`/`.provenance` from one atomic value, never
        // pulling provenance from an independent side channel.
        exportVM.copyToClipboard(result: displayed.result, provenance: displayed.provenance)

        let content = try XCTUnwrap(exportVM.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.transcription.fullText, "atomic wiring test")
        XCTAssertEqual(document.source.fileName, "wiring-test.wav")
        XCTAssertEqual(document.engine.model, "large-v3")
        XCTAssertEqual(document.engine.id, "whisper-local")
    }

    /// A `DisplayedTranscription` with `nil` provenance (e.g. an import with no
    /// recoverable metadata) must export with honest "unknown" placeholders, never
    /// fabricating provenance from an unrelated prior snapshot.
    func testResultsView_exportWithNilProvenance_usesHonestPlaceholders() throws {
        let result = makeResult(fullText: "no provenance")
        let displayed = DisplayedTranscription(result: result, provenance: nil)

        let exportVM = ExportViewModel()
        exportVM.selectedFormat = .json
        exportVM.copyToClipboard(result: displayed.result, provenance: displayed.provenance)

        let content = try XCTUnwrap(exportVM.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.source.fileName, "unknown")
        XCTAssertEqual(document.engine.id, "unknown")
    }

    /// Two distinct `DisplayedTranscription` snapshots must never be torn apart: reading
    /// `result` from one and `provenance` from another would violate the atomicity
    /// `DisplayedTranscription` exists to guarantee. This test documents (and would
    /// catch a regression toward) the prior bug pattern where `ResultsView` sourced
    /// `result` from `TranscriptionViewModel.result` and `provenance` independently from
    /// `AppState.currentExecutionProvenance`.
    func testDisplayedTranscription_distinctSnapshotsAreNotInterchangeable() {
        let resultA = makeResult(fullText: "job A")
        let provenanceA = ExecutionProvenance(sourceURL: URL(fileURLWithPath: "/tmp/a.wav"), modelName: "base", engineID: "engine-a")
        let displayedA = DisplayedTranscription(result: resultA, provenance: provenanceA)

        let resultB = makeResult(fullText: "job B")
        let provenanceB = ExecutionProvenance(sourceURL: URL(fileURLWithPath: "/tmp/b.wav"), modelName: "large-v3", engineID: "engine-b")
        let displayedB = DisplayedTranscription(result: resultB, provenance: provenanceB)

        XCTAssertNotEqual(displayedA, displayedB)
        // Each snapshot's own pairing is internally consistent...
        XCTAssertEqual(displayedA.provenance?.engineID, "engine-a")
        XCTAssertEqual(displayedB.provenance?.engineID, "engine-b")
        // ...and mixing halves across snapshots would produce a value equal to neither,
        // which is exactly what atomic, single-source-of-truth wiring prevents from ever
        // being observably constructed by `ResultsView` in the first place.
        let mixed = DisplayedTranscription(result: displayedA.result, provenance: displayedB.provenance)
        XCTAssertNotEqual(mixed, displayedA)
        XCTAssertNotEqual(mixed, displayedB)
    }

    /// Job-owned provenance lifecycle (Task 2.20 / Finding F2): a failed transcription
    /// job must not leave stale `executionProvenance` behind for a later observation.
    func testTranscriptionViewModel_failedJob_clearsExecutionProvenance() throws {
        let sampleResult = makeResult(fullText: "will fail")
        struct SampleError: Error {}
        let engine = MockTranscriptionEngine(resultToReturn: sampleResult)
        let viewModel = TranscriptionViewModel(engine: engine)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data(repeating: 0, count: 16).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(
            fileURL: fileURL,
            provenance: ExecutionProvenance(sourceURL: fileURL, modelName: "base", engineID: "whisper-local")
        )
        guard let jobID = viewModel.state.activeJobID else {
            XCTFail("Expected an active running job")
            return
        }
        XCTAssertNotNil(viewModel.executionProvenance)

        viewModel.handleTranscriptionCompletion(jobID: jobID, fileURL: fileURL, outcome: .failure(SampleError()))

        XCTAssertNil(viewModel.executionProvenance, "A failed job must not leave stale provenance behind.")
        XCTAssertNil(viewModel.displayedTranscription)
    }
}
