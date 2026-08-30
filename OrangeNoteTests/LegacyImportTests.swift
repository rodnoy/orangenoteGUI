//
//  LegacyImportTests.swift
//  OrangeNoteTests
//
//  Unit tests for unversioned legacy fallback decoding in `TranscriptionImportService` (Task 2.4):
//  when `schemaVersion` is absent, import first attempts the legacy Swift `TranscriptionResult`
//  Codable shape, then falls back to the legacy FFI exporter shape (`start_ms` / `end_ms` /
//  `confidence`), converting it into the domain `TranscriptionResult`.
//

import XCTest
@testable import OrangeNote

final class LegacyImportTests: XCTestCase {

    private func fixtureURL(named name: String) throws -> URL {
        guard let url = Bundle(for: LegacyImportTests.self).url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json not found in test bundle")
        }
        return url
    }

    // MARK: - Legacy Swift Codable shape

    func testImportFromFile_legacyCodableFixture_decodesSuccessfully() throws {
        let url = try fixtureURL(named: "legacy_codable")

        let result = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.duration, 7.25)
        XCTAssertEqual(result.fullText, "Hello from legacy Swift Codable format. This is the second segment.")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startTime, 0.0)
        XCTAssertEqual(result.segments[0].endTime, 3.5)
        XCTAssertEqual(result.segments[0].text, "Hello from legacy Swift Codable format.")
        XCTAssertEqual(result.segments[1].startTime, 3.5)
        XCTAssertEqual(result.segments[1].endTime, 7.25)
        XCTAssertEqual(result.segments[1].text, "This is the second segment.")
    }

    // MARK: - Legacy FFI exporter shape

    func testImportFromFile_legacyFFIFixture_decodesAndConvertsSuccessfully() throws {
        let url = try fixtureURL(named: "legacy_ffi")

        let result = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(result.language, "fr")
        // FFI timestamps are in milliseconds; expect conversion to seconds.
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startTime, 0.0)
        XCTAssertEqual(result.segments[0].endTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.segments[0].text, "Bonjour depuis le format exporteur FFI.")
        XCTAssertEqual(result.segments[1].startTime, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.segments[1].endTime, 8.9, accuracy: 0.0001)
        XCTAssertEqual(result.segments[1].text, "Ceci est le second segment.")
        XCTAssertEqual(result.fullText, "Bonjour depuis le format exporteur FFI. Ceci est le second segment.")
        XCTAssertEqual(result.duration, 8.9, accuracy: 0.0001)
    }

    // MARK: - Unsorted segments (Finding B6)

    /// Legacy FFI exports are not guaranteed to be sorted by time. `duration` must be derived
    /// from the maximum `endTime` across all segments, not `segments.last?.endTime` (which
    /// would silently under-report duration for an out-of-order fixture like this one).
    func testImportFromFile_legacyFFIFixtureWithUnsortedSegments_computesMaxEndTimeAsDuration() throws {
        let url = try fixtureURL(named: "legacy_ffi_unsorted")

        let result = try TranscriptionImportService.importFromFile(url: url)

        XCTAssertEqual(result.segments.count, 2)
        // The last segment in file order ends at 4.2s, but the first segment (out of order)
        // ends at 8.9s, which is the true maximum.
        XCTAssertEqual(result.segments.last?.endTime ?? -1, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.duration, 8.9, accuracy: 0.0001)
    }
}
