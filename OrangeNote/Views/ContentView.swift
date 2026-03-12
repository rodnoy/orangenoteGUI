//
//  ContentView.swift
//  OrangeNote
//
//  Main window with sidebar navigation using NavigationSplitView.
//

import SwiftUI
import UniformTypeIdentifiers

/// Sidebar navigation items.
enum NavigationItem: String, CaseIterable, Identifiable {
    case transcribe
    case results
    case models
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .transcribe: return "nav.transcribe"
        case .results:    return "nav.results"
        case .models:     return "nav.models"
        case .settings:   return "nav.settings"
        }
    }

    var icon: String {
        switch self {
        case .transcribe: return "waveform"
        case .results:    return "doc.text"
        case .models:     return "arrow.down.circle"
        case .settings:   return "gear"
        }
    }
}

/// The main content view with sidebar navigation.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appState: AppState

    @StateObject private var transcriptionVM = TranscriptionViewModel()
    @StateObject private var modelManagerVM = ModelManagerViewModel()
    @StateObject private var exportVM = ExportViewModel()

    @State private var selectedItem: NavigationItem? = .transcribe

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 550)
        .onChange(of: transcriptionVM.result, initial: true) {
            appState.currentTranscriptionResult = transcriptionVM.result
        }
        .onChange(of: appState.triggerSave) {
            guard appState.triggerSave, let result = appState.currentTranscriptionResult else { return }
            appState.triggerSave = false
            exportVM.saveToFile(result: result)
        }
        .onChange(of: appState.triggerExport) {
            guard appState.triggerExport, let result = appState.currentTranscriptionResult else { return }
            appState.triggerExport = false
            // Open save panel directly with format selection
            exportVM.saveToFile(result: result)
        }
        .onChange(of: appState.triggerOpenTranscription) {
            guard appState.triggerOpenTranscription else { return }
            appState.triggerOpenTranscription = false
            openTranscriptionFile()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationItem.allCases, selection: $selectedItem) { item in
            Label(LocalizedStringKey(item.titleKey), systemImage: item.icon)
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
                        .foregroundStyle(transcriptionVM.isTranscribing ? .green : .secondary)
                    Text(transcriptionVM.statusMessage)
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
        switch selectedItem {
        case .transcribe:
            TranscriptionView(viewModel: transcriptionVM)
                .environmentObject(settings)

        case .results:
            ResultsView(
                result: transcriptionVM.result,
                exportVM: exportVM
            )

        case .models:
            ModelManagerView(viewModel: modelManagerVM)

        case .settings:
            SettingsView()
                .environmentObject(settings)

        case nil:
            Text("nav.selectSidebar")
                .font(.title2)
                .foregroundStyle(.secondary)
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
                let result = try TranscriptionImportService.importFromFile(url: url)
                transcriptionVM.result = result
                selectedItem = .results
            } catch {
                print("[Import] Error: \(error.localizedDescription)")
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
