//
//  BatchTranscriptionViewModel.swift
//  OrangeNote
//
//  View model managing the in-memory batch transcription queue, output directory resolution,
//  progress tracking, lifecycle coordination, and live per-item updates (Task 3.15 / D010 / D015–D023).
//

import Foundation
import SwiftUI

/// Conceptual lifecycle state of the batch transcription workflow.
enum BatchLifecycleState: Equatable, Sendable {
    /// No items loaded in the batch queue.
    case empty
    /// Batch queue is populated and ready for execution.
    case ready
    /// Batch transcription is actively running.
    case running
    /// Cancellation has been requested and the batch is draining the active item (stop-after-current, D021).
    case cancelling
    /// Batch transcription has completed (all items have reached a terminal state).
    case completed
}

/// View model driving the batch transcription UI and orchestrating batch operations.
@MainActor
final class BatchTranscriptionViewModel: ObservableObject {

    // MARK: - Published State

    /// In-memory queue of batch items (D019).
    @Published private(set) var items: [BatchItem] = []

    /// The source that populated the current batch items.
    @Published private(set) var inputSource: BatchInputSource = .empty

    /// The destination directory URL where canonical JSON documents will be written (D017).
    @Published private(set) var outputDirectory: URL?

    /// The resolution origin of `outputDirectory` (user override, source folder, system default, or custom).
    @Published private(set) var outputResolutionSource: BatchOutputPolicyResolutionSource?

    /// Whether batch processing is actively running.
    @Published private(set) var isRunning: Bool = false

    /// Whether cancellation has been requested and the batch is draining the active item (D021).
    @Published private(set) var isCancelling: Bool = false

    /// Overall progress across all items in the queue (0.0...1.0).
    @Published private(set) var overallProgress: Float = 0.0

    /// Index of the item currently being processed (transcribing or saving), or `nil` if idle.
    @Published private(set) var activeIndex: Int?

    /// UUID of the item currently being processed, or `nil` if idle.
    @Published private(set) var activeItemID: UUID?

    /// Aggregated execution summary of items in the queue (Task 3.9 / D016).
    @Published private(set) var summary: BatchTranscriptionSummary = BatchTranscriptionSummary(items: [])

    /// User-facing error message, if any.
    @Published private(set) var errorMessage: String?

    /// Current status message for UI display.
    @Published private(set) var statusMessage: String = L10n.localizedString("status.ready")

    /// Active transcription configuration settings (model, language, chunking, etc.).
    @Published var configuration: BatchTranscriptionConfiguration = BatchTranscriptionConfiguration()

    // MARK: - Lifecycle & Convenience Projections

    /// Current conceptual lifecycle state of the batch.
    var lifecycleState: BatchLifecycleState {
        if isCancelling {
            return .cancelling
        }
        if isRunning {
            return .running
        }
        if items.isEmpty {
            return .empty
        }
        if summary.completedCount == items.count && items.count > 0 {
            return .completed
        }
        return .ready
    }

    /// Whether the view model is currently busy (running or cancelling).
    var isBusy: Bool {
        isRunning || isCancelling
    }

    /// Whether the batch can be started.
    var canStart: Bool {
        !isBusy && !items.isEmpty && outputDirectory != nil && (isSingleFileBusy?() != true)
    }

    /// Whether there are items in the queue.
    var hasItems: Bool {
        !items.isEmpty
    }

    /// Total number of items in the queue.
    var itemCount: Int {
        items.count
    }

    /// Recomputes localized status message upon application language changes.
    func refreshLocalization() {
        switch lifecycleState {
        case .empty:
            statusMessage = L10n.localizedString("status.ready")
        case .ready:
            statusMessage = String(format: L10n.localizedString("batch.status.queued"), items.count)
        case .running:
            if let index = activeIndex, index < items.count {
                statusMessage = String(
                    format: L10n.localizedString("batch.status.runningItem"),
                    index + 1,
                    items.count,
                    items[index].sourceURL.lastPathComponent
                )
            } else {
                statusMessage = String(format: L10n.localizedString("batch.status.queued"), items.count)
            }
        case .cancelling:
            statusMessage = L10n.localizedString("batch.status.cancelling")
        case .completed:
            statusMessage = String(
                format: L10n.localizedString("batch.status.completed"),
                summary.succeededCount,
                summary.totalCount
            )
        }
    }

