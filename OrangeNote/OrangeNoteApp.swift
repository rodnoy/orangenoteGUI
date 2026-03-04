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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(minWidth: 450, minHeight: 400)
        }
    }
}
