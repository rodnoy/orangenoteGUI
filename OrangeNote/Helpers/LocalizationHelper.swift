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

    /// Languages supported by the app UI, including the "system" meta-option.
    static let supportedLanguages: [(code: String, name: String)] = [
        ("system", "System Default"),
        ("en", "English"),
        ("fr", "Français"),
        ("ru", "Русский"),
    ]
}
