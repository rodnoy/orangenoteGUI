//
//  ModelManagerView.swift
//  OrangeNote
//
//  Model download and management interface.
//

import SwiftUI

/// Displays available Whisper models with their download/cache status.
struct ModelManagerView: View {
    @ObservedObject var viewModel: ModelManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingState
            } else if viewModel.models.isEmpty {
                emptyState
            } else {
                modelList
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

            if viewModel.cacheDirectory != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        viewModel.openCacheDirectory()
                    } label: {
                        Label("models.openCache", systemImage: "folder")
                    }
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
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("models.empty.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Button("models.retry") {
                Task { await viewModel.loadModels() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Model List

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.models) { model in
                    modelRow(model)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: WhisperModel) -> some View {
        HStack(spacing: 16) {
            // Model icon
            Image(systemName: model.isCached ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(model.isCached ? .green : .orange)
                .frame(width: 32)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name.capitalized)
                    .font(.body.weight(.medium))

                HStack(spacing: 8) {
                    Text(model.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.isCached {
                        Text("models.cached")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background {
                                Capsule()
                                    .fill(Color.green.opacity(0.1))
                            }
                    }
                }
            }

            Spacer()

            // Status / action
            if model.isCached {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.body.weight(.medium))
            } else {
                Text("models.notDownloaded")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        }
    }
}

// MARK: - Preview

#Preview {
    ModelManagerView(viewModel: ModelManagerViewModel())
        .frame(width: 600, height: 500)
}
