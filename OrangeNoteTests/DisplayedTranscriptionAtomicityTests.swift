//
//  DisplayedTranscriptionAtomicityTests.swift
//  OrangeNoteTests
//
//  Unit tests for Task 2.16 (Findings R1 & R2): the atomic `DisplayedTranscription`
//  commit semantics on `TranscriptionViewModel`, honest "unknown" engine ID export
//  defaults, and Canonical import metadata preservation without fabricated paths.
//

import XCTest
@testable import OrangeNote

@MainActor
final class DisplayedTranscriptionAtomicityTests: XCTestCase {

    private func makeSampleResult(fullText: String = "Hello world.") -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: fullText)
            ],
            fullText: fullText,
            language: "en",
            duration: 2.0
        )
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try Data(repeating: 0, count: 16).write(to: url)
        return url
    }

    // MARK: - (a) Honest "unknown" engine ID default (Finding R1)

    func testExportViewModel_generateExport_defaultEngineID_isHonestlyUnknown_notWhisperLocal() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json

        // No provenance forwarded at all — simulates an export with no known execution
        // context. Must never silently default to "whisper-local".
        viewModel.generateExport(result: makeSampleResult())

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.engine.id, "unknown")
        XCTAssertNotEqual(document.engine.id, WhisperTranscriptionEngine.stableEngineID)
    }

    func testExportViewModel_saveToFile_withNilProvenance_defaultsEngineIDToUnknown() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json

        // `saveToFile` regenerates `exportedContent` via `generateExport` before
        // presenting the (untested, deferred) save panel; verify the honest default
        // propagates through that fallback path too.
        viewModel.saveToFile(result: makeSampleResult(), provenance: nil)

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.engine.id, "unknown")
    }

    // MARK: - (b) Atomic commit semantics (Finding R2)

    func testDisplayedTranscription_isNilWhileRunning_andNeverReflectsStalePriorRun() throws {
        let engine = MockTranscriptionEngine(resultToReturn: makeSampleResult())
        let viewModel = TranscriptionViewModel(engine: engine)
        let fileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.handleDroppedFile(fileURL)
        XCTAssertNil(viewModel.displayedTranscription, "No result should be displayed before any run.")

        let settings = AppSettings()
        settings.selectedModel = "base"
        viewModel.startTranscription(settings: settings)

        // While a job is logically running, `displayedTranscription` must be nil —
        // never a stale prior value, and never partially populated with only the
        // result or only the provenance half of a not-yet-committed pair.
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertNil(viewModel.displayedTranscription)
        // The in-flight provenance is tracked separately and is not yet part of any
        // displayed context.
        XCTAssertNotNil(viewModel.executionProvenance)
    }

    func testDisplayedTranscription_commitsAtomically_resultAndProvenanceTogether() throws {
        let expectedResult = makeSampleResult(fullText: "atomic commit test")
        let engine = MockTranscriptionEngine(resultToReturn: expectedResult)
        let viewModel = TranscriptionViewModel(engine: engine)
        let fileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        // Drive the deterministic completion path directly (mirrors production
        // `startTranscription`'s eventual `handleTranscriptionCompletion` call) so the
        // atomic commit can be observed synchronously without depending on `Task`
        // scheduling.
        guard let activeJobID = viewModel.state.activeJobID else {
            XCTFail("Expected an active running job after startTranscriptionForTesting")
            return
        }

        XCTAssertNil(viewModel.displayedTranscription, "Must remain nil until the job commits.")

        viewModel.handleTranscriptionCompletion(jobID: activeJobID, fileURL: fileURL, outcome: .success(expectedResult))

        // Upon successful completion, `result`, `executionProvenance`, and
        // `displayedTranscription` must all reflect the same completed job in a single
        // observable state — never torn between "new result, old/nil provenance" or
        // vice versa.
        let displayed = try XCTUnwrap(viewModel.displayedTranscription)
        XCTAssertEqual(displayed.result, expectedResult)
        XCTAssertEqual(displayed.result, viewModel.result)
        // Both halves of the atomic pair must agree, whichever the provenance value is
        // (this seam does not simulate `settings`-driven provenance capture — that is
        // covered separately in `ExecutionProvenanceExportTests` — the point here is
        // that `displayedTranscription.provenance` and `executionProvenance` can never
        // disagree once committed).
        XCTAssertEqual(displayed.provenance, viewModel.executionProvenance)
    }

    func testDisplayedTranscription_realStartTranscription_commitsResultAndProvenanceTogether() async throws {
        let expectedResult = makeSampleResult(fullText: "real end-to-end atomic commit")
        let engine = MockTranscriptionEngine(resultToReturn: expectedResult)
        let viewModel = TranscriptionViewModel(engine: engine)
        let fileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.handleDroppedFile(fileURL)
        let settings = AppSettings()
        settings.selectedModel = "base"
        viewModel.startTranscription(settings: settings)

        XCTAssertNil(viewModel.displayedTranscription, "Must remain nil while the real job is in flight.")

        // Poll until the async completion has landed (bounded to avoid an indefinite hang).
        for _ in 0..<200 where viewModel.displayedTranscription == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let displayed = try XCTUnwrap(viewModel.displayedTranscription, "Expected a committed displayed transcription after real completion.")
        XCTAssertEqual(displayed.result, expectedResult)
        let provenance = try XCTUnwrap(displayed.provenance)
        XCTAssertEqual(provenance.sourceURL, fileURL)
        XCTAssertEqual(provenance.modelName, "base")
        // The engine ID is snapshotted dynamically from the injected engine
        // instance (Finding R3), not hardcoded to the Whisper engine's ID.
        XCTAssertEqual(provenance.engineID, engine.engineID)
        // Never torn: both properties agree.
        XCTAssertEqual(viewModel.result, displayed.result)
        XCTAssertEqual(viewModel.executionProvenance, displayed.provenance)
    }

    func testDisplayedTranscription_importedResult_hasNilProvenanceWhenNoneSupplied() {
        let viewModel = TranscriptionViewModel()
        let imported = makeSampleResult(fullText: "imported, no metadata")

        viewModel.applyImportedResult(imported)

        let displayed = viewModel.displayedTranscription
        XCTAssertEqual(displayed?.result, imported)
        XCTAssertNil(displayed?.provenance, "Imports without recoverable metadata must not fabricate provenance.")
    }

    func testDisplayedTranscription_importedResult_withProvenance_commitsAtomically() {
        let viewModel = TranscriptionViewModel()
        let imported = makeSampleResult(fullText: "imported, with metadata")
        let provenance = ExecutionProvenance(
            sourceURL: URL(fileURLWithPath: "podcast-episode.json"),
            modelName: "small",
            engineID: "whisper-local"
        )

        viewModel.applyImportedResult(imported, provenance: provenance)

        let displayed = viewModel.displayedTranscription
        XCTAssertEqual(displayed?.result, imported)
        XCTAssertEqual(displayed?.provenance, provenance)
        XCTAssertEqual(viewModel.executionProvenance, provenance)
    }

    // MARK: - (c) Canonical import metadata preservation without fabricated paths (Finding R1)

    func testImportWithProvenance_canonicalJSON_preservesFileNameModelAndEngineID_withNilPath() throws {
        let originalResult = makeSampleResult(fullText: "Preserve my metadata.")
        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: originalResult,
            sourceURL: URL(fileURLWithPath: "/private/tmp/lecture-recording.wav"),
            modelName: "large-v3",
            engineID: "whisper-local",
            includeSourcePath: false
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let imported = try TranscriptionImportService.importWithProvenance(url: tempFile)

        let provenance = try XCTUnwrap(imported.provenance)
        XCTAssertEqual(provenance.modelName, "large-v3")
        XCTAssertEqual(provenance.engineID, "whisper-local")
        // The real fileName is preserved honestly...
        XCTAssertEqual(provenance.sourceFileName, "lecture-recording.wav")
        // ...but no real file URL is fabricated for a Canonical import (Task 2.20 /
        // Finding F3): there is no actual file on disk backing the imported document.
        XCTAssertNil(provenance.sourceURL)
        XCTAssertEqual(imported.result.fullText, originalResult.fullText)

        // ...but re-exporting the imported result must never fabricate/reconstruct a
        // real absolute file path (the original `/private/tmp/...` path is not
        // recoverable from the canonical document and must not resurface).
        let exportVM = ExportViewModel()
        exportVM.selectedFormat = .json
        exportVM.generateExport(
            result: imported.result,
            sourceFileName: provenance.sourceFileName,
            sourceURL: provenance.sourceURL,
            modelName: provenance.modelName,
            engineID: provenance.engineID
        )
        let exportedContent = try XCTUnwrap(exportVM.exportedContent)
        let exportedData = try XCTUnwrap(exportedContent.data(using: .utf8))
        let reExportedDocument = try CanonicalTranscriptionSerializer.decode(exportedData)

        XCTAssertNil(reExportedDocument.source.path, "Re-exporting an imported result must never embed a fabricated path.")
        XCTAssertEqual(reExportedDocument.source.fileName, "lecture-recording.wav")
        XCTAssertEqual(reExportedDocument.engine.model, "large-v3")
        XCTAssertEqual(reExportedDocument.engine.id, "whisper-local")
        XCTAssertFalse(exportedContent.contains("/private/tmp"))
    }

    func testImportWithProvenance_legacyJSON_hasNilProvenance() throws {
        let legacyResult = makeSampleResult(fullText: "legacy import")
        let data = try JSONEncoder().encode(legacyResult)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let imported = try TranscriptionImportService.importWithProvenance(url: tempFile)

        XCTAssertNil(imported.provenance, "Legacy JSON has no model/engine metadata to honestly report.")
        XCTAssertEqual(imported.result.fullText, legacyResult.fullText)
    }

    func testImportFromFile_backwardCompatible_returnsSameResultAsImportWithProvenance() throws {
        let originalResult = makeSampleResult(fullText: "compat check")
        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: originalResult,
            sourceURL: URL(fileURLWithPath: "/tmp/interview.wav"),
            modelName: "base",
            engineID: "whisper-local",
            includeSourcePath: false
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try TranscriptionImportService.importFromFile(url: tempFile)
        XCTAssertEqual(result.fullText, originalResult.fullText)
    }
}
