//
//  TranslationViewModel.swift
//  OrangeNote
//
//  View model for managing Apple Translation state (macOS 15+).
//

import SwiftUI

#if canImport(Translation)
import Translation
#endif

/// Manages translation state and coordinates with the `.translationTask()` SwiftUI modifier.
///
/// Translation on macOS 15+ requires using SwiftUI's `.translationTask(configuration)` modifier
/// to obtain a `TranslationSession`. This view model manages the configuration lifecycle
/// and stores translation results.
@available(macOS 15.0, *)
@MainActor
final class TranslationViewModel: ObservableObject {

    // MARK: - Published State

    /// Whether a translation is currently in progress.
    @Published var isTranslating: Bool = false

    /// The translated result, available after successful translation.
    @Published var translatedResult: TranslatedResult?

    /// The selected target language code for translation.
    @Published var selectedTargetLanguage: String = "en"

    /// Error message to display when translation fails.
    @Published var errorMessage: String?

    /// Available target languages for the current source language.
    @Published var availableLanguages: [LanguageOption] = []

    /// Whether to show translated text instead of original.
    @Published var showTranslation: Bool = false

    /// Translation progress from 0.0 to 1.0 during batch segment translation.
    @Published var translationProgress: Double = 0

    /// The translation configuration that triggers `.translationTask()` when set.
    @Published var translationConfiguration: TranslationSession.Configuration?

    // MARK: - Types

    /// Represents a selectable target language for translation.
    struct LanguageOption: Identifiable, Hashable {
        let id: String
        let code: String
        let localizationKey: String
    }

    // MARK: - Private

    /// Segments pending translation, stored between configuration trigger and session callback.
    private var pendingSegments: [TranscriptionSegment] = []

    /// Full text pending translation.
    private var pendingFullText: String = ""

    /// Source language for the pending translation.
    private var pendingSourceLanguage: String = ""

    // MARK: - Actions

    /// Loads available target languages for the given source language.
    func loadAvailableLanguages(sourceLanguage: String) {
        let targets = TranslationService.availableTargetLanguages(excluding: sourceLanguage)
        availableLanguages = targets.map { target in
            LanguageOption(
                id: target.code,
                code: target.code,
                localizationKey: target.localizationKey
            )
        }

        // Default to English if available, otherwise first available language
        if let firstEnglish = availableLanguages.first(where: { $0.code == "en" }) {
            selectedTargetLanguage = firstEnglish.code
        } else if let first = availableLanguages.first {
            selectedTargetLanguage = first.code
        }
    }

    /// Triggers translation of the given transcription result.
    ///
    /// Sets up the `translationConfiguration` which the View observes via `.translationTask()`.
    func translate(result: TranscriptionResult) {
        guard !isTranslating else { return }

        let sourceCode = TranslationService.mapWhisperToAppleLanguage(result.language)
        let targetCode = selectedTargetLanguage

        pendingSegments = result.segments
        pendingFullText = result.fullText
        pendingSourceLanguage = result.language

        isTranslating = true
        errorMessage = nil
        showTranslation = false
        translationProgress = 0

        let source = Locale.Language(identifier: sourceCode)
        let target = Locale.Language(identifier: targetCode)

        // Setting configuration triggers the `.translationTask()` modifier in the View
        if translationConfiguration != nil {
            translationConfiguration?.invalidate()
        }
        translationConfiguration = .init(source: source, target: target)
    }

    /// Called by the View's `.translationTask()` callback with the active session.
    func performTranslation(using session: TranslationSession) async {
        do {
            // Translate full text
            let fullTextResponse = try await session.translate(pendingFullText)
            let translatedFullText = fullTextResponse.targetText

            // Translate segments in batch
            let requests = pendingSegments.enumerated().map { index, segment in
                TranslationSession.Request(
                    sourceText: segment.text,
                    clientIdentifier: "\(index)"
                )
            }

            var translatedTexts = Array(repeating: "", count: pendingSegments.count)
            let totalSegments = Double(pendingSegments.count)
            var completedSegments = 0.0

            for try await response in session.translate(batch: requests) {
                if let clientId = response.clientIdentifier,
                   let index = Int(clientId) {
                    translatedTexts[index] = response.targetText
                    completedSegments += 1
                    translationProgress = completedSegments / totalSegments
                }
            }

            let translatedSegments = pendingSegments.enumerated().map { index, segment in
                TranslatedSegment(
                    original: segment,
                    translatedText: translatedTexts[index]
                )
            }

            translatedResult = TranslatedResult(
                original: TranscriptionResult(
                    segments: pendingSegments,
                    fullText: pendingFullText,
                    language: pendingSourceLanguage,
                    duration: 0
                ),
                targetLanguage: selectedTargetLanguage,
                translatedFullText: translatedFullText,
                translatedSegments: translatedSegments
            )

            showTranslation = true

            NotificationService.sendTranslationComplete(
                targetLanguage: selectedTargetLanguage,
                segmentCount: translatedSegments.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }

    /// Clears the current translation and resets state.
    func clearTranslation() {
        translatedResult = nil
        showTranslation = false
        errorMessage = nil
        translationConfiguration = nil
        translationProgress = 0
        pendingSegments = []
        pendingFullText = ""
        pendingSourceLanguage = ""
    }
}
