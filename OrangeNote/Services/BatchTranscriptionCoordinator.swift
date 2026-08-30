//
//  BatchTranscriptionCoordinator.swift
//  OrangeNote
//
//  Coordinates sequential batch transcription of audio files (Task 3.8 / D015),
//  managing lifecycle transitions, output persistence via AtomicFileWriter,
//  error isolation and continuation (Task 3.9 / D016), and stop-after-current
//  cancellation (Task 3.10 / D021, D022).
//

import Foundation

/// Configuration options for a batch transcription run.
struct BatchTranscriptionConfiguration: Sendable, Equatable {
    /// The model name/identifier to use for transcription (e.g. "base", "small").
    var modelName: String

    /// The language code (e.g. "en", "ru") or `nil` for auto-detection.
    var language: String?

    /// Whether transcription output should be translated to English.
    var translateToEnglish: Bool

    /// Whether chunked processing should be used for long audio files.
    var chunkingEnabled: Bool

    /// Duration of each chunk in seconds when chunking is enabled.
    var chunkDurationSeconds: Double?

    /// Overlap duration between chunks in seconds when chunking is enabled.
    var overlapDurationSeconds: Double?

    /// Whether to embed the full source path in the Canonical JSON document (defaults to `false` for privacy).
    var includeSourcePathInCanonicalDocument: Bool

    init(
        modelName: String = "base",
        language: String? = nil,
        translateToEnglish: Bool = false,
        chunkingEnabled: Bool = false,
        chunkDurationSeconds: Double? = nil,
        overlapDurationSeconds: Double? = nil,
        includeSourcePathInCanonicalDocument: Bool = false
    ) {
        self.modelName = modelName
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.chunkingEnabled = chunkingEnabled
        self.chunkDurationSeconds = chunkDurationSeconds
        self.overlapDurationSeconds = overlapDurationSeconds
        self.includeSourcePathInCanonicalDocument = includeSourcePathInCanonicalDocument
    }
}

/// The result of executing a batch transcription run, pairing processed items with their aggregated summary.
struct BatchTranscriptionProcessResult: Sendable, Equatable {
    /// The final array of processed `BatchItem`s in original queue order.
    let items: [BatchItem]

    /// Aggregated summary counts and metrics for this batch run.
    let summary: BatchTranscriptionSummary

    init(items: [BatchItem], summary: BatchTranscriptionSummary? = nil) {
        self.items = items
        self.summary = summary ?? BatchTranscriptionSummary(items: items)
    }
}

/// Actor that coordinates sequential transcription of a queue of `BatchItem`s.
///
/// Guarantees:
/// 1. **Sequential Execution**: Audio files are processed strictly sequentially, one at a time (D015).
/// 2. **Lifecycle Transitions**: Follows `queued` → `transcribing` → `saving` → `succeeded`/`failed`/`skipped`/`cancelled` (D019).
/// 3. **Non-Overwriting Persistence**: Existing output files are skipped without overwriting (D018) and saved atomically via `AtomicFileWriter` (D018).
/// 4. **Continue-on-Failure**: Individual file failures do not abort the batch (D016); errors are recorded per item and the queue proceeds.
/// 5. **Stop-After-Current Cancellation**: Cooperative cancellation (D021) lets the currently active item complete its transcription and atomic save, while marking all remaining queued items as `.cancelled`.
/// 6. **File Retention**: All successfully written output files are preserved on disk and never deleted upon cancellation (D022).
/// Protocol defining the interface for batch transcription coordination,
/// allowing dependency injection and mocking in unit tests (Task 3.15).
protocol BatchTranscriptionCoordinatorProtocol: Sendable {
    /// Requests cooperative stop-after-current cancellation (D021).
    func cancel() async

    /// Resets the cancellation flag.
    func resetCancellation() async

    /// Processes an array of batch items sequentially.
    func processBatch(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> [BatchItem]

    /// Processes an array of batch items and returns both processed items and their summary.
    func processBatchWithSummary(
        items: [BatchItem],
        destinationDirectory: URL?,
        configuration: BatchTranscriptionConfiguration,
        onItemUpdated: (@Sendable (BatchItem) -> Void)?
    ) async -> BatchTranscriptionProcessResult
}

extension BatchTranscriptionCoordinatorProtocol {
    func processBatch(
        items: [BatchItem],
        destinationDirectory: URL? = nil,
        configuration: BatchTranscriptionConfiguration = BatchTranscriptionConfiguration(),
        onItemUpdated: (@Sendable (BatchItem) -> Void)? = nil
    ) async -> [BatchItem] {
        await processBatch(
            items: items,
            destinationDirectory: destinationDirectory,
            configuration: configuration,
            onItemUpdated: onItemUpdated
        )
    }

