//
//  TranslatedResult.swift
//  OrangeNote
//
//  Models for translated transcription results.
//

import Foundation

/// A complete translation of a transcription result.
struct TranslatedResult: Sendable {
    /// The original transcription result.
    let original: TranscriptionResult

    /// The target language code (e.g. "fr", "de").
    let targetLanguage: String

    /// The full translated text.
    let translatedFullText: String

    /// Individual translated segments with original text preserved.
    let translatedSegments: [TranslatedSegment]
}

/// A single segment with its translation alongside the original.
struct TranslatedSegment: Identifiable, Sendable {
    /// Inherits the identifier from the original segment.
    var id: UUID { original.id }

    /// The original transcription segment.
    let original: TranscriptionSegment

    /// The translated text for this segment.
    let translatedText: String
}
