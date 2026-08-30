//
//  AppStateRoutingTests.swift
//  OrangeNoteTests
//
//  Unit tests verifying AppState results routing, navigation state transitions,
//  batch item deep-linking, cross-mode isolation, and live coordinator event handling (Task 3.17 / D010 / D028).
//

import XCTest
import SwiftUI
@testable import OrangeNote

@MainActor
final class AppStateRoutingTests: XCTestCase {

    private func makeSampleResult(text: String = "Test transcription result", duration: Double = 12.5) -> TranscriptionResult {
        let segment = TranscriptionSegment(
            id: UUID(),
            startTime: 0.0,
            endTime: duration,
            text: text
        )
        return TranscriptionResult(
            segments: [segment],
            fullText: text,
            language: "en",
            duration: duration
        )
    }

    // MARK: - Navigation State Transitions

    func testInitialAppStateNavigationState() {
        let appState = AppState()

        XCTAssertEqual(appState.selectedNavigationItem, .transcribe)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertNil(appState.displayedTranscription)
        XCTAssertNil(appState.currentTranscriptionResult)
        XCTAssertNil(appState.currentExecutionProvenance)
        XCTAssertFalse(appState.hasTranscriptionResult)
        XCTAssertFalse(appState.showExportSheet)
        XCTAssertFalse(appState.triggerSave)
        XCTAssertFalse(appState.triggerExport)
        XCTAssertFalse(appState.triggerOpenTranscription)
        XCTAssertNil(appState.importErrorMessage)
    }

    func testNavigateToDestination() {
        let appState = AppState()

        appState.navigate(to: .results)
        XCTAssertEqual(appState.selectedNavigationItem, .results)

        appState.navigate(to: .models)
        XCTAssertEqual(appState.selectedNavigationItem, .models)

        appState.navigate(to: .settings)
        XCTAssertEqual(appState.selectedNavigationItem, .settings)

        appState.navigate(to: .transcribe)
        XCTAssertEqual(appState.selectedNavigationItem, .transcribe)
    }

    // MARK: - Single-File & Import Routing

    func testSetDisplayedTranscriptionWithoutNavigation() {
        let appState = AppState()
        let result = makeSampleResult()
        let provenance = ExecutionProvenance(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.mp3"),
            modelName: "base",
            engineID: "whisper-local"
        )
        let displayed = DisplayedTranscription(result: result, provenance: provenance)

        appState.setDisplayedTranscription(displayed, navigateToResults: false)

        XCTAssertEqual(appState.displayedTranscription, displayed)
        XCTAssertEqual(appState.currentTranscriptionResult, result)
        XCTAssertEqual(appState.currentExecutionProvenance, provenance)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertEqual(appState.selectedNavigationItem, .transcribe)
        XCTAssertTrue(appState.hasTranscriptionResult)
    }

    func testSetDisplayedTranscriptionWithNavigationToResults() {
        let appState = AppState()
        let result = makeSampleResult()
        let provenance = ExecutionProvenance(
            sourceFileName: "imported.json",
            sourceURL: nil,
            modelName: "unknown",
            engineID: "unknown"
        )
        let displayed = DisplayedTranscription(result: result, provenance: provenance)

        appState.setDisplayedTranscription(displayed, navigateToResults: true)

        XCTAssertEqual(appState.displayedTranscription, displayed)
        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertTrue(appState.hasTranscriptionResult)
    }

    // MARK: - Batch Item Routing & Deep-Linking (D028)

