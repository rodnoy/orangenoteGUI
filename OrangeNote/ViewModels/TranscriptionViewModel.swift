//
//  TranscriptionViewModel.swift
//  OrangeNote
//
//  Main view model for file selection, transcription control, and progress tracking.
//

import SwiftUI
import UniformTypeIdentifiers

/// Conceptual lifecycle states for the single-file transcription workflow.
///
/// This enum models the 5 states a single transcription session can be in. It is kept
/// internal to the view model; consumers continue to read the synchronized `@Published`
/// convenience properties below. The `jobID` associated value on `.running` is used to
/// guard asynchronous FFI completion callbacks against stale events (see `isActiveJob(_:)`).
enum TranscriptionLifecycleState: Equatable {
    case empty
    case ready(file: URL)
    case running(file: URL, jobID: UUID)
    case completed(file: URL, result: TranscriptionResult)
    case completedImported(result: TranscriptionResult)
    case failed(file: URL, error: String)

    /// The `jobID` associated with `.running`, or `nil` for any other state.
    var activeJobID: UUID? {
        if case .running(_, let jobID) = self {
            return jobID
        }
        return nil
    }
}

/// Manages the transcription workflow: file selection, transcription execution, and results.
@MainActor
final class TranscriptionViewModel: ObservableObject {
    // MARK: - Lifecycle State

    /// The current conceptual lifecycle state. All `@Published` convenience properties
    /// below are kept in sync whenever this state changes.
    @Published private(set) var state: TranscriptionLifecycleState = .empty {
        didSet { syncPublishedProperties() }
    }

    // MARK: - Published State

    /// URL of the selected audio file.
    ///
    /// Read-only projection (`private(set)`) synchronized exclusively from `state` (see
    /// `syncPublishedProperties()`). External code must route file changes through
    /// `selectFile()` / `handleDroppedFile(_:)` rather than assigning this property
    /// directly, preventing desynchronization from the authoritative lifecycle `state`.
    @Published private(set) var selectedFileURL: URL?

    /// Whether a transcription is currently in progress.
    @Published private(set) var isTranscribing: Bool = false

    /// Transcription progress (0.0–1.0).
    @Published private(set) var progress: Float = 0.0

    /// The transcription result, available after successful completion.
    @Published private(set) var result: TranscriptionResult?

    /// Error message to display to the user.
    @Published private(set) var errorMessage: String?

    /// Current status message.
    @Published private(set) var statusMessage: String = L10n.localizedString("status.ready")

    /// Whether a native Whisper FFI call is currently executing on a background thread.
    ///
    /// Distinct from `isTranscribing`: `isTranscribing` reflects the *logical* lifecycle
    /// state (`.running`), which can be exited immediately on cancellation (see D011).
    /// `isNativeBusy` tracks whether the blocking Rust FFI call itself has actually
    /// returned yet, since Swift `Task.cancel()` does not interrupt it. This guard ensures
    /// at most one native Whisper operation executes at any time, even across a logical
    /// cancellation, by blocking new starts and file/drop changes until the background
    /// thread drains.
    @Published private(set) var isNativeBusy: Bool = false

    /// Whether the user has requested cancellation while the native FFI call is still
    /// draining (`isNativeBusy == true`). Used to present truthful "cancelling…" status
    /// messaging until the background thread actually returns.
    @Published private(set) var isCancelling: Bool = false

    /// Execution provenance (source file, model, engine) for the current/most recent
    /// transcription run, tracked separately from the domain `TranscriptionResult`
    /// (Task 2.13 / Finding B3). `nil` when no local transcription has been run yet
    /// for the current lifecycle state (e.g. `.empty`, `.ready`, or an imported result),
    /// so consumers never fabricate fake source metadata.
    ///
    /// Job-owned (Task 2.20 / Finding F2): every write to this property is paired with
    /// `runningJobID` recording which `jobID` it belongs to (`nil` once no job owns it).
    /// Every terminal transition of that job — success, failure, cancellation, or being
    /// superseded by a new job/file selection/import — clears both together, so this can
    /// never be observed holding a stale, superseded job's provenance (the specific gap
    /// this task closes: the failure path previously left this untouched).
    @Published private(set) var executionProvenance: ExecutionProvenance?

