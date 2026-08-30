//
//  DocumentPickerHelperTests.swift
//  OrangeNoteTests
//
//  Unit tests for DocumentPickerHelper, audio-type filtering, input source detection,
//  top-level folder ingestion, multi-file ingestion, mock picker interactions, and
//  BatchOutputPolicy integration (Task 3.13).
//

import XCTest
@testable import OrangeNote

/// Mock document picker conforming to `BatchDocumentPickerProtocol` and `DirectoryPickerProtocol`
/// for deterministic testing without AppKit modal windows.
final class MockDocumentPicker: BatchDocumentPickerProtocol, DirectoryPickerProtocol, @unchecked Sendable {
    var filesToReturn: [URL]?
    var folderToReturn: URL?
    var outputDirectoryToReturn: URL?

    private(set) var pickFilesCallCount: Int = 0
    private(set) var lastFilesPrompt: String?
    private(set) var lastFilesInitialDirectory: URL?

    private(set) var pickFolderCallCount: Int = 0
    private(set) var lastFolderPrompt: String?
    private(set) var lastFolderInitialDirectory: URL?

    private(set) var pickOutputCallCount: Int = 0
    private(set) var lastOutputPrompt: String?
    private(set) var lastOutputInitialDirectory: URL?

    init(
        filesToReturn: [URL]? = nil,
        folderToReturn: URL? = nil,
        outputDirectoryToReturn: URL? = nil
    ) {
        self.filesToReturn = filesToReturn
        self.folderToReturn = folderToReturn
        self.outputDirectoryToReturn = outputDirectoryToReturn
    }

    func pickMultipleAudioFiles(prompt: String?, initialDirectory: URL?) async -> [URL]? {
        pickFilesCallCount += 1
        lastFilesPrompt = prompt
        lastFilesInitialDirectory = initialDirectory
        return filesToReturn
    }

    func pickSingleFolder(prompt: String?, initialDirectory: URL?) async -> URL? {
        pickFolderCallCount += 1
        lastFolderPrompt = prompt
        lastFolderInitialDirectory = initialDirectory
        return folderToReturn
    }

    func pickOutputDirectory(prompt: String?, initialDirectory: URL?) async -> URL? {
        pickOutputCallCount += 1
        lastOutputPrompt = prompt
        lastOutputInitialDirectory = initialDirectory
        return outputDirectoryToReturn
    }

    func pickDirectory(prompt: String?, initialDirectory: URL?) async -> URL? {
        await pickOutputDirectory(prompt: prompt, initialDirectory: initialDirectory)
    }
}

final class DocumentPickerHelperTests: XCTestCase {
    private var tempDirectory: URL!
    private var mockUserDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "DocumentPickerHelperTests_\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: suiteName)!

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DocumentPickerHelperTests_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let mockUserDefaults = mockUserDefaults, let suiteName = suiteName {
            mockUserDefaults.removePersistentDomain(forName: suiteName)
        }
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func createTestFile(named name: String, content: String = "mock audio content") throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func createSubDirectory(named name: String) throws -> URL {
        let dirURL = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }

    // MARK: - Audio File Filtering Tests