    func testRouteToBatchItemResultSucceeded() {
        let appState = AppState()
        let sampleURL = URL(fileURLWithPath: "/tmp/batch_audio.wav")
        let result = makeSampleResult(text: "Batch audio transcribed", duration: 8.0)
        let batchItem = BatchItem(
            id: UUID(),
            sourceURL: sampleURL,
            outputURL: URL(fileURLWithPath: "/tmp/batch_audio.json"),
            status: .succeeded,
            progress: 1.0,
            result: result
        )

        appState.routeToBatchItemResult(batchItem, modelName: "small", engineID: "whisper-local")

        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertEqual(appState.selectedBatchItemID, batchItem.id)
        XCTAssertTrue(appState.hasTranscriptionResult)
        XCTAssertEqual(appState.currentTranscriptionResult, result)

        let provenance = try? XCTUnwrap(appState.currentExecutionProvenance)
        XCTAssertEqual(provenance?.sourceFileName, "batch_audio.wav")
        XCTAssertEqual(provenance?.sourceURL, sampleURL)
        XCTAssertEqual(provenance?.modelName, "small")
        XCTAssertEqual(provenance?.engineID, "whisper-local")
    }

    func testRouteToBatchItemResultWithoutResult_isNoOp() {
        let appState = AppState()
        let sampleURL = URL(fileURLWithPath: "/tmp/failed.wav")
        let failedItem = BatchItem(
            id: UUID(),
            sourceURL: sampleURL,
            status: .failed,
            errorMessage: "Decode failed",
            result: nil
        )

        appState.routeToBatchItemResult(failedItem)

        XCTAssertEqual(appState.selectedNavigationItem, .transcribe)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertNil(appState.displayedTranscription)
        XCTAssertFalse(appState.hasTranscriptionResult)
    }

    func testClearDisplayedTranscriptionResetsSelectionAndDisplayed() {
        let appState = AppState()
        let result = makeSampleResult()
        let batchItem = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/item.mp3"),
            status: .succeeded,
            result: result
        )

        appState.routeToBatchItemResult(batchItem)
        XCTAssertNotNil(appState.displayedTranscription)
        XCTAssertNotNil(appState.selectedBatchItemID)

        appState.clearDisplayedTranscription()

