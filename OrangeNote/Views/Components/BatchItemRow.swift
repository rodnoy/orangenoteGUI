//
//  BatchItemRow.swift
//  OrangeNote
//
//  Row view displaying a single BatchItem in the batch queue with status, progress, and controls.
//

import SwiftUI

/// A row view displaying status, progress, and actions for an individual `BatchItem`.
struct BatchItemRow: View {
    /// The batch item to display.
    let item: BatchItem

    /// Whether this item is currently actively processing.
    var isProcessing: Bool = false

    /// Whether this item is currently selected and viewed in Results (Task 3.17).
    var isSelected: Bool = false

    /// Whether individual item removal is allowed (e.g. queue is not actively busy).
    var canRemove: Bool = true

    /// Optional callback when the remove button is tapped.
    var onRemove: (() -> Void)? = nil

    /// Optional callback when a completed item is selected/tapped to inspect its transcript (Task 3.17).
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon
                .frame(width: 24, height: 24)

            // File & Progress Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceURL.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                detailText
            }

            Spacer()

            // Status Badge
            statusBadge

            // Inspect Indicator for completed items
            if item.status == .succeeded && onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.orange : Color.secondary.opacity(0.5))
                    .padding(.leading, 2)
            }

            // Remove Button
            if canRemove && item.status == .queued {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help(L10n.string("batch.action.remove"))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
        }
        .overlay {
            if isProcessing {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.status == .succeeded {
                onSelect?()
            }
        }
        .help(item.status == .succeeded && onSelect != nil ? L10n.string("batch.action.viewTranscript") : "")
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
        case .transcribing:
            Image(systemName: "waveform")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .saving:
            Image(systemName: "arrow.down.doc.fill")
                .foregroundStyle(.orange)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.secondary)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail / Subtext

    @ViewBuilder
    private var detailText: some View {
        switch item.status {
        case .queued:
            Text(L10n.string("batch.status.item.queued"))
                .font(.caption)
                .foregroundStyle(.secondary)

        case .transcribing:
            HStack(spacing: 8) {
                ProgressView(value: Double(item.progress))
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(maxWidth: 120)

                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            }

        case .saving:
            Text(L10n.string("batch.status.item.saving"))
                .font(.caption)
                .foregroundStyle(.orange)

        case .succeeded:
            if let result = item.result {
                Text("\(result.formattedDuration) • \(result.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("batch.status.item.succeeded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed:
            if let errorMessage = item.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(L10n.string("batch.status.item.failed"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

        case .skipped:
            Text(L10n.string("batch.status.item.skipped"))
                .font(.caption)
                .foregroundStyle(.secondary)

        case .cancelled:
            Text(L10n.string("batch.status.item.cancelled"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        badgeContent
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(badgeForegroundColor)
            .background {
                Capsule()
                    .fill(badgeBackgroundColor)
            }
    }

    @ViewBuilder
    private var badgeContent: some View {
        switch item.status {
        case .queued:
            Text(L10n.string("batch.status.item.queued"))
        case .transcribing:
            Text(L10n.string("batch.status.item.transcribing"))
        case .saving:
            Text(L10n.string("batch.status.item.saving"))
        case .succeeded:
            Text(L10n.string("batch.status.item.succeeded"))
        case .failed:
            Text(L10n.string("batch.status.item.failed"))
        case .skipped:
            Text(L10n.string("batch.status.item.skipped"))
        case .cancelled:
            Text(L10n.string("batch.status.item.cancelled"))
        }
    }

    private var badgeForegroundColor: Color {
        switch item.status {
        case .queued:
            return .secondary
        case .transcribing, .saving:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .skipped, .cancelled:
            return .secondary
        }
    }

    private var badgeBackgroundColor: Color {
        switch item.status {
        case .queued:
            return Color.secondary.opacity(0.1)
        case .transcribing, .saving:
            return Color.orange.opacity(0.12)
        case .succeeded:
            return Color.green.opacity(0.12)
        case .failed:
            return Color.red.opacity(0.12)
        case .skipped, .cancelled:
            return Color.secondary.opacity(0.1)
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.orange.opacity(0.08)
        }
        if isProcessing {
            return Color.orange.opacity(0.04)
        }
        return Color.secondary.opacity(0.04)
    }
}