    func testFilterAudioFiles_filtersNonAudioFiles() throws {
        let mp3 = try createTestFile(named: "audio1.mp3")
        let wav = try createTestFile(named: "audio2.WAV")
        let txt = try createTestFile(named: "notes.txt")
        let json = try createTestFile(named: "data.json")

        let filtered = DocumentPickerHelper.filterAudioFiles([mp3, txt, wav, json])

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.lastPathComponent), ["audio1.mp3", "audio2.WAV"])
    }

    func testFilterAudioFiles_supportsAllAuditedExtensions() throws {
        let extensions = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"]
        var files: [URL] = []
        for ext in extensions {
            let file = try createTestFile(named: "test.\(ext)")
            files.append(file)
        }

        let filtered = DocumentPickerHelper.filterAudioFiles(files)

        XCTAssertEqual(filtered.count, extensions.count)
    }

    func testFilterAudioFiles_rejectsDirectoriesEvenWithAudioExtension() throws {
        let fakeAudioDir = try createSubDirectory(named: "fakeAudio.mp3")
        let realAudio = try createTestFile(named: "realAudio.mp3")

        let filtered = DocumentPickerHelper.filterAudioFiles([fakeAudioDir, realAudio])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.lastPathComponent, "realAudio.mp3")
    }

    func testFilterAudioFiles_rejectsNonExistentFiles() {
        let nonExistent = tempDirectory.appendingPathComponent("ghost.mp3")

        let filtered = DocumentPickerHelper.filterAudioFiles([nonExistent])

        XCTAssertTrue(filtered.isEmpty)
    }

    func testFilterAudioFiles_deduplicatesIdenticalPathsPreservingOrder() throws {
        let file1 = try createTestFile(named: "first.mp3")
        let file2 = try createTestFile(named: "second.wav")

        let duplicateInput = [file1, file2, file1, file2]
        let filtered = DocumentPickerHelper.filterAudioFiles(duplicateInput)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered, [file1.standardizedFileURL, file2.standardizedFileURL])
    }

    // MARK: - Input Source Detection Tests

    func testDetectInputSource_emptyURLs_returnsEmpty() {
        let source = DocumentPickerHelper.detectInputSource(from: [])
        XCTAssertEqual(source, .empty)
    }

    func testDetectInputSource_singleDirectoryURL_returnsFolder() throws {
        let dirURL = try createSubDirectory(named: "AudioFolder")
        let source = DocumentPickerHelper.detectInputSource(from: [dirURL])

        XCTAssertEqual(source, .folder(dirURL.standardizedFileURL))
        XCTAssertEqual(source.sourceFolderURL, dirURL.standardizedFileURL)
    }

    func testDetectInputSource_singleFileURL_returnsFiles() throws {
        let fileURL = try createTestFile(named: "single.mp3")
        let source = DocumentPickerHelper.detectInputSource(from: [fileURL])

        XCTAssertEqual(source, .files([fileURL.standardizedFileURL]))
        XCTAssertNil(source.sourceFolderURL)
    }

    func testDetectInputSource_multipleURLs_returnsFiles() throws {
        let file1 = try createTestFile(named: "first.mp3")
        let file2 = try createTestFile(named: "second.mp3")
        let source = DocumentPickerHelper.detectInputSource(from: [file1, file2])

        XCTAssertEqual(source, .files([file1.standardizedFileURL, file2.standardizedFileURL]))
    }

    // MARK: - Process Picked Folder Tests

    func testProcessFolder_collectsTopLevelAudioFilesOnly() throws {
        let audioFolder = try createSubDirectory(named: "TopLevelAudioFolder")
        let file1 = audioFolder.appendingPathComponent("track1.mp3")
        try "audio1".write(to: file1, atomically: true, encoding: .utf8)
        let file2 = audioFolder.appendingPathComponent("track2.wav")
        try "audio2".write(to: file2, atomically: true, encoding: .utf8)
        let textFile = audioFolder.appendingPathComponent("readme.txt")
        try "text".write(to: textFile, atomically: true, encoding: .utf8)

        let subFolder = audioFolder.appendingPathComponent("NestedSubdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        let nestedAudio = subFolder.appendingPathComponent("nestedTrack.mp3")
        try "nested".write(to: nestedAudio, atomically: true, encoding: .utf8)

        let result = DocumentPickerHelper.processFolder(audioFolder)

        XCTAssertEqual(result.source, .folder(audioFolder.standardizedFileURL))
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.audioURLs.map(\.lastPathComponent), ["track1.mp3", "track2.wav"])
    }

    func testProcessFolder_emptyFolder_returnsEmptyResultWithFolderSource() throws {
        let emptyFolder = try createSubDirectory(named: "EmptyFolder")

        let result = DocumentPickerHelper.processFolder(emptyFolder)

        XCTAssertEqual(result.source, .folder(emptyFolder.standardizedFileURL))
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Process Picked Files Tests

    func testProcessFiles_filtersDeduplicatesAndSorts() throws {
        let fileB = try createTestFile(named: "b_track.mp3")
        let fileA = try createTestFile(named: "a_track.wav")
        let text = try createTestFile(named: "ignore.txt")

        let result = DocumentPickerHelper.processFiles([fileB, text, fileA, fileB])

        XCTAssertEqual(result.count, 2)
        // BatchFileCollector sorts by natural full path: a_track.wav then b_track.mp3
        XCTAssertEqual(result.items.map(\.sourceURL.lastPathComponent), ["a_track.wav", "b_track.mp3"])
        XCTAssertEqual(result.source, .files([fileA.standardizedFileURL, fileB.standardizedFileURL]))
    }

    // MARK: - Candidate URL Processing Tests

    func testProcessCandidateURLs_routesFolderCorrectly() throws {
        let folder = try createSubDirectory(named: "BatchDirectory")
        let audio = folder.appendingPathComponent("audio.mp3")
        try "test".write(to: audio, atomically: true, encoding: .utf8)

        let result = DocumentPickerHelper.processCandidateURLs([folder])

        XCTAssertEqual(result.source, .folder(folder.standardizedFileURL))
        XCTAssertEqual(result.count, 1)
    }

    func testProcessCandidateURLs_routesFilesCorrectly() throws {
        let file1 = try createTestFile(named: "file1.mp3")
        let file2 = try createTestFile(named: "file2.mp3")

        let result = DocumentPickerHelper.processCandidateURLs([file1, file2])

        XCTAssertEqual(result.source, .files([file1.standardizedFileURL, file2.standardizedFileURL]))
        XCTAssertEqual(result.count, 2)
    }

    func testProcessCandidateURLs_empty_returnsEmptyResult() {
        let result = DocumentPickerHelper.processCandidateURLs([])

        XCTAssertEqual(result.source, .empty)
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Injected Helper Async Operations

    func testPromptAndIngestMultipleFiles_success() async throws {
        let file1 = try createTestFile(named: "song1.mp3")
        let file2 = try createTestFile(named: "song2.wav")

        let mockPicker = MockDocumentPicker(filesToReturn: [file1, file2])
        let helper = DocumentPickerHelper(picker: mockPicker)

        let result = await helper.promptAndIngestMultipleFiles(prompt: "Select Songs")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(mockPicker.pickFilesCallCount, 1)
        XCTAssertEqual(mockPicker.lastFilesPrompt, "Select Songs")
    }

    func testPromptAndIngestMultipleFiles_cancelled_returnsNil() async {
        let mockPicker = MockDocumentPicker(filesToReturn: nil)
        let helper = DocumentPickerHelper(picker: mockPicker)

        let result = await helper.promptAndIngestMultipleFiles()

        XCTAssertNil(result)
        XCTAssertEqual(mockPicker.pickFilesCallCount, 1)
    }

    func testPromptAndIngestFolder_success() async throws {
        let folder = try createSubDirectory(named: "AlbumFolder")
        let track = folder.appendingPathComponent("track.flac")
        try "flac data".write(to: track, atomically: true, encoding: .utf8)

        let mockPicker = MockDocumentPicker(folderToReturn: folder)
        let helper = DocumentPickerHelper(picker: mockPicker)

        let result = await helper.promptAndIngestFolder(prompt: "Select Album")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.source, .folder(folder.standardizedFileURL))
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(mockPicker.pickFolderCallCount, 1)
        XCTAssertEqual(mockPicker.lastFolderPrompt, "Select Album")
    }

    func testPromptAndIngestFolder_cancelled_returnsNil() async {
        let mockPicker = MockDocumentPicker(folderToReturn: nil)
        let helper = DocumentPickerHelper(picker: mockPicker)

        let result = await helper.promptAndIngestFolder()

        XCTAssertNil(result)
        XCTAssertEqual(mockPicker.pickFolderCallCount, 1)
    }

    func testPromptAndSelectOutputDirectory_success_savesToOutputPolicy() async throws {
        let outputDir = try createSubDirectory(named: "BatchOutputFolder")
        let mockPicker = MockDocumentPicker(outputDirectoryToReturn: outputDir)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let helper = DocumentPickerHelper(picker: mockPicker, outputPolicy: policy)

        let savedURL = try await helper.promptAndSelectOutputDirectory(prompt: "Choose Output")

        XCTAssertEqual(savedURL?.standardizedFileURL.path, outputDir.standardizedFileURL.path)
        XCTAssertEqual(mockPicker.pickOutputCallCount, 1)
        XCTAssertEqual(mockPicker.lastOutputPrompt, "Choose Output")

        // Verify policy loaded override matches
        let loadedOverride = policy.loadUserOverride()
        switch loadedOverride {
        case .success(let url):
            XCTAssertEqual(url.standardizedFileURL.path, outputDir.standardizedFileURL.path)
        default:
            XCTFail("Expected saved override in policy")
        }
    }

    func testPromptAndSelectOutputDirectory_cancelled_returnsNil() async throws {
        let mockPicker = MockDocumentPicker(outputDirectoryToReturn: nil)
        let policy = BatchOutputPolicy(userDefaults: mockUserDefaults)
        let helper = DocumentPickerHelper(picker: mockPicker, outputPolicy: policy)

        let result = try await helper.promptAndSelectOutputDirectory()

        XCTAssertNil(result)
        XCTAssertEqual(mockPicker.pickOutputCallCount, 1)
    }

    // MARK: - BatchIngestionResult Equality & Properties

    func testBatchIngestionResult_equalityAndAccessors() throws {
        let file = try createTestFile(named: "item.mp3")
        let item = BatchItem(sourceURL: file)

        let res1 = BatchIngestionResult(source: .files([file]), items: [item])
        let res2 = BatchIngestionResult(source: .files([file]), items: [item])
        let res3 = BatchIngestionResult(source: .empty, items: [])

        XCTAssertEqual(res1, res2)
        XCTAssertNotEqual(res1, res3)
        XCTAssertEqual(res1.count, 1)
        XCTAssertFalse(res1.isEmpty)
        XCTAssertEqual(res1.audioURLs, [file.standardizedFileURL])
    }
}
