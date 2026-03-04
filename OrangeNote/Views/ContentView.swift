//
//  ContentView.swift
//  OrangeNote
//
//  Main window with sidebar navigation using NavigationSplitView.
//

import SwiftUI

/// Sidebar navigation items.
enum NavigationItem: String, CaseIterable, Identifiable {
    case transcribe
    case results
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcribe: return "Transcribe"
        case .results:    return "Results"
        case .models:     return "Models"
        case .settings:   return "Settings"
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationItem.allCases, selection: $selectedItem) { item in
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
            Text("Select an item from the sidebar")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