        XCTAssertNil(appState.displayedTranscription)
        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertFalse(appState.hasTranscriptionResult)
    }

    // MARK: - Cross-Mode Isolation

    func testCrossModeIsolation_SingleFileClearsBatchSelection() {
        let appState = AppState()
        let batchResult = makeSampleResult(text: "Batch text")
        let batchItem = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/batch.mp3"),
            status: .succeeded,
            result: batchResult
        )

        appState.routeToBatchItemResult(batchItem)
        XCTAssertEqual(appState.selectedBatchItemID, batchItem.id)

        let singleResult = makeSampleResult(text: "Single file text")
        let singleDisplayed = DisplayedTranscription(
            result: singleResult,
            provenance: ExecutionProvenance(
                sourceURL: URL(fileURLWithPath: "/tmp/single.mp3"),
                modelName: "base",
                engineID: "whisper-local"
            )
        )

        appState.setDisplayedTranscription(singleDisplayed)

        XCTAssertNil(appState.selectedBatchItemID)
        XCTAssertEqual(appState.displayedTranscription?.result.fullText, "Single file text")
    }

    // MARK: - BatchItemRow UI Interaction & Highlighting

    func testBatchItemRowSelectionCallbackOnSucceededItem() {
        let result = makeSampleResult()
        let item = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            status: .succeeded,
            result: result
        )

        var selected = false
        let row = BatchItemRow(
            item: item,
            isSelected: false,
            onSelect: { selected = true }
        )

        XCTAssertFalse(row.isSelected)
        row.onSelect?()
        XCTAssertTrue(selected)
    }

    func testBatchItemRowSelectedHighlightState() {
        let result = makeSampleResult()
        let item = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            status: .succeeded,
            result: result
        )

        let row = BatchItemRow(
            item: item,
            isSelected: true,
            onSelect: {}
        )

        XCTAssertTrue(row.isSelected)
    }

    // MARK: - D010 Invariant Respect (Read-Only Inspection)

    func testResultsRoutingDoesNotMutateBatchViewModelOrViolateD010() {
        let appState = AppState()
        let batchVM = BatchTranscriptionViewModel()
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let item = BatchItem(
            id: UUID(),
            sourceURL: tempDir.appendingPathComponent("audio1.wav"),
            status: .succeeded,
            result: makeSampleResult()
        )

        batchVM.ingestResult(BatchIngestionResult(source: .folder(tempDir), items: [item]))
        XCTAssertFalse(batchVM.isBusy)

        // Route to result
        appState.routeToBatchItemResult(item, modelName: batchVM.configuration.modelName)

        // Verify AppState transitioned
        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertEqual(appState.selectedBatchItemID, item.id)

        // Verify Batch VM state is completely undisturbed
        XCTAssertFalse(batchVM.isBusy)
        XCTAssertEqual(batchVM.itemCount, 1)
        XCTAssertEqual(batchVM.items.first?.id, item.id)
    }

    // MARK: - Live Coordinator Updates Integration

    func testLiveCoordinatorEventUpdatesAndRouting() async {
        let appState = AppState()
        let item1 = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/test1.mp3")
        )
        let item2 = BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/test2.mp3")
        )

        let result1 = makeSampleResult(text: "Result 1")
        let result2 = makeSampleResult(text: "Result 2")

        let mockCoordinator = MockBatchCoordinator(
            processHandler: { items, _, _, onItemUpdated in
                var processed: [BatchItem] = []
                for (idx, itm) in items.enumerated() {
                    var updated = itm
                    updated.status = .succeeded
                    updated.progress = 1.0
                    updated.result = idx == 0 ? result1 : result2
                    onItemUpdated?(updated)
                    processed.append(updated)
                }
                return processed
            }
        )

        let batchVM = BatchTranscriptionViewModel(coordinator: mockCoordinator)
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        batchVM.ingestResult(BatchIngestionResult(source: .folder(tempDir), items: [item1, item2]))

        batchVM.start()

        // Wait for batch processing to complete
        let deadline = Date().addingTimeInterval(2.0)
        while batchVM.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(batchVM.isBusy)
        XCTAssertEqual(batchVM.summary.succeededCount, 2)

        // Select item 1
        let completedItem1 = batchVM.items[0]
        appState.routeToBatchItemResult(completedItem1, modelName: batchVM.configuration.modelName)
        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertEqual(appState.selectedBatchItemID, completedItem1.id)
        XCTAssertEqual(appState.displayedTranscription?.result.fullText, "Result 1")

        // Select item 2
        let completedItem2 = batchVM.items[1]
        appState.routeToBatchItemResult(completedItem2, modelName: batchVM.configuration.modelName)
        XCTAssertEqual(appState.selectedNavigationItem, .results)
        XCTAssertEqual(appState.selectedBatchItemID, completedItem2.id)
        XCTAssertEqual(appState.displayedTranscription?.result.fullText, "Result 2")
    }
}

// MARK: - Mock Batch Coordinator

private final class MockBatchCoordinator: BatchTranscriptionCoordinatorProtocol, @unchecked Sendable {
    private let processHandler: @Sendable ([BatchItem], URL?, BatchTranscriptionConfiguration, (@Sendable (BatchItem) -> Void)?) async -> [BatchItem]

    init(
        processHandler: @escaping @Sendable ([BatchItem], URL?, BatchTranscriptionConfiguration, (@Sendable (BatchItem) -> Void)?) async -> [BatchItem]
    ) {
        self.processHandler = processHandler
    }

    func cancel() async {}
    func resetCancellation() async {}

    func processBatch(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> [BatchItem] {
        await processHandler(items, destinationDirectory, configuration, onItemUpdated)
    }

    func processBatchWithSummary(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> BatchTranscriptionProcessResult {
        let processed = await processHandler(items, destinationDirectory, configuration, onItemUpdated)
        return BatchTranscriptionProcessResult(items: processed, summary: BatchTranscriptionSummary(items: processed))
    }
}
