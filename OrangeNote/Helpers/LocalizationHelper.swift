//
//  LocalizationHelper.swift
//  OrangeNote
//
//  Localization utilities, dynamic bundle resolution, and supported language definitions.
//

import Foundation
import SwiftUI

/// Localization namespace providing dynamic locale resolution, bundle caching,
/// and localized string lookups across English, Russian, French, and System languages.
public enum L10n {
    /// Lock for thread-safe access to cached bundles and active language.
    private static let lock = NSLock()

    /// Bundle cache keyed by language identifier (e.g. "en", "ru", "fr").
    private static var bundleCache: [String: Bundle] = [:]

    /// Current application language ("system", "en", "ru", "fr").
    /// Default is initialized from UserDefaults.standard.
    private static var _currentLanguage: String = {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    }()

    /// Active language code for dynamic lookups.
    public static var currentLanguage: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentLanguage
        }
        set {
            lock.lock()
            _currentLanguage = newValue
            lock.unlock()
        }
    }

    /// Resolves the locale to use based on user preference.
    public static var currentLocale: Locale {
        let lang = currentLanguage
        if lang == "system" {
            return .current
        }
        return Locale(identifier: lang)
    }

    /// Resolves the appropriate Bundle for a given language code.
    ///
    /// - Parameter languageCode: The language identifier (e.g. "en", "ru", "fr") or "system".
    /// - Returns: The resolved bundle containing localized strings.
    public static func bundle(for languageCode: String? = nil) -> Bundle {
        let targetCode = languageCode ?? currentLanguage
        let effectiveCode: String
        if targetCode == "system" {
            effectiveCode = Bundle.main.preferredLocalizations.first
                ?? Locale.current.language.languageCode?.identifier
                ?? "en"
        } else {
            effectiveCode = targetCode
        }

        lock.lock()
        defer { lock.unlock() }

        if let cached = bundleCache[effectiveCode] {
            return cached
        }

        let candidateBundles = [Bundle.main, Bundle(for: AppSettings.self)] + Bundle.allBundles + Bundle.allFrameworks
        for candidate in candidateBundles {
            if let path = candidate.path(forResource: effectiveCode, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundleCache[effectiveCode] = bundle
                return bundle
            }
        }

        bundleCache[effectiveCode] = Bundle.main
        return Bundle.main
    }

    /// Resolves a localized string using the dynamic active language or an explicit language code.
    ///
    /// - Parameters:
    ///   - key: The localization key in Localizable.strings.
    ///   - languageCode: Optional explicit language code override.
    /// - Returns: The localized string.
    public static func localizedString(_ key: String, languageCode: String? = nil) -> String {
        let targetBundle = bundle(for: languageCode)
        let string = targetBundle.localizedString(forKey: key, value: nil, table: nil)
        if string == key && targetBundle != Bundle.main {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return string
    }

    /// Convenience shorthand for `localizedString(_:languageCode:)`.
    public static func string(_ key: String, languageCode: String? = nil) -> String {
        localizedString(key, languageCode: languageCode)
    }

    /// Formats a localized string with the provided arguments using current language.
    public static func format(_ key: String, _ args: CVarArg...) -> String {
        let formatString = localizedString(key)
        return String(format: formatString, arguments: args)
    }

    /// Formats a localized string for an explicit language code with arguments.
    public static func format(languageCode: String?, _ key: String, _ args: CVarArg...) -> String {
        let formatString = localizedString(key, languageCode: languageCode)
        return String(format: formatString, arguments: args)
    }

    /// Returns a SwiftUI `Text` view rendering the dynamically resolved localized string.
    public static func text(_ key: String) -> Text {
        Text(string(key))
    }

    /// Returns a SwiftUI `Text` view rendering the dynamically resolved and formatted localized string.
    public static func text(_ key: String, _ args: CVarArg...) -> Text {
        Text(String(format: string(key), arguments: args))
    }

    /// Languages supported by the app UI, including the "system" meta-option.
    public static let supportedLanguages: [(code: String, name: String)] = [
        ("system", "settings.language.systemDefault"),
        ("en", "English"),
        ("fr", "Français"),
        ("ru", "Русский"),
    ]
}

/// A SwiftUI view helper for rendering dynamically localized text strings.
public struct LocalizedText: View {
    private let key: String
    private let args: [CVarArg]

    public init(_ key: String, _ args: CVarArg...) {
        self.key = key
        self.args = args
    }

    public var body: some View {
        if args.isEmpty {
            Text(L10n.string(key))
        } else {
            Text(String(format: L10n.string(key), arguments: args))
        }
    }
}
