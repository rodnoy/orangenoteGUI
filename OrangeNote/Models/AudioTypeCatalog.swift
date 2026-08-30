//
//  AudioTypeCatalog.swift
//  OrangeNote
//
//  Single source of truth for supported audio file types, shared between
//  the single-file (`AudioFileValidator`) and batch ingestion pipelines.
//

import Foundation
import UniformTypeIdentifiers

/// Centralized catalog of audio file types supported by the Whisper audio
/// pipeline, audited against `orangenote-core/src/infrastructure/audio/processor.rs`
/// (symphonia-based decoding: MP3, WAV, FLAC, M4A, OGG, AAC, Opus).
///
/// This enum has no instances; it exposes only static members and acts as
/// the canonical registry consulted by file pickers, drag-and-drop
/// ingestion, and batch folder collection.
enum AudioTypeCatalog {
    /// Audio file extensions verified as supported by the Rust audio
    /// pipeline (`orangenote-core/src/infrastructure/audio/processor.rs`,
    /// decoded via `symphonia`). Lowercase, no leading dot.
    static let allowedExtensions: Set<String> = ["mp3", "wav", "m4a", "flac", "ogg", "aac", "opus"]

    /// `UTType` equivalents of `allowedExtensions`, used for `NSOpenPanel`
    /// content type filtering and UTI-based drag-and-drop checks.
    /// `.mp3`, `.wav`, and `.mpeg4Audio` are built-in static `UTType`
    /// members. FLAC, OGG, AAC, and Opus have no built-in static members,
    /// so they are resolved dynamically via `UTType(filenameExtension:)`,
    /// falling back to `.audio` if resolution fails.
    static let allowedUTTypes: [UTType] = [
        .mp3,
        .wav,
        .mpeg4Audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "ogg") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio,
        UTType(filenameExtension: "opus") ?? .audio
    ]

    /// Returns whether the given URL's file extension is a supported audio
    /// format, based purely on the path extension (case-insensitive).
    ///
    /// This is a pure extension check; file existence and readability are
    /// validated separately by `AudioFileValidator`.
    ///
    /// - Parameter url: Candidate file URL.
    /// - Returns: `true` if the extension is in `allowedExtensions`.
    static func isSupported(url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }
}
