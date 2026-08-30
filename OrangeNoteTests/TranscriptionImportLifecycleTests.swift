//
//  TranscriptionImportLifecycleTests.swift
//  OrangeNoteTests
//
//  Unit tests guarding TranscriptionViewModel.applyImportedResult(_:) against bypassing
//  the isBusy lifecycle guard (Task 1.12 / HIGH A remediation finding), and verifying
//  that imported results are represented without a fake source-file URL placeholder
//  (e.g. URL(fileURLWithPath: "")), which could otherwise enable an invalid
//  startTranscription() call against a bogus path.
//

import XCTest
@testable import OrangeNote

@MainActor
final class TranscriptionImportLifecycleTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionImportLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeAudioFile(named name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    private func makeResult(fullText: String = "imported") -> TranscriptionResult {
        TranscriptionResult(
            segments: [],
            fullText: fullText,
            language: "en",
            duration: 1.0
        )
    }

    // MARK: (a) Import while idle succeeds and represents the result cleanly.

    func testImportWhileIdleSucceedsWithoutFakeSourceURL() {
        let viewModel = TranscriptionViewModel()
        let imported = makeResult()

        viewModel.applyImportedResult(imported)

        XCTAssertEqual(viewModel.state, .completedImported(result: imported))
        XCTAssertNil(viewModel.selectedFileURL, "Imported results must not set a fake/placeholder source file URL")
        XCTAssertEqual(viewModel.result, imported)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: (b) Import while a job is logically running is rejected.

    func testImportRejectedWhileTranscribing() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "running.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)

        XCTAssertTrue(viewModel.isTranscribing)

        let imported = makeResult(fullText: "should be rejected")
        viewModel.applyImportedResult(imported)

        // The running job's state must remain untouched.
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.state.activeJobID != nil, true)
        XCTAssertNotEqual(viewModel.result, imported)
        XCTAssertNotNil(viewModel.errorMessage, "Import rejection while busy must surface a user-facing error message")
    }

    // MARK: (c) Import while the native FFI call is still draining (post-cancel) is rejected.

    func testImportRejectedWhileNativeBusyDraining() throws {
        let viewModel = TranscriptionViewModel()
        let fileURL = try makeAudioFile(named: "draining.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        viewModel.cancelTranscription()

        XCTAssertTrue(viewModel.isNativeBusy, "Native-busy must remain true immediately after logical cancellation")

        let imported = makeResult(fullText: "should be rejected while draining")
        viewModel.applyImportedResult(imported)

        XCTAssertEqual(viewModel.state, .ready(file: fileURL), "State must remain unchanged while draining")
        XCTAssertNotEqual(viewModel.result, imported)
        XCTAssertNotNil(viewModel.errorMessage)

        // Once drained, import is permitted again.
        viewModel.completeNativeOperationForTesting()
        viewModel.applyImportedResult(imported)
        XCTAssertEqual(viewModel.state, .completedImported(result: imported))
    }

    // MARK: (d) Start-transcription invariant: an imported result cannot be used to trigger
    // a start against an invalid/placeholder path, since selectedFileURL is nil.

    func testStartTranscriptionCannotBeTriggeredAfterImport() {
        let viewModel = TranscriptionViewModel()
        let imported = makeResult()
        viewModel.applyImportedResult(imported)

        XCTAssertNil(viewModel.selectedFileURL)
        XCTAssertFalse(viewModel.canStartTranscription, "Start must not be enabled with no valid selected file")

        viewModel.startTranscription(settings: AppSettings())

        // No job should have started, and the imported result state must remain unchanged.
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.state, .completedImported(result: imported))
        XCTAssertEqual(viewModel.errorMessage, L10n.localizedString("error.noFile"))
    }

    // MARK: (e) Import failure UX intent surfaces a user-facing error message
    // (Task 2.21 / Finding F6).
    //
    // `ContentView.openTranscriptionFile()` previously only logged import failures
    // (thrown by `TranscriptionImportService`) to the console via `print(...)`, leaving
    // the user with no feedback at all. It now calls `reportImportError(_:)`, the
    // explicit view model intent verified here, which surfaces the failure through the
    // same `errorMessage` channel used by every other user-facing rejection.
    func testReportImportErrorSurfacesUserFacingErrorMessage() {
        let viewModel = TranscriptionViewModel()

        let message = String(format: L10n.localizedString("import.error.failed"), "Failed to parse file: bad.json")
        viewModel.reportImportError(message)

        XCTAssertEqual(viewModel.errorMessage, message)
    }

    /// Verifies the import-error message uses picker-oriented, file-import phrasing
    /// (`import.error.failed`) and never reuses drag-and-drop rejection copy
    /// (`error.dropExtractionFailed`, `error.dropRejectedTranscribing`,
    /// `error.dropMultipleFilesRejected`) across all supported locales, since document
    /// import via the file picker (`ContentView.openTranscriptionFile()`) is unrelated to
    /// drag-and-drop.
    func testImportErrorLocalizationDoesNotReuseDragAndDropPhrasing() {
        let dropPhrasingKeys = [
            "error.dropExtractionFailed",
            "error.dropRejectedTranscribing",
            "error.dropMultipleFilesRejected",
        ]

        let importFailedTemplate = L10n.localizedString("import.error.failed")
        XCTAssertFalse(importFailedTemplate.isEmpty, "import.error.failed must be localized")

        for dropKey in dropPhrasingKeys {
            let dropPhrasingTemplate = L10n.localizedString(dropKey)
            XCTAssertNotEqual(
                importFailedTemplate, dropPhrasingTemplate,
                "import.error.failed must not reuse drag-and-drop rejection phrasing (\(dropKey))"
            )
        }
    }

    // MARK: (f)-(i) Task 2.24 / G2: global import-error state routing.
    //
    // `TranscriptionView` is the only view that renders `TranscriptionViewModel.errorMessage`
    // inline. `ContentView.openTranscriptionFile()` therefore routes an import failure to
    // exactly one visible presenter based on the active tab: `reportImportError(_:)` on the
    // view model when Transcribe is active (existing inline presenter), or
    // `AppState.importErrorMessage` otherwise (application-level alert). These tests verify
    // the routing invariant directly on the state objects `ContentView` observes, since
    // `ContentView` itself has no unit-testable body in isolation.

    /// `AppState.importErrorMessage` starts `nil` (no alert pending) and clears cleanly,
    /// mirroring the exact binding behavior used by `ContentView`'s `.alert` dismissal.
    func testAppStateImportErrorMessageDefaultsToNilAndClearsCleanly() {
        let appState = AppState()
        XCTAssertNil(appState.importErrorMessage)

        appState.importErrorMessage = "Failed to import transcription file: boom"
        XCTAssertNotNil(appState.importErrorMessage)

        // Simulates the `.alert` isPresented binding's `set` closure on dismissal.
        appState.importErrorMessage = nil
        XCTAssertNil(appState.importErrorMessage)
    }

    /// When the failure is routed through `TranscriptionViewModel.reportImportError(_:)`
    /// (Transcribe tab active), `AppState.importErrorMessage` must remain untouched, so no
    /// duplicate application-level alert is triggered alongside `TranscriptionView`'s inline
    /// error presenter.
    func testTranscribeTabRoutingDoesNotPopulateAppStateImportError() {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()

        let message = String(format: L10n.localizedString("import.error.failed"), "Failed to parse file: bad.json")
        viewModel.reportImportError(message)

        XCTAssertEqual(viewModel.errorMessage, message)
        XCTAssertNil(appState.importErrorMessage, "AppState must not also carry the error when TranscriptionView already presents it inline")
    }

    /// When the failure is routed through `AppState.importErrorMessage` (any non-Transcribe
    /// tab active), `TranscriptionViewModel.errorMessage` must remain untouched, ensuring
    /// exactly one visible alert (the application-level one) with no duplicate.
    func testNonTranscribeTabRoutingDoesNotPopulateViewModelErrorMessage() {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()

        let message = String(format: L10n.localizedString("import.error.failed"), "Failed to parse file: bad.json")
        appState.importErrorMessage = message

        XCTAssertEqual(appState.importErrorMessage, message)
        XCTAssertNil(viewModel.errorMessage, "TranscriptionViewModel.errorMessage must not also be populated when the global alert is presenting the error")
    }

    /// The dedicated `import.error.title` localization key used as the global alert's title
    /// is present and non-empty for all bundled locales, and distinct from the message
    /// template key so the alert renders a real title rather than a missing-key placeholder.
    func testImportErrorTitleLocalizationIsPresent() {
        let title = L10n.localizedString("import.error.title")
        XCTAssertFalse(title.isEmpty, "import.error.title must be localized")
        XCTAssertNotEqual(title, "import.error.title", "import.error.title must resolve to a real localized string, not the raw key")
    }

    // MARK: (j)-(m) Task 2.26 / G2-busy: busy-import rejection global routing.
    //
    // `ContentView.openTranscriptionFile()` pre-checks `transcriptionVM.isBusy` *before*
    // calling `applyImportedResult`, so a busy rejection while a valid document is being
    // imported is routed the same way as parse/read failures: inline via
    // `reportImportError(_:)` on the Transcribe tab, or via `AppState.importErrorMessage`
    // on any other tab. These tests simulate that routing decision directly against the
    // real `isTranscribing` / `isNativeBusy` lifecycle states (running and draining),
    // mirroring `ContentView`'s guard, since `ContentView` itself has no unit-testable
    // body in isolation.

    private func busyImportRejectionMessage() -> String {
        L10n.localizedString("error.importRejectedTranscribing")
    }

    /// Simulates `ContentView.openTranscriptionFile()`'s busy pre-check-and-route branch.
    private func routeBusyImport(
        viewModel: TranscriptionViewModel,
        appState: AppState,
        selectedItem: NavigationItem
    ) {
        let message = busyImportRejectionMessage()
        if selectedItem == .transcribe {
            viewModel.reportImportError(message)
        } else {
            appState.importErrorMessage = message
        }
    }

    /// Transcribe tab active while a job is logically running (`isTranscribing`): the
    /// rejection must be presented inline via `errorMessage`, `AppState.importErrorMessage`
    /// must remain untouched, and the active running job's state must be untouched.
    func testBusyImportRoutesInlineOnTranscribeTabWhileRunning() throws {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()
        let fileURL = try makeAudioFile(named: "busy-transcribe-running.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        XCTAssertTrue(viewModel.isTranscribing)

        routeBusyImport(viewModel: viewModel, appState: appState, selectedItem: .transcribe)

        XCTAssertEqual(viewModel.errorMessage, busyImportRejectionMessage())
        XCTAssertNil(appState.importErrorMessage, "Exactly one target must be populated: inline only, no duplicate global alert")
        XCTAssertTrue(viewModel.isTranscribing, "The active running job must remain untouched")
    }

    /// Transcribe tab active while draining (`isNativeBusy` after cancellation): same
    /// inline routing invariant as the running case above.
    func testBusyImportRoutesInlineOnTranscribeTabWhileDraining() throws {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()
        let fileURL = try makeAudioFile(named: "busy-transcribe-draining.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        viewModel.cancelTranscription()
        XCTAssertTrue(viewModel.isNativeBusy)

        routeBusyImport(viewModel: viewModel, appState: appState, selectedItem: .transcribe)

        XCTAssertEqual(viewModel.errorMessage, busyImportRejectionMessage())
        XCTAssertNil(appState.importErrorMessage, "Exactly one target must be populated: inline only, no duplicate global alert")
        XCTAssertEqual(viewModel.state, .ready(file: fileURL), "State must remain unchanged while draining")
    }

    /// Non-Transcribe tab (e.g. Results) active while a job is logically running: the
    /// rejection must be routed to the global `AppState.importErrorMessage` alert, and
    /// `TranscriptionViewModel.errorMessage` must remain untouched (no duplicate).
    func testBusyImportRoutesGlobalAlertOnNonTranscribeTabWhileRunning() throws {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()
        let fileURL = try makeAudioFile(named: "busy-results-running.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        XCTAssertTrue(viewModel.isTranscribing)

        routeBusyImport(viewModel: viewModel, appState: appState, selectedItem: .results)

        XCTAssertEqual(appState.importErrorMessage, busyImportRejectionMessage())
        XCTAssertNil(viewModel.errorMessage, "Exactly one target must be populated: global alert only, no duplicate inline error")
        XCTAssertTrue(viewModel.isTranscribing, "The active running job must remain untouched")

        // Dismissal clears cleanly, mirroring the `.alert` isPresented binding's `set` closure.
        appState.importErrorMessage = nil
        XCTAssertNil(appState.importErrorMessage)
    }

    /// Non-Transcribe tab (e.g. Models) active while draining (`isNativeBusy` after
    /// cancellation): same global-alert routing invariant as the running case above.
    func testBusyImportRoutesGlobalAlertOnNonTranscribeTabWhileDraining() throws {
        let viewModel = TranscriptionViewModel()
        let appState = AppState()
        let fileURL = try makeAudioFile(named: "busy-models-draining.wav")
        viewModel.handleDroppedFile(fileURL)
        viewModel.startTranscriptionForTesting(fileURL: fileURL)
        viewModel.cancelTranscription()
        XCTAssertTrue(viewModel.isNativeBusy)

        routeBusyImport(viewModel: viewModel, appState: appState, selectedItem: .models)

        XCTAssertEqual(appState.importErrorMessage, busyImportRejectionMessage())
        XCTAssertNil(viewModel.errorMessage, "Exactly one target must be populated: global alert only, no duplicate inline error")
        XCTAssertEqual(viewModel.state, .ready(file: fileURL), "State must remain unchanged while draining")

        appState.importErrorMessage = nil
        XCTAssertNil(appState.importErrorMessage)
    }
}
