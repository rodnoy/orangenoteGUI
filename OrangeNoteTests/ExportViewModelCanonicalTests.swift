//
//  ExportViewModelCanonicalTests.swift
//  OrangeNoteTests
//
//  Unit tests verifying that `.json` export produces Canonical JSON v1 output (D013).
//

import XCTest
@testable import OrangeNote

@MainActor
final class ExportViewModelCanonicalTests: XCTestCase {

    private func makeSampleResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: "Hello world."),
                TranscriptionSegment(id: UUID(), startTime: 2.0, endTime: 4.5, text: "This is a test.")
            ],
            fullText: "Hello world. This is a test.",
            language: "en",
            duration: 4.5
        )
    }

    func testJSONExport_producesCanonicalV1WithSchemaVersionOne() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()

        viewModel.generateExport(
            result: result,
            sourceURL: URL(fileURLWithPath: "/tmp/sample-audio.wav"),
            modelName: "base",
            engineID: "whisper-local"
        )

        XCTAssertNil(viewModel.errorMessage)
        let content = try XCTUnwrap(viewModel.exportedContent)
        let data = try XCTUnwrap(content.data(using: .utf8))

        let document = try CanonicalTranscriptionSerializer.decode(data)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.source.fileName, "sample-audio.wav")
        XCTAssertEqual(document.engine.id, "whisper-local")
        XCTAssertEqual(document.engine.model, "base")
        XCTAssertEqual(document.transcription.language, "en")
        XCTAssertEqual(document.transcription.durationSeconds, 4.5)
        XCTAssertEqual(document.transcription.fullText, "Hello world. This is a test.")
        XCTAssertEqual(document.transcription.segments.count, 2)
        XCTAssertEqual(document.transcription.segments[0].index, 0)
        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 0)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 2000)
        XCTAssertEqual(document.transcription.segments[0].text, "Hello world.")
        XCTAssertEqual(document.transcription.segments[1].startMilliseconds, 2000)
        XCTAssertEqual(document.transcription.segments[1].endMilliseconds, 4500)
    }

    func testJSONExport_containsRawSchemaVersionKey() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .json
        let result = makeSampleResult()

        viewModel.generateExport(result: result)

        let content = try XCTUnwrap(viewModel.exportedContent)
        XCTAssertTrue(content.contains("\"schemaVersion\""))
        XCTAssertTrue(content.contains("1"))
    }

    func testTxtExport_isUnaffectedByCanonicalChange() throws {
        let viewModel = ExportViewModel()
        viewModel.selectedFormat = .txt
        let result = makeSampleResult()

        viewModel.generateExport(result: result)

        XCTAssertNil(viewModel.errorMessage)
        let content = try XCTUnwrap(viewModel.exportedContent)
        XCTAssertFalse(content.contains("\"schemaVersion\""))
    }
}
