//
//  ResultsView.swift
//  OrangeNote
//
//  Displays transcription results with segments, search, and copy functionality.
//

import SwiftUI

/// Displays the transcription result with segment list, search, and export options.
struct ResultsView: View {
    let result: TranscriptionResult?
    @ObservedObject var exportVM: ExportViewModel

    @State private var searchText = ""
    @State private var showFullText = false

    var body: some View {
        Group {
            if let result {
                resultContent(result)
            } else {
                emptyState
            }
        }
        .navigationTitle("Results")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Results Yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Transcribe an audio file to see results here")
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

            if showFullText {
                fullTextView(result)
            } else {
                segmentListView(result)
            }
        }
    }

    // MARK: - Toolbar

    private func toolbar(_ result: TranscriptionResult) -> some View {
        HStack(spacing: 12) {
            // View mode toggle
            Picker("View", selection: $showFullText) {
                Label("Segments", systemImage: "list.bullet")
                    .tag(false)
                Label("Full Text", systemImage: "doc.plaintext")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            if !showFullText {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search segments…", text: $searchText)
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
                Label("\(result.segmentCount) segments", systemImage: "text.alignleft")
                Label(result.formattedDuration, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Copy button
            Menu {
                Button("Copy All Text") {
                    copyToClipboard(result.fullText)
                }
                Button("Copy as JSON") {
                    exportVM.selectedFormat = .json
                    exportVM.copyToClipboard(result: result)
                }
                Button("Copy as SRT") {
                    exportVM.selectedFormat = .srt
                    exportVM.copyToClipboard(result: result)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    // MARK: - Helpers

    private func filteredSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        guard !searchText.isEmpty else { return segments }
        return segments.filter { segment in
            segment.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
