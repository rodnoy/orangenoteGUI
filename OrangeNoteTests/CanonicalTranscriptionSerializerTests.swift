//
//  CanonicalTranscriptionSerializerTests.swift
//  OrangeNoteTests
//
//  Unit tests for bidirectional mapping and JSON serialization between
//  `TranscriptionResult` and `CanonicalTranscriptionDocument` v1.
//

import XCTest
@testable import OrangeNote

final class CanonicalTranscriptionSerializerTests: XCTestCase {

    private func makeSampleResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: "Hello world."),
                TranscriptionSegment(id: UUID(), startTime: 2.0, endTime: 4.5, text: "This is a test."),
                TranscriptionSegment(id: UUID(), startTime: 4.5, endTime: 4.501, text: "Édge cäse — Юникод 日本語.")
            ],
            fullText: "Hello world. This is a test. Édge cäse — Юникод 日本語.",
            language: "en",
            duration: 4.501
        )
    }

    private func makeTemporaryAudioFile(sizeBytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        let data = Data(repeating: 0, count: sizeBytes)
        try data.write(to: url)
        return url
    }

    // MARK: - Domain -> Canonical mapping

    func testMakeDocument_mapsFieldsCorrectly() throws {
        let result = makeSampleResult()
        let sourceURL = try makeTemporaryAudioFile(sizeBytes: 1024)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.source.fileName, sourceURL.lastPathComponent)
        XCTAssertEqual(document.source.fileSizeBytes, 1024)
        XCTAssertEqual(document.source.path, sourceURL.path)
        XCTAssertEqual(document.engine.id, "whisper-local")
        XCTAssertEqual(document.engine.model, "base")
        XCTAssertEqual(document.transcription.language, "en")
        XCTAssertEqual(document.transcription.durationSeconds, result.duration)
        XCTAssertEqual(document.transcription.fullText, result.fullText)
        XCTAssertEqual(document.transcription.segments.count, 3)

        XCTAssertEqual(document.transcription.segments[0].index, 0)
        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 0)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 2000)
        XCTAssertEqual(document.transcription.segments[0].text, "Hello world.")

        XCTAssertEqual(document.transcription.segments[1].index, 1)
        XCTAssertEqual(document.transcription.segments[1].startMilliseconds, 2000)
        XCTAssertEqual(document.transcription.segments[1].endMilliseconds, 4500)

        XCTAssertEqual(document.transcription.segments[2].index, 2)
        XCTAssertEqual(document.transcription.segments[2].startMilliseconds, 4500)
        XCTAssertEqual(document.transcription.segments[2].endMilliseconds, 4501)
    }

    func testMakeDocument_missingSourceFile_defaultsFileSizeToZero() throws {
        let result = makeSampleResult()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).mp3")

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: missingURL,
            modelName: "base",
            engineID: "whisper-local"
        )

        XCTAssertEqual(document.source.fileSizeBytes, 0)
    }

    // MARK: - Canonical -> Domain mapping

    func testMakeResult_mapsFieldsCorrectly() {
        let document = CanonicalTranscriptionDocument(
            createdAt: "2026-08-28T12:00:00.000Z",
            source: .init(fileName: "audio.mp3", fileSizeBytes: 2048, path: "/tmp/audio.mp3"),
            engine: .init(id: "whisper-local", model: "base"),
            transcription: .init(
                language: "fr",
                durationSeconds: 10.25,
                fullText: "Bonjour le monde.",
                segments: [
                    .init(index: 0, startMilliseconds: 0, endMilliseconds: 1000, text: "Bonjour", confidence: 0.9),
                    .init(index: 1, startMilliseconds: 1000, endMilliseconds: 2500, text: "le monde.", confidence: nil)
                ]
            )
        )

        let result = CanonicalTranscriptionSerializer.makeResult(from: document)

        XCTAssertEqual(result.language, "fr")
        XCTAssertEqual(result.duration, 10.25)
        XCTAssertEqual(result.fullText, "Bonjour le monde.")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startTime, 0.0)
        XCTAssertEqual(result.segments[0].endTime, 1.0)
        XCTAssertEqual(result.segments[0].text, "Bonjour")
        XCTAssertEqual(result.segments[1].startTime, 1.0)
        XCTAssertEqual(result.segments[1].endTime, 2.5)
        XCTAssertEqual(result.segments[1].text, "le monde.")
    }

    // MARK: - createdAt formatting

    func testFormatAndParseCreatedAt_roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatted = CanonicalTranscriptionSerializer.formatCreatedAt(date)
        let parsed = try CanonicalTranscriptionSerializer.parseCreatedAt(formatted)

        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testParseCreatedAt_invalidFormat_throws() {
        XCTAssertThrowsError(try CanonicalTranscriptionSerializer.parseCreatedAt("not-a-date")) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidCreatedAtFormat("not-a-date")
            )
        }
    }

    // MARK: - JSON encode/decode

    func testEncode_producesSortedPrettyPrintedJSON() throws {
        let result = makeSampleResult()
        let sourceURL = try makeTemporaryAudioFile(sizeBytes: 512)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result,
            sourceURL: sourceURL,
            modelName: "base",
            engineID: "whisper-local"
        )

        let data = try CanonicalTranscriptionSerializer.encode(document)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Pretty-printed JSON contains newlines and indentation.
        XCTAssertTrue(jsonString.contains("\n"))
        // Sorted keys: "createdAt" precedes "engine" precedes "schemaVersion" precedes "source" precedes "transcription".
        let createdAtRange = try XCTUnwrap(jsonString.range(of: "\"createdAt\""))
        let engineRange = try XCTUnwrap(jsonString.range(of: "\"engine\""))
        let schemaVersionRange = try XCTUnwrap(jsonString.range(of: "\"schemaVersion\""))
        let sourceRange = try XCTUnwrap(jsonString.range(of: "\"source\""))
        let transcriptionRange = try XCTUnwrap(jsonString.range(of: "\"transcription\""))

        XCTAssertTrue(createdAtRange.lowerBound < engineRange.lowerBound)
        XCTAssertTrue(engineRange.lowerBound < schemaVersionRange.lowerBound)
        XCTAssertTrue(schemaVersionRange.lowerBound < sourceRange.lowerBound)
        XCTAssertTrue(sourceRange.lowerBound < transcriptionRange.lowerBound)
    }

    func testDecode_invalidCreatedAtFormat_throws() {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "28-08-2026",
            "source": { "fileName": "a.mp3", "fileSizeBytes": 0, "path": null },
            "engine": { "id": "whisper-local", "model": "base" },
            "transcription": { "language": "en", "durationSeconds": 0, "fullText": "", "segments": [] }
        }
        """

        XCTAssertThrowsError(try CanonicalTranscriptionSerializer.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidCreatedAtFormat("28-08-2026")
            )
        }
    }

    func testDecode_validISO8601CreatedAt_succeeds() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": { "fileName": "a.mp3", "fileSizeBytes": 0, "path": null },
            "engine": { "id": "whisper-local", "model": "base" },
            "transcription": { "language": "en", "durationSeconds": 0, "fullText": "", "segments": [] }
        }
        """

        let document = try CanonicalTranscriptionSerializer.decode(Data(json.utf8))
        XCTAssertEqual(document.createdAt, "2026-08-28T12:00:00Z")
    }

    // MARK: - Full round-trip fidelity: domain -> canonical -> JSON -> canonical -> domain

    func testFullRoundTrip_domainToCanonicalToJSONToCanonicalToDomain_preservesFidelity() throws {
        let originalResult = makeSampleResult()
        let sourceURL = try makeTemporaryAudioFile(sizeBytes: 4096)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: originalResult,
            sourceURL: sourceURL,
            modelName: "large-v3",
            engineID: "whisper-local"
        )

        let jsonData = try CanonicalTranscriptionSerializer.encode(document)
        let decodedDocument = try CanonicalTranscriptionSerializer.decode(jsonData)

        // Canonical document fidelity (excluding fresh segment UUIDs, which don't exist in canonical form).
        XCTAssertEqual(decodedDocument, document)

        let roundTrippedResult = CanonicalTranscriptionSerializer.makeResult(from: decodedDocument)

        XCTAssertEqual(roundTrippedResult.language, originalResult.language)
        XCTAssertEqual(roundTrippedResult.duration, originalResult.duration)
        XCTAssertEqual(roundTrippedResult.fullText, originalResult.fullText)
        XCTAssertEqual(roundTrippedResult.segments.count, originalResult.segments.count)

        for (original, roundTripped) in zip(originalResult.segments, roundTrippedResult.segments) {
            XCTAssertEqual(roundTripped.startTime, original.startTime, accuracy: 0.001)
            XCTAssertEqual(roundTripped.endTime, original.endTime, accuracy: 0.001)
            XCTAssertEqual(roundTripped.text, original.text)
        }
    }
}
