//
//  UpdateAlertView.swift
//  OrangeNote
//
//  Sheet view displaying update check results.
//

import SwiftUI

/// Sheet view displaying update check results.
struct UpdateAlertView: View {
    @ObservedObject var viewModel: UpdateCheckerViewModel

    var body: some View {
        VStack(spacing: 20) {
            headerView
            contentView
            buttonBar
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        switch viewModel.status {
        case .checking:
            ProgressView()
                .scaleEffect(1.5)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
        case .updateAvailable:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.status {
        case .checking:
            Text("update.checking")
                .font(.headline)

        case .upToDate(let version):
            VStack(spacing: 8) {
                Text("update.upToDate")
                    .font(.headline)
                Text(String(format: L10n.localizedString("update.latestVersion"), version))
                    .foregroundStyle(.secondary)
            }

        case .updateAvailable(let current, let latest, _, let releaseNotes, _):
            VStack(spacing: 12) {
                Text("update.available")
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack {
                        Text("update.current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(current)
                            .font(.title3.monospacedDigit())
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    VStack {
                        Text("update.latest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(latest)
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.orange)
                    }
                }

                if !releaseNotes.isEmpty {
                    GroupBox {
                        ScrollView {
                            Text(releaseNotes)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    } label: {
                        Label("update.releaseNotes", systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

        case .error(let message):
            VStack(spacing: 8) {
                Text("update.failed")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .idle:
            EmptyView()
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonBar: some View {
        switch viewModel.status {
        case .checking:
            EmptyView()

        case .updateAvailable:
            HStack(spacing: 12) {
                Button("update.later") {
                    viewModel.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("update.download") {
                    viewModel.openReleasePage()
                    viewModel.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

        default:
            Button("update.ok") {
                viewModel.dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