    // MARK: - Dependencies & Private State

    private let coordinator: BatchTranscriptionCoordinatorProtocol
    private let outputPolicy: BatchOutputPolicy
    private let documentPickerHelper: DocumentPickerHelper
    private let fileManager: FileManager
    private let isSingleFileBusy: (() -> Bool)?

    /// Security-scoped token held in memory for single-folder batch ingestion (D023).
    private var activeSecurityScopeToken: SecurityScopeToken?

    /// Active background execution task.
    private var activeExecutionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        coordinator: BatchTranscriptionCoordinatorProtocol = BatchTranscriptionCoordinator(),
        outputPolicy: BatchOutputPolicy = BatchOutputPolicy(),
        documentPickerHelper: DocumentPickerHelper? = nil,
        fileManager: FileManager = .default,
        isSingleFileBusy: (() -> Bool)? = nil
    ) {
        self.coordinator = coordinator
        self.outputPolicy = outputPolicy
        self.documentPickerHelper = documentPickerHelper ?? DocumentPickerHelper(outputPolicy: outputPolicy)
        self.fileManager = fileManager
        self.isSingleFileBusy = isSingleFileBusy
    }

    deinit {
        activeExecutionTask?.cancel()
    }

    // MARK: - Ingestion Commands

    /// Ingests an array of candidate file URLs into the batch queue.
    ///
    /// Filters, deduplicates, and sorts audio files via `BatchFileCollector` (Tasks 3.3–3.5),
    /// resolves the destination output directory via `BatchOutputPolicy` (Task 3.12),
    /// and plans initial output paths via `BatchOutputPlanner` (Task 3.6 / D017 / D018).
    ///
    /// - Parameter urls: Candidate file URLs.
    func ingestFiles(_ urls: [URL]) {
        guard !isBusy else {
            errorMessage = L10n.localizedString("error.dropRejectedTranscribing")
            return
        }
        let result = DocumentPickerHelper.processFiles(urls)
        applyIngestionResult(result)
    }

    /// Ingests a single top-level folder for batch processing (non-recursive, D020).
    ///
    /// Scans top-level audio files, acquires memory-held security scope (D023),
    /// resolves output directory (defaulting to the source folder), and plans output paths.
    ///
    /// - Parameter folderURL: The folder URL to ingest.
    func ingestFolder(_ folderURL: URL) {
        guard !isBusy else {
            errorMessage = L10n.localizedString("error.dropRejectedTranscribing")
            return
        }
        let result = DocumentPickerHelper.processFolder(folderURL)
        applyIngestionResult(result)
    }

    /// Ingests a pre-constructed `BatchIngestionResult` (e.g. from `DropItemResolver` or `DocumentPickerHelper`).
    ///
    /// - Parameter result: The ingestion result to apply.
    func ingestResult(_ result: BatchIngestionResult) {
        guard !isBusy else {
            errorMessage = L10n.localizedString("error.dropRejectedTranscribing")
            return
        }
        applyIngestionResult(result)
    }

    /// Prompts the user to pick multiple audio files and ingests them into the batch queue.
    func promptAndIngestFiles() async {
        guard !isBusy else { return }
        if let result = await documentPickerHelper.promptAndIngestMultipleFiles() {
            applyIngestionResult(result)
        }
    }

    /// Prompts the user to pick a folder and ingests its top-level audio files into the batch queue.
    func promptAndIngestFolder() async {
        guard !isBusy else { return }
        if let result = await documentPickerHelper.promptAndIngestFolder() {
            applyIngestionResult(result)
        }
    }

    // MARK: - Output Directory Commands

    /// Sets an explicit output destination directory, validates it, and replans output paths.
    ///
    /// - Parameter url: The chosen destination directory URL.
    func setOutputDirectory(_ url: URL) {
        guard !isBusy else { return }
        switch outputPolicy.validateDirectory(url) {
        case .success(let validatedURL):
            outputDirectory = validatedURL
            outputResolutionSource = .custom
            errorMessage = nil
            items = BatchOutputPlanner.plan(items: items, destinationDirectory: validatedURL, fileManager: fileManager)
            summary = BatchTranscriptionSummary(items: items)
            recalculateOverallProgress()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Prompts the user to pick an output directory override and applies it.
    func promptAndSelectOutputDirectory() async {
        guard !isBusy else { return }
        do {
            if let savedURL = try await documentPickerHelper.promptAndSelectOutputDirectory() {
                outputDirectory = savedURL
                outputResolutionSource = .userOverride
                errorMessage = nil
                items = BatchOutputPlanner.plan(items: items, destinationDirectory: savedURL, fileManager: fileManager)
                summary = BatchTranscriptionSummary(items: items)
                recalculateOverallProgress()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Execution Lifecycle Commands

    /// Initiates sequential batch transcription execution (Tasks 3.8–3.10 / D015 / D016 / D021).
    func start() {
        startBatch()
    }

    /// Initiates sequential batch transcription execution (alias for `start()`).
    func startBatch() {
        guard !isBusy else { return }

        // D010: Reject batch execution if single-file transcription is active
        if let isSingleFileBusy, isSingleFileBusy() {
            errorMessage = L10n.localizedString("batch.error.singleFileBusy")
            return
        }

        guard !items.isEmpty else {
            errorMessage = L10n.localizedString("batch.error.emptyQueue")
            return
        }

        guard let targetOutputDirectory = outputDirectory else {
            errorMessage = L10n.localizedString("batch.error.noOutputDirectory")
            return
        }

        // Validate output directory before starting
        switch outputPolicy.validateDirectory(targetOutputDirectory) {
        case .success(let validatedDir):
            self.outputDirectory = validatedDir
        case .failure(let error):
            self.errorMessage = error.localizedDescription
            return
        }

        // Replan items before execution to capture newly created files on disk
        items = BatchOutputPlanner.plan(items: items, destinationDirectory: targetOutputDirectory, fileManager: fileManager)
        summary = BatchTranscriptionSummary(items: items)

        // Check if all items are already skipped or terminal
        let allTerminal = items.allSatisfy { item in
            item.status == .skipped || item.status == .succeeded || item.status == .failed || item.status == .cancelled
        }
        if allTerminal {
            overallProgress = 1.0
            statusMessage = String(
                format: L10n.localizedString("batch.status.completed"),
                summary.succeededCount,
                summary.totalCount
            )
            return
        }

        isRunning = true
        isCancelling = false
        errorMessage = nil
        recalculateOverallProgress()

        let itemsToProcess = items
        let destinationDir = targetOutputDirectory
        let currentConfig = configuration

        activeExecutionTask = Task { [weak self, coordinator] in
            await coordinator.resetCancellation()

            let result = await coordinator.processBatchWithSummary(
                items: itemsToProcess,
                destinationDirectory: destinationDir,
                configuration: currentConfig,
                onItemUpdated: { [weak self] updatedItem in
                    Task { @MainActor [weak self] in
                        self?.handleItemUpdated(updatedItem)
                    }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.handleBatchCompleted(result)
            }
        }
    }

    /// Requests cooperative stop-after-current cancellation of the active batch run (D021).
    func cancel() {
        cancelBatch()
    }

    /// Requests cooperative stop-after-current cancellation of the active batch run (alias for `cancel()`).
    func cancelBatch() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        statusMessage = L10n.localizedString("batch.status.cancelling")
        activeExecutionTask?.cancel()
        Task { [coordinator] in
            await coordinator.cancel()
        }
    }

    /// Clears the batch queue, releasing held security scopes and resetting progress.
    func clear() {
        clearQueue()
    }

    /// Clears the batch queue (alias for `clear()`).
    func clearQueue() {
        guard !isBusy else { return }
        items.removeAll()
        inputSource = .empty
        overallProgress = 0.0
        activeIndex = nil
        activeItemID = nil
        summary = BatchTranscriptionSummary(items: [])
        errorMessage = nil
        activeSecurityScopeToken = nil
        statusMessage = L10n.localizedString("status.ready")
    }

    /// Removes an individual item from the batch queue by its UUID.
    ///
    /// - Parameter id: The UUID of the item to remove.
    func removeItem(id: UUID) {
        guard !isBusy else { return }
        items.removeAll(where: { $0.id == id })
        summary = BatchTranscriptionSummary(items: items)
        recalculateOverallProgress()
        if items.isEmpty {
            statusMessage = L10n.localizedString("status.ready")
        }
    }

    /// Removes items at the specified offsets from the batch queue.
    ///
    /// - Parameter indexSet: Offsets to remove.
    func removeItems(at indexSet: IndexSet) {
        guard !isBusy else { return }
        items.remove(atOffsets: indexSet)
        summary = BatchTranscriptionSummary(items: items)
        recalculateOverallProgress()
        if items.isEmpty {
            statusMessage = L10n.localizedString("status.ready")
        }
    }

    /// Dismisses any active user-facing error message.
    func dismissError() {
        errorMessage = nil
    }

    /// Updates the transcription configuration settings.
    ///
    /// - Parameter config: The new configuration.
    func updateConfiguration(_ config: BatchTranscriptionConfiguration) {
        guard !isBusy else { return }
        self.configuration = config
    }

    // MARK: - Private Coordination Helpers

    /// Applies an ingestion result to the queue, resolving output policy and planning paths.
    private func applyIngestionResult(_ result: BatchIngestionResult) {
        activeSecurityScopeToken = result.securityToken
        inputSource = result.source
        errorMessage = nil
        activeIndex = nil
        activeItemID = nil
        overallProgress = 0.0

        let resolution = outputPolicy.resolveOutputDirectory(for: result.source)
        switch resolution {
        case .success(let res):
            outputDirectory = res.url
            outputResolutionSource = res.source
            items = BatchOutputPlanner.plan(items: result.items, destinationDirectory: res.url, fileManager: fileManager)
        case .failure(let error):
            outputDirectory = nil
            outputResolutionSource = nil
            items = result.items
            errorMessage = error.localizedDescription
        }

        summary = BatchTranscriptionSummary(items: items)
        if items.isEmpty {
            statusMessage = L10n.localizedString("status.ready")
        } else {
            statusMessage = String(format: L10n.localizedString("batch.status.queued"), items.count)
        }
        recalculateOverallProgress()
    }

    /// Live callback handler invoked when an individual batch item is updated during processing.
    private func handleItemUpdated(_ updatedItem: BatchItem) {
        guard let index = items.firstIndex(where: { $0.id == updatedItem.id }) else {
            return
        }
        items[index] = updatedItem

        if updatedItem.status == .transcribing || updatedItem.status == .saving {
            activeIndex = index
            activeItemID = updatedItem.id
            statusMessage = String(
                format: L10n.localizedString("batch.status.runningItem"),
                index + 1,
                items.count,
                updatedItem.sourceURL.lastPathComponent
            )
        }

        summary = BatchTranscriptionSummary(items: items)
        recalculateOverallProgress()
    }

    /// Terminal completion handler invoked when coordinator finishes the batch run.
    private func handleBatchCompleted(_ result: BatchTranscriptionProcessResult) {
        self.items = result.items
        self.summary = result.summary
        self.isRunning = false
        self.activeIndex = nil
        self.activeItemID = nil
        self.activeExecutionTask = nil

        recalculateOverallProgress()

        if self.isCancelling || result.items.contains(where: { $0.status == .cancelled }) {
            self.isCancelling = false
            self.statusMessage = L10n.localizedString("batch.status.cancelled")
        } else {
            self.isCancelling = false
            self.overallProgress = 1.0
            self.statusMessage = String(
                format: L10n.localizedString("batch.status.completed"),
                summary.succeededCount,
                summary.totalCount
            )
        }
    }

    /// Computes the overall progress as a continuous value in `0.0...1.0`.
    private func recalculateOverallProgress() {
        guard !items.isEmpty else {
            overallProgress = 0.0
            return
        }

        var totalScore: Float = 0.0
        for item in items {
            switch item.status {
            case .succeeded, .skipped, .failed, .cancelled:
                totalScore += 1.0
            case .transcribing:
                totalScore += max(0.0, min(1.0, item.progress))
            case .saving:
                totalScore += 1.0
            case .queued:
                totalScore += 0.0
            }
        }

        overallProgress = min(1.0, max(0.0, totalScore / Float(items.count)))
    }
}
