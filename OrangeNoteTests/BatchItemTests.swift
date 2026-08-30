//
//  BatchItemTests.swift
//  OrangeNoteTests
//
//  Unit tests for the BatchItem model and its exact status lifecycle (Task 3.2).
//

import XCTest
@testable import OrangeNote

final class BatchItemTests: XCTestCase {

    private func makeURL(_ name: String = "audio.mp3") -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    // MARK: - Default initialization

    func testDefaultInitialization() {
        let item = BatchItem(sourceURL: makeURL())

        XCTAssertEqual(item.status, .queued)
        XCTAssertEqual(item.progress, 0)
        XCTAssertNil(item.outputURL)
        XCTAssertNil(item.errorMessage)
        XCTAssertNil(item.result)
        XCTAssertNotNil(item.id)
    }

    func testDefaultInitializationGeneratesUniqueIDs() {
        let item1 = BatchItem(sourceURL: makeURL())
        let item2 = BatchItem(sourceURL: makeURL())

        XCTAssertNotEqual(item1.id, item2.id)
    }

    // MARK: - Status transitions

    func testFullSuccessLifecycleTransitions() {
        var item = BatchItem(sourceURL: makeURL())

        XCTAssertEqual(item.status, .queued)

        item.status = .transcribing
        XCTAssertEqual(item.status, .transcribing)

        item.status = .saving
        XCTAssertEqual(item.status, .saving)

        item.status = .succeeded
        XCTAssertEqual(item.status, .succeeded)
    }

    // MARK: - Failure path

    func testFailurePathSetsErrorMessage() {
        var item = BatchItem(sourceURL: makeURL())
        item.status = .transcribing
        item.status = .failed
        item.errorMessage = "Transcription engine crashed"

        XCTAssertEqual(item.status, .failed)
        XCTAssertEqual(item.errorMessage, "Transcription engine crashed")
    }

    // MARK: - Skipped and cancelled

    func testSkippedStatus() {
        var item = BatchItem(sourceURL: makeURL())
        item.status = .skipped

        XCTAssertEqual(item.status, .skipped)
        XCTAssertNotEqual(item.status, .cancelled)
    }

    func testCancelledStatus() {
        var item = BatchItem(sourceURL: makeURL())
        item.status = .transcribing
        item.status = .cancelled

        XCTAssertEqual(item.status, .cancelled)
        XCTAssertNotEqual(item.status, .skipped)
    }

    // MARK: - Equatable conformance

    func testEquatableSameIDAndFieldsAreEqual() {
        let id = UUID()
        let url = makeURL()
        let item1 = BatchItem(id: id, sourceURL: url, status: .queued, progress: 0)
        let item2 = BatchItem(id: id, sourceURL: url, status: .queued, progress: 0)

        XCTAssertEqual(item1, item2)
    }

    func testEquatableDifferingIDsAreUnequal() {
        let url = makeURL()
        let item1 = BatchItem(id: UUID(), sourceURL: url, status: .queued, progress: 0)
        let item2 = BatchItem(id: UUID(), sourceURL: url, status: .queued, progress: 0)

        XCTAssertNotEqual(item1, item2)
    }

    // MARK: - Property mutation

    func testProgressUpdatesIndependentlyOfStatus() {
        var item = BatchItem(sourceURL: makeURL())
        item.status = .transcribing

        item.progress = 0.25
        XCTAssertEqual(item.status, .transcribing)
        XCTAssertEqual(item.progress, 0.25)

        item.progress = 0.75
        XCTAssertEqual(item.status, .transcribing)
        XCTAssertEqual(item.progress, 0.75)
    }
}
