//
//  AppState.swift
//  OrangeNote
//
//  Shared application state accessible from menu commands and views.
//

import SwiftUI

/// Shared application state for coordinating menu commands with views.
@MainActor
final class AppState: ObservableObject {
    /// The current transcription result, if available.
    @Published var currentTranscriptionResult: TranscriptionResult?

    /// Trigger flag for the Save menu command (⌘S).
    @Published var triggerSave: Bool = false

    /// Trigger flag for the Export menu command (⌘⇧E).
    @Published var triggerExport: Bool = false

    /// Whether a transcription result is currently available.
    var hasTranscriptionResult: Bool {
        currentTranscriptionResult != nil
    }
}
