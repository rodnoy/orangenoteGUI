//
//  TranscriptionImportService.swift
//  OrangeNote
//
//  Service for importing transcription files in JSON and SRT formats.
//

import Foundation

/// Handles importing transcription results from external files.
enum TranscriptionImportService {

    enum ImportError: LocalizedError {
        case unsupportedFormat(String)
        case parseError(String)
        case fileReadError(String)
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return String(format: L10n.localizedString("import.error.unsupportedFormat"), ext)
            case .parseError(let detail):
                return String(format: L10n.localizedString("import.error.parseError"), detail)
            case .fileReadError(let detail):
                return String(format: L10n.localizedString("import.error.fileReadError"), detail)
            case .unsupportedSchemaVersion(let version):
                return String(format: L10n.localizedString("import.error.unsupportedSchemaVersion"), version)
            }
        }
    }

    /// Pairs an imported domain `TranscriptionResult` with any safe, honest execution
    /// provenance metadata recovered from the import source (Task 2.16 / Finding R1).
    ///
    /// `provenance` is `nil` whenever the imported format carries no real model/engine
    /// metadata (legacy JSON fallbacks, SRT), so callers never fabricate placeholder
    /// values. When present, `provenance.sourceFileName` honestly reports the original
    /// `source.fileName` while `provenance.sourceURL` is explicitly `nil` (Task 2.20 /
    /// Finding F3), since no real file URL is recoverable from a Canonical import —
    /// downstream export flows (`ExportViewModel`) read `sourceFileName` directly
    /// instead of reconstructing it from a fabricated `sourceURL`.
    struct ImportedTranscription {
        let result: TranscriptionResult
        let provenance: ExecutionProvenance?
    }

    /// Import a transcription from a file URL.
    static func importFromFile(url: URL) throws -> TranscriptionResult {
        try importWithProvenance(url: url).result
    }

    /// Import a transcription from a file URL, preserving any safe source metadata
    /// (`source.fileName`, `engine.model`, `engine.id`) available from a Canonical JSON
    /// v1 document as `ExecutionProvenance` (Task 2.16 / Finding R1). Legacy JSON and SRT
    /// imports carry no such metadata and honestly report `provenance: nil`.
    static func importWithProvenance(url: URL) throws -> ImportedTranscription {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try importJSON(url: url)
        case "srt":
            return try ImportedTranscription(result: importSRT(url: url), provenance: nil)
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

    // MARK: - JSON Import

    /// Minimal envelope used only to detect the presence and value of `schemaVersion`
    /// without requiring the full Canonical document shape to decode successfully.
    private struct SchemaVersionEnvelope: Decodable {
        let schemaVersion: Int?
    }

    private static func importJSON(url: URL) throws -> ImportedTranscription {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileReadError(error.localizedDescription)
        }

        // Detect schemaVersion presence before deciding on a decoding strategy.
        let schemaVersion = (try? JSONDecoder().decode(SchemaVersionEnvelope.self, from: data))?.schemaVersion

        if let schemaVersion {
            guard schemaVersion == 1 else {
                throw ImportError.unsupportedSchemaVersion(schemaVersion)
            }
            do {
                let document = try CanonicalTranscriptionSerializer.decode(data)
                let result = CanonicalTranscriptionSerializer.makeResult(from: document)
                // Preserve safe source metadata honestly: `sourceFileName` carries only
                // the original file *name*, and `sourceURL` is explicitly `nil` rather
                // than a fabricated `URL(fileURLWithPath:)` constructed from a bare
                // filename (Task 2.20 / Finding F3) — no real file URL is recoverable
                // from a Canonical import. Downstream exports still report the real
                // fileName/model/engine.id without fabricating a path (Task 2.16 /
                // Finding R1).
                let provenance = ExecutionProvenance(
                    sourceFileName: document.source.fileName,
                    sourceURL: nil,
                    modelName: document.engine.model,
                    engineID: document.engine.id
                )
                return ImportedTranscription(result: result, provenance: provenance)
            } catch {
                throw ImportError.parseError(error.localizedDescription)
            }
        }

        // Legacy fallback #1: plain Swift Codable `TranscriptionResult` shape.
        if let result = try? JSONDecoder().decode(TranscriptionResult.self, from: data) {
            return ImportedTranscription(result: result, provenance: nil)
        }

        // Legacy fallback #2: FFI exporter shape (`start_ms` / `end_ms` / `confidence`).
        do {
            let ffiResult = try JSONDecoder().decode(FFITranscriptionResult.self, from: data)
            return ImportedTranscription(result: makeResult(fromFFI: ffiResult), provenance: nil)
        } catch {
            throw ImportError.parseError(error.localizedDescription)
        }
    }

    /// Convert a legacy FFI exporter transcription result into the domain `TranscriptionResult`.
    private static func makeResult(fromFFI ffiResult: FFITranscriptionResult) -> TranscriptionResult {
        let segments = ffiResult.segments.map { ffiSegment in
            TranscriptionSegment(
                id: UUID(),
                startTime: Double(ffiSegment.startMs) / 1000.0,
                endTime: Double(ffiSegment.endMs) / 1000.0,
                text: ffiSegment.text
            )
        }
        let fullText = segments.map(\.text).joined(separator: " ")
        // Compute duration as the maximum `endTime` across all segments rather than
        // `segments.last?.endTime`, since legacy FFI exports are not guaranteed to be
        // sorted by time (Finding B6).
        let duration = segments.map(\.endTime).max() ?? 0.0

        return TranscriptionResult(
            segments: segments,
            fullText: fullText,
            language: ffiResult.language,
            duration: duration
        )
    }

    // MARK: - SRT Import

    private static func importSRT(url: URL) throws -> TranscriptionResult {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.fileReadError(error.localizedDescription)
        }

        let segments = try parseSRT(content)

        guard !segments.isEmpty else {
            throw ImportError.parseError("No segments found in SRT file")
        }

        let fullText = segments.map(\.text).joined(separator: " ")
        let duration = segments.last?.endTime ?? 0

        return TranscriptionResult(
            segments: segments,
            fullText: fullText,
            language: "unknown",
            duration: duration
        )
    }

    /// Parse SRT format content into transcription segments.
    ///
    /// SRT format:
    /// ```
    /// 1
    /// 00:00:00,000 --> 00:00:05,200
    /// Hello, welcome to this demo.
    ///
    /// 2
    /// 00:00:05,200 --> 00:00:10,800
    /// This is a sample transcription.
    /// ```
    private static func parseSRT(_ content: String) throws -> [TranscriptionSegment] {
        var segments: [TranscriptionSegment] = []

        // Split by double newline (or more) to get blocks
        let blocks = content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            // Need at least 3 lines: index, timestamp, text
            guard lines.count >= 3 else { continue }

            // Line 0: sequence number (skip)
            // Line 1: timestamp "HH:MM:SS,mmm --> HH:MM:SS,mmm"
            let timestampLine = lines[1]
            guard let (start, end) = parseTimestampLine(timestampLine) else { continue }

            // Lines 2+: text (may span multiple lines)
            let text = lines[2...].joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            segments.append(TranscriptionSegment(
                id: UUID(),
                startTime: start,
                endTime: end,
                text: text
            ))
        }

        return segments
    }

    /// Parse an SRT timestamp line like "00:01:23,456 --> 00:01:28,789".
    private static func parseTimestampLine(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { return nil }

        guard let start = parseSRTTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseSRTTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        return (start, end)
    }

    /// Parse an SRT timestamp like "00:01:23,456" to seconds.
    private static func parseSRTTimestamp(_ timestamp: String) -> Double? {
        // Format: HH:MM:SS,mmm or HH:MM:SS.mmm
        let normalized = timestamp.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }

        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }

        return hours * 3600 + minutes * 60 + seconds
    }
}
