//
//  TranslationService.swift
//  OrangeNote
//
//  Service for language availability checks and mapping for Apple Translation (macOS 15+).
//

import Foundation

#if canImport(Translation)
import Translation
#endif

/// Provides language mapping and availability checks for Apple Translation.
///
/// The actual translation is performed via SwiftUI's `.translationTask()` modifier,
/// since `TranslationSession` cannot be instantiated directly outside of that context.
/// This service handles language code mapping between Whisper and Apple Translation,
/// and checks whether translation is available on the current system.
@available(macOS 15.0, *)
enum TranslationService {

    // MARK: - Supported Languages

    /// Languages supported by Apple Translation, as `(code, localizationKey)` pairs.
    static let supportedLanguages: [(code: String, localizationKey: String)] = [
        ("ar", "lang.ar"),
        ("zh-Hans", "lang.zh"),
        ("zh-Hant", "lang.zh"),
        ("nl", "lang.nl"),
        ("en", "lang.en"),
        ("fr", "lang.fr"),
        ("de", "lang.de"),
        ("hi", "lang.hi"),
        ("id", "lang.id"),
        ("it", "lang.it"),
        ("ja", "lang.ja"),
        ("ko", "lang.ko"),
        ("pl", "lang.pl"),
        ("pt-BR", "lang.pt"),
        ("ru", "lang.ru"),
        ("es", "lang.es"),
        ("th", "lang.th"),
        ("tr", "lang.tr"),
        ("uk", "lang.uk"),
        ("vi", "lang.vi"),
    ]

    // MARK: - Language Mapping

    /// Maps Whisper language codes to Apple Translation language codes.
    static func mapWhisperToAppleLanguage(_ code: String) -> String {
        switch code {
        case "zh": return "zh-Hans"
        case "pt": return "pt-BR"
        default:   return code
        }
    }

    /// Whether a Whisper language code is supported by Apple Translation.
    static func isLanguageSupported(_ languageCode: String) -> Bool {
        let mapped = mapWhisperToAppleLanguage(languageCode)
        return supportedLanguages.contains { $0.code == mapped }
    }

    /// Returns available target languages, excluding the source language.
    static func availableTargetLanguages(
        excluding sourceCode: String
    ) -> [(code: String, localizationKey: String)] {
        let mappedSource = mapWhisperToAppleLanguage(sourceCode)
        return supportedLanguages.filter { $0.code != mappedSource }
    }

    // MARK: - Availability Check

    /// Checks whether translation is available for a given language pair using `LanguageAvailability`.
    static func isAvailable(
        from source: String,
        to target: String
    ) async -> Bool {
        let availability = LanguageAvailability()
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)
        let status = await availability.status(from: sourceLang, to: targetLang)
        return status == .installed || status == .supported
    }
}
