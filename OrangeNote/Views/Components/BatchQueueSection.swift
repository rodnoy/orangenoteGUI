//
//  BatchQueueSection.swift
//  OrangeNote
//
//  Component rendering the batch queue, progress summary, destination directory, and controls.
//

import SwiftUI

/// A component displaying the batch transcription queue, progress, output destination, and controls.
struct BatchQueueSection: View {
    @ObservedObject var viewModel: BatchTranscriptionViewModel
    var singleFileIsBusy: Bool = false
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Output Destination Card
            destinationCard

            // Action Toolbar (Add files, folder, clear)
            actionToolbar

            // Overall Progress & Summary (when active or completed)
            if viewModel.isBusy || viewModel.summary.completedCount > 0 {
                overallProgressCard
            }

            // Queue List / Empty State
            queueContent

            // Execution Controls (Start / Cancel)
            executionControls

            // Quick Settings Summary
            settingsSummary

            // Error Message
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.string("batch.destination"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let source = viewModel.outputResolutionSource {
                        resolutionTag(for: source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let outputDir = viewModel.outputDirectory {
                    Text(outputDir.path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                } else {
                    Text(L10n.string("batch.destination.none"))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button {
                Task {
                    await viewModel.promptAndSelectOutputDirectory()
                }
            } label: {
                Text(L10n.string("batch.destination.change"))
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isBusy)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        }
    }

    @ViewBuilder
    private func resolutionTag(for source: BatchOutputPolicyResolutionSource) -> some View {
        switch source {
        case .sourceFolder:
            Text(L10n.string("batch.destination.source"))
        case .custom:
            Text(L10n.string("batch.destination.custom"))
        case .userOverride:
            Text(L10n.string("batch.destination.override"))
        case .systemDefault:
            Text(L10n.string("batch.destination.system"))
        }
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.promptAndIngestFiles()
                }
            } label: {
                Label(L10n.string("batch.action.addFiles"), systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)

            Button {
                Task {
                    await viewModel.promptAndIngestFolder()
                }
            } label: {
                Label(L10n.string("batch.action.addFolder"), systemImage: "folder.badge.plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)

            Spacer()

            Button {
                viewModel.clear()
            } label: {
                Label(L10n.string("batch.action.clear"), systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isBusy || viewModel.items.isEmpty ? Color.secondary.opacity(0.5) : Color.secondary)
            .disabled(viewModel.isBusy || viewModel.items.isEmpty)
        }
    }

    // MARK: - Overall Progress Card

    private var overallProgressCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(viewModel.statusMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(viewModel.overallProgress * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(viewModel.overallProgress))
                .progressViewStyle(.linear)
                .tint(.orange)

            // Summary counts chips
            HStack(spacing: 12) {
                summaryChip(
                    title: L10n.string("batch.summary.total"),
                    count: viewModel.summary.totalCount,
                    color: .secondary
                )
                summaryChip(
                    title: L10n.string("batch.summary.succeeded"),
                    count: viewModel.summary.succeededCount,
                    color: .green
                )
                if viewModel.summary.failedCount > 0 {
                    summaryChip(
                        title: L10n.string("batch.summary.failed"),
                        count: viewModel.summary.failedCount,
                        color: .red
                    )
                }
                if viewModel.summary.skippedCount > 0 {
                    summaryChip(
                        title: L10n.string("batch.summary.skipped"),
                        count: viewModel.summary.skippedCount,
                        color: .orange
                    )
                }
                summaryChip(
                    title: L10n.string("batch.summary.queued"),
                    count: max(0, viewModel.summary.totalCount - viewModel.summary.completedCount),
                    color: .secondary
                )
                Spacer()
            }
            .font(.caption2)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private func summaryChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.1))
        }
    }

    // MARK: - Queue Content

    @ViewBuilder
    private var queueContent: some View {
        if viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.down.forward")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(L10n.string("batch.queue.empty"))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(L10n.string("batch.queue.emptySubtitle"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.string("batch.queue.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.items.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 6) {
                    ForEach(viewModel.items) { item in
                        BatchItemRow(
                            item: item,
                            isProcessing: viewModel.activeItemID == item.id,
                            isSelected: appState.selectedBatchItemID == item.id,
                            canRemove: !viewModel.isBusy,
                            onRemove: {
                                viewModel.removeItem(id: item.id)
                            },
                            onSelect: item.status == .succeeded ? {
                                appState.routeToBatchItemResult(
                                    item,
                                    modelName: viewModel.configuration.modelName
                                )
                            } : nil
                        )
                    }
                }
            }
        }
    }

    // MARK: - Execution Controls

    private var executionControls: some View {
        VStack(spacing: 12) {
            if viewModel.isCancelling {
                Button(role: .cancel) {} label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string("batch.action.cancelling"))
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
            } else if viewModel.isRunning {
                Button(role: .destructive) {
                    viewModel.cancel()
                } label: {
                    Label(L10n.string("batch.action.cancel"), systemImage: "xmark.circle")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    startBatchWithSettings()
                } label: {
                    Label(L10n.string("batch.action.start"), systemImage: "play.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(!viewModel.canStart || singleFileIsBusy)
            }
        }
        .padding(.top, 8)
    }

    private func startBatchWithSettings() {
        let config = BatchTranscriptionConfiguration(
            modelName: settings.selectedModel,
            language: settings.language == "auto" ? nil : settings.language,
            translateToEnglish: settings.translateToEnglish,
            chunkingEnabled: settings.useChunking,
            chunkDurationSeconds: settings.useChunking ? Double(settings.chunkDuration) : nil,
            overlapDurationSeconds: settings.useChunking ? Double(settings.overlapDuration) : nil
        )
        viewModel.updateConfiguration(config)
        viewModel.start()
    }

    // MARK: - Settings Summary

    private var settingsSummary: some View {
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

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
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
    }
}
