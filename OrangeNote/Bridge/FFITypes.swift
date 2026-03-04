//
//  FFITypes.swift
//  OrangeNote
//
//  Swift Codable types matching the JSON structures returned by the FFI layer.
//

import Foundation

// MARK: - Model Info

/// Represents a single model entry returned by `orangenote_list_models`.
///
/// JSON shape: `{ "name": "tiny", "size_mb": 39, "cached": false }`
struct FFIModelInfo: Codable, Sendable {
    let name: String
    let sizeMb: Int
    let cached: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case sizeMb = "size_mb"
        case cached
    }
}

// MARK: - Transcription Segment

/// A single transcription segment returned inside the transcription result JSON.
///
/// JSON shape: `{ "id": 0, "start_ms": 0, "end_ms": 5000, "text": "...", "confidence": 0.95 }`
struct FFITranscriptionSegment: Codable, Sendable {
    let id: Int
    let startMs: Int64
    let endMs: Int64
    let text: String
    let confidence: Float

    private enum CodingKeys: String, CodingKey {
        case id
        case startMs = "start_ms"
        case endMs = "end_ms"
        case text
        case confidence
    }
}

// MARK: - Transcription Result

/// The full transcription result returned by `orangenote_transcribe_file`
/// and `orangenote_transcribe_file_chunked`.
///
/// JSON shape: `{ "language": "en", "segments": [...] }`
struct FFITranscriptionResult: Codable, Sendable {
    let language: String
    let segments: [FFITranscriptionSegment]
}
