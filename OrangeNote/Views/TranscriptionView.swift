//
//  TranscriptionView.swift
//  OrangeNote
//
//  File selection, batch queue management, transcription control, and progress display.
//

import SwiftUI

/// Conceptual mode for the transcription screen.
enum TranscriptionMode: String, CaseIterable, Identifiable {
    case single
    case batch

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .single: return "transcription.mode.single"
        case .batch: return "transcription.mode.batch"
        }
    }

    var title: String {
        L10n.string(titleKey)
    }
}

/// The main transcription interface supporting single-file and batch modes with progress tracking.
@MainActor
struct TranscriptionView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @ObservedObject var batchViewModel: BatchTranscriptionViewModel
    @EnvironmentObject private var settings: AppSettings

    /// Current mode (single file vs batch queue).
    @State var selectedMode: TranscriptionMode

    /// Whether a drag is currently hovering over the page-level drop target (Task 1.6 / 3.14).
    @State private var isDropTargeted = false

    init(
        viewModel: TranscriptionViewModel,
        batchViewModel: BatchTranscriptionViewModel,
        initialMode: TranscriptionMode = .single
    ) {
        self.viewModel = viewModel
        self.batchViewModel = batchViewModel
        self._selectedMode = State(initialValue: initialMode)
    }

    init(
        viewModel: TranscriptionViewModel,
        initialMode: TranscriptionMode = .single
    ) {
        self.viewModel = viewModel
        self.batchViewModel = BatchTranscriptionViewModel()
        self._selectedMode = State(initialValue: initialMode)
    }

    private var isAnyBusy: Bool {
        viewModel.isBusy || batchViewModel.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                modePickerSection

                switch selectedMode {
                case .single:
                    fileSection
                    controlSection
                    progressSection
                    errorSection
                case .batch:
                    BatchQueueSection(
                        viewModel: batchViewModel,
                        singleFileIsBusy: viewModel.isBusy,
                        settings: settings
                    )
                }
            }
            .padding(24)
        }
        .navigationTitle(L10n.string("transcription.title"))
        .overlay {
            // Visual drop-target indicator shown for the entire page while a drag is hovering.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.05))
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        // Page-level drop target (Tasks 1.6, 3.14): stays attached to the whole view regardless of
        // whether a file is already selected, so users can drag files or folders at any time while idle.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handlePageDrop(providers: providers)
        }
    }

    // MARK: - Drop Handling

    private func handlePageDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        DropItemResolver.extractAndResolve(from: providers, isTranscribing: isAnyBusy) { resolution in
            switch resolution {
            case .accepted(let url):
                // Re-check busy state at commit time (Task 1.13 / D010)
                if isAnyBusy {
                    if let message = DropResolution.rejectedTranscribing.localizedMessage {
                        reportDropRejection(message)
                    }
                } else {
                    if selectedMode == .batch {
                        batchViewModel.ingestFiles([url])
                    } else {
                        viewModel.handleDroppedFile(url)
                    }
                }
            case .batch(let ingestionResult):
                if isAnyBusy {
                    if let message = DropResolution.rejectedTranscribing.localizedMessage {
                        reportDropRejection(message)
                    }
                } else {
                    selectedMode = .batch
                    batchViewModel.ingestResult(ingestionResult)
                }
            case .rejectedTranscribing, .rejectedMixedItems, .rejectedMultipleItems, .invalidFile, .noAudioFilesFound, .extractionFailed:
                if let message = resolution.localizedMessage {
                    reportDropRejection(message)
                }
            }
        }
        return true
    }

    private func reportDropRejection(_ message: String) {
        if selectedMode == .batch {
            viewModel.reportDropRejection(message)
        } else {
            viewModel.reportDropRejection(message)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(L10n.string("transcription.header"))
                .font(.title2.weight(.semibold))

            Text(L10n.string("transcription.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Mode Picker

    private var modePickerSection: some View {
        Picker(L10n.string("transcription.mode"), selection: $selectedMode) {
            Text(L10n.string("transcription.mode.single")).tag(TranscriptionMode.single)
            Text(L10n.string("transcription.mode.batch")).tag(TranscriptionMode.batch)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
        .disabled(isAnyBusy)
    }

    // MARK: - Single File: File Selection

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
                    Label(L10n.string("transcription.changeFile"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(viewModel.isBusy)
            } else {
                FileDropZone(
                    onChooseFile: {
                        viewModel.selectFile()
                    },
                    onChooseFolder: {
                        selectedMode = .batch
                        Task {
                            await batchViewModel.promptAndIngestFolder()
                        }
                    },
                    isTargeted: isDropTargeted
                )
            }
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Single File: Controls

    private var controlSection: some View {
        VStack(spacing: 12) {
            if viewModel.isTranscribing {
                Button(role: .destructive) {
                    viewModel.cancelTranscription()
                } label: {
                    Label(L10n.string("transcription.cancel"), systemImage: "xmark.circle")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    viewModel.startTranscription(settings: settings)
                } label: {
                    Label(L10n.string("transcription.start"), systemImage: "play.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(!viewModel.canStartTranscription || batchViewModel.isBusy)
            }

            // Quick settings summary
            HStack(spacing: 16) {
                Label(settings.selectedModel, systemImage: "cpu")
                if settings.language == "auto" {
                    Label(L10n.string("transcription.auto"), systemImage: "globe")
                } else {
                    Label(settings.language.uppercased(), systemImage: "globe")
                }
                if settings.useChunking {
                    Label(L10n.string("transcription.chunked"), systemImage: "rectangle.split.3x1")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Single File: Progress

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
        } else if viewModel.isCancelling {
            ProgressIndicator(
                progress: 0,
                statusMessage: viewModel.statusMessage,
                isIndeterminate: true
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

    // MARK: - Single File: Error

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
                Button(L10n.string("transcription.dismiss")) {
                    viewModel.dismissError()
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

    // MARK: - Single File: Completion Summary

    private func completionSummary(_ result: TranscriptionResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text(L10n.string("transcription.complete"))
                .font(.headline)

            HStack(spacing: 24) {
                statItem(title: L10n.string("transcription.duration"), value: result.formattedDuration)
                statItem(title: L10n.string("transcription.segments"), value: "\(result.segmentCount)")
                statItem(title: L10n.string("transcription.words"), value: "\(result.wordCount)")
                statItem(title: L10n.string("transcription.language"), value: result.language.uppercased())
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
    TranscriptionView(
        viewModel: TranscriptionViewModel(),
        batchViewModel: BatchTranscriptionViewModel()
    )
    .environmentObject(AppSettings())
    .frame(width: 600, height: 600)
}
