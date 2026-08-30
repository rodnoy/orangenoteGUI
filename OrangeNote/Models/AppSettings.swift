//
//  AppSettings.swift
//  OrangeNote
//
//  Observable user settings persisted via UserDefaults.
//

import SwiftUI

/// Application-wide settings persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private let userDefaults: UserDefaults

    /// Selected Whisper model name (e.g. "base", "small", "medium").
    @Published var selectedModel: String {
        didSet { userDefaults.set(selectedModel, forKey: "selectedModel") }
    }

    /// Language code for transcription ("auto" for auto-detection).
    @Published var language: String {
        didSet { userDefaults.set(language, forKey: "language") }
    }

    /// Whether to use chunked transcription for long files.
    @Published var useChunking: Bool {
        didSet { userDefaults.set(useChunking, forKey: "useChunking") }
    }

    /// Duration of each chunk in seconds (when chunking is enabled).
    @Published var chunkDuration: Int {
        didSet { userDefaults.set(chunkDuration, forKey: "chunkDuration") }
    }

    /// Overlap between chunks in seconds (when chunking is enabled).
    @Published var overlapDuration: Int {
        didSet { userDefaults.set(overlapDuration, forKey: "overlapDuration") }
    }

    /// Whether to translate non-English audio to English using Whisper's built-in translate mode.
    @Published var translateToEnglish: Bool {
        didSet { userDefaults.set(translateToEnglish, forKey: "translateToEnglish") }
    }

    /// User-selected app language override ("system" follows system locale).
    @Published var appLanguage: String {
        didSet {
            userDefaults.set(appLanguage, forKey: "appLanguage")
            syncAppleLanguages(for: appLanguage)
            L10n.currentLanguage = appLanguage
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedModel = userDefaults.string(forKey: "selectedModel") ?? "base"
        self.selectedModel = (storedModel == "large") ? "large-v3" : storedModel
        self.language = userDefaults.string(forKey: "language") ?? "auto"
        self.useChunking = userDefaults.object(forKey: "useChunking") as? Bool ?? false
        self.chunkDuration = userDefaults.object(forKey: "chunkDuration") as? Int ?? 30
        self.overlapDuration = userDefaults.object(forKey: "overlapDuration") as? Int ?? 5
        self.translateToEnglish = userDefaults.object(forKey: "translateToEnglish") as? Bool ?? false
        let lang = userDefaults.string(forKey: "appLanguage") ?? "system"
        self.appLanguage = lang
        syncAppleLanguages(for: lang)
        L10n.currentLanguage = lang
    }

    /// Synchronizes UserDefaults `AppleLanguages` with the selected language.
    ///
    /// For explicit languages ("en", "ru", "fr"), sets `[languageCode]` so the OS respects it on next launch.
    /// For "system", removes the key so system choice applies on future process launches.
    private func syncAppleLanguages(for language: String) {
        if language == "system" {
            userDefaults.removeObject(forKey: "AppleLanguages")
        } else {
            userDefaults.set([language], forKey: "AppleLanguages")
        }
    }

    /// Available language options for the language picker.
    static let availableLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("uk", "Ukrainian"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("no", "Norwegian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
        ("id", "Indonesian"),
    ]
}
