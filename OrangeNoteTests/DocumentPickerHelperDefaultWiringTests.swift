//
//  DocumentPickerHelperDefaultWiringTests.swift
//  OrangeNoteTests
//
//  Verifies default DocumentPickerHelper initialization, AppKit picker wiring,
//  and BatchTranscriptionViewModel prompt interactions.
//

import XCTest
@testable import OrangeNote

@MainActor
final class DocumentPickerHelperDefaultWiringTests: XCTestCase {

    func testDefaultInitCreatesNonNilAppKitPickerOnMacOS() {
        let helper = DocumentPickerHelper()
        #if canImport(AppKit)
        XCTAssertNotNil(helper.picker)
        XCTAssertTrue(helper.picker is OpenPanelDocumentPicker)
        #endif
    }

    func testBatchTranscriptionViewModelDefaultInitWiresNonNilPicker() {
        let viewModel = BatchTranscriptionViewModel()
        XCTAssertFalse(viewModel.canStart)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.items.count, 0)
    }

    func testPromptAndIngestFilesInvokesInjectedPicker() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("test1.mp3")
        FileManager.default.createFile(atPath: file1.path, contents: Data([0x01]))

        let mockPicker = MockDocumentPicker(filesToReturn: [file1])
        let helper = DocumentPickerHelper(picker: mockPicker)
        let viewModel = BatchTranscriptionViewModel(documentPickerHelper: helper)

        await viewModel.promptAndIngestFiles()

        XCTAssertEqual(mockPicker.pickFilesCallCount, 1)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL.standardizedFileURL, file1.standardizedFileURL)
    }

    func testPromptAndIngestFolderInvokesInjectedPicker() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioFile = tempDir.appendingPathComponent("song.wav")
        FileManager.default.createFile(atPath: audioFile.path, contents: Data([0x01]))

        let mockPicker = MockDocumentPicker(folderToReturn: tempDir)
        let helper = DocumentPickerHelper(picker: mockPicker)
        let viewModel = BatchTranscriptionViewModel(documentPickerHelper: helper)

        await viewModel.promptAndIngestFolder()

        XCTAssertEqual(mockPicker.pickFolderCallCount, 1)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.sourceURL.standardizedFileURL, audioFile.standardizedFileURL)
    }

    func testPromptAndSelectOutputDirectoryInvokesInjectedPicker() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockPicker = MockDocumentPicker(outputDirectoryToReturn: tempDir)
        let helper = DocumentPickerHelper(picker: mockPicker)
        let viewModel = BatchTranscriptionViewModel(documentPickerHelper: helper)

        await viewModel.promptAndSelectOutputDirectory()

        XCTAssertEqual(mockPicker.pickOutputCallCount, 1)
        XCTAssertEqual(viewModel.outputDirectory?.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertEqual(viewModel.outputResolutionSource, .userOverride)
    }
}
