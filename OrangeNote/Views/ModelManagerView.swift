//
//  ModelManagerView.swift
//  OrangeNote
//
//  Displays locally cached Whisper models with file paths and Finder integration.
//

import SwiftUI

/// Displays downloaded Whisper models with their file paths and Finder actions.
struct ModelManagerView: View {
    @ObservedObject var viewModel: ModelManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingState
            } else if viewModel.cachedModels.isEmpty {
                emptyState
            } else {
                modelList
            }

            if let cacheDir = viewModel.cacheDirectory {
                cacheDirFooter(cacheDir)
            }
        }
        .navigationTitle("models.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadModels() }
                } label: {
                    Label("models.refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            if viewModel.models.isEmpty {
                await viewModel.loadModels()
            }
        }
        .alert("models.error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("models.ok") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("models.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("models.noModels")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("models.noModels.description")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Model List

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Section {
                    ForEach(viewModel.cachedModels) { model in
                        modelRow(model)
                    }
                } header: {
                    HStack {
                        Text("models.downloaded")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: WhisperModel) -> some View {
        HStack(spacing: 16) {
            // Model icon
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 32)

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name.capitalized)
                        .font(.body.weight(.medium))

                    Text(model.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let filePath = model.filePath {
                    HStack(spacing: 4) {
                        Text("models.filePath")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(abbreviatePath(filePath))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            // Show in Finder button
            if model.filePath != nil {
                Button {
                    viewModel.openInFinder(model: model)
                } label: {
                    Label("models.showInFinder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        }
    }

    // MARK: - Cache Directory Footer

    private func cacheDirFooter(_ path: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("models.cacheDir")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(abbreviatePath(path))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                viewModel.openCacheDirectory()
            } label: {
                Label("models.openCacheDir", systemImage: "folder.badge.gearshape")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(Color(.windowBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: -1)
        }
    }

    // MARK: - Helpers

    /// Abbreviates a file path by replacing the home directory with `~`.
    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Preview

#Preview {
    ModelManagerView(viewModel: ModelManagerViewModel())
        .frame(width: 600, height: 500)
}
