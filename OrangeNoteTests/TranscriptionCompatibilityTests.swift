//
//  TranscriptionCompatibilityTests.swift
//  OrangeNoteTests
//
//  Comprehensive cross-version compatibility suite for Task 2.6 (Chunk G closure):
//  validates Canonical v1 encoding/decoding, legacy import fallback, edge cases (empty
//  segments, Unicode, very long text), boundary timestamp values, and invalid JSON
//  handling. This suite intentionally complements (not duplicates) the existing coverage in
//  CanonicalTranscriptionDocumentTests, CanonicalTranscriptionSerializerTests,
//  TranscriptionImportServiceTests, and LegacyImportTests.
//

import XCTest
@testable import OrangeNote

final class TranscriptionCompatibilityTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func writeJSON(_ data: Data, named name: String = "compat.json") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - Full domain roundtrip via import service (end-to-end, not just serializer-level)

    func testFullRoundTrip_viaImportService_preservesFidelity() throws {
        let originalResult = TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 1.2, text: "First segment."),
                TranscriptionSegment(id: UUID(), startTime: 1.2, endTime: 3.75, text: "Second segment.")
            ],
            fullText: "First segment. Second segment.",
            language: "en",
            duration: 3.75
        )
        let sourceURL = tempDirectory.appendingPathComponent("source.mp3")
        try Data(repeating: 0, count: 128).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: originalResult,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let url = try writeJSON(data)

        let importedResult = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(importedResult.language, originalResult.language)
        XCTAssertEqual(importedResult.duration, originalResult.duration)
        XCTAssertEqual(importedResult.fullText, originalResult.fullText)
        XCTAssertEqual(importedResult.segments.count, originalResult.segments.count)
        for (original, imported) in zip(originalResult.segments, importedResult.segments) {
            XCTAssertEqual(imported.startTime, original.startTime, accuracy: 0.001)
            XCTAssertEqual(imported.endTime, original.endTime, accuracy: 0.001)
            XCTAssertEqual(imported.text, original.text)
        }
    }

    // MARK: - Missing / optional metadata handling

    func testMakeDocument_nilSourcePath_whenSourceFileHasNoAccessiblePath() throws {
        // Simulate a URL that cannot be resolved to a real file (nonexistent), which should
        // still populate `path` from the URL itself, but `fileSizeBytes` defaults to 0.
        let result = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0, endTime: 1, text: "x")],
            fullText: "x",
            language: "en",
            duration: 1
        )
        let missingURL = tempDirectory.appendingPathComponent("missing.mp3")

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: missingURL,
            modelName: "base",
            engineID: "whisper-local"
        )

        XCTAssertEqual(document.source.fileSizeBytes, 0)
    }

    func testDecode_nilConfidenceOnAllSegments_decodesSuccessfully() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": { "fileName": "a.mp3", "fileSizeBytes": 10, "path": null },
            "engine": { "id": "whisper-local", "model": "base" },
            "transcription": {
                "language": "en",
                "durationSeconds": 1.0,
                "fullText": "Hi.",
                "segments": [
                    { "index": 0, "startMilliseconds": 0, "endMilliseconds": 1000, "text": "Hi.", "confidence": null }
                ]
            }
        }
        """
        let document = try CanonicalTranscriptionSerializer.decode(Data(json.utf8))
        XCTAssertNil(document.source.path)
        XCTAssertNil(document.transcription.segments[0].confidence)

        let result = CanonicalTranscriptionSerializer.makeResult(from: document)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].text, "Hi.")
    }

    // MARK: - Invalid JSON syntax handling

    func testImportFromFile_malformedJSONSyntax_throwsCleanlyWithoutCrashing() throws {
        let malformed = "{ this is not valid JSON at all !! "
        let url = try writeJSON(Data(malformed.utf8))

        XCTAssertThrowsError(try TranscriptionImportService.importFromFile(url: url)) { error in
            guard let importError = error as? TranscriptionImportService.ImportError else {
                XCTFail("Expected ImportError, got \(error)")
                return
            }
            switch importError {
            case .parseError:
                break
            default:
                XCTFail("Expected .parseError, got \(importError)")
            }
        }
    }

    func testImportFromFile_emptyFileContents_throwsCleanlyWithoutCrashing() throws {
        let url = try writeJSON(Data())

        XCTAssertThrowsError(try TranscriptionImportService.importFromFile(url: url))
    }

    func testDecode_truncatedCanonicalJSON_throwsDecodingError() {
        let truncated = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": { "fileName": "a.mp3",
        """
        XCTAssertThrowsError(try CanonicalTranscriptionSerializer.decode(Data(truncated.utf8)))
    }

    // MARK: - Unversioned vs versioned document import behavior

    func testImportFromFile_schemaVersionAbsent_triggersLegacyPath() throws {
        let legacyResult = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0, endTime: 2, text: "Legacy path.")],
            fullText: "Legacy path.",
            language: "en",
            duration: 2
        )
        let data = try JSONEncoder().encode(legacyResult)
        let url = try writeJSON(data)

        let result = try TranscriptionImportService.importFromFile(url: url)
        XCTAssertEqual(result.fullText, "Legacy path.")
    }

    func testImportFromFile_schemaVersionOne_triggersCanonicalPath() throws {
        let document = CanonicalTranscriptionDocument(
            schemaVersion: 1,
            createdAt: CanonicalTranscriptionSerializer.formatCreatedAt(Date()),
            source: .init(fileName: "audio.mp3", fileSizeBytes: 100, path: "/tmp/audio.mp3"),
            engine: .init(id: "whisper-local", model: "base"),
            transcription: .init(
                language: "en",
                durationSeconds: 2.0,
                fullText: "Canonical path.",
                segments: [.init(index: 0, startMilliseconds: 0, endMilliseconds: 2000, text: "Canonical path.", confidence: nil)]
            )
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let url = try writeJSON(data)

        let result = try TranscriptionImportService.importFromFile(url: url)
        XCTAssertEqual(result.fullText, "Canonical path.")
    }

    func testImportFromFile_schemaVersionGreaterThanOne_throwsAndNeverFallsBack() throws {
        // Payload superficially resembles a valid canonical document but with an unsupported
        // future schema version; it must fail explicitly, never attempting legacy fallback.
        let document = CanonicalTranscriptionDocument(
            schemaVersion: 2,
            createdAt: CanonicalTranscriptionSerializer.formatCreatedAt(Date()),
            source: .init(fileName: "audio.mp3", fileSizeBytes: 100, path: "/tmp/audio.mp3"),
            engine: .init(id: "whisper-local", model: "base"),
            transcription: .init(
                language: "en",
                durationSeconds: 2.0,
                fullText: "Future schema.",
                segments: []
            )
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let url = try writeJSON(data)

        XCTAssertThrowsError(try TranscriptionImportService.importFromFile(url: url)) { error in
            guard let importError = error as? TranscriptionImportService.ImportError,
                  case .unsupportedSchemaVersion(let version) = importError else {
                XCTFail("Expected .unsupportedSchemaVersion, got \(error)")
                return
            }
            XCTAssertEqual(version, 2)
        }
    }

    // MARK: - Edge cases: empty segments array

    func testMakeDocument_emptySegmentsArray_roundTripsSuccessfully() throws {
        let result = TranscriptionResult(segments: [], fullText: "", language: "en", duration: 0)
        let sourceURL = tempDirectory.appendingPathComponent("empty.mp3")
        try Data(repeating: 0, count: 8).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        XCTAssertTrue(document.transcription.segments.isEmpty)

        let data = try CanonicalTranscriptionSerializer.encode(document)
        let decoded = try CanonicalTranscriptionSerializer.decode(data)
        XCTAssertTrue(decoded.transcription.segments.isEmpty)

        let roundTripped = CanonicalTranscriptionSerializer.makeResult(from: decoded)
        XCTAssertTrue(roundTripped.segments.isEmpty)
        XCTAssertEqual(roundTripped.fullText, "")
    }

    // MARK: - Edge cases: Unicode text

    func testMakeDocument_unicodeTextInSegmentsAndFullText_roundTripsSuccessfully() throws {
        let unicodeText = "日本語のテスト — Тест на русском — émojis: 🎙️🌍✨ — العربية"
        let result = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0, endTime: 1, text: unicodeText)],
            fullText: unicodeText,
            language: "multi",
            duration: 1
        )
        let sourceURL = tempDirectory.appendingPathComponent("unicode.mp3")
        try Data(repeating: 0, count: 8).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let decoded = try CanonicalTranscriptionSerializer.decode(data)
        let roundTripped = CanonicalTranscriptionSerializer.makeResult(from: decoded)

        XCTAssertEqual(roundTripped.fullText, unicodeText)
        XCTAssertEqual(roundTripped.segments[0].text, unicodeText)
    }

    // MARK: - Edge cases: very long text strings

    func testMakeDocument_veryLongText_roundTripsSuccessfully() throws {
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 5_000) // ~145,000 chars
        let result = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0, endTime: 1, text: longText)],
            fullText: longText,
            language: "en",
            duration: 1
        )
        let sourceURL = tempDirectory.appendingPathComponent("long.mp3")
        try Data(repeating: 0, count: 8).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        let data = try CanonicalTranscriptionSerializer.encode(document)
        let decoded = try CanonicalTranscriptionSerializer.decode(data)
        let roundTripped = CanonicalTranscriptionSerializer.makeResult(from: decoded)

        XCTAssertEqual(roundTripped.fullText.count, longText.count)
        XCTAssertEqual(roundTripped.fullText, longText)
    }

    // MARK: - Boundary timestamp values

    func testMakeDocument_zeroMillisecondTimestamps_roundTripsSuccessfully() throws {
        let result = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 0.0, text: "Zero-length segment.")],
            fullText: "Zero-length segment.",
            language: "en",
            duration: 0.0
        )
        let sourceURL = tempDirectory.appendingPathComponent("zero.mp3")
        try Data(repeating: 0, count: 8).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 0)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 0)

        let data = try CanonicalTranscriptionSerializer.encode(document)
        let decoded = try CanonicalTranscriptionSerializer.decode(data)
        let roundTripped = CanonicalTranscriptionSerializer.makeResult(from: decoded)
        XCTAssertEqual(roundTripped.segments[0].startTime, 0.0)
        XCTAssertEqual(roundTripped.segments[0].endTime, 0.0)
    }

    func testMakeDocument_veryLargeMillisecondTimestamps_roundTripsSuccessfully() throws {
        // Simulate an extremely long recording (~27.7 hours) to exercise large millisecond values.
        let largeStart = 99_999_000.0 / 1000.0
        let largeEnd = 100_000_000.0 / 1000.0
        let result = TranscriptionResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: largeStart, endTime: largeEnd, text: "Very late segment.")],
            fullText: "Very late segment.",
            language: "en",
            duration: largeEnd
        )
        let sourceURL = tempDirectory.appendingPathComponent("large.mp3")
        try Data(repeating: 0, count: 8).write(to: sourceURL)

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )
        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 99_999_000)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 100_000_000)

        let data = try CanonicalTranscriptionSerializer.encode(document)
        let decoded = try CanonicalTranscriptionSerializer.decode(data)
        let roundTripped = CanonicalTranscriptionSerializer.makeResult(from: decoded)
        XCTAssertEqual(roundTripped.segments[0].startTime, largeStart, accuracy: 0.001)
        XCTAssertEqual(roundTripped.segments[0].endTime, largeEnd, accuracy: 0.001)
    }

    func testDecode_boundaryMillisecondValues_fromFixedJSON_decodesSuccessfully() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": { "fileName": "a.mp3", "fileSizeBytes": 0, "path": null },
            "engine": { "id": "whisper-local", "model": "base" },
            "transcription": {
                "language": "en",
                "durationSeconds": 100000.0,
                "fullText": "Boundary segments.",
                "segments": [
                    { "index": 0, "startMilliseconds": 0, "endMilliseconds": 0, "text": "instant", "confidence": null },
                    { "index": 1, "startMilliseconds": 0, "endMilliseconds": 100000000, "text": "long span", "confidence": null }
                ]
            }
        }
        """
        let document = try CanonicalTranscriptionSerializer.decode(Data(json.utf8))
        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 0)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 0)
        XCTAssertEqual(document.transcription.segments[1].endMilliseconds, 100_000_000)
    }
}
