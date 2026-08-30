//
//  TranscriptionImportServiceTests.swift
//  OrangeNoteTests
//
//  Unit tests for version-aware JSON import in `TranscriptionImportService` (Task 2.3):
//  Canonical JSON v1 documents are decoded via `CanonicalTranscriptionSerializer`, unversioned
//  legacy documents continue to use the existing `TranscriptionResult` decoder, and unsupported
//  future `schemaVersion` values fail explicitly without any fallback attempt.
//

import XCTest
@testable import OrangeNote

final class TranscriptionImportServiceTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionImportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func writeJSON(_ data: Data, named name: String = "import.json") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeCanonicalDocument(schemaVersion: Int = 1) -> CanonicalTranscriptionDocument {
        CanonicalTranscriptionDocument(
            schemaVersion: schemaVersion,
            createdAt: CanonicalTranscriptionSerializer.formatCreatedAt(Date()),
            source: .init(fileName: "audio.mp3", fileSizeBytes: 1024, path: "/tmp/audio.mp3"),
            engine: .init(id: "whisper-local", model: "base"),
            transcription: .init(
                language: "en",
                durationSeconds: 4.5,
                fullText: "Hello world. This is a test.",
                segments: [
                    .init(index: 0, startMilliseconds: 0, endMilliseconds: 2000, text: "Hello world.", confidence: nil),
                    .init(index: 1, startMilliseconds: 2000, endMilliseconds: 4500, text: "This is a test.", confidence: nil)
                ]
            )
        )
    }

    // MARK: - Canonical v1 import

    func testImportFromFile_canonicalV1_decodesSuccessfully() throws {
        let document = makeCanonicalDocument(schemaVersion: 1)
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let url = try writeJSON(data)

        let result = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.duration, 4.5)
        XCTAssertEqual(result.fullText, "Hello world. This is a test.")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startTime, 0.0)
        XCTAssertEqual(result.segments[0].endTime, 2.0)
        XCTAssertEqual(result.segments[0].text, "Hello world.")
        XCTAssertEqual(result.segments[1].startTime, 2.0)
        XCTAssertEqual(result.segments[1].endTime, 4.5)
    }

    // MARK: - Unsupported future schema version

    func testImportFromFile_unsupportedFutureSchemaVersion_throwsExplicitError() throws {
        let document = makeCanonicalDocument(schemaVersion: 2)
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let url = try writeJSON(data)

        XCTAssertThrowsError(try TranscriptionImportService.importFromFile(url: url)) { error in
            guard let importError = error as? TranscriptionImportService.ImportError else {
                XCTFail("Expected ImportError, got \(error)")
                return
            }
            switch importError {
            case .unsupportedSchemaVersion(let version):
                XCTAssertEqual(version, 2)
            default:
                XCTFail("Expected .unsupportedSchemaVersion, got \(importError)")
            }
        }
    }

    func testImportFromFile_unsupportedSchemaVersion_doesNotFallBackToLegacyDecoding() throws {
        // Even if the payload otherwise superficially resembles a legacy TranscriptionResult
        // shape, an unsupported schemaVersion must fail rather than attempt legacy decoding.
        let json = """
        {
            "schemaVersion": 99,
            "segments": [],
            "fullText": "should not decode",
            "language": "en",
            "duration": 1.0
        }
        """
        let url = try writeJSON(Data(json.utf8))

        XCTAssertThrowsError(try TranscriptionImportService.importFromFile(url: url)) { error in
            guard let importError = error as? TranscriptionImportService.ImportError,
                  case .unsupportedSchemaVersion(let version) = importError else {
                XCTFail("Expected .unsupportedSchemaVersion, got \(error)")
                return
            }
            XCTAssertEqual(version, 99)
        }
    }

    // MARK: - Legacy (unversioned) import behavior preserved

    func testImportFromFile_legacyUnversionedJSON_stillDecodesViaExistingPath() throws {
        let legacyResult = TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 1.5, text: "Legacy segment.")
            ],
            fullText: "Legacy segment.",
            language: "en",
            duration: 1.5
        )
        let data = try JSONEncoder().encode(legacyResult)
        let url = try writeJSON(data)

        let result = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(result.fullText, "Legacy segment.")
        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertEqual(result.segments.count, 1)
    }
}
