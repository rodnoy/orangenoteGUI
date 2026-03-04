//
//  TranscriptionView.swift
//  OrangeNote
//
//  File selection, transcription control, and progress display.
//

import SwiftUI

/// The main transcription interface with file selection and progress tracking.
struct TranscriptionView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                fileSection
                controlSection
                progressSection
                errorSection
            }
            .padding(24)
        }
        .navigationTitle("Transcribe")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Audio Transcription")
                .font(.title2.weight(.semibold))

            Text("Select an audio file to transcribe using Whisper")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: - File Selection

    private var fileSection: some View {
        VStack(spacing: 12) {
            if let fileName = viewModel.selectedFileName {
                AudioFileInfo(
                    fileName: fileName,
                    fileSize: viewModel.selectedFileSize
                )

                // Change file button
                Button {
                    viewModel.selectFile()
                } label: {
                    Label("Change File", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                FileDropZone(
                    onDrop: { url in
                        viewModel.handleDroppedFile(url)
                    },
                    onChooseFile: {
                        viewModel.selectFile()
                    }
                )
            }
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controlSection: some View {
        VStack(spacing: 12) {
            if viewModel.isTranscribing {
                Button(role: .destructive) {
                    viewModel.cancelTranscription()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    viewModel.startTranscription(settings: settings)
                } label: {
                    Label("Start Transcription", systemImage: "play.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(!viewModel.canStartTranscription)
            }

            // Quick settings summary
            HStack(spacing: 16) {
                Label(settings.selectedModel, systemImage: "cpu")
                Label(
                    settings.language == "auto" ? "Auto" : settings.language.uppercased(),
                    systemImage: "globe"
                )
                if settings.useChunking {
                    Label("Chunked", systemImage: "rectangle.split.3x1")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if viewModel.isTranscribing {
            ProgressIndicator(
                progress: viewModel.progress,
                statusMessage: viewModel.statusMessage,
                isIndeterminate: viewModel.progress == 0
            )
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if let result = viewModel.result {
            completionSummary(result)
                .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                Spacer()
                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Completion Summary

    private func completionSummary(_ result: TranscriptionResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("Transcription Complete")
                .font(.headline)

            HStack(spacing: 24) {
                statItem(title: "Duration", value: result.formattedDuration)
                statItem(title: "Segments", value: "\(result.segmentCount)")
                statItem(title: "Words", value: "\(result.wordCount)")
                statItem(title: "Language", value: result.language.uppercased())
            }
        }
        .padding(16)
        .frame(maxWidth: 500)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.green.opacity(0.2))
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    TranscriptionView(viewModel: TranscriptionViewModel())
        .environmentObject(AppSettings())
        .frame(width: 600, height: 500)
}
