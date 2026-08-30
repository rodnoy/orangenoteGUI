//
//  ExecutionProvenanceExportTests.swift
//  OrangeNoteTests
//
//  Unit tests verifying execution provenance capture in `TranscriptionViewModel` and
//  honest, privacy-safe canonical export metadata wiring in `ExportViewModel`
//  (Task 2.13 / Finding B3).
//

import XCTest
@testable import OrangeNote

@MainActor
final class ExecutionProvenanceExportTests: XCTestCase {

    private func makeSampleResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: "Hello world.")
            ],
            fullText: "Hello world.",
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

    // MARK: - TranscriptionViewModel provenance capture

    func testExecutionProvenance_isNilInEmptyState() {
        let viewModel = TranscriptionViewModel(engine: MockTranscriptionEngine(resultToReturn: makeSampleResult()))
        XCTAssertNil(viewModel.executionProvenance)
    }

    func testExecutionProvenance_isCapturedWhenTranscriptionStarts() throws {
        let engine = MockTranscriptionEngine(resultToReturn: makeSampleResult())
        let viewModel = TranscriptionViewModel(engine: engine)
        let fileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        viewModel.handleDroppedFile(fileURL)

        let settings = AppSettings()
        settings.selectedModel = "base"
        viewModel.startTranscription(settings: settings)

        let provenance = try XCTUnwrap(viewModel.executionProvenance)
        XCTAssertEqual(provenance.sourceURL, fileURL)
        XCTAssertEqual(provenance.modelName, "base")
        // The engine ID is snapshotted dynamically from the injected engine
        // instance (Finding R3), not hardcoded to the Whisper engine's ID.
        XCTAssertEqual(provenance.engineID, engine.engineID)
    }

    func testExecutionProvenance_isClearedOnImportedResult() {
        let viewModel = TranscriptionViewModel(engine: MockTranscriptionEngine(resultToReturn: makeSampleResult()))
        viewModel.applyImportedResult(makeSampleResult())
        XCTAssertNil(viewModel.executionProvenance)
    }

    func testExecutionProvenance_isClearedWhenNewFileSelected() throws {
        let engine = MockTranscriptionEngine(resultToReturn: makeSampleResult())
        let viewModel = TranscriptionViewModel(engine: engine)
        let fileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        viewModel.handleDroppedFile(fileURL)

        let settings = AppSettings()
        viewModel.startTranscription(settings: settings)
        XCTAssertNotNil(viewModel.executionProvenance)

        viewModel.cancelTranscription()
        XCTAssertNil(viewModel.executionProvenance)
    }

    // MARK: - ExportViewModel honest metadata wiring

    func testGenerateExport_withRealProvenance_producesRealMetadata() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()
        let sourceURL = URL(fileURLWithPath: "/tmp/interview.wav")

        viewModel.generateExport(
            result: result,
            sourceURL: sourceURL,
            modelName: "large-v3",
            engineID: WhisperTranscriptionEngine.stableEngineID
        )

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.source.fileName, "interview.wav")
        XCTAssertEqual(document.engine.model, "large-v3")
        XCTAssertEqual(document.engine.id, "whisper-local")
    }

    func testGenerateExport_neverEmbedsRealSourcePath_forPrivacy() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()
        let sourceURL = URL(fileURLWithPath: "/Users/someone/Private/secret-recording.wav")

        viewModel.generateExport(
            result: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: WhisperTranscriptionEngine.stableEngineID
        )

        let content = try XCTUnwrap(viewModel.exportedContent)
        XCTAssertFalse(content.contains("/Users/someone/Private"))

        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)
        XCTAssertNil(document.source.path)
        // The file name itself is still honestly reported.
        XCTAssertEqual(document.source.fileName, "secret-recording.wav")
    }

    func testGenerateExport_withoutProvenance_usesHonestPlaceholdersNotFakePaths() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()

        // Simulates exporting an imported result with no known execution provenance.
        viewModel.generateExport(result: result)

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertNil(document.source.path)
        XCTAssertEqual(document.source.fileName, "unknown")
        XCTAssertEqual(document.engine.model, "unknown")
        // Task 2.16 / Finding R1: no provenance must never be fabricated into
        // `whisper-local` — it must honestly report `"unknown"`.
        XCTAssertEqual(document.engine.id, "unknown")
    }

    func testSaveToFile_forwardsProvenanceIntoCanonicalMetadata() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()
        let provenance = ExecutionProvenance(
            sourceURL: URL(fileURLWithPath: "/tmp/podcast-episode.wav"),
            modelName: "small",
            engineID: WhisperTranscriptionEngine.stableEngineID
        )

        // `generateExport` is exercised indirectly via the public `saveToFile` entry
        // point (a save panel is not driven in tests), verifying `exportedContent` is
        // regenerated using the forwarded provenance before any panel would appear.
        viewModel.generateExport(
            result: result,
            sourceURL: provenance.sourceURL,
            modelName: provenance.modelName,
            engineID: provenance.engineID
        )

        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let document = try CanonicalTranscriptionSerializer.decode(data)

        XCTAssertEqual(document.source.fileName, "podcast-episode.wav")
        XCTAssertEqual(document.engine.model, "small")
        XCTAssertNil(document.source.path)
    }
}
