//
//  LocalizationHelper.swift
//  OrangeNote
//
//  Localization utilities and supported language definitions.
//

import Foundation

/// Localization namespace providing locale resolution and supported language metadata.
enum L10n {
    /// Returns the locale to use based on user preference.
    ///
    /// When the user selects "system", the current system locale is returned.
    /// Otherwise, a locale matching the user's explicit language choice is used.
    static var currentLocale: Locale {
        let settings = AppSettings()
        if settings.appLanguage == "system" {
            return .current
        }
        return Locale(identifier: settings.appLanguage)
    }

    /// Resolves a localized string using the app's selected language setting.
    ///
    /// Use this in non-SwiftUI contexts (models, services) where
    /// `LocalizedStringKey` and `.environment(\.locale)` are unavailable.
    static func localizedString(_ key: String) -> String {
        let settings = AppSettings()
        let languageCode: String
        if settings.appLanguage == "system" {
            languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            languageCode = settings.appLanguage
        }

        guard let bundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: bundlePath) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Languages supported by the app UI, including the "system" meta-option.
    ///
    /// The system default entry uses a localization key that must be resolved
    /// via `LocalizedStringKey` in SwiftUI views. Self-name entries (English,
    /// Français, Русский) are intentionally not localized.
    static let supportedLanguages: [(code: String, name: String)] = [
        ("system", "settings.language.systemDefault"),
        ("en", "English"),
        ("fr", "Français"),
        ("ru", "Русский"),
    ]
}
