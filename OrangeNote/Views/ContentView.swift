//
//  ContentView.swift
//  OrangeNote
//
//  Main window with sidebar navigation using NavigationSplitView.
//

import SwiftUI
import UniformTypeIdentifiers

/// The main content view with sidebar navigation.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appState: AppState

    @StateObject private var transcriptionVM: TranscriptionViewModel
    @StateObject private var batchVM: BatchTranscriptionViewModel
    @StateObject private var modelManagerVM: ModelManagerViewModel
    @StateObject private var exportVM: ExportViewModel

    init() {
        let singleVM = TranscriptionViewModel()
        let bVM = BatchTranscriptionViewModel(isSingleFileBusy: { [weak singleVM] in
            singleVM?.isBusy ?? false
        })
        _transcriptionVM = StateObject(wrappedValue: singleVM)
        _batchVM = StateObject(wrappedValue: bVM)
        _modelManagerVM = StateObject(wrappedValue: ModelManagerViewModel())
        _exportVM = StateObject(wrappedValue: ExportViewModel())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 550)
        .onChange(of: transcriptionVM.displayedTranscription, initial: true) {
            // Task 2.16 / Finding R2: mirror the atomic `DisplayedTranscription` context
            // in a single `@Published` assignment. When a single-file transcription
            // result is present, synchronize it to AppState; when nil and no batch item
            // is actively inspected, clear AppState.
            if transcriptionVM.displayedTranscription != nil {
                appState.setDisplayedTranscription(transcriptionVM.displayedTranscription)
            } else if appState.selectedBatchItemID == nil {
                appState.clearDisplayedTranscription()
            }
        }
        .onChange(of: appState.triggerSave) {
            guard appState.triggerSave, let displayed = appState.displayedTranscription else { return }
            appState.triggerSave = false
            exportVM.saveToFile(result: displayed.result, provenance: displayed.provenance)
        }
        .onChange(of: appState.triggerExport) {
            guard appState.triggerExport, let displayed = appState.displayedTranscription else { return }
            appState.triggerExport = false
            // Open save panel directly with format selection
            exportVM.saveToFile(result: displayed.result, provenance: displayed.provenance)
        }
        .onChange(of: appState.triggerOpenTranscription) {
            guard appState.triggerOpenTranscription else { return }
            appState.triggerOpenTranscription = false
            openTranscriptionFile()
        }
        .onChange(of: settings.appLanguage) {
            transcriptionVM.refreshLocalization()
            batchVM.refreshLocalization()
        }
        // Task 2.24 / G2: application-level alert presenter for document import
        // failures that occur while `TranscriptionView` is not the active tab.
        // `TranscriptionView` already renders `transcriptionVM.errorMessage` inline,
        // so this alert is driven by a separate `AppState.importErrorMessage` field
        // to guarantee exactly one visible alert and no duplicate presentation.
        .alert(
            L10n.string("import.error.title"),
            isPresented: Binding(
                get: { appState.importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { appState.importErrorMessage = nil }
                }
            )
        ) {
            Button(L10n.string("common.ok")) { appState.importErrorMessage = nil }
        } message: {
            Text(appState.importErrorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationItem.allCases, selection: Binding(
            get: { appState.selectedNavigationItem },
            set: { newValue in
                if let newValue {
                    appState.selectedNavigationItem = newValue
                }
            }
        )) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Divider()
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(transcriptionVM.isTranscribing || batchVM.isRunning ? .green : .secondary)
                    Text(batchVM.isRunning ? batchVM.statusMessage : transcriptionVM.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedNavigationItem {
        case .transcribe:
            TranscriptionView(
                viewModel: transcriptionVM,
                batchViewModel: batchVM
            )
            .environmentObject(settings)

        case .results:
            ResultsView(
                displayedTranscription: appState.displayedTranscription,
                exportVM: exportVM
            )

        case .models:
            ModelManagerView(viewModel: modelManagerVM)

        case .settings:
            SettingsView()
                .environmentObject(settings)
        }
    }

    // MARK: - Import

    /// Opens a file panel to import a transcription file (JSON or SRT).
    private func openTranscriptionFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.localizedString("import.panelTitle")
        panel.allowedContentTypes = [
            .json,
            UTType(filenameExtension: "srt") ?? .plainText,
        ]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try TranscriptionImportService.importWithProvenance(url: url)
                // Task 2.26 / G2-busy: pre-check the busy state *before* calling
                // `applyImportedResult`, rather than relying on its internal busy guard
                // (which only sets `transcriptionVM.errorMessage`). This lets the busy
                // rejection be routed the same way as parse/read import failures below —
                // inline on the Transcribe tab, or as an `AppState.importErrorMessage`
                // global alert on Results/Models/Settings — instead of silently returning
                // with zero visible feedback on non-Transcribe tabs.
                guard !transcriptionVM.isBusy else {
                    let message = L10n.localizedString("error.importRejectedTranscribing")
                    if appState.selectedNavigationItem == .transcribe {
                        transcriptionVM.reportImportError(message)
                    } else {
                        appState.importErrorMessage = message
                    }
                    return
                }
                transcriptionVM.applyImportedResult(imported.result, provenance: imported.provenance)
                // Defer tab switch to the next RunLoop iteration so that
                // NavigationSplitView picks up the updated result before
                // the selection change triggers a detail-view rebuild.
                Task { @MainActor in
                    appState.selectedNavigationItem = .results
                }
            } catch {
                // Task 2.21 / Finding F6: surface the failure to the user instead of only
                // logging to the console. Task 2.24 / G2: route the failure so that exactly
                // one visible alert is presented regardless of which tab is active — if
                // `TranscriptionView` is active, its inline `errorMessage` presenter already
                // shows the error; otherwise, present the application-level alert via
                // `AppState.importErrorMessage` so Results/Models/Settings users also see it.
                let message = String(format: L10n.localizedString("import.error.failed"), error.localizedDescription)
                if appState.selectedNavigationItem == .transcribe {
                    transcriptionVM.reportImportError(message)
                } else {
                    appState.importErrorMessage = message
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(AppState())
}