    /// The `jobID` that `executionProvenance` currently belongs to, if any (Task 2.20 /
    /// Finding F2). `nil` whenever `executionProvenance` is `nil` or belongs to an
    /// import (which has no running job).
    private var runningJobID: UUID?

    /// Atomic pairing of `result` and `executionProvenance` at the moment a transcription
    /// (local run or import) successfully completes (Task 2.16 / Finding R2).
    ///
    /// Unlike `result`/`executionProvenance` — separate `@Published` properties that
    /// SwiftUI publishes as independent events — this property is set exactly once per
    /// completion transition inside `syncPublishedProperties()`, alongside `result` and
    /// reading the already-consistent `executionProvenance` for that same job/import in
    /// the same synchronous update. Consumers that need the result and its provenance
    /// together for export/UI presentation (`ContentView`, `AppState`) should read this
    /// property rather than combining `result` and `executionProvenance` separately,
    /// eliminating any window where one could be observed without the other. `nil`
    /// whenever no result is currently displayed (`.empty`, `.ready`, `.running`,
    /// `.failed`) — in particular, an in-flight `.running` job's `executionProvenance` is
    /// never surfaced here until it commits atomically on successful completion.
    @Published private(set) var displayedTranscription: DisplayedTranscription?

    // MARK: - Private

    private let engine: TranscriptionEngineProtocol
    private var transcriptionTask: Task<Void, Never>?

    /// Clears `executionProvenance` (and its owning `runningJobID`) unconditionally.
    ///
    /// Centralizes every "no longer valid" transition — new file selection, drop,
    /// cancellation, failure, and manual clear — so no call site can forget to clear one
    /// half of the pair (Task 2.20 / Finding F2).
    private func clearRunningProvenance() {
        executionProvenance = nil
        runningJobID = nil
    }

    /// Records `provenance` as owned by `jobID`, superseding any previously running
    /// job's provenance (Task 2.20 / Finding F2).
    private func setRunningProvenance(_ provenance: ExecutionProvenance, jobID: UUID) {
        executionProvenance = provenance
        runningJobID = jobID
    }

    /// - Parameter engine: The backend-agnostic transcription engine to delegate to
    ///   (D004). Defaults to `WhisperTranscriptionEngine()` (local Whisper via FFI, D003).
    ///   Injecting a mock conforming to `TranscriptionEngineProtocol` allows unit tests to
    ///   exercise `startTranscription(settings:)` without invoking the real Rust FFI.
    init(engine: TranscriptionEngineProtocol = WhisperTranscriptionEngine()) {
        self.engine = engine
    }

    /// Identity token of the currently outstanding native FFI operation, if any.
    ///
    /// Distinct from `state.activeJobID`: the lifecycle `state` moves out of `.running`
    /// immediately on logical cancellation (D011), which would otherwise make it
    /// impossible for `finishNativeOperation(token:)` to verify which operation is
    /// actually draining. This token is set exactly once per native operation (in
    /// `beginRunning(file:)`) and cleared only by the matching `finishNativeOperation(token:)`
    /// call, so a stale/superseded operation's completion can never clear busy state that
    /// now belongs to a newer operation (MEDIUM C).
    private var nativeOperationToken: UUID?

    /// Returns `true` if `jobID` is still the currently active running job in `state`.
    ///
    /// Used to guard asynchronous FFI completion callbacks (progress, success, failure)
    /// against stale events arriving after the job has been superseded — e.g. the user
    /// cancelled, started a new file's transcription, or the job otherwise moved out of
    /// `.running` — since Swift `Task.cancel()` does not stop an in-flight blocking Rust
    /// FFI call (D011).
    func isActiveJob(_ jobID: UUID) -> Bool {
        state.activeJobID == jobID
    }

