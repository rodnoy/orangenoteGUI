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
        case .txt:  return "Plain Text"
        case .srt:  return "SubRip (SRT)"
        case .vtt:  return "WebVTT"
        case .json: return "JSON"
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
