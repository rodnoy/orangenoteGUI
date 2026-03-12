//
//  OrangeNoteApp.swift
//  OrangeNote
//
//  Application entry point for the OrangeNote macOS app.
//

import SwiftUI

/// Main application entry point.
@main
struct OrangeNoteApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var appState = AppState()
    @StateObject private var updateChecker = UpdateCheckerViewModel()

    init() {
        NotificationService.requestPermission()
        NotificationService.setupDelegate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(appState)
                .environment(\.locale, localeFromSettings)
                .sheet(isPresented: $updateChecker.showingUpdateSheet) {
                    UpdateAlertView(viewModel: updateChecker)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("menu.openTranscription") {
                    appState.triggerOpenTranscription = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("menu.checkUpdates") {
                    Task {
                        await updateChecker.checkForUpdates()
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(updateChecker.isChecking)

                Divider()

                Button("menu.testNotification") {
                    NotificationService.sendTestNotification()
                }
            }

            CommandGroup(after: .saveItem) {
                Button("menu.save") {
                    appState.triggerSave = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.hasTranscriptionResult)

                Button("menu.export") {
                    appState.triggerExport = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.hasTranscriptionResult)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environment(\.locale, localeFromSettings)
                .frame(minWidth: 450, minHeight: 400)
        }
    }

    // MARK: - Private

    /// Resolves the locale based on the user's language preference.
    private var localeFromSettings: Locale {
        if settings.appLanguage == "system" {
            return .current
        }
        return Locale(identifier: settings.appLanguage)
    }
}