    /// Testing-only accessor exposing the `jobID` that currently owns
    /// `executionProvenance`, if any (Task 2.23 / Finding G1). `nil` means no job
    /// currently owns `executionProvenance` — every terminal transition (successful
    /// completion, failure, cancellation, or replacement) must leave this `nil`, since
    /// no job is "running" and therefore able to own it afterward.
    var runningJobIDForTesting: UUID? { runningJobID }

    /// Applies a progress update for `jobID`, discarding it if `jobID` is no longer the
    /// active running job (stale/superseded job progress callback).
    ///
    /// Exposed at `internal` access (not `private`) so unit tests can simulate stale and
    /// current progress callbacks without invoking the real Rust FFI.
    func handleProgressUpdate(jobID: UUID, progressValue: Float) {
        guard isActiveJob(jobID) else { return }
        progress = progressValue
    }

    /// Applies a transcription completion outcome for `jobID`, discarding it if `jobID` is
    /// no longer the active running job (stale/superseded job completion — e.g. the user
    /// cancelled or started a new transcription before this one finished).
    ///
    /// Exposed at `internal` access (not `private`) so unit tests can simulate stale and
    /// current completions without invoking the real Rust FFI.
    func handleTranscriptionCompletion(
        jobID: UUID,
        fileURL: URL,
        outcome: Result<TranscriptionResult, Error>
    ) {
        guard isActiveJob(jobID) else { return }
        switch outcome {
        case .success(let transcriptionResult):
            // Task 2.23 / Finding G1: `isActiveJob(jobID)` already confirms `jobID`
            // matches the currently running lifecycle state, but `runningJobID` is the
            // explicit ownership token for `executionProvenance` itself (Task 2.20 /
            // Finding F2). Validating it here — rather than trusting `executionProvenance`
            // implicitly belongs to `jobID` — closes the gap where a stale, unrelated
            // job's provenance could otherwise attach to this job's terminal result if
            // the two ever became desynchronized. Only the verified-owned provenance is
            // carried into the terminal snapshot; a mismatch yields `nil` rather than
            // fabricating or misattributing provenance.
            let ownedProvenance = (runningJobID == jobID) ? executionProvenance : nil
            // This job is terminal now — no job is "running" anymore — so its ownership
            // token must be cleared immediately (the concrete gap this task closes:
            // `runningJobID` previously remained set after successful completion).
            // `executionProvenance` itself is retained as the atomic terminal snapshot
            // read by `syncPublishedProperties` below to build `displayedTranscription`.
            runningJobID = nil
            executionProvenance = ownedProvenance
            state = .completed(file: fileURL, result: transcriptionResult)
            NotificationService.sendTranscriptionComplete(
                fileName: fileURL.lastPathComponent,
                segmentCount: transcriptionResult.segmentCount,
                duration: transcriptionResult.duration
            )
        case .failure(let error):
            // Task 2.20 / Finding F2: a failed job's provenance must not leak into a
            // later observation of `executionProvenance` — clear it alongside the
            // failure transition, exactly as cancellation and new file selection
            // already do.
            clearRunningProvenance()
            state = .failed(file: fileURL, error: error.localizedDescription)
        }
    }

    /// Transitions directly into `.running(file:jobID:)` with a freshly generated `jobID`,
    /// setting `statusMessage` and `isNativeBusy` exactly as the real `startTranscription`
    /// does, without dispatching an actual asynchronous FFI transcription call.
    ///
    /// This is a testing-only seam that reuses the same internal `beginRunning(file:)`
    /// lifecycle transition primitive used by production code (see `startTranscription`),
    /// so it models a legitimate state change rather than a parallel fake path. It lets
    /// unit tests exercise the stale-completion guard (`handleTranscriptionCompletion`,
    /// `handleProgressUpdate`) against a real `jobID` produced the same way production
    /// code produces one, without depending on the real Rust FFI or network/model
    /// resources.
    ///
    /// - Parameter provenance: Optional execution provenance to associate with this
    ///   testing-only job, mirroring the real `startTranscription`'s capture of
    ///   `ExecutionProvenance` for the run (Task 2.13 / Finding B3). Lets tests exercise
    ///   real job-replacement scenarios (Finding R7) — starting a second job with distinct
    ///   provenance before the first completes — and assert that `displayedTranscription`
    ///   deterministically reflects the replacing job's context, not the superseded job's.
    ///   `nil` (the default) leaves `executionProvenance` untouched, matching prior
    ///   behavior for existing call sites that only exercise lifecycle-state transitions.
    func startTranscriptionForTesting(fileURL: URL, provenance: ExecutionProvenance? = nil) {
        let jobID = beginRunning(file: fileURL)
        if let provenance {
            setRunningProvenance(provenance, jobID: jobID)
        }
    }

