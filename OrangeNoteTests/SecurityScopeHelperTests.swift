//
//  SecurityScopeHelperTests.swift
//  OrangeNoteTests
//
//  Unit tests for SecurityScopeHelper, SecurityScopeToken, bookmark round-trips,
//  and sandbox entitlement configuration (Task 3.11 / D023).
//

import XCTest
@testable import OrangeNote

final class SecurityScopeHelperTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SecurityScopeHelperTests_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Token Acquisition & Lifecycle Tests

    func testAcquireScope_singleURL_handlesStandardURLSafely() {
        let fileURL = tempDirectory.appendingPathComponent("test.mp3")
        let token = SecurityScopeHelper.acquireScope(for: fileURL)

        // For non-security-scoped URLs (in unit test runs), startAccessingSecurityScopedResource
        // returns false, so token starts with 0 active URLs and does not attempt stopAccessing.
        XCTAssertEqual(token.activeURLCount, 0)
        XCTAssertFalse(token.hasActiveScope)

        token.stopAccessing()
        XCTAssertFalse(token.hasActiveScope)
        XCTAssertEqual(token.activeURLCount, 0)
    }

    func testAcquireScope_multipleURLs_handlesStandardURLsSafely() {
        let file1 = tempDirectory.appendingPathComponent("1.mp3")
        let file2 = tempDirectory.appendingPathComponent("2.wav")
        let token = SecurityScopeHelper.acquireScope(for: [file1, file2])

        XCTAssertFalse(token.hasActiveScope)
        token.stopAccessing()
        XCTAssertFalse(token.hasActiveScope)
    }

    func testToken_stopAccessing_isIdempotent() {
        let token = SecurityScopeToken(accessedURLs: [])
        token.stopAccessing()
        token.stopAccessing()
        token.stopAccessing()
        XCTAssertFalse(token.hasActiveScope)
        XCTAssertEqual(token.activeURLCount, 0)
    }

    // MARK: - Synchronous Block Scoping Tests

    func testWithSecurityScope_synchronousClosure_returnsValue() {
        let fileURL = tempDirectory.appendingPathComponent("test.wav")
        let result = SecurityScopeHelper.withSecurityScope(for: fileURL) {
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testWithSecurityScope_synchronousClosure_propagatesErrors() {
        struct TestError: Error, Equatable {}
        let fileURL = tempDirectory.appendingPathComponent("test.wav")

        XCTAssertThrowsError(
            try SecurityScopeHelper.withSecurityScope(for: fileURL) {
                throw TestError()
            }
        ) { error in
            XCTAssertTrue(error is TestError)
        }
    }

    func testWithSecurityScope_multipleURLs_synchronousClosure_returnsValue() {
        let file1 = tempDirectory.appendingPathComponent("1.wav")
        let file2 = tempDirectory.appendingPathComponent("2.wav")
        let result = SecurityScopeHelper.withSecurityScope(for: [file1, file2]) {
            return "success"
        }
        XCTAssertEqual(result, "success")
    }

    // MARK: - Asynchronous Block Scoping Tests

    func testWithSecurityScope_asyncClosure_returnsValue() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test.wav")
        let result = try await SecurityScopeHelper.withSecurityScope(for: fileURL) {
            try await Task.sleep(nanoseconds: 1_000_000)
            return "async_value"
        }
        XCTAssertEqual(result, "async_value")
    }

    func testWithSecurityScope_asyncClosure_propagatesErrors() async {
        struct AsyncTestError: Error, Equatable {}
        let fileURL = tempDirectory.appendingPathComponent("test.wav")

        do {
            _ = try await SecurityScopeHelper.withSecurityScope(for: fileURL) {
                try await Task.sleep(nanoseconds: 1_000_000)
                throw AsyncTestError()
            }
            XCTFail("Expected AsyncTestError was not thrown")
        } catch {
            XCTAssertTrue(error is AsyncTestError)
        }
    }

    func testWithSecurityScope_multipleURLs_asyncClosure_returnsValue() async throws {
        let file1 = tempDirectory.appendingPathComponent("1.wav")
        let file2 = tempDirectory.appendingPathComponent("2.wav")
        let result = try await SecurityScopeHelper.withSecurityScope(for: [file1, file2]) {
            return ["a", "b"]
        }
        XCTAssertEqual(result, ["a", "b"])
    }

    // MARK: - Bookmark Management Tests

    func testBookmarkCreateAndResolve_roundTrip() throws {
        let testFile = tempDirectory.appendingPathComponent("sample.mp3")
        try "audio-data".write(to: testFile, atomically: true, encoding: .utf8)

        let bookmarkData = try SecurityScopeHelper.createBookmark(for: testFile)
        XCTAssertFalse(bookmarkData.isEmpty)

        let (resolvedURL, isStale) = try SecurityScopeHelper.resolveBookmark(data: bookmarkData)
        XCTAssertEqual(resolvedURL.standardizedFileURL.path, testFile.standardizedFileURL.path)
        XCTAssertFalse(isStale)
    }

    func testBookmarkResolve_invalidData_throwsError() {
        let garbageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertThrowsError(try SecurityScopeHelper.resolveBookmark(data: garbageData)) { error in
            guard case SecurityScopeBookmarkError.resolutionFailed = error else {
                XCTFail("Expected SecurityScopeBookmarkError.resolutionFailed but got \(error)")
                return
            }
        }
    }

    // MARK: - BatchFileCollector Integration Tests

    func testBatchFileCollector_collectTopLevel_withSecurityScope() throws {
        let audio1 = tempDirectory.appendingPathComponent("a.mp3")
        let audio2 = tempDirectory.appendingPathComponent("b.wav")
        let textFile = tempDirectory.appendingPathComponent("c.txt")

        try "mp3".write(to: audio1, atomically: true, encoding: .utf8)
        try "wav".write(to: audio2, atomically: true, encoding: .utf8)
        try "txt".write(to: textFile, atomically: true, encoding: .utf8)

        let items = BatchFileCollector.collectTopLevel(fromFolder: tempDirectory)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.sourceURL.lastPathComponent), ["a.mp3", "b.wav"])
    }

    // MARK: - Entitlement Configuration Verification

    func testEntitlementsFile_containsUserSelectedReadWrite() throws {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // OrangeNoteTests
            .deletingLastPathComponent() // repo root
        let entitlementsURL = repoRoot.appendingPathComponent("OrangeNote/OrangeNote.entitlements")

        let data = try Data(contentsOf: entitlementsURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]

        let dict = try XCTUnwrap(propertyList)
        XCTAssertEqual(dict["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(dict["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(dict["com.apple.security.network.client"] as? Bool, true)
        XCTAssertNil(dict["com.apple.security.files.user-selected.read-only"], "Read-only entitlement must not be present alongside read-write")
    }
}
