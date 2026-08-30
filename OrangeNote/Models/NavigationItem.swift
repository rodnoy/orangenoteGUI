//
//  NavigationItem.swift
//  OrangeNote
//
//  Sidebar navigation items and routing destinations for the main window (Task 3.17).
//

import Foundation

/// Sidebar navigation items and routing destinations.
enum NavigationItem: String, CaseIterable, Identifiable, Sendable, Equatable {
    case transcribe
    case results
    case models
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .transcribe: return "nav.transcribe"
        case .results:    return "nav.results"
        case .models:     return "nav.models"
        case .settings:   return "nav.settings"
        }
    }

    var title: String {
        L10n.string(titleKey)
    }

    var icon: String {
        switch self {
        case .transcribe: return "waveform"
        case .results:    return "doc.text"
        case .models:     return "arrow.down.circle"
        case .settings:   return "gear"
        }
    }
}