    /// Simulates the pre-FFI execution-identity checkpoint (HIGH B) that production
    /// `startTranscription` evaluates on its background `Task`, immediately before setting
    /// `statusMessage` to "transcribing" and invoking the real (blocking) native engine
    /// call. Mirrors the exact `isActiveJob(jobID)` identity guard used in production —
    /// `Task.isCancelled` is intentionally not part of this simulation, since this method
    /// is invoked directly rather than from within a `Task`, but `isActiveJob(jobID)`
    /// alone already reflects the observable effect of cancellation, because
    /// `cancelTranscription()` moves `state` out of `.running` immediately (D011).
    ///
    /// If the job is no longer active (superseded or logically cancelled), this halts
    /// exactly as production code would: it returns without ever "invoking" native code,
    /// and completes the native operation via the identity-bound `finishNativeOperation(token:)`
    /// so busy state and any pending "cancelling…" status are truthfully finalized.
    ///
    /// - Returns: `true` if the job is still active and production code would proceed to
    ///   invoke the native engine call; `false` if it halted at the pre-FFI checkpoint.
    @discardableResult
    func simulatePreFFICheckpointForTesting(jobID: UUID) -> Bool {
        guard isActiveJob(jobID) else {
            finishNativeOperation(token: jobID)
            return false
        }
        return true
    }

    /// Simulates the background FFI thread draining (returning) for a job started via
    /// `startTranscriptionForTesting`, mirroring the `defer` cleanup performed by the real
    /// `startTranscription` background `Task`. Lets unit tests verify the native-busy guard
    /// and cancellation-draining status messaging without invoking the real Rust FFI.
    ///
    /// Resolves the identity token of the currently outstanding native operation (if any)
    /// and completes it via `finishNativeOperation(token:)`, exercising the same
    /// identity-bound cleanup path production code uses (MEDIUM C) rather than a parallel
    /// unguarded path that could bypass busy-state identity checks.
    ///
    /// - Parameter token: An explicit token to complete, overriding the current
    ///   `nativeOperationToken`. Exposed only so unit tests can simulate a *stale* native
    ///   completion (e.g. an older, superseded job's completion arriving after a newer job
    ///   has already started) and verify it is correctly ignored by the identity check in
    ///   `finishNativeOperation(token:)`. Defaults to the current token, matching the
    ///   ordinary (non-stale) testing usage.
    func completeNativeOperationForTesting(token: UUID? = nil) {
        guard let resolvedToken = token ?? nativeOperationToken else { return }
        finishNativeOperation(token: resolvedToken)
    }

    // MARK: - State Synchronization

