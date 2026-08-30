//
//  DropItemResolverRemediationTests.swift
//  OrangeNoteTests
//
//  Unit tests for DropItemResolver remediation and asynchronous provider loading.
//

import XCTest
import UniformTypeIdentifiers
@testable import OrangeNote

final class DropItemResolverRemediationTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropItemResolverRemediationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    // MARK: - Cardinality pre-check (before async loading)

    func testExtractAndResolve_zeroProviders_rejectsImmediatelyWithoutLoading() {
        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: [], isTranscribing: false) { resolution in
            XCTAssertEqual(resolution, .rejectedMultipleItems(count: 0))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testExtractAndResolve_multipleProviders_resolvesToBatch() throws {
        let first = try makeFile(named: "a.mp3")
        let second = try makeFile(named: "b.wav")
        let providers = [NSItemProvider(contentsOf: first)!, NSItemProvider(contentsOf: second)!]

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            guard case .batch(let ingestion) = resolution else {
                return XCTFail("Expected .batch, got \(resolution)")
            }
            XCTAssertEqual(ingestion.count, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_whileTranscribing_rejectsBeforeAnyAsyncLoad() throws {
        let url = try makeFile(named: "song.mp3")
        let providers = [NSItemProvider(contentsOf: url)!]

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: true) { resolution in
            XCTAssertEqual(resolution, .rejectedTranscribing)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Single provider success path

    func testExtractAndResolve_singleValidAudioFile_isAccepted() throws {
        let url = try makeFile(named: "song.mp3")
        let providers = [NSItemProvider(contentsOf: url)!]

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            if case .accepted(let resolvedURL) = resolution {
                XCTAssertEqual(resolvedURL.lastPathComponent, url.lastPathComponent)
            } else {
                XCTFail("Expected .accepted, got \(resolution)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testExtractAndResolve_singleNonAudioFile_isInvalidFile() throws {
        let url = try makeFile(named: "notes.txt")
        let providers = [NSItemProvider(contentsOf: url)!]

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            guard case .invalidFile(let error) = resolution else {
                return XCTFail("Expected .invalidFile, got \(resolution)")
            }
            XCTAssertEqual(error, .unsupportedFormat("txt"))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - UTType.fileURL fallback

    func testExtractAndResolve_providerWithOnlyFileURLTypeIdentifier_usesFallback() throws {
        let url = try makeFile(named: "song.wav")
        let data = url.dataRepresentation
        let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.fileURL.identifier)

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: [provider], isTranscribing: false) { resolution in
            if case .accepted(let resolvedURL) = resolution {
                XCTAssertEqual(resolvedURL.lastPathComponent, url.lastPathComponent)
            } else {
                XCTFail("Expected .accepted via fallback, got \(resolution)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Dispatch normalization (Task 1.13 / MEDIUM D)

    func testExtractAndResolve_whileTranscribing_completionIsDispatchedAsynchronously() throws {
        let url = try makeFile(named: "song.mp3")
        let providers = [NSItemProvider(contentsOf: url)!]

        var stillPending = true
        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: true) { resolution in
            stillPending = false
            XCTAssertEqual(resolution, .rejectedTranscribing)
            expectation.fulfill()
        }

        XCTAssertTrue(stillPending, "rejectedTranscribing completion must not fire synchronously in-line")

        wait(for: [expectation], timeout: 1.0)
    }

    func testExtractAndResolve_multipleProviders_completionIsDispatchedAsynchronously() throws {
        let first = try makeFile(named: "a.mp3")
        let second = try makeFile(named: "b.wav")
        let providers = [NSItemProvider(contentsOf: first)!, NSItemProvider(contentsOf: second)!]

        var stillPending = true
        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: false) { resolution in
            stillPending = false
            guard case .batch(let ingestion) = resolution else {
                return XCTFail("Expected .batch, got \(resolution)")
            }
            XCTAssertEqual(ingestion.count, 2)
            expectation.fulfill()
        }

        XCTAssertTrue(stillPending, "batch completion must not fire synchronously in-line")

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Typed extraction failure

    func testExtractAndResolve_providerWithUnsupportedType_reportsExtractionFailed() {
        let provider = NSItemProvider(item: NSString("hello"), typeIdentifier: UTType.plainText.identifier)

        let expectation = expectation(description: "resolution")

        DropItemResolver.extractAndResolve(from: [provider], isTranscribing: false) { resolution in
            XCTAssertEqual(resolution, .extractionFailed)
            XCTAssertNotNil(resolution.localizedMessage)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
