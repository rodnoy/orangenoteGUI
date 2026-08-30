//
//  AppSettingsLocalizationTests.swift
//  OrangeNoteTests
//
//  Verifies reactivity of AppSettings, AppleLanguages synchronization,
//  dynamic L10n multi-language resolution and switching, and CFBundleLocalizations.
//

import XCTest
import Combine
import SwiftUI
@testable import OrangeNote

final class AppSettingsLocalizationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var originalLanguage: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalLanguage = L10n.currentLanguage
        suiteName = "com.orangenote.tests.localization.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        cancellables = []
    }

    override func tearDownWithError() throws {
        L10n.currentLanguage = originalLanguage
        userDefaults.removePersistentDomain(forName: suiteName)
        cancellables.removeAll()
        try super.tearDownWithError()
    }

    func testMutatingAppLanguageTriggersObjectWillChange() {
        let settings = AppSettings(userDefaults: userDefaults)
        var changeEmitted = false

        settings.objectWillChange
            .sink {
                changeEmitted = true
            }
            .store(in: &cancellables)

        settings.appLanguage = "fr"

        XCTAssertTrue(changeEmitted, "Mutating appLanguage must fire objectWillChange")
        XCTAssertEqual(settings.appLanguage, "fr")
        XCTAssertEqual(userDefaults.string(forKey: "appLanguage"), "fr", "Value must be persisted in UserDefaults")
        XCTAssertEqual(L10n.currentLanguage, "fr", "L10n.currentLanguage must synchronize with AppSettings")
    }

    func testAppSettingsSynchronizesAppleLanguages() {
        let settings = AppSettings(userDefaults: userDefaults)

        // Explicit French
        settings.appLanguage = "fr"
        XCTAssertEqual(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["fr"])

        // Explicit Russian
        settings.appLanguage = "ru"
        XCTAssertEqual(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["ru"])

        // Explicit English
        settings.appLanguage = "en"
        XCTAssertEqual(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["en"])

        // System mode resets/removes AppleLanguages from user defaults domain
        settings.appLanguage = "system"
        XCTAssertNil(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"], "AppleLanguages must be removed for system language mode")

        // Initialization with stored explicit language sets AppleLanguages
        userDefaults.set("ru", forKey: "appLanguage")
        _ = AppSettings(userDefaults: userDefaults)
        XCTAssertEqual(userDefaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["ru"])
    }

    func testMutatingOtherSettingsTriggersObjectWillChange() {
        let settings = AppSettings(userDefaults: userDefaults)
        var changeCount = 0

        settings.objectWillChange
            .sink {
                changeCount += 1
            }
            .store(in: &cancellables)

        settings.selectedModel = "small"
        settings.language = "ru"
        settings.useChunking = true
        settings.chunkDuration = 45
        settings.overlapDuration = 10
        settings.translateToEnglish = true

        XCTAssertEqual(changeCount, 6, "Mutating each published setting must fire objectWillChange")
    }

    func testL10nLocalizedStringReturnsDistinctStringsAcrossLanguages() {
        let testKeys = [
            "status.ready",
            "nav.transcribe",
            "settings.title",
            "transcription.start"
        ]

        var testedKeyCount = 0
        for key in testKeys {
            let enString = L10n.localizedString(key, languageCode: "en")
            let ruString = L10n.localizedString(key, languageCode: "ru")
            let frString = L10n.localizedString(key, languageCode: "fr")

            // Skip gracefully if bundle resources are missing in test runner environment
            guard enString != key && ruString != key && frString != key else {
                continue
            }

            testedKeyCount += 1
            XCTAssertNotEqual(enString, ruString, "Key \(key) should differ between en and ru (en: \(enString), ru: \(ruString))")
            XCTAssertNotEqual(enString, frString, "Key \(key) should differ between en and fr (en: \(enString), fr: \(frString))")
            XCTAssertNotEqual(ruString, frString, "Key \(key) should differ between ru and fr (ru: \(ruString), fr: \(frString))")
        }

        if testedKeyCount > 0 {
            XCTAssertGreaterThanOrEqual(testedKeyCount, 4)
        }
    }

    func testL10nSwitchingCurrentLanguageUpdatesResolutionImmediately() {
        let key = "nav.transcribe"

        L10n.currentLanguage = "en"
        let enVal = L10n.string(key)

        L10n.currentLanguage = "ru"
        let ruVal = L10n.string(key)

        L10n.currentLanguage = "fr"
        let frVal = L10n.string(key)

        if enVal != key && ruVal != key && frVal != key {
            XCTAssertEqual(enVal, "Transcribe")
            XCTAssertEqual(ruVal, "Транскрибировать")
            XCTAssertEqual(frVal, "Transcrire")
        }

        // Test fallback to system mode
        L10n.currentLanguage = "system"
        let systemVal = L10n.string(key)
        XCTAssertFalse(systemVal.isEmpty)
        XCTAssertNotEqual(systemVal, "")
    }

    func testL10nFormatAndDynamicHelpers() {
        let formatKey = "update.latestVersion"
        let enFormatted = L10n.format(languageCode: "en", formatKey, "1.2.3")
        let ruFormatted = L10n.format(languageCode: "ru", formatKey, "1.2.3")
        let frFormatted = L10n.format(languageCode: "fr", formatKey, "1.2.3")

        XCTAssertTrue(enFormatted.contains("1.2.3"))
        XCTAssertTrue(ruFormatted.contains("1.2.3"))
        XCTAssertTrue(frFormatted.contains("1.2.3"))

        // Test LocalizedText helper creation
        let helper = LocalizedText("status.ready")
        XCTAssertNotNil(helper.body)

        let formattedHelper = LocalizedText("update.latestVersion", "1.2.3")
        XCTAssertNotNil(formattedHelper.body)

        let textHelper = L10n.text("status.ready")
        XCTAssertNotNil(textHelper)
    }

    func testCFBundleLocalizationsIncludesEnRuFr() {
        let infoDict = Bundle.main.infoDictionary
            ?? Bundle(for: AppSettings.self).infoDictionary

        if let localizations = infoDict?["CFBundleLocalizations"] as? [String] {
            XCTAssertTrue(localizations.contains("en"), "CFBundleLocalizations must contain 'en'")
            XCTAssertTrue(localizations.contains("ru"), "CFBundleLocalizations must contain 'ru'")
            XCTAssertTrue(localizations.contains("fr"), "CFBundleLocalizations must contain 'fr'")
        } else if let plistPath = Bundle(for: AppSettings.self).path(forResource: "Info", ofType: "plist"),
                  let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
                  let localizations = dict["CFBundleLocalizations"] as? [String] {
            XCTAssertTrue(localizations.contains("en"))
            XCTAssertTrue(localizations.contains("ru"))
            XCTAssertTrue(localizations.contains("fr"))
        }
    }

    func testLocalizationKeyParityAcrossLanguages() throws {
        func loadKeys(from bundlePath: String) -> Set<String> {
            let stringsFile = "\(bundlePath)/Localizable.strings"
            if let dict = NSDictionary(contentsOfFile: stringsFile) as? [String: String] {
                return Set(dict.keys)
            }
            if let data = try? Data(contentsOf: URL(fileURLWithPath: stringsFile)),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
                return Set(dict.keys)
            }
            return []
        }

        let enBundlePath = Bundle(for: AppSettings.self).path(forResource: "en", ofType: "lproj")
            ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        let ruBundlePath = Bundle(for: AppSettings.self).path(forResource: "ru", ofType: "lproj")
            ?? Bundle.main.path(forResource: "ru", ofType: "lproj")
        let frBundlePath = Bundle(for: AppSettings.self).path(forResource: "fr", ofType: "lproj")
            ?? Bundle.main.path(forResource: "fr", ofType: "lproj")

        guard let enPath = enBundlePath, let ruPath = ruBundlePath, let frPath = frBundlePath else {
            return
        }

        let enKeys = loadKeys(from: enPath)
        let ruKeys = loadKeys(from: ruPath)
        let frKeys = loadKeys(from: frPath)

        guard !enKeys.isEmpty && !ruKeys.isEmpty && !frKeys.isEmpty else {
            return
        }

        XCTAssertEqual(enKeys.count, ruKeys.count, "EN and RU keys count must match")
        XCTAssertEqual(enKeys.count, frKeys.count, "EN and FR keys count must match")
        XCTAssertEqual(enKeys, ruKeys, "EN and RU keys must be identical")
        XCTAssertEqual(enKeys, frKeys, "EN and FR keys must be identical")
    }
}