    /// Synchronizes the `@Published` convenience properties from the current lifecycle state.
    /// Progress is intentionally left untouched here for `.running`, since it is updated
    /// independently and frequently via the progress callback while remaining in that state.
    private func syncPublishedProperties() {
        switch state {
        case .empty:
            selectedFileURL = nil
            isTranscribing = false
            progress = 0.0
            result = nil
            errorMessage = nil
            statusMessage = L10n.localizedString("status.ready")
            displayedTranscription = nil
        case .ready(let file):
            selectedFileURL = file
            isTranscribing = false
            progress = 0.0
            result = nil
            errorMessage = nil
            statusMessage = L10n.localizedString("status.fileSelected")
            displayedTranscription = nil
        case .running(let file, _):
            selectedFileURL = file
            isTranscribing = true
            progress = 0.0
            result = nil
            errorMessage = nil
            displayedTranscription = nil
        case .completed(let file, let transcriptionResult):
            selectedFileURL = file
            isTranscribing = false
            progress = 1.0
            result = transcriptionResult
            errorMessage = nil
            statusMessage = L10n.localizedString("status.complete")
            // Atomic commit (Task 2.16 / Finding R2): `executionProvenance` was captured
            // for this exact job in `startTranscription` and left untouched throughout
            // its run (guarded by the single-active-job invariant), so it is guaranteed
            // to correspond to `transcriptionResult` here.
            displayedTranscription = DisplayedTranscription(result: transcriptionResult, provenance: executionProvenance)
        case .completedImported(let transcriptionResult):
            // Imported results have no associated source audio file on disk, so
            // `selectedFileURL` is explicitly cleared rather than pointed at a fake
            // placeholder path (e.g. `URL(fileURLWithPath: "")`), which could otherwise
            // enable an invalid `startTranscription()` call against a bogus path.
            selectedFileURL = nil
            isTranscribing = false
            progress = 1.0
            result = transcriptionResult
            errorMessage = nil
            statusMessage = L10n.localizedString("status.complete")
            // `executionProvenance` is set by `applyImportedResult(_:provenance:)` before
            // this state transition, so it already honestly reflects either preserved
            // Canonical import metadata or `nil` for formats with no such metadata.
            displayedTranscription = DisplayedTranscription(result: transcriptionResult, provenance: executionProvenance)
        case .failed(let file, let error):
            selectedFileURL = file
            isTranscribing = false
            progress = 0.0
            result = nil
            errorMessage = error
            statusMessage = L10n.localizedString("status.failed")
            displayedTranscription = nil
        }
    }

    // MARK: - Native Busy Guard

    /// Transitions the lifecycle state into `.running(file:jobID:)` with a freshly
    /// generated `jobID`, marking the native FFI operation as busy and updating the
    /// status message. This is the single lifecycle transition primitive used both by
    /// production `startTranscription` (before dispatching the real background FFI task)
    /// and by the `startTranscriptionForTesting` seam, ensuring both paths produce an
    /// identical, deterministic state change.
    private func beginRunning(file: URL) -> UUID {
        let jobID = UUID()
        state = .running(file: file, jobID: jobID)
        statusMessage = L10n.localizedString("status.preparing")
        isNativeBusy = true
        nativeOperationToken = jobID
        return jobID
    }

    /// Marks the background native FFI operation identified by `token` as drained
    /// (returned), and — if a cancellation was pending while it drained — finalizes the
    /// truthful "cancelled" status message that was deferred until the engine actually
    /// stopped.
    ///
    /// Only clears `isNativeBusy` if `token` matches the currently outstanding
    /// `nativeOperationToken` (MEDIUM C). This prevents a stale completion from a
    /// superseded operation (e.g. one that never entered the FFI call due to pre-FFI
    /// cancellation, or an older job) from incorrectly clearing busy state that now
    /// belongs to a different, newer native operation.
    private func finishNativeOperation(token: UUID) {
        guard nativeOperationToken == token else { return }
        nativeOperationToken = nil
        isNativeBusy = false
        if isCancelling {
            isCancelling = false
            statusMessage = L10n.localizedString("status.cancelled")
        }
    }

    // MARK: - Computed Properties

    /// Display name of the selected file.
    var selectedFileName: String? {
        selectedFileURL?.lastPathComponent
    }

