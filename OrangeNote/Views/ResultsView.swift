//
//  ResultsView.swift
//  OrangeNote
//
//  Displays transcription results with segments, search, copy, and translation functionality.
//

import SwiftUI

#if canImport(Translation)
import Translation
#endif

/// Displays the transcription result with segment list, search, export, and translation options.
struct ResultsView: View {
    let result: TranscriptionResult?
    @ObservedObject var exportVM: ExportViewModel

    @State private var searchText = ""
    @State private var showFullText = false

    // Translation view model — only used on macOS 15+
    private let translationVM: AnyObject?

    init(result: TranscriptionResult?, exportVM: ExportViewModel) {
        self.result = result
        self.exportVM = exportVM

        if #available(macOS 15.0, *) {
            self.translationVM = TranslationViewModel()
        } else {
            self.translationVM = nil
        }
    }

    var body: some View {
        Group {
            if let result {
                resultContent(result)
            } else {
                emptyState
            }
        }
        .navigationTitle("results.title")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("results.empty.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("results.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result Content

    private func resultContent(_ result: TranscriptionResult) -> some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar(result)
            Divider()

            // Translation toolbar (macOS 15+ only)
            if #available(macOS 15.0, *) {
                translationToolbar(result)
            }

            if showFullText {
                if #available(macOS 15.0, *),
                   let vm = translationVM as? TranslationViewModel,
                   vm.showTranslation,
                   let translated = vm.translatedResult {
                    translatedFullTextView(translated)
                } else {
                    fullTextView(result)
                }
            } else {
                if #available(macOS 15.0, *),
                   let vm = translationVM as? TranslationViewModel,
                   vm.showTranslation,
                   let translated = vm.translatedResult {
                    translatedSegmentListView(translated)
                } else {
                    segmentListView(result)
                }
            }
        }
        .modifier(TranslationTaskModifier(translationVM: translationVM))
    }

    // MARK: - Toolbar

    private func toolbar(_ result: TranscriptionResult) -> some View {
        HStack(spacing: 12) {
            // View mode toggle
            Picker("results.view", selection: $showFullText) {
                Label("results.view.segments", systemImage: "list.bullet")
                    .tag(false)
                Label("results.view.fullText", systemImage: "doc.plaintext")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if !showFullText {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("results.search", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                }
                .frame(maxWidth: 250)
            }

            Spacer()

            // Stats
            HStack(spacing: 12) {
                Label(String(format: String(localized: "results.segmentsCount"), result.segmentCount), systemImage: "text.alignleft")
                Label(result.formattedDuration, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Copy button
            Menu {
                Button("results.copyAll") {
                    copyToClipboard(result.fullText)
                }
                Button("results.copyAsJson") {
                    exportVM.selectedFormat = .json
                    exportVM.copyToClipboard(result: result)
                }
                Button("results.copyAsSrt") {
                    exportVM.selectedFormat = .srt
                    exportVM.copyToClipboard(result: result)
                }
            } label: {
                Label("results.copy", systemImage: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Translation Toolbar (macOS 15+)

    @available(macOS 15.0, *)
    private func translationToolbar(_ result: TranscriptionResult) -> some View {
        TranslationToolbarContent(
            result: result,
            translationVM: translationVM as! TranslationViewModel
        )
    }

    // MARK: - Segment List

    private func segmentListView(_ result: TranscriptionResult) -> some View {
        let filteredSegments = filteredSegments(result.segments)

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSegments) { segment in
                    SegmentRow(
                        segment: segment,
                        isHighlighted: !searchText.isEmpty
                    )
                    Divider()
                        .padding(.leading, 16)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Translated Segment List

    @available(macOS 15.0, *)
    private func translatedSegmentListView(_ translated: TranslatedResult) -> some View {
        let filteredSegments = filteredTranslatedSegments(translated.translatedSegments)

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSegments) { segment in
                    TranslatedSegmentRow(
                        segment: segment,
                        isHighlighted: !searchText.isEmpty
                    )
                    Divider()
                        .padding(.leading, 16)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Full Text

    private func fullTextView(_ result: TranscriptionResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(result.fullText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    // MARK: - Translated Full Text

    @available(macOS 15.0, *)
    private func translatedFullTextView(_ translated: TranslatedResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Original text (dimmed)
                Text(translated.original.fullText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Translated text
                Text(translated.translatedFullText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Helpers

    private func filteredSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !searchText.isEmpty else { return segments }
        return segments.filter { segment in
            segment.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    @available(macOS 15.0, *)
    private func filteredTranslatedSegments(_ segments: [TranslatedSegment]) -> [TranslatedSegment] {
        guard !searchText.isEmpty else { return segments }
        return segments.filter { segment in
            segment.original.text.localizedCaseInsensitiveContains(searchText)
            || segment.translatedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Translation Toolbar Content (macOS 15+)

@available(macOS 15.0, *)
private struct TranslationToolbarContent: View {
    let result: TranscriptionResult
    @ObservedObject var translationVM: TranslationViewModel

    var body: some View {
        let canTranslate = TranslationService.isLanguageSupported(result.language)

        if canTranslate {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("translation.title", systemImage: "character.book.closed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    // Target language picker
                    Picker("translation.targetLanguage", selection: $translationVM.selectedTargetLanguage) {
                        ForEach(translationVM.availableLanguages) { lang in
                            Text(String(localized: LocalizedStringResource(stringLiteral: lang.localizationKey)))
                                .tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)

                    // Translate button
                    if translationVM.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                        Text("translation.translating")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            translationVM.translate(result: result)
                        } label: {
                            Label("translation.translate", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    // Show original / translation toggle
                    if translationVM.translatedResult != nil {
                        Toggle(isOn: $translationVM.showTranslation) {
                            Text(translationVM.showTranslation
                                 ? "translation.showOriginal"
                                 : "translation.showTranslation")
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Button("translation.clear") {
                            translationVM.clearTranslation()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Error message
                if let error = translationVM.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: String(localized: "translation.error"), error))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                Divider()
            }
            .onAppear {
                translationVM.loadAvailableLanguages(sourceLanguage: result.language)
            }
            .onChange(of: result.language) {
                translationVM.loadAvailableLanguages(sourceLanguage: result.language)
                translationVM.clearTranslation()
            }
        }
    }
}

// MARK: - Translation Task Modifier

/// A view modifier that conditionally applies `.translationTask()` on macOS 15+.
private struct TranslationTaskModifier: ViewModifier {
    let translationVM: AnyObject?

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *),
           let vm = translationVM as? TranslationViewModel {
            content
                .translationTask(vm.translationConfiguration) { session in
                    await vm.performTranslation(using: session)
                }
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview("With Results") {
    ResultsView(
        result: TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0, endTime: 5.2, text: "Hello, welcome to this demo."),
                TranscriptionSegment(id: UUID(), startTime: 5.2, endTime: 10.8, text: "This is a sample transcription result."),
                TranscriptionSegment(id: UUID(), startTime: 10.8, endTime: 15.0, text: "Each segment has timestamps."),
            ],
            fullText: "Hello, welcome to this demo. This is a sample transcription result. Each segment has timestamps.",
            language: "en",
            duration: 15.0
        ),
        exportVM: ExportViewModel()
    )
    .frame(width: 700, height: 500)
}

#Preview("Empty") {
    ResultsView(result: nil, exportVM: ExportViewModel())
        .frame(width: 700, height: 500)
}
