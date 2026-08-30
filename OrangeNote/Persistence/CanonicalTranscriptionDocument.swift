//
//  CanonicalTranscriptionDocument.swift
//  OrangeNote
//
//  Canonical JSON schema (v1) for persisted transcription documents.
//

import Foundation

/// The canonical, versioned JSON document schema used for exporting and importing
/// transcription results, independent of the in-memory `TranscriptionResult` model.
struct CanonicalTranscriptionDocument: Codable, Sendable, Equatable {
    /// Schema version of this document. Always `1` for this shape.
    let schemaVersion: Int
    /// ISO 8601 timestamp of when this document was created.
    let createdAt: String
    /// Metadata describing the original source audio file.
    let source: SourceMetadata
    /// Metadata describing the transcription engine that produced this result.
    let engine: EngineMetadata
    /// The actual transcription content: language, duration, text, and segments.
    let transcription: TranscriptionBody

    init(
        schemaVersion: Int = 1,
        createdAt: String,
        source: SourceMetadata,
        engine: EngineMetadata,
        transcription: TranscriptionBody
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.source = source
        self.engine = engine
        self.transcription = transcription
    }

    /// Metadata describing the original source audio file.
    struct SourceMetadata: Codable, Sendable, Equatable {
        let fileName: String
        let fileSizeBytes: Int64
        let path: String?
    }

    /// Metadata describing the transcription engine that produced this result.
    struct EngineMetadata: Codable, Sendable, Equatable {
        let id: String
        let model: String
    }

    /// The transcription content: language, duration, full text, and segments.
    struct TranscriptionBody: Codable, Sendable, Equatable {
        let language: String
        let durationSeconds: Double
        let fullText: String
        let segments: [CanonicalSegment]
    }

    /// A single timed segment within the transcription.
    struct CanonicalSegment: Codable, Sendable, Equatable {
        let index: Int
        let startMilliseconds: Int
        let endMilliseconds: Int
        let text: String
        let confidence: Double?
    }
}
