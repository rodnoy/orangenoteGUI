//
//  AppSettings.swift
//  OrangeNote
//
//  Observable user settings persisted via AppStorage.
//

import SwiftUI

/// Application-wide settings persisted in UserDefaults.
final class AppSettings: ObservableObject {
    /// Selected Whisper model name (e.g. "base", "small", "medium").
    @AppStorage("selectedModel") var selectedModel: String = "base"

    /// Language code for transcription ("auto" for auto-detection).
    @AppStorage("language") var language: String = "auto"

    /// Whether to use chunked transcription for long files.
    @AppStorage("useChunking") var useChunking: Bool = false

    /// Duration of each chunk in seconds (when chunking is enabled).
    @AppStorage("chunkDuration") var chunkDuration: Int = 30

    /// Overlap between chunks in seconds (when chunking is enabled).
    @AppStorage("overlapDuration") var overlapDuration: Int = 5

    /// Whether to translate non-English audio to English using Whisper's built-in translate mode.
    @AppStorage("translateToEnglish") var translateToEnglish: Bool = false

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
