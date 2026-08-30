//
//  CanonicalTranscriptionSerializer.swift
//  OrangeNote
//
//  Bidirectional mapping and JSON serialization between the domain
//  `TranscriptionResult` model and the persisted `CanonicalTranscriptionDocument` v1.
//

import Foundation

/// Errors thrown while serializing/deserializing Canonical Transcription Documents.
enum CanonicalTranscriptionSerializerError: Error, Equatable {
    /// The JSON document's `createdAt` field did not match the expected ISO 8601 format.
    case invalidCreatedAtFormat(String)
    /// A numeric field required to be finite (not `NaN`/`Infinity`) contained a non-finite value.
    /// `field` identifies the offending value (e.g. `"transcription.durationSeconds"`,
    /// `"segments[2].startTime"`) for diagnosability.
    case invalidNumericValue(field: String)
    /// A numeric field was finite but fell outside its allowed range (e.g. negative timestamp,
    /// or a segment whose `endTime` precedes its `startTime`). `value` is the offending value.
    case outOfRange(field: String, value: Double)
}

/// Provides mapping between the in-memory `TranscriptionResult` domain model and the
/// versioned `CanonicalTranscriptionDocument` (v1) persistence schema, along with
/// deterministic, formatted JSON encoding/decoding.
enum CanonicalTranscriptionSerializer {

    // MARK: - Date Formatting

    /// ISO 8601 formatter (with fractional seconds) used for `createdAt` timestamps.
    private static let iso8601FormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO 8601 formatter (without fractional seconds) used as a fallback for `createdAt` timestamps.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Formats a `Date` as a strict ISO 8601 string (with fractional seconds) for `createdAt`.
    static func formatCreatedAt(_ date: Date) -> String {
        iso8601FormatterWithFractionalSeconds.string(from: date)
    }

    /// Parses a strict ISO 8601 `createdAt` string into a `Date`, trying with and without
    /// fractional seconds. Throws `.invalidCreatedAtFormat` if neither format matches.
    static func parseCreatedAt(_ string: String) throws -> Date {
        if let date = iso8601FormatterWithFractionalSeconds.date(from: string) {
            return date
        }
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        throw CanonicalTranscriptionSerializerError.invalidCreatedAtFormat(string)
    }

    // MARK: - Numeric Validation (Finding B5)

    /// Single source of truth for the minimum allowed duration (in seconds) of an individual
    /// transcription segment/chunk. Segments whose `endTime - startTime` falls below this
    /// value are rejected rather than silently coerced. `0` permits zero-length segments
    /// (e.g. instantaneous markers) while still rejecting negative-duration segments
    /// (`endTime < startTime`).
    static let minimumChunkDurationSeconds: Double = 0.0

