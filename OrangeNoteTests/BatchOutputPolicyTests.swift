//
//  BatchOutputPolicyTests.swift
//  OrangeNoteTests
//
//  Unit tests for BatchOutputPolicy, directory validation, UserDefaults bookmark persistence,
//  fallback rules, directory picker abstraction, and BatchOutputPlanner integration (Task 3.12).
//

import XCTest
@testable import OrangeNote

/// Mock directory picker conforming to `DirectoryPickerProtocol` for deterministic testing.
final class MockDirectoryPicker: DirectoryPickerProtocol, @unchecked Sendable {
    var directoryToReturn: URL?
    private(set) var pickCallCount: Int = 0
    private(set) var lastPrompt: String?
    private(set) var lastInitialDirectory: URL?

    init(directoryToReturn: URL? = nil) {
        self.directoryToReturn = directoryToReturn
    }

    func pickDirectory(prompt: String?, initialDirectory: URL?) async -> URL? {
        pickCallCount += 1
        lastPrompt = prompt
        lastInitialDirectory = initialDirectory
        return directoryToReturn
    }
}

final class BatchOutputPolicyTests: XCTestCase {
    private var tempDirectory: URL!
    private var mockUserDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "BatchOutputPolicyTests_\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: suiteName)!

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BatchOutputPolicyTests_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let mockUserDefaults = mockUserDefaults, let suiteName = suiteName {
            mockUserDefaults.removePersistentDomain(forName: suiteName)
        }
        if let tempDirectory = tempDirectory {
            // Restore write permissions in case read-only subdirectories exist
            restorePermissionsRecursively(at: tempDirectory)
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func restorePermissionsRecursively(at url: URL) {
        chmod(url.path, 0o755)
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                chmod(fileURL.path, 0o755)
            }
        }
    }

    // MARK: - Validation Tests

    func testValidateDirectory_validWritableDirectory_returnsSuccess() throws {
        let subDir = tempDirectory.appendingPathComponent("ValidSubDir", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let result = BatchOutputPolicy.validateDirectory(subDir)

        switch result {
        case .success(let validatedURL):
            XCTAssertEqual(validatedURL.standardizedFileURL.path, subDir.standardizedFileURL.path)
        case .failure(let error):
            XCTFail("Expected validation success, but got failure: \(error)")
        }
    }

    func testValidateDirectory_nonFileURL_returnsNotFileURL() {
        let httpURL = URL(string: "https://example.com/transcripts")!

        let result = BatchOutputPolicy.validateDirectory(httpURL)

        XCTAssertEqual(result, .failure(.notFileURL(httpURL)))
    }

    func testValidateDirectory_nonExistentDirectory_returnsDirectoryNotFound() {
        let missingDir = tempDirectory.appendingPathComponent("DoesNotExist_\(UUID().uuidString)")

        let result = BatchOutputPolicy.validateDirectory(missingDir)

        XCTAssertEqual(result, .failure(.directoryNotFound(missingDir.standardizedFileURL)))
    }

    func testValidateDirectory_regularFile_returnsNotADirectory() throws {
        let filePath = tempDirectory.appendingPathComponent("sample_file.txt")
        try "hello".write(to: filePath, atomically: true, encoding: .utf8)

        let result = BatchOutputPolicy.validateDirectory(filePath)

        XCTAssertEqual(result, .failure(.notADirectory(filePath.standardizedFileURL)))
    }

    func testValidateDirectory_readOnlyDirectory_returnsNotWritable() throws {
        let readOnlyDir = tempDirectory.appendingPathComponent("ReadOnlyDir", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)

        // Set directory permissions to read-only (0o444)
        let chmodResult = chmod(readOnlyDir.path, 0o444)
        XCTAssertEqual(chmodResult, 0, "Failed to set chmod 0o444 on test directory")

        let result = BatchOutputPolicy.validateDirectory(readOnlyDir)

        XCTAssertEqual(result, .failure(.notWritable(readOnlyDir.standardizedFileURL)))
    }

    // MARK: - Persistence & Bookmark Round-Trip Tests

    func testUserOverride_saveAndLoad_roundTripsSuccessfully() throws {
        let outputDir = tempDirectory.appendingPathComponent("UserTranscripts", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)

        XCTAssertNil(policy.loadUserOverride())

        let savedURL = try policy.saveUserOverride(directory: outputDir)
        XCTAssertEqual(savedURL.path, outputDir.standardizedFileURL.path)

        // Verify saved in UserDefaults
        XCTAssertNotNil(mockUserDefaults.data(forKey: BatchOutputPolicy.bookmarkStorageKey))
        XCTAssertEqual(mockUserDefaults.string(forKey: BatchOutputPolicy.pathStorageKey), outputDir.standardizedFileURL.path)

        // Load override
        let loadedResult = policy.loadUserOverride()
        XCTAssertNotNil(loadedResult)
        switch loadedResult! {
        case .success(let loadedURL):
            XCTAssertEqual(loadedURL.path, outputDir.standardizedFileURL.path)
        case .failure(let error):
            XCTFail("Expected load success, but got failure: \(error)")
        }
    }

    func testUserOverride_clear_removesStoredKeys() throws {
        let outputDir = tempDirectory.appendingPathComponent("ClearTest", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        try policy.saveUserOverride(directory: outputDir)

        XCTAssertNotNil(policy.loadUserOverride())

        policy.clearUserOverride()

        XCTAssertNil(policy.loadUserOverride())
        XCTAssertNil(mockUserDefaults.data(forKey: BatchOutputPolicy.bookmarkStorageKey))
        XCTAssertNil(mockUserDefaults.string(forKey: BatchOutputPolicy.pathStorageKey))
    }

    func testUserOverride_savedDirectoryDeleted_loadReturnsDirectoryNotFound() throws {
        let outputDir = tempDirectory.appendingPathComponent("WillDelete", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        try policy.saveUserOverride(directory: outputDir)

        // Delete the directory
        try FileManager.default.removeItem(at: outputDir)

        let loadedResult = policy.loadUserOverride()
        XCTAssertNotNil(loadedResult)
        switch loadedResult! {
        case .failure(let error):
            // Either directoryNotFound or resolution failure is expected
            if case .directoryNotFound(let url) = error {
                XCTAssertEqual(url.path, outputDir.standardizedFileURL.path)
            } else if case .bookmarkResolutionFailed = error {
                // Also acceptable if OS fails bookmark resolution for deleted target
                XCTAssertTrue(true)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        case .success(let url):
            XCTFail("Expected failure for deleted directory, got: \(url)")
        }
    }

    func testUserOverride_savedDirectoryMadeReadOnly_loadReturnsNotWritable() throws {
        let outputDir = tempDirectory.appendingPathComponent("WillMakeReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        try policy.saveUserOverride(directory: outputDir)

        // Make read-only
        chmod(outputDir.path, 0o444)

        let loadedResult = policy.loadUserOverride()
        XCTAssertNotNil(loadedResult)
        XCTAssertEqual(loadedResult, .failure(.notWritable(outputDir.standardizedFileURL)))
    }

    func testUserOverride_corruptedBookmarkData_returnsBookmarkResolutionFailed() {
        mockUserDefaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: BatchOutputPolicy.bookmarkStorageKey)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let loadedResult = policy.loadUserOverride()

        XCTAssertNotNil(loadedResult)
        if case .failure(let error) = loadedResult! {
            if case .bookmarkResolutionFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected .bookmarkResolutionFailed, got \(error)")
            }
        } else {
            XCTFail("Expected failure for corrupt bookmark data")
        }
    }

    // MARK: - Policy Resolution Logic Tests

    func testResolveOutputDirectory_singleFolderGrant_proposesSourceFolder() throws {
        let folderURL = tempDirectory.appendingPathComponent("AudiosFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let source = BatchInputSource.folder(folderURL)

        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.url.path, folderURL.standardizedFileURL.path)
            XCTAssertEqual(resolution.source, .sourceFolder)
        case .failure(let error):
            XCTFail("Expected sourceFolder resolution, got failure: \(error)")
        }
    }

    func testResolveOutputDirectory_multiFiles_withoutUserOverride_fallsBackToSystemDefault() throws {
        let file1 = tempDirectory.appendingPathComponent("1.mp3")
        let file2 = tempDirectory.appendingPathComponent("2.wav")
        try "data1".write(to: file1, atomically: true, encoding: .utf8)
        try "data2".write(to: file2, atomically: true, encoding: .utf8)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let source = BatchInputSource.files([file1, file2])

        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.source, .systemDefault)
            XCTAssertTrue(FileManager.default.fileExists(atPath: resolution.url.path))
        case .failure(let error):
            XCTFail("Expected systemDefault fallback resolution, got failure: \(error)")
        }
    }

    func testResolveOutputDirectory_emptySource_withoutUserOverride_fallsBackToSystemDefault() {
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let source = BatchInputSource.empty

        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.source, .systemDefault)
        case .failure(let error):
            XCTFail("Expected systemDefault fallback, got: \(error)")
        }
    }

    func testResolveOutputDirectory_userOverrideTakesPrecedenceOverFolderGrant() throws {
        let folderURL = tempDirectory.appendingPathComponent("AudiosFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let overrideURL = tempDirectory.appendingPathComponent("OverrideFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        try policy.saveUserOverride(directory: overrideURL)

        let source = BatchInputSource.folder(folderURL)
        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.url.path, overrideURL.standardizedFileURL.path)
            XCTAssertEqual(resolution.source, .userOverride)
        case .failure(let error):
            XCTFail("Expected userOverride resolution, got failure: \(error)")
        }
    }

    func testResolveOutputDirectory_invalidUserOverride_fallsBackToFolderGrant() throws {
        let folderURL = tempDirectory.appendingPathComponent("AudiosFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let deletedOverrideURL = tempDirectory.appendingPathComponent("DeletedFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: deletedOverrideURL, withIntermediateDirectories: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        try policy.saveUserOverride(directory: deletedOverrideURL)

        // Delete override directory
        try FileManager.default.removeItem(at: deletedOverrideURL)

        let source = BatchInputSource.folder(folderURL)
        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.url.path, folderURL.standardizedFileURL.path)
            XCTAssertEqual(resolution.source, .sourceFolder)
        case .failure(let error):
            XCTFail("Expected fallback to sourceFolder, got failure: \(error)")
        }
    }

    func testResolveOutputDirectory_invalidFolderGrant_fallsBackToSystemDefault() {
        let nonExistentFolder = tempDirectory.appendingPathComponent("DoesNotExist", isDirectory: true)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let source = BatchInputSource.folder(nonExistentFolder)

        let resolutionResult = policy.resolveOutputDirectory(for: source)

        switch resolutionResult {
        case .success(let resolution):
            XCTAssertEqual(resolution.source, .systemDefault)
        case .failure(let error):
            XCTFail("Expected fallback to systemDefault, got failure: \(error)")
        }
    }

    // MARK: - Directory Picker Abstraction Tests

    func testPromptAndSaveUserOverride_userSelectsValidDirectory_savesOverride() async throws {
        let chosenDir = tempDirectory.appendingPathComponent("ChosenByPicker", isDirectory: true)
        try FileManager.default.createDirectory(at: chosenDir, withIntermediateDirectories: true)

        let mockPicker = MockDirectoryPicker(directoryToReturn: chosenDir)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, directoryPicker: mockPicker)

        let resultURL = try await policy.promptAndSaveUserOverride(prompt: "Select Transcripts Folder")

        XCTAssertEqual(resultURL?.path, chosenDir.standardizedFileURL.path)
        XCTAssertEqual(mockPicker.pickCallCount, 1)
        XCTAssertEqual(mockPicker.lastPrompt, "Select Transcripts Folder")

        // Verify persisted
        let loaded = policy.loadUserOverride()
        XCTAssertEqual(loaded, .success(chosenDir.standardizedFileURL))
    }

    func testPromptAndSaveUserOverride_userCancelsPicker_returnsNilAndDoesNotSave() async throws {
        let mockPicker = MockDirectoryPicker(directoryToReturn: nil)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, directoryPicker: mockPicker)

        let resultURL = try await policy.promptAndSaveUserOverride()

        XCTAssertNil(resultURL)
        XCTAssertEqual(mockPicker.pickCallCount, 1)
        XCTAssertNil(policy.loadUserOverride())
    }

    func testPromptAndSaveUserOverride_pickerReturnsReadOnlyDirectory_throwsValidationError() async throws {
        let readOnlyDir = tempDirectory.appendingPathComponent("PickerReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        chmod(readOnlyDir.path, 0o444)

        let mockPicker = MockDirectoryPicker(directoryToReturn: readOnlyDir)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults, directoryPicker: mockPicker)

        do {
            _ = try await policy.promptAndSaveUserOverride()
            XCTFail("Expected validation error when saving read-only directory")
        } catch let error as BatchOutputDirectoryValidationError {
            XCTAssertEqual(error, .notWritable(readOnlyDir.standardizedFileURL))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Integration with BatchOutputPlanner Tests

    func testBatchOutputPlanner_planWithPolicy_folderSource_plansInSourceFolder() throws {
        let folderURL = tempDirectory.appendingPathComponent("AudioInputs", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let file1 = folderURL.appendingPathComponent("track1.mp3")
        let file2 = folderURL.appendingPathComponent("track2.wav")
        try "audio1".write(to: file1, atomically: true, encoding: .utf8)
        try "audio2".write(to: file2, atomically: true, encoding: .utf8)

        let item1 = BatchItem(sourceURL: file1)
        let item2 = BatchItem(sourceURL: file2)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let planResult = try BatchOutputPlanner.plan(
            items: [item1, item2],
            source: .folder(folderURL),
            policy: policy
        )

        XCTAssertEqual(planResult.resolvedDirectory.path, folderURL.standardizedFileURL.path)
        XCTAssertEqual(planResult.items.count, 2)
        XCTAssertEqual(planResult.items[0].outputURL?.path, folderURL.appendingPathComponent("track1.json").standardizedFileURL.path)
        XCTAssertEqual(planResult.items[1].outputURL?.path, folderURL.appendingPathComponent("track2.json").standardizedFileURL.path)
        XCTAssertEqual(planResult.items[0].status, .queued)
        XCTAssertEqual(planResult.items[1].status, .queued)
    }

    func testBatchOutputPlanner_planWithPolicy_detectsExistingFilesAndMarksSkipped() throws {
        let folderURL = tempDirectory.appendingPathComponent("AudioInputs", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let file1 = folderURL.appendingPathComponent("track1.mp3")
        let file2 = folderURL.appendingPathComponent("track2.wav")
        try "audio1".write(to: file1, atomically: true, encoding: .utf8)
        try "audio2".write(to: file2, atomically: true, encoding: .utf8)

        // Create pre-existing track1.json
        let existingJSON = folderURL.appendingPathComponent("track1.json")
        try "{}".write(to: existingJSON, atomically: true, encoding: .utf8)

        let item1 = BatchItem(sourceURL: file1)
        let item2 = BatchItem(sourceURL: file2)

        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let planResult = try BatchOutputPlanner.plan(
            items: [item1, item2],
            source: .folder(folderURL),
            policy: policy
        )

        XCTAssertEqual(planResult.items[0].status, .skipped)
        XCTAssertEqual(planResult.items[1].status, .queued)
    }
}
