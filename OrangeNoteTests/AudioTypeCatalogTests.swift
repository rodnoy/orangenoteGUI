//
//  AudioTypeCatalogTests.swift
//  OrangeNoteTests
//
//  Unit tests for the centralized audio type catalog.
//

import XCTest
import UniformTypeIdentifiers
@testable import OrangeNote

final class AudioTypeCatalogTests: XCTestCase {

    func testAllowedExtensionsContainsAllPipelineFormats() {
        let expected: Set<String> = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"]
        XCTAssertEqual(AudioTypeCatalog.allowedExtensions, expected)
    }

    func testAllowedExtensionsExcludesUnverifiedFormats() {
        XCTAssertFalse(AudioTypeCatalog.allowedExtensions.contains("aiff"))
        XCTAssertFalse(AudioTypeCatalog.allowedExtensions.contains("txt"))
    }

    func testAllowedUTTypesCountMatchesExtensions() {
        XCTAssertEqual(AudioTypeCatalog.allowedUTTypes.count, AudioTypeCatalog.allowedExtensions.count)
        for type in AudioTypeCatalog.allowedUTTypes {
            XCTAssertFalse(type.identifier.isEmpty)
        }
    }

    func testIsSupportedForAllPipelineExtensions() {
        for ext in ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"] {
            let url = URL(fileURLWithPath: "/tmp/sample.\(ext)")
            XCTAssertTrue(AudioTypeCatalog.isSupported(url: url), "Expected \(ext) to be supported")
        }
    }

    func testIsSupportedIsCaseInsensitive() {
        XCTAssertTrue(AudioTypeCatalog.isSupported(url: URL(fileURLWithPath: "/tmp/sample.MP3")))
        XCTAssertTrue(AudioTypeCatalog.isSupported(url: URL(fileURLWithPath: "/tmp/sample.FlAc")))
    }

    func testIsSupportedFalseForUnsupportedOrMissingExtensions() {
        XCTAssertFalse(AudioTypeCatalog.isSupported(url: URL(fileURLWithPath: "/tmp/sample.txt")))
        XCTAssertFalse(AudioTypeCatalog.isSupported(url: URL(fileURLWithPath: "/tmp/sample.aiff")))
        XCTAssertFalse(AudioTypeCatalog.isSupported(url: URL(fileURLWithPath: "/tmp/sample")))
    }
}
