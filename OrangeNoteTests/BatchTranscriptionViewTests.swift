//
//  BatchTranscriptionViewTests.swift
//  OrangeNoteTests
//
//  Unit tests covering Batch UI view components, mode switching, and lifecycle-bound controls (Task 3.16).
//

import XCTest
import SwiftUI
@testable import OrangeNote

@MainActor
final class BatchTranscriptionViewTests: XCTestCase {

    // MARK: - Mode Enum & Titles

    func testTranscriptionModeEnumCasesAndTitles() {
        XCTAssertEqual(TranscriptionMode.allCases.count, 2)
        XCTAssertEqual(TranscriptionMode.single.id, "single")
        XCTAssertEqual(TranscriptionMode.batch.id, "batch")
        XCTAssertEqual(TranscriptionMode.single.titleKey, "transcription.mode.single")
        XCTAssertEqual(TranscriptionMode.batch.titleKey, "transcription.mode.batch")
    }

    // MARK: - TranscriptionView Initialization & Mode

    func testTranscriptionViewInitializationDefaultMode() {
        let singleVM = TranscriptionViewModel()
        let batchVM = BatchTranscriptionViewModel()

        let view = TranscriptionView(
            viewModel: singleVM,
            batchViewModel: batchVM
        )

        XCTAssertEqual(view.selectedMode, .single)
    }

    func testTranscriptionViewInitializationCustomMode() {
        let singleVM = TranscriptionViewModel()
        let batchVM = BatchTranscriptionViewModel()

        let view = TranscriptionView(
            viewModel: singleVM,
            batchViewModel: batchVM,
            initialMode: .batch
        )

        XCTAssertEqual(view.selectedMode, .batch)
    }

    // MARK: - BatchItemRow Tests

    func testBatchItemRowQueuedState() {
        let item = BatchItem(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.mp3"),
            status: .queued
        )

        var removed = false
        let row = BatchItemRow(
            item: item,
            isProcessing: false,
            canRemove: true,
            onRemove: { removed = true }
        )

        XCTAssertEqual(row.item.id, item.id)
        XCTAssertFalse(row.isProcessing)
        XCTAssertTrue(row.canRemove)

        row.onRemove?()
        XCTAssertTrue(removed)
    }

    func testBatchItemRowTranscribingState() {
        let item = BatchItem(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            status: .transcribing,
            progress: 0.45
        )

        let row = BatchItemRow(
            item: item,
            isProcessing: true,
            canRemove: false
        )

        XCTAssertEqual(row.item.status, .transcribing)
        XCTAssertEqual(row.item.progress, 0.45)
        XCTAssertTrue(row.isProcessing)
        XCTAssertFalse(row.canRemove)
    }

    func testBatchItemRowSucceededStateWithResult() {
        let segment = TranscriptionSegment(
            id: UUID(),
            startTime: 0.0,
            endTime: 5.0,
            text: "Hello world"
        )
        let result = TranscriptionResult(
            segments: [segment],
            fullText: "Hello world",
            language: "en",
            duration: 5.0
        )
        let item = BatchItem(
            sourceURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            outputURL: URL(fileURLWithPath: "/tmp/test.json"),
            status: .succeeded,
            progress: 1.0,
            result: result
        )

        let row = BatchItemRow(
            item: item,
            isProcessing: false,
            canRemove: false
        )

        XCTAssertEqual(row.item.status, .succeeded)
        XCTAssertNotNil(row.item.result)
        XCTAssertEqual(row.item.result?.segmentCount, 1)
    }

    func testBatchItemRowFailedStateWithError() {
        let item = BatchItem(
            sourceURL: URL(fileURLWithPath: "/tmp/corrupt.mp3"),
            status: .failed,
            errorMessage: "Decode error"
        )

        let row = BatchItemRow(
            item: item,
            isProcessing: false,
            canRemove: true
        )

        XCTAssertEqual(row.item.status, .failed)
        XCTAssertEqual(row.item.errorMessage, "Decode error")
    }

    func testBatchItemRowSkippedState() {
        let item = BatchItem(
            sourceURL: URL(fileURLWithPath: "/tmp/existing.flac"),
            outputURL: URL(fileURLWithPath: "/tmp/existing.json"),
            status: .skipped
        )

        let row = BatchItemRow(
            item: item,
            isProcessing: false,
            canRemove: true
        )

        XCTAssertEqual(row.item.status, .skipped)
    }

    // MARK: - BatchQueueSection Assembly & Settings Mapping

    func testBatchQueueSectionAssembly() {
        let batchVM = BatchTranscriptionViewModel()
        let settings = AppSettings()

        let section = BatchQueueSection(
            viewModel: batchVM,
            singleFileIsBusy: false,
            settings: settings
        )

        XCTAssertFalse(section.singleFileIsBusy)
        XCTAssertEqual(section.viewModel.itemCount, 0)
    }

    func testSettingsMappingToBatchConfiguration() {
        let settings = AppSettings()
        settings.selectedModel = "small"
        settings.language = "ru"
        settings.translateToEnglish = true
        settings.useChunking = true
        settings.chunkDuration = 45
        settings.overlapDuration = 10

        let config = BatchTranscriptionConfiguration(
            modelName: settings.selectedModel,
            language: settings.language == "auto" ? nil : settings.language,
            translateToEnglish: settings.translateToEnglish,
            chunkingEnabled: settings.useChunking,
            chunkDurationSeconds: settings.useChunking ? Double(settings.chunkDuration) : nil,
            overlapDurationSeconds: settings.useChunking ? Double(settings.overlapDuration) : nil
        )

        XCTAssertEqual(config.modelName, "small")
        XCTAssertEqual(config.language, "ru")
        XCTAssertTrue(config.translateToEnglish)
        XCTAssertTrue(config.chunkingEnabled)
        XCTAssertEqual(config.chunkDurationSeconds, 45.0)
        XCTAssertEqual(config.overlapDurationSeconds, 10.0)
    }

    func testSettingsMappingAutoLanguageResolvesNil() {
        let settings = AppSettings()
        settings.selectedModel = "base"
        settings.language = "auto"
        settings.useChunking = false

        let config = BatchTranscriptionConfiguration(
            modelName: settings.selectedModel,
            language: settings.language == "auto" ? nil : settings.language,
            translateToEnglish: settings.translateToEnglish,
            chunkingEnabled: settings.useChunking,
            chunkDurationSeconds: settings.useChunking ? Double(settings.chunkDuration) : nil,
            overlapDurationSeconds: settings.useChunking ? Double(settings.overlapDuration) : nil
        )

        XCTAssertEqual(config.modelName, "base")
        XCTAssertNil(config.language)
        XCTAssertFalse(config.chunkingEnabled)
        XCTAssertNil(config.chunkDurationSeconds)
        XCTAssertNil(config.overlapDurationSeconds)
    }

    // MARK: - Cross-Mode Busy Invariants

    func testBatchStartDisabledWhenSingleFileIsBusy() {
        var singleFileBusy = true
        let batchVM = BatchTranscriptionViewModel(
            isSingleFileBusy: { singleFileBusy }
        )

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let item = BatchItem(sourceURL: tempDir.appendingPathComponent("test.mp3"))
        batchVM.ingestResult(BatchIngestionResult(source: .folder(tempDir), items: [item]))

        XCTAssertFalse(batchVM.canStart)

        singleFileBusy = false
        XCTAssertTrue(batchVM.canStart)
    }
}
