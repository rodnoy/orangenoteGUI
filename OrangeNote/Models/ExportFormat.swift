//
//  ExportFormat.swift
//  OrangeNote
//
//  Supported export formats for transcription results.
//

import Foundation

/// Available export formats for transcription output.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt
    case srt
    case vtt
    case json

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .txt:  return L10n.localizedString("format.txt")
        case .srt:  return L10n.localizedString("format.srt")
        case .vtt:  return L10n.localizedString("format.vtt")
        case .json: return L10n.localizedString("format.json")
        }
    }

    /// File extension for save dialogs.
    var fileExtension: String { rawValue }

    /// UTType identifier for save panels.
    var contentType: String {
        switch self {
        case .txt:  return "public.plain-text"
        case .srt:  return "public.plain-text"
        case .vtt:  return "public.plain-text"
        case .json: return "public.json"
        }
    }
}