    /// Formatted file size of the selected file.
    var selectedFileSize: String? {
        guard let url = selectedFileURL else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Whether the start button should be enabled.
    var canStartTranscription: Bool {
        selectedFileURL != nil && !isTranscribing && !isNativeBusy
    }

    /// Whether any user-facing action that would change the selected file or start a new
    /// transcription must currently be blocked: either a job is logically running, or a
    /// prior job's native FFI call is still draining after cancellation (D011).
    var isBusy: Bool {
        isTranscribing || isNativeBusy
    }

    /// Recomputes localized status message upon application language changes.
    func refreshLocalization() {
        switch state {
        case .empty:
            statusMessage = L10n.localizedString("status.ready")
        case .ready:
            statusMessage = L10n.localizedString("status.fileSelected")
        case .running:
            statusMessage = isCancelling ? L10n.localizedString("status.cancelling") : L10n.localizedString("status.transcribing")
        case .completed, .completedImported:
            statusMessage = L10n.localizedString("status.complete")
        case .failed:
            statusMessage = L10n.localizedString("status.failed")
        }
    }

    // MARK: - Actions

    /// Opens a file picker for audio files.
    func selectFile() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.title = L10n.localizedString("transcription.selectFile")
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.mp3,
            UTType(filenameExtension: "ogg") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "m4a") ?? .audio,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            switch AudioFileValidator.validate(url) {
            case .success(let validatedURL):
                clearRunningProvenance()
                state = .ready(file: validatedURL)
            case .failure(let validationError):
                errorMessage = validationError.errorDescription
            }
        }
    }

    /// Reports a localized drag-and-drop rejection (multi-item drop, or drop
    /// while a transcription job is active) surfaced by `DropItemResolver`.
    func reportDropRejection(_ message: String) {
        errorMessage = message
    }

    /// Reports a localized document import failure (Task 2.21 / Finding F6),
    /// surfacing it via `errorMessage` for user-facing UI feedback instead of
    /// only logging to the console. Used by `ContentView`'s file-picker-driven
    /// transcript import flow (`openTranscriptionFile`), which is unrelated to
    /// drag-and-drop, so the message must not reuse drop-rejection phrasing.
    func reportImportError(_ message: String) {
        errorMessage = message
    }

    /// Explicit user intent to dismiss the currently displayed error message, without
    /// otherwise altering the lifecycle state (e.g. selected file, result).
    ///
    /// Views must call this instead of mutating `errorMessage` directly, since it is a
    /// read-only projection (`private(set)`) of the view model's internal state.
    func dismissError() {
        errorMessage = nil
    }

    /// Handles a file dropped onto the drop zone.
    func handleDroppedFile(_ url: URL) {
        guard !isBusy else { return }

        switch AudioFileValidator.validate(url) {
        case .success(let validatedURL):
            clearRunningProvenance()
            state = .ready(file: validatedURL)
        case .failure(let validationError):
            errorMessage = validationError.errorDescription
        }
    }

    /// Starts the transcription process.
    func startTranscription(settings: AppSettings) {
        // Reject re-triggering while a job is logically running, or while a prior job's
        // native FFI call is still draining after cancellation — at most one native
        // Whisper operation may execute at any time.
        guard !isBusy else { return }

        guard let fileURL = selectedFileURL else {
            errorMessage = L10n.localizedString("error.noFile")
            return
        }

        let jobID = beginRunning(file: fileURL)

        // Capture execution provenance for this run (Task 2.13 / Finding B3) alongside
        // the domain `TranscriptionResult`, so exports can reflect the real source file,
        // model, and engine instead of hardcoded placeholders. The `engineID` is snapshotted
        // dynamically from the actually injected `engine` instance (Finding R3) rather than
        // hardcoded to `WhisperTranscriptionEngine`, so arbitrary conforming engines (e.g.
        // test mocks or future alternative implementations) are labeled honestly.
        setRunningProvenance(
            ExecutionProvenance(
                sourceURL: fileURL,
                modelName: settings.selectedModel,
                engineID: engine.engineID
            ),
            jobID: jobID
        )

        let shouldTranslate = settings.language != "en" && settings.translateToEnglish
        let request = TranscriptionRequest(
            sourceURL: fileURL,
            modelName: settings.selectedModel,
            language: settings.language,
            translateToEnglish: shouldTranslate,
            chunkingEnabled: settings.useChunking,
            chunkDurationSeconds: settings.useChunking ? Double(settings.chunkDuration) : nil,
            overlapDurationSeconds: settings.useChunking ? Double(settings.overlapDuration) : nil
        )

        transcriptionTask = Task {
            defer { finishNativeOperation(token: jobID) }
            do {
                // Pre-FFI cancellation checkpoint (HIGH B): if this job was already
                // cancelled or superseded (e.g. the user cancelled immediately, or a
                // scheduling delay let a newer job take over) before the blocking Rust
                // FFI call is entered, halt here without ever invoking native code. The
                // engine was never actually invoked, so `defer`'s `finishNativeOperation`
                // safely clears busy state without waiting on any real background thread.
                guard !Task.isCancelled, isActiveJob(jobID) else {
                    return
                }

                statusMessage = L10n.localizedString("status.transcribing")

                let transcriptionResult = try await engine.transcribe(
                    request: request,
                    progressHandler: { [weak self] progressValue in
                        Task { @MainActor in
                            self?.handleProgressUpdate(jobID: jobID, progressValue: progressValue)
                        }
                    }
                )

                handleTranscriptionCompletion(jobID: jobID, fileURL: fileURL, outcome: .success(transcriptionResult))
            } catch {
                if !Task.isCancelled {
                    handleTranscriptionCompletion(jobID: jobID, fileURL: fileURL, outcome: .failure(error))
                }
            }
        }
    }

    /// Cancels the current transcription.
    ///
    /// This is a *logical* cancellation only (D011): it clears the active job so late FFI
    /// completions are suppressed and the UI returns to a ready/empty state immediately,
    /// but it does NOT stop the background native FFI thread, which keeps running until
    /// `orangenote_transcribe_file`/`_chunked` returns. `isNativeBusy` remains `true` until
    /// then, blocking new starts and file/drop changes, and the status message truthfully
    /// reflects that cancellation is still draining until the engine actually stops.
    func cancelTranscription() {
        guard isTranscribing else { return }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        clearRunningProvenance()
        if let file = selectedFileURL {
            state = .ready(file: file)
        } else {
            state = .empty
        }

        if isNativeBusy {
            isCancelling = true
            statusMessage = L10n.localizedString("status.cancelling")
        } else {
            statusMessage = L10n.localizedString("status.cancelled")
        }
    }

    /// Clears the current result and resets state.
    ///
    /// Rejected (no-op) while `isBusy` (a transcription job is logically running, or a
    /// prior job's native FFI call is still draining after cancellation) to prevent this
    /// from transitioning `state` to `.ready`/`.empty` while native Whisper execution is
    /// still ongoing, which would corrupt the active lifecycle state while the background
    /// FFI thread continues (see D011).
    func clearResult() {
        guard !isBusy else { return }
        clearRunningProvenance()
        if let file = selectedFileURL {
            state = .ready(file: file)
        } else {
            state = .empty
        }
    }

    /// Applies an externally imported transcription result (e.g. from
    /// `TranscriptionImportService`), transitioning into `.completedImported` for display
    /// in the results view without any associated audio file selection.
    ///
    /// Rejected while `isBusy` (a transcription job is logically running, or a prior job's
    /// native FFI call is still draining after cancellation) to prevent import from
    /// bypassing lifecycle protection and corrupting an in-flight transcription's state.
    /// The rejection is surfaced to the user via `errorMessage`, consistent with other
    /// busy-rejection paths (e.g. drag-and-drop rejection while transcribing).
    ///
    /// `executionProvenance` reflects `provenance`: an imported result was not produced by
    /// a local transcription run in this session, so there is generally no real source
    /// file, model, or engine to report and `provenance` honestly defaults to `nil`.
    /// Callers that imported a Canonical JSON v1 document with recoverable safe metadata
    /// (`source.fileName`, `engine.model`, `engine.id`) may pass it here so exports of the
    /// imported result can preserve it (Task 2.16 / Finding R1), rather than always
    /// fabricating or discarding real metadata.
    func applyImportedResult(_ result: TranscriptionResult, provenance: ExecutionProvenance? = nil) {
        guard !isBusy else {
            errorMessage = L10n.localizedString("error.importRejectedTranscribing")
            return
        }
        executionProvenance = provenance
        runningJobID = nil
        state = .completedImported(result: result)
    }
}
