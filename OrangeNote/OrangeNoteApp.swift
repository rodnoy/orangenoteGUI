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
    @StateObject private var updateChecker = UpdateCheckerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .sheet(isPresented: $updateChecker.showingUpdateSheet) {
                    UpdateAlertView(viewModel: updateChecker)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task {
                        await updateChecker.checkForUpdates()
                    }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(updateChecker.isChecking)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(minWidth: 450, minHeight: 400)
        }
    }
}