    /// Validates that `value` is finite, throwing `.invalidNumericValue` for `NaN`/`Infinity`.
    private static func validateFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw CanonicalTranscriptionSerializerError.invalidNumericValue(field: field)
        }
    }

    /// Validates that `value` is non-negative, throwing `.outOfRange` otherwise.
    private static func validateNonNegative(_ value: Double, field: String) throws {
        guard value >= 0 else {
            throw CanonicalTranscriptionSerializerError.outOfRange(field: field, value: value)
        }
    }

    // MARK: - Domain -> Canonical

    /// Maps a domain `TranscriptionResult` into a `CanonicalTranscriptionDocument` v1.
    ///
    /// - Parameters:
    ///   - result: The domain transcription result to map.
    ///   - sourceURL: The URL of the original source audio file.
    ///   - modelName: The name/identifier of the model used for transcription.
    ///   - engineID: The identifier of the transcription engine used (e.g. "whisper-local").
    ///   - createdAt: The creation timestamp to embed (defaults to now).
    ///   - includeSourcePath: Whether to embed `sourceURL.path` in `source.path`. Defaults
    ///     to `true` for direct callers of this API. UI export flows (`ExportViewModel`)
    ///     pass `false` by default for privacy (Task 2.13 / Finding B3): the real absolute
    ///     file path is not embedded in user-facing exports unless explicitly opted into.
    /// - Throws: `CanonicalTranscriptionSerializerError.invalidNumericValue` if `result.duration`
    ///   or any segment's `startTime`/`endTime` is non-finite (`NaN`/`Infinity`).
    ///   `CanonicalTranscriptionSerializerError.outOfRange` if `result.duration` or any segment
    ///   timestamp is negative, or a segment's duration (`endTime - startTime`) falls below
    ///   `minimumChunkDurationSeconds` (Finding B5). Values are validated up front rather than
    ///   silently coerced or allowed to trap during `Double` -> `Int` millisecond conversion.
    /// - Note: `source.fileSizeBytes` is derived from the file at `sourceURL` via `FileManager`.
    ///   If the file is inaccessible (e.g. does not exist or attributes cannot be read), the size
    ///   defaults to `0` rather than throwing, since a missing/moved source file should not block
    ///   producing a valid canonical document from an already-completed transcription.
    static func makeDocument(
        from result: TranscriptionResult,
        sourceURL: URL,
        modelName: String,
        engineID: String,
        createdAt: Date = Date(),
        includeSourcePath: Bool = true
    ) throws -> CanonicalTranscriptionDocument {
        try makeDocument(
            from: result,
            sourceFileName: sourceURL.lastPathComponent,
            sourceURL: sourceURL,
            modelName: modelName,
            engineID: engineID,
            createdAt: createdAt,
            includeSourcePath: includeSourcePath
        )
    }

    /// Maps a domain `TranscriptionResult` into a `CanonicalTranscriptionDocument` v1
    /// using honest source metadata that does not require a real file URL to exist
    /// (Task 2.20 / Finding F3).
    ///
    /// - Parameters:
    ///   - result: The domain transcription result to map.
    ///   - sourceFileName: The display name of the source file (always known, never
    ///     fabricated — e.g. recovered from a Canonical import or a real local run).
    ///   - sourceURL: The real URL of the source audio file on disk, if actually known.
    ///     `nil` when no real file URL exists (e.g. re-exporting an imported result).
    ///     `source.fileSizeBytes` defaults to `0` and `source.path` is never embedded
    ///     when `sourceURL` is `nil`, since there is no real file to read.
    ///   - modelName: The name/identifier of the model used for transcription.
    ///   - engineID: The identifier of the transcription engine used (e.g. "whisper-local").
    ///   - createdAt: The creation timestamp to embed (defaults to now).
    ///   - includeSourcePath: Whether to embed `sourceURL.path` in `source.path` when
    ///     `sourceURL` is non-`nil`. Defaults to `true`; UI export flows pass `false`
    ///     for privacy (Task 2.13 / Finding B3).
    /// - Throws: See the `sourceURL: URL` overload above for numeric validation errors.
    static func makeDocument(
        from result: TranscriptionResult,
        sourceFileName: String,
        sourceURL: URL? = nil,
        modelName: String,
        engineID: String,
        createdAt: Date = Date(),
        includeSourcePath: Bool = true
    ) throws -> CanonicalTranscriptionDocument {
        let fileSizeBytes = sourceURL.map(fileSize(at:)) ?? 0

        try validateFinite(result.duration, field: "transcription.durationSeconds")
        try validateNonNegative(result.duration, field: "transcription.durationSeconds")

        let segments = try result.segments.enumerated().map { index, segment -> CanonicalTranscriptionDocument.CanonicalSegment in
            try validateFinite(segment.startTime, field: "segments[\(index)].startTime")
            try validateFinite(segment.endTime, field: "segments[\(index)].endTime")
            try validateNonNegative(segment.startTime, field: "segments[\(index)].startTime")
            try validateNonNegative(segment.endTime, field: "segments[\(index)].endTime")

            let segmentDuration = segment.endTime - segment.startTime
            guard segmentDuration >= minimumChunkDurationSeconds else {
                throw CanonicalTranscriptionSerializerError.outOfRange(
                    field: "segments[\(index)].duration",
                    value: segmentDuration
                )
            }

            return CanonicalTranscriptionDocument.CanonicalSegment(
                index: index,
                startMilliseconds: Int((segment.startTime * 1000).rounded()),
                endMilliseconds: Int((segment.endTime * 1000).rounded()),
                text: segment.text,
                confidence: nil
            )
        }

        return CanonicalTranscriptionDocument(
            createdAt: formatCreatedAt(createdAt),
            source: .init(
                fileName: sourceFileName,
                fileSizeBytes: fileSizeBytes,
                path: includeSourcePath ? sourceURL?.path : nil
            ),
            engine: .init(id: engineID, model: modelName),
            transcription: .init(
                language: result.language,
                durationSeconds: result.duration,
                fullText: result.fullText,
                segments: segments
            )
        )
    }

    /// Reads the file size at `url` via `FileManager`, defaulting to `0` if unavailable.
    private static func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    // MARK: - Canonical -> Domain

    /// Maps a `CanonicalTranscriptionDocument` back into a domain `TranscriptionResult`.
    ///
    /// Segment `id`s are freshly generated `UUID`s since the canonical schema does not persist
    /// segment identity, only ordering (`index`) and timing.
    static func makeResult(from document: CanonicalTranscriptionDocument) -> TranscriptionResult {
        let segments = document.transcription.segments.map { canonicalSegment in
            TranscriptionSegment(
                id: UUID(),
                startTime: Double(canonicalSegment.startMilliseconds) / 1000.0,
                endTime: Double(canonicalSegment.endMilliseconds) / 1000.0,
                text: canonicalSegment.text
            )
        }

        return TranscriptionResult(
            segments: segments,
            fullText: document.transcription.fullText,
            language: document.transcription.language,
            duration: document.transcription.durationSeconds
        )
    }

    // MARK: - JSON Encoding / Decoding

    /// Encodes a `CanonicalTranscriptionDocument` into deterministic, formatted JSON `Data`
    /// with sorted keys and pretty printing.
    static func encode(_ document: CanonicalTranscriptionDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Decodes a `CanonicalTranscriptionDocument` from JSON `Data`, validating that `createdAt`
    /// strictly matches the expected ISO 8601 format.
    static func decode(_ data: Data) throws -> CanonicalTranscriptionDocument {
        let decoder = JSONDecoder()
        let document = try decoder.decode(CanonicalTranscriptionDocument.self, from: data)
        // Validate strict ISO 8601 date formatting of `createdAt` up front.
        _ = try parseCreatedAt(document.createdAt)
        return document
    }
}
