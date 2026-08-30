//
//  ExportViewModelSavePanelRegressionTests.swift
//  OrangeNoteTests
//
//  Regression test for a crash found during Task 2.15 manual verification: clicking
//  "Export" triggered an `EXC_BREAKPOINT` inside `ExportViewModel.saveToFile` at the
//  `NSSavePanel()` construction site. Root cause: `saveToFile` is invoked directly from
//  SwiftUI `onChange` handlers (menu commands) and button actions; presenting a blocking
//  modal (`NSSavePanel.runModal()`) synchronously from within such a callback can re-enter
//  SwiftUI's view-update machinery mid-transaction. The fix defers panel presentation to
//  the next main run-loop turn via `DispatchQueue.main.async`.
//
//  A true UI-level test that drives `NSSavePanel` is not feasible in a headless XCTest
//  environment (it would show a real blocking modal). This test instead exercises the
//  synchronous portion of `saveToFile` that runs before panel presentation is scheduled —
//  content generation and the "no content" guard — to verify that path remains correct
//  and crash-free after the fix.
//

import XCTest
@testable import OrangeNote

@MainActor
final class ExportViewModelSavePanelRegressionTests: XCTestCase {

    /// A segment with `endTime < startTime` causes `CanonicalTranscriptionSerializer`
    /// to throw `.outOfRange`, so `generateExport` sets `errorMessage` and leaves
    /// `exportedContent` `nil`. `saveToFile` must return via its "no content" guard
    /// in this case without ever reaching the deferred panel-presentation code.
    private func makeInvalidResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 5.0, endTime: 1.0, text: "Invalid segment.")
            ],
            fullText: "Invalid segment.",
            language: "en",
            duration: 5.0
        )
    }

    private func makeValidResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: "Hello world.")
            ],
            fullText: "Hello world.",
            language: "en",
            duration: 2.0
        )
    }

    /// Verifies that `saveToFile` synchronously regenerates content and surfaces a
    /// user-facing error via the "no content" guard, returning before scheduling any
    /// panel presentation, when export content generation fails.
    func testSaveToFile_withInvalidContent_setsNoContentErrorAndReturnsSynchronously() {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeInvalidResult()

        // Must return synchronously without presenting a panel or crashing.
        viewModel.saveToFile(result: result)

        XCTAssertNil(viewModel.exportedContent)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// Verifies that the content-generation step of `saveToFile` (which runs
    /// synchronously, before the deferred panel presentation) produces valid Canonical
    /// JSON v1 output for a well-formed result, mirroring exactly what would be written
    /// to disk once the deferred panel completes.
    func testGenerateExport_precedingSaveToFile_producesValidCanonicalJSON() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeValidResult()
        let provenance = ExecutionProvenance(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            modelName: "base",
            engineID: WhisperTranscriptionEngine.stableEngineID
        )

        viewModel.generateExport(
            result: result,
            sourceURL: provenance.sourceURL,
            modelName: provenance.modelName,
            engineID: provenance.engineID
        )

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.source.fileName, "sample.wav")
        XCTAssertEqual(document.engine.model, "base")
        XCTAssertNil(viewModel.errorMessage)
    }
}
