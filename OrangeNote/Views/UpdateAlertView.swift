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
            Text("Checking for updates...")
                .font(.headline)

        case .upToDate(let version):
            VStack(spacing: 8) {
                Text("You're up to date!")
                    .font(.headline)
                Text("OrangeNote \(version) is the latest version.")
                    .foregroundStyle(.secondary)
            }

        case .updateAvailable(let current, let latest, _, let releaseNotes, _):
            VStack(spacing: 12) {
                Text("Update Available")
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(current)
                            .font(.title3.monospacedDigit())
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    VStack {
                        Text("Latest")
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
                        Label("Release Notes", systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

        case .error(let message):
            VStack(spacing: 8) {
                Text("Update Check Failed")
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
                Button("Later") {
                    viewModel.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Download") {
                    viewModel.openReleasePage()
                    viewModel.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

        default:
            Button("OK") {
                viewModel.dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
