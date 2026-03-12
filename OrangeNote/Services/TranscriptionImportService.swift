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

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return String(format: L10n.localizedString("import.error.unsupportedFormat"), ext)
            case .parseError(let detail):
                return String(format: L10n.localizedString("import.error.parseError"), detail)
            case .fileReadError(let detail):
                return String(format: L10n.localizedString("import.error.fileReadError"), detail)
            }
        }
    }

    /// Import a transcription from a file URL.
    static func importFromFile(url: URL) throws -> TranscriptionResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try importJSON(url: url)
        case "srt":
            return try importSRT(url: url)
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

    // MARK: - JSON Import

    private static func importJSON(url: URL) throws -> TranscriptionResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileReadError(error.localizedDescription)
        }

        do {
            let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
            return result
        } catch {
            throw ImportError.parseError(error.localizedDescription)
        }
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