    func processBatchWithSummary(
        items: [BatchItem],
        destinationDirectory: URL? = nil,
        configuration: BatchTranscriptionConfiguration = BatchTranscriptionConfiguration(),
        onItemUpdated: (@Sendable (BatchItem) -> Void)? = nil
    ) async -> BatchTranscriptionProcessResult {
        await processBatchWithSummary(
            items: items,
            destinationDirectory: destinationDirectory,
            configuration: configuration,
            onItemUpdated: onItemUpdated
        )
    }
}

actor BatchTranscriptionCoordinator {
    private let engine: TranscriptionEngineProtocol
    private let fileManager: FileManager

    /// Whether cancellation has been requested on this coordinator.
    private(set) var isCancelled: Bool = false

    /// Initializes the coordinator with a transcription engine and file manager.
    ///
    /// - Parameters:
    ///   - engine: The transcription engine conforming to `TranscriptionEngineProtocol` (defaults to `WhisperTranscriptionEngine()`).
    ///   - fileManager: The file manager used for file existence checks and atomic writes (defaults to `.default`).
    init(
        engine: TranscriptionEngineProtocol = WhisperTranscriptionEngine(),
        fileManager: FileManager = .default
    ) {
        self.engine = engine
        self.fileManager = fileManager
    }

    /// Requests cooperative stop-after-current cancellation of the batch operation (D021).
    ///
    /// This method is safe and idempotent:
    /// - If a transcription job is currently in flight, that active item completes its transcription
    ///   and atomic save before the coordinator halts.
    /// - All subsequent unprocessed queued items are marked as `.cancelled` with zero progress.
    /// - All previously or newly written output files are retained on disk (D022).
    /// - Calling `cancel()` repeatedly has no adverse side-effects.
    func cancel() {
        isCancelled = true
    }

    /// Resets the cancellation flag so this coordinator instance can be reused for subsequent batch runs.
    func resetCancellation() {
        isCancelled = false
    }

    /// Processes an array of `BatchItem`s sequentially, continuing on individual item failures (D016)
    /// and respecting stop-after-current cancellation (D021, D022).
    ///
    /// - Parameters:
    ///   - items: The batch items to process in queue order.
    ///   - destinationDirectory: Optional destination directory for JSON outputs (if an item lacks an `outputURL`).
    ///   - configuration: The transcription settings to use for this batch.
    ///   - onItemUpdated: Invoked whenever an item's status, progress, result, or error changes.
    /// - Returns: The final array of processed `BatchItem`s in original queue order.
    func processBatch(
        items: [BatchItem],
        destinationDirectory: URL? = nil,
        configuration: BatchTranscriptionConfiguration = BatchTranscriptionConfiguration(),
        onItemUpdated: (@Sendable (BatchItem) -> Void)? = nil
    ) async -> [BatchItem] {
        var processedItems: [BatchItem] = []

        for (index, item) in items.enumerated() {
            var currentItem = item

            // Resolve output URL if not already assigned
            if currentItem.outputURL == nil, let destinationDirectory {
                currentItem.outputURL = BatchOutputPlanner.computeOutputURL(
                    for: currentItem.sourceURL,
                    in: destinationDirectory
                )
            }

            // If item was already skipped, cancelled, succeeded, or failed, keep it as-is
            if currentItem.status == .skipped || currentItem.status == .cancelled || currentItem.status == .succeeded || currentItem.status == .failed {
                onItemUpdated?(currentItem)
                processedItems.append(currentItem)
                continue
            }

            // Check cancellation before starting a queued item (D021)
            if isCancelled || Task.isCancelled {
                isCancelled = true
                // Mark this and all remaining unprocessed items as cancelled
                currentItem.status = .cancelled
                currentItem.progress = 0.0
                currentItem.errorMessage = nil
                onItemUpdated?(currentItem)
                processedItems.append(currentItem)

                for remainingIndex in (index + 1)..<items.count {
                    var remainingItem = items[remainingIndex]
                    if remainingItem.outputURL == nil, let destinationDirectory {
                        remainingItem.outputURL = BatchOutputPlanner.computeOutputURL(
                            for: remainingItem.sourceURL,
                            in: destinationDirectory
                        )
                    }
                    if remainingItem.status == .queued {
                        remainingItem.status = .cancelled
                        remainingItem.progress = 0.0
                        remainingItem.errorMessage = nil
                    }
                    onItemUpdated?(remainingItem)
                    processedItems.append(remainingItem)
                }
                break
            }

            // Check if output file already exists on disk (D018)
            if let outputURL = currentItem.outputURL, fileManager.fileExists(atPath: outputURL.path) {
                currentItem.status = .skipped
                currentItem.progress = 1.0
                currentItem.errorMessage = nil
                onItemUpdated?(currentItem)
                processedItems.append(currentItem)
                continue
            }

            // Verify that we have a destination URL to write to
            guard let outputURL = currentItem.outputURL else {
                currentItem.status = .failed
                currentItem.progress = 0.0
                currentItem.result = nil
                currentItem.errorMessage = "Missing destination directory or output URL"
                onItemUpdated?(currentItem)
                processedItems.append(currentItem)
                continue
            }

            // Step 1: Transcribing
            currentItem.status = .transcribing
            currentItem.progress = 0.0
            currentItem.errorMessage = nil
            currentItem.result = nil
            onItemUpdated?(currentItem)

            let request = TranscriptionRequest(
                sourceURL: currentItem.sourceURL,
                modelName: configuration.modelName,
                language: configuration.language,
                translateToEnglish: configuration.translateToEnglish,
                chunkingEnabled: configuration.chunkingEnabled,
                chunkDurationSeconds: configuration.chunkDurationSeconds,
                overlapDurationSeconds: configuration.overlapDurationSeconds
            )

            let snapshotForProgress = currentItem
            let transcriptionResult: TranscriptionResult
            do {
                transcriptionResult = try await engine.transcribe(request: request) { [onItemUpdated] progress in
                    var progressItem = snapshotForProgress
                    progressItem.status = .transcribing
                    progressItem.progress = progress
                    onItemUpdated?(progressItem)
                }
            } catch {
                // Per D016: record failure status and continue with remaining queue items
                currentItem.status = .failed
                currentItem.progress = 0.0
                currentItem.result = nil
                currentItem.errorMessage = error.localizedDescription
                onItemUpdated?(currentItem)
                processedItems.append(currentItem)
                continue
            }

            // Step 2: Saving (atomic persistence)
            currentItem.result = transcriptionResult
            currentItem.status = .saving
            currentItem.progress = 1.0
            onItemUpdated?(currentItem)

            do {
                let document = try CanonicalTranscriptionSerializer.makeDocument(
                    from: transcriptionResult,
                    sourceFileName: currentItem.sourceURL.lastPathComponent,
                    sourceURL: currentItem.sourceURL,
                    modelName: configuration.modelName,
                    engineID: engine.engineID,
                    includeSourcePath: configuration.includeSourcePathInCanonicalDocument
                )

                let writeResult = try AtomicFileWriter.write(
                    document: document,
                    to: outputURL,
                    fileManager: fileManager
                )

                switch writeResult {
                case .written(let writtenURL):
                    currentItem.status = .succeeded
                    currentItem.outputURL = writtenURL
                    currentItem.errorMessage = nil
                case .skippedAlreadyExists(let existingURL):
                    currentItem.status = .skipped
                    currentItem.outputURL = existingURL
                    currentItem.errorMessage = nil
                }
            } catch {
                // Per D016: persistence error is captured on item, does not abort batch
                currentItem.status = .failed
                currentItem.progress = 0.0
                currentItem.errorMessage = error.localizedDescription
            }

            onItemUpdated?(currentItem)
            processedItems.append(currentItem)
        }

        return processedItems
    }

    /// Processes an array of `BatchItem`s sequentially and returns both processed items and their summary.
    ///
    /// - Parameters:
    ///   - items: The batch items to process.
    ///   - destinationDirectory: Optional destination directory for JSON outputs (if an item lacks an `outputURL`).
    ///   - configuration: The transcription settings to use for this batch.
    ///   - onItemUpdated: Invoked whenever an item's status, progress, result, or error changes.
    /// - Returns: A `BatchTranscriptionProcessResult` containing the processed items and the aggregated summary.
    func processBatchWithSummary(
        items: [BatchItem],
        destinationDirectory: URL? = nil,
        configuration: BatchTranscriptionConfiguration = BatchTranscriptionConfiguration(),
        onItemUpdated: (@Sendable (BatchItem) -> Void)? = nil
    ) async -> BatchTranscriptionProcessResult {
        let processedItems = await processBatch(
            items: items,
            destinationDirectory: destinationDirectory,
            configuration: configuration,
            onItemUpdated: onItemUpdated
        )
        return BatchTranscriptionProcessResult(items: processedItems)
    }
}


extension BatchTranscriptionCoordinator: BatchTranscriptionCoordinatorProtocol {}
