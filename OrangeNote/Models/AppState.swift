//
//  AppState.swift
//  OrangeNote
//
//  Shared application state accessible from menu commands, navigation routing, and views.
//

import SwiftUI

/// Shared application state for coordinating menu commands, navigation routing, and results inspection with views.
@MainActor
final class AppState: ObservableObject {
    /// Active sidebar navigation selection in the main window.
    @Published var selectedNavigationItem: NavigationItem = .transcribe

    /// UUID of the currently inspected batch item, if the displayed transcription originated from a batch run (Task 3.17 / D028).
    @Published var selectedBatchItemID: UUID?

    /// The currently displayed transcription result and its execution provenance,
    /// synchronized atomically from `TranscriptionViewModel.displayedTranscription`
    /// or selected `BatchItem` (Task 2.16 / Finding R2 / Task 3.17 / D028).
    /// `AppState` mirrors strictly the current displayed context — there is no historical store.
    /// `nil` when no result is currently displayed.
    @Published var displayedTranscription: DisplayedTranscription?

    /// The current transcription result, if available.
    ///
    /// Backward-compatible convenience projection of `displayedTranscription.result`.
    var currentTranscriptionResult: TranscriptionResult? {
        displayedTranscription?.result
    }

    /// Execution provenance (source file, model, engine) for `currentTranscriptionResult`,
    /// if known (Task 2.13 / Finding B3). `nil` when unavailable (e.g. imported results
    /// with no recoverable metadata), so exports never fabricate fake source metadata.
    ///
    /// Backward-compatible convenience projection of `displayedTranscription.provenance`.
    var currentExecutionProvenance: ExecutionProvenance? {
        displayedTranscription?.provenance
    }

    /// Trigger flag for the Open Transcription menu command (⌘O).
    @Published var triggerOpenTranscription: Bool = false

    /// Trigger flag for the Save menu command (⌘S).
    @Published var triggerSave: Bool = false

    /// Trigger flag for the Export menu command (⌘⇧E).
    @Published var triggerExport: Bool = false

    /// Whether the export sheet is currently presented.
    @Published var showExportSheet: Bool = false

    /// Dedicated global import-error state (Task 2.24 / G2). Set by `ContentView`'s
    /// document import flow when the failure occurs while `TranscriptionView` is NOT
    /// the active tab (Results, Models, Settings), so that the failure is visibly
    /// presented via an application-level alert instead of being silently recorded
    /// only on `TranscriptionViewModel.errorMessage` (which is only rendered by
    /// `TranscriptionView`). `nil` when no global import alert is pending.
    @Published var importErrorMessage: String?

    /// Whether a transcription result is currently available.
    var hasTranscriptionResult: Bool {
        displayedTranscription != nil
    }

    // MARK: - Navigation & Routing Commands

    /// Navigates directly to the specified sidebar destination.
    func navigate(to item: NavigationItem) {
        self.selectedNavigationItem = item
    }

    /// Sets the displayed transcription result and provenance directly (e.g. from single-file or import).
    func setDisplayedTranscription(_ displayed: DisplayedTranscription?, navigateToResults: Bool = false) {
        self.displayedTranscription = displayed
        self.selectedBatchItemID = nil
        if navigateToResults && displayed != nil {
            self.selectedNavigationItem = .results
        }
    }

    /// Routes to the Results tab displaying the transcript of a completed batch item (Task 3.17 / D028).
    func routeToBatchItemResult(
        _ item: BatchItem,
        modelName: String = "base",
        engineID: String = "whisper-local"
    ) {
        guard let result = item.result else { return }
        let provenance = ExecutionProvenance(
            sourceURL: item.sourceURL,
            modelName: modelName,
            engineID: engineID
        )
        self.displayedTranscription = DisplayedTranscription(result: result, provenance: provenance)
        self.selectedBatchItemID = item.id
        self.selectedNavigationItem = .results
    }

    /// Clears the currently displayed transcription and batch selection.
    func clearDisplayedTranscription() {
        self.displayedTranscription = nil
        self.selectedBatchItemID = nil
    }
}
