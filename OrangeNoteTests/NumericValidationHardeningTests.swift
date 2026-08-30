//
//  NumericValidationHardeningTests.swift
//  OrangeNoteTests
//
//  Unit tests for `CanonicalTranscriptionSerializer` numeric validation hardening (Finding B5):
//  non-finite (`NaN`/`Infinity`) and out-of-range (negative, inverted-duration) timestamps must
//  be rejected with typed errors rather than trapping during `Double` -> `Int` millisecond
//  conversion or being silently coerced.
//

import XCTest
@testable import OrangeNote

final class NumericValidationHardeningTests: XCTestCase {

    private func makeResult(segments: [TranscriptionSegment], duration: Double = 0) -> TranscriptionResult {
        TranscriptionResult(
            segments: segments,
            fullText: segments.map(\.text).joined(separator: " "),
            language: "en",
            duration: duration
        )
    }

    private let sourceURL = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.mp3")

    // MARK: - Non-finite segment timestamps

    func testMakeDocument_nanStartTime_throwsInvalidNumericValue() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: Double.nan, endTime: 1.0, text: "x")],
            duration: 1.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidNumericValue(field: "segments[0].startTime")
            )
        }
    }

    func testMakeDocument_infiniteEndTime_throwsInvalidNumericValue() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: Double.infinity, text: "x")],
            duration: 1.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidNumericValue(field: "segments[0].endTime")
            )
        }
    }

    func testMakeDocument_negativeInfiniteStartTime_throwsInvalidNumericValue() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: -Double.infinity, endTime: 1.0, text: "x")],
            duration: 1.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidNumericValue(field: "segments[0].startTime")
            )
        }
    }

    // MARK: - Non-finite duration

    func testMakeDocument_nanDuration_throwsInvalidNumericValue() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 1.0, text: "x")],
            duration: Double.nan
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .invalidNumericValue(field: "transcription.durationSeconds")
            )
        }
    }

    // MARK: - Negative (but finite) values

    func testMakeDocument_negativeStartTime_throwsOutOfRange() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: -1.0, endTime: 1.0, text: "x")],
            duration: 1.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .outOfRange(field: "segments[0].startTime", value: -1.0)
            )
        }
    }

    func testMakeDocument_negativeDuration_throwsOutOfRange() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 1.0, text: "x")],
            duration: -5.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .outOfRange(field: "transcription.durationSeconds", value: -5.0)
            )
        }
    }

    // MARK: - Inverted segment duration (chunk duration constraint)

    func testMakeDocument_endTimeBeforeStartTime_throwsOutOfRange() {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 5.0, endTime: 2.0, text: "x")],
            duration: 5.0
        )

        XCTAssertThrowsError(
            try CanonicalTranscriptionSerializer.makeDocument(
                from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalTranscriptionSerializerError,
                .outOfRange(field: "segments[0].duration", value: -3.0)
            )
        }
    }

    // MARK: - Valid boundary values still succeed

    func testMakeDocument_zeroLengthSegment_succeeds() throws {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 1.0, endTime: 1.0, text: "x")],
            duration: 1.0
        )

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
        )

        XCTAssertEqual(document.transcription.segments[0].startMilliseconds, 1000)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 1000)
    }

    func testMakeDocument_validFiniteValues_succeeds() throws {
        let result = makeResult(
            segments: [TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.5, text: "x")],
            duration: 2.5
        )

        let document = try CanonicalTranscriptionSerializer.makeDocument(
            from: result, sourceURL: sourceURL, modelName: "base", engineID: "whisper-local"
        )

        XCTAssertEqual(document.transcription.durationSeconds, 2.5)
        XCTAssertEqual(document.transcription.segments[0].endMilliseconds, 2500)
    }
}
