//
//  SettingsView.swift
//  OrangeNote
//
//  Application settings for model, language, and chunking configuration.
//

import SwiftUI

/// Settings interface for configuring transcription parameters.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                modelSection
                languageSection
                chunkingSection
                aboutSection
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
    }

    // MARK: - Model Section

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Whisper Model", systemImage: "cpu")
                    .font(.headline)

                Picker("Model", selection: $settings.selectedModel) {
                    Text("Tiny").tag("tiny")
                    Text("Base").tag("base")
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
                .pickerStyle(.menu)

                Text("Larger models are more accurate but slower and require more memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Language", systemImage: "globe")
                    .font(.headline)

                Picker("Language", selection: $settings.language) {
                    ForEach(AppSettings.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                Text("Select \"Auto-detect\" to let Whisper identify the language automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Chunking Section

    private var chunkingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Chunked Processing", systemImage: "rectangle.split.3x1")
                    .font(.headline)

                Toggle("Enable chunked transcription", isOn: $settings.useChunking)

                if settings.useChunking {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Chunk duration:")
                                .font(.subheadline)
                            Spacer()
                            Text("\(settings.chunkDuration)s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.chunkDuration) },
                                set: { settings.chunkDuration = Int($0) }
                            ),
                            in: 10...120,
                            step: 5
                        )
                        .tint(.orange)

                        HStack {
                            Text("Overlap duration:")
                                .font(.subheadline)
                            Spacer()
                            Text("\(settings.overlapDuration)s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.overlapDuration) },
                                set: { settings.overlapDuration = Int($0) }
                            ),
                            in: 0...30,
                            step: 1
                        )
                        .tint(.orange)
                    }
                    .padding(.leading, 4)
                }

                Text("Chunking splits long audio files into smaller pieces for processing. Use this for files longer than a few minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("About", systemImage: "info.circle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("OrangeNote")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("v\(UpdateCheckerService.currentAppVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Local audio transcription powered by Whisper")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("All processing happens on your device. No data is sent to external servers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .frame(width: 500, height: 600)
}
