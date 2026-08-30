//
//  CanonicalTranscriptionDocumentTests.swift
//  OrangeNoteTests
//
//  Unit tests for the Canonical Transcription Document v1 schema (Codable round-trip).
//

import XCTest
@testable import OrangeNote

final class CanonicalTranscriptionDocumentTests: XCTestCase {

    private func makeSampleDocument() -> CanonicalTranscriptionDocument {
        CanonicalTranscriptionDocument(
            createdAt: "2026-08-28T12:00:00Z",
            source: .init(
                fileName: "interview.mp3",
                fileSizeBytes: 1_048_576,
                path: "/Users/test/Audio/interview.mp3"
            ),
            engine: .init(id: "whisper-local", model: "base"),
            transcription: .init(
                language: "en",
                durationSeconds: 123.45,
                fullText: "Hello world. This is a test.",
                segments: [
                    .init(index: 0, startMilliseconds: 0, endMilliseconds: 2000, text: "Hello world.", confidence: 0.95),
                    .init(index: 1, startMilliseconds: 2000, endMilliseconds: 4500, text: "This is a test.", confidence: nil)
                ]
            )
        )
    }

    // MARK: - Default schema version

    func testInit_defaultSchemaVersion_isOne() {
        let document = makeSampleDocument()
        XCTAssertEqual(document.schemaVersion, 1)
    }

    // MARK: - Round-trip encode/decode

    func testEncodeDecode_roundTrip_preservesEquality() throws {
        let document = makeSampleDocument()

        let encoder = JSONEncoder()
        let data = try encoder.encode(document)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CanonicalTranscriptionDocument.self, from: data)

        XCTAssertEqual(decoded, document)
    }

    // MARK: - JSON shape / key names

    func testEncode_jsonKeys_matchApprovedCanonicalShape() throws {
        let document = makeSampleDocument()

        let encoder = JSONEncoder()
        let data = try encoder.encode(document)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let json = try XCTUnwrap(jsonObject)

        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["createdAt"] as? String, "2026-08-28T12:00:00Z")

        let source = try XCTUnwrap(json["source"] as? [String: Any])
        XCTAssertEqual(source["fileName"] as? String, "interview.mp3")
        XCTAssertEqual(source["fileSizeBytes"] as? Int64, 1_048_576)
        XCTAssertEqual(source["path"] as? String, "/Users/test/Audio/interview.mp3")

        let engine = try XCTUnwrap(json["engine"] as? [String: Any])
        XCTAssertEqual(engine["id"] as? String, "whisper-local")
        XCTAssertEqual(engine["model"] as? String, "base")

        let transcription = try XCTUnwrap(json["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["language"] as? String, "en")
        XCTAssertEqual(transcription["durationSeconds"] as? Double, 123.45)
        XCTAssertEqual(transcription["fullText"] as? String, "Hello world. This is a test.")

        let segments = try XCTUnwrap(transcription["segments"] as? [[String: Any]])
        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0]["index"] as? Int, 0)
        XCTAssertEqual(segments[0]["startMilliseconds"] as? Int, 0)
        XCTAssertEqual(segments[0]["endMilliseconds"] as? Int, 2000)
        XCTAssertEqual(segments[0]["text"] as? String, "Hello world.")
        XCTAssertEqual(segments[0]["confidence"] as? Double, 0.95)

        XCTAssertEqual(segments[1]["index"] as? Int, 1)
        XCTAssertNil(segments[1]["confidence"])
    }

    // MARK: - Decoding from a fixed JSON fixture string

    func testDecode_fixedJSONFixture_producesExpectedDocument() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": {
                "fileName": "interview.mp3",
                "fileSizeBytes": 1048576,
                "path": "/Users/test/Audio/interview.mp3"
            },
            "engine": {
                "id": "whisper-local",
                "model": "base"
            },
            "transcription": {
                "language": "en",
                "durationSeconds": 123.45,
                "fullText": "Hello world. This is a test.",
                "segments": [
                    {
                        "index": 0,
                        "startMilliseconds": 0,
                        "endMilliseconds": 2000,
                        "text": "Hello world.",
                        "confidence": 0.95
                    },
                    {
                        "index": 1,
                        "startMilliseconds": 2000,
                        "endMilliseconds": 4500,
                        "text": "This is a test.",
                        "confidence": null
                    }
                ]
            }
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CanonicalTranscriptionDocument.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, makeSampleDocument())
    }

    // MARK: - Optional source.path

    func testDecode_nilSourcePath_decodesSuccessfully() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2026-08-28T12:00:00Z",
            "source": {
                "fileName": "interview.mp3",
                "fileSizeBytes": 1048576,
                "path": null
            },
            "engine": {
                "id": "whisper-local",
                "model": "base"
            },
            "transcription": {
                "language": "en",
                "durationSeconds": 0,
                "fullText": "",
                "segments": []
            }
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CanonicalTranscriptionDocument.self, from: Data(json.utf8))

        XCTAssertNil(decoded.source.path)
        XCTAssertTrue(decoded.transcription.segments.isEmpty)
    }

    // MARK: - Equatable

    func testEquatable_differingSegmentText_notEqual() {
        let document = makeSampleDocument()
        var mutatedSegments = document.transcription.segments
        mutatedSegments[0] = .init(
            index: mutatedSegments[0].index,
            startMilliseconds: mutatedSegments[0].startMilliseconds,
            endMilliseconds: mutatedSegments[0].endMilliseconds,
            text: "Different text.",
            confidence: mutatedSegments[0].confidence
        )
        let mutatedDocument = CanonicalTranscriptionDocument(
            createdAt: document.createdAt,
            source: document.source,
            engine: document.engine,
            transcription: .init(
                language: document.transcription.language,
                durationSeconds: document.transcription.durationSeconds,
                fullText: document.transcription.fullText,
                segments: mutatedSegments
            )
        )

        XCTAssertNotEqual(document, mutatedDocument)
    }
}
