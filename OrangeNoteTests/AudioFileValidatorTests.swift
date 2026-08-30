//
//  AudioFileValidatorTests.swift
//  OrangeNoteTests
//
//  Unit tests for the centralized single-file audio validator.
//

import XCTest
@testable import OrangeNote

final class AudioFileValidatorTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileValidatorTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Valid extensions

    func testValidExtensions_allSupportedFormats_succeed() throws {
        let extensions = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"]
        for ext in extensions {
            let url = try makeFile(named: "sample.\(ext)")
            let result = AudioFileValidator.validate(url)
            switch result {
            case .success(let validatedURL):
                XCTAssertEqual(validatedURL, url)
            case .failure(let error):
                XCTFail("Expected success for extension \(ext), got error: \(error)")
            }
        }
    }

    func testValidExtensions_uppercaseVariant_succeeds() throws {
        let url = try makeFile(named: "sample.MP3")
        let result = AudioFileValidator.validate(url)
        switch result {
        case .success(let validatedURL):
            XCTAssertEqual(validatedURL, url)
        case .failure(let error):
            XCTFail("Expected success for uppercase extension, got error: \(error)")
        }
    }

    func testValidExtensions_mixedCaseVariant_succeeds() throws {
        let url = try makeFile(named: "sample.FlAc")
        let result = AudioFileValidator.validate(url)
        switch result {
        case .success(let validatedURL):
            XCTAssertEqual(validatedURL, url)
        case .failure(let error):
            XCTFail("Expected success for mixed-case extension, got error: \(error)")
        }
    }

    // MARK: - Missing files

    func testMissingFile_returnsFileNotFound() {
        let url = tempDirectory.appendingPathComponent("does-not-exist.mp3")
        let result = AudioFileValidator.validate(url)
        switch result {
        case .success:
            XCTFail("Expected failure for missing file")
        case .failure(let error):
            XCTAssertEqual(error, .fileNotFound(url.path))
        }
    }

    // MARK: - Directory paths

    func testDirectoryPath_returnsIsDirectory() {
        let result = AudioFileValidator.validate(tempDirectory)
        switch result {
        case .success:
            XCTFail("Expected failure for directory path")
        case .failure(let error):
            XCTAssertEqual(error, .isDirectory(tempDirectory.path))
        }
    }

    // MARK: - Unsupported extensions

    func testUnsupportedExtension_returnsUnsupportedFormat() throws {
        let url = try makeFile(named: "sample.txt")
        let result = AudioFileValidator.validate(url)
        switch result {
        case .success:
            XCTFail("Expected failure for unsupported extension")
        case .failure(let error):
            XCTAssertEqual(error, .unsupportedFormat("txt"))
        }
    }

    func testUnsupportedExtension_invented_aiff_isRejected() throws {
        // `aiff` is not a verified format supported by the Rust audio pipeline
        // (orangenote-core/src/infrastructure/audio/processor.rs); ensure it is rejected.
        let url = try makeFile(named: "sample.aiff")
        let result = AudioFileValidator.validate(url)
        switch result {
        case .success:
            XCTFail("Expected failure for unverified aiff extension")
        case .failure(let error):
            XCTAssertEqual(error, .unsupportedFormat("aiff"))
        }
    }

    // MARK: - Error descriptions

    func testErrorDescriptions_areLocalizedAndNonEmpty() throws {
        let url = try makeFile(named: "sample.txt")
        let result = AudioFileValidator.validate(url)
        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }
}
