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

    /// Whether the translate toggle should be disabled (English is explicitly selected).
    private var isTranslateDisabled: Bool {
        settings.language == "en"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                modelSection
                languageSection
                translationSection
                chunkingSection
                appLanguageSection
                aboutSection
            }
            .padding(24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("settings.title")
    }

    // MARK: - Model Section

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("settings.model.title", systemImage: "cpu")
                    .font(.headline)

                Picker("settings.model.label", selection: $settings.selectedModel) {
                    Text("model.tiny").tag("tiny")
                    Text("model.base").tag("base")
                    Text("model.small").tag("small")
                    Text("model.medium").tag("medium")
                    Text("model.large").tag("large")
                }
                .pickerStyle(.menu)

                Text("settings.model.description")
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
                Label("settings.language.title", systemImage: "globe")
                    .font(.headline)

                Picker("settings.language.label", selection: $settings.language) {
                    ForEach(AppSettings.availableLanguages, id: \.code) { lang in
                        Text(verbatim: L10n.localizedString("lang.\(lang.code)")).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                Text("settings.language.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Translation Section

    private var translationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("settings.translation.title", systemImage: "character.book.closed")
                    .font(.headline)

                Toggle("settings.translation.toEnglish", isOn: $settings.translateToEnglish)
                    .disabled(isTranslateDisabled)
                    .onChange(of: settings.language) { _, newValue in
                        if newValue == "en" {
                            settings.translateToEnglish = false
                        }
                    }

                Text("settings.translation.description")
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
                Label("settings.chunking.title", systemImage: "rectangle.split.3x1")
                    .font(.headline)

                Toggle("settings.chunking.enable", isOn: $settings.useChunking)

                if settings.useChunking {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("settings.chunking.duration")
                                .font(.subheadline)
                            Spacer()
                            (Text("\(settings.chunkDuration)") + Text(LocalizedStringKey("time.seconds.short")))
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
                            Text("settings.chunking.overlap")
                                .font(.subheadline)
                            Spacer()
                            (Text("\(settings.overlapDuration)") + Text(LocalizedStringKey("time.seconds.short")))
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

                Text("settings.chunking.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - About Section

    private var appLanguageSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("settings.appLanguage.title", systemImage: "globe")
                    .font(.headline)

                Picker("settings.appLanguage.title", selection: $settings.appLanguage) {
                    ForEach(L10n.supportedLanguages, id: \.code) { lang in
                        if lang.code == "system" {
                            Text(verbatim: L10n.localizedString(lang.name)).tag(lang.code)
                        } else {
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var aboutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("settings.about.title", systemImage: "info.circle")
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

                    Text("settings.about.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("settings.about.privacy")
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
