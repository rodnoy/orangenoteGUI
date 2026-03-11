//
//  ExportView.swift
//  OrangeNote
//
//  Export format selection, preview, and save functionality.
//

import SwiftUI

/// Interface for exporting transcription results to various formats.
struct ExportView: View {
    let result: TranscriptionResult?
    @ObservedObject var viewModel: ExportViewModel

    var body: some View {
        Group {
            if let result {
                exportContent(result)
            } else {
                emptyState
            }
        }
        .navigationTitle("export.title")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("export.empty.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("export.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export Content

    private func exportContent(_ result: TranscriptionResult) -> some View {
        VStack(spacing: 0) {
            // Format picker and actions
            HStack(spacing: 16) {
                Picker("export.format", selection: $viewModel.selectedFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()

                Button {
                    viewModel.copyToClipboard(result: result)
                } label: {
                    Label("export.copy", systemImage: "doc.on.doc")
                }

                Button {
                    viewModel.saveToFile(result: result)
                } label: {
                    Label("export.saveAs", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(16)

            Divider()

            // Success banner
            if viewModel.exportSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("export.success")
                        .font(.callout)
                    Spacer()
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("export.dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
            }

            // Preview
            ScrollView {
                if let content = viewModel.exportedContent {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    VStack(spacing: 8) {
                        Text("export.preview")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                }
            }
            .background(Color(.textBackgroundColor))
        }
        .onChange(of: viewModel.selectedFormat) {
            viewModel.generateExport(result: result)
        }
        .onAppear {
            viewModel.generateExport(result: result)
        }
    }
}

// MARK: - Preview

#Preview {
    ExportView(
        result: TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0, endTime: 5.2, text: "Hello world."),
            ],
            fullText: "Hello world.",
            language: "en",
            duration: 5.2
        ),
        viewModel: ExportViewModel()
    )
    .frame(width: 700, height: 500)
}
