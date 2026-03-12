//
//  OrangeNoteFFI.swift
//  OrangeNote
//
//  Swift wrapper around the OrangeNote C FFI functions.
//  All FFI calls are blocking and must be dispatched off the main thread.
//

import Foundation

// MARK: - FFI Error

/// Errors originating from the native FFI layer.
enum OrangeNoteFFIError: LocalizedError {
    case ffiError(String)
    case decodingError(String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .ffiError(let message):
            return "FFI Error: \(message)"
        case .decodingError(let message):
            return "Decoding Error: \(message)"
        case .invalidState(let message):
            return "Invalid State: \(message)"
        }
    }
}

// MARK: - OrangeNoteEngine

/// Thread-safe wrapper around the OrangeNote C FFI.
///
/// All heavy FFI calls are dispatched to a background queue.
/// Progress callbacks are routed back to the caller via Swift closures.
final class OrangeNoteEngine: Sendable {

    // MARK: - JSON Decoder

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    // MARK: - Model Management

    /// Returns the default model cache directory path.
    func modelCacheDir() throws -> String {
        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let resultPtr = orangenote_model_cache_dir(&errorPtr) else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(resultPtr) }
        return String(cString: resultPtr)
    }

    /// Lists all available Whisper models.
    func listModels() throws -> [WhisperModel] {
        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let jsonPtr = orangenote_list_models(&errorPtr) else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(jsonPtr) }

        let jsonString = String(cString: jsonPtr)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OrangeNoteFFIError.decodingError("Failed to convert JSON string to data")
        }

        let ffiModels = try Self.decoder.decode([FFIModelInfo].self, from: jsonData)
        return ffiModels.map { info in
            WhisperModel(
                id: info.name,
                name: info.name,
                size: Self.formatSize(mb: info.sizeMb),
                isCached: info.cached,
                filePath: nil
            )
        }
    }

    /// Checks whether a model is cached locally.
    func isModelCached(name: String) -> Bool {
        return name.withCString { cName in
            orangenote_model_is_cached(cName)
        }
    }

    /// Returns the file-system path of a cached model.
    func modelPath(name: String) throws -> String {
        var errorPtr: UnsafeMutablePointer<CChar>?
        let resultPtr = name.withCString { cName in
            orangenote_model_path(cName, &errorPtr)
        }
        guard let resultPtr else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(resultPtr) }
        return String(cString: resultPtr)
    }

    // MARK: - Transcription

    /// Transcribes an audio file using the specified model.
    ///
    /// - Parameters:
    ///   - path: Path to the audio file.
    ///   - modelPath: Path to the Whisper model file.
    ///   - language: Language code (e.g. "en", "ru") or "auto" for auto-detection.
    ///   - translate: Whether to translate the transcription to English.
    ///   - progressCallback: Called with progress fraction (0.0–1.0).
    /// - Returns: The transcription result.
    func transcribeFile(
        path: String,
        modelPath: String,
        language: String,
        translate: Bool,
        progressCallback: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.performTranscription(
                        audioPath: path,
                        modelPath: modelPath,
                        language: language,
                        translate: translate
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Transcribes an audio file using chunked processing for long files.
    ///
    /// - Parameters:
    ///   - path: Path to the audio file.
    ///   - modelPath: Path to the Whisper model file.
    ///   - language: Language code or "auto" for auto-detection.
    ///   - translate: Whether to translate the transcription to English.
    ///   - chunkSeconds: Duration of each chunk in seconds.
    ///   - overlapSeconds: Overlap between chunks in seconds.
    ///   - progressCallback: Called with progress fraction (0.0–1.0).
    /// - Returns: The merged transcription result.
    func transcribeFileChunked(
        path: String,
        modelPath: String,
        language: String,
        translate: Bool,
        chunkSeconds: Int,
        overlapSeconds: Int,
        progressCallback: @escaping @Sendable (Float) -> Void
    ) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.performChunkedTranscription(
                        audioPath: path,
                        modelPath: modelPath,
                        language: language,
                        translate: translate,
                        chunkSeconds: chunkSeconds,
                        overlapSeconds: overlapSeconds,
                        progressCallback: progressCallback
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Export

    /// Exports a transcription result to the specified format.
    ///
    /// - Parameters:
    ///   - result: The transcription result to export.
    ///   - format: The desired export format.
    /// - Returns: The formatted string content.
    func export(result: TranscriptionResult, format: ExportFormat) throws -> String {
        // Build JSON in the format expected by the Rust FFI:
        // { "language": "...", "segments": [{ "id": 0, "start_ms": 0, "end_ms": 5000, "text": "...", "confidence": 0.0 }] }
        struct ExportSegment: Encodable {
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

        struct ExportResult: Encodable {
            let language: String
            let segments: [ExportSegment]
        }

        let exportResult = ExportResult(
            language: result.language,
            segments: result.segments.enumerated().map { index, segment in
                ExportSegment(
                    id: index,
                    startMs: Int64(segment.startTime * 1000.0),
                    endMs: Int64(segment.endTime * 1000.0),
                    text: segment.text,
                    confidence: 0.0
                )
            }
        )

        let jsonData = try JSONEncoder().encode(exportResult)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw OrangeNoteFFIError.decodingError("Failed to encode result to JSON")
        }

        var errorPtr: UnsafeMutablePointer<CChar>?
        let resultPtr = jsonString.withCString { cJson in
            format.rawValue.withCString { cFormat in
                orangenote_export(cJson, cFormat, &errorPtr)
            }
        }
        guard let resultPtr else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(resultPtr) }
        return String(cString: resultPtr)
    }

    // MARK: - Private Helpers

    /// Performs a blocking transcription (non-chunked).
    private func performTranscription(
        audioPath: String,
        modelPath: String,
        language: String,
        translate: Bool
    ) throws -> TranscriptionResult {
        // Create transcriber
        var errorPtr: UnsafeMutablePointer<CChar>?
        let transcriber = modelPath.withCString { cModel in
            orangenote_transcriber_new(cModel, Int32(ProcessInfo.processInfo.activeProcessorCount), &errorPtr)
        }
        guard let transcriber else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_transcriber_free(transcriber) }

        // Perform transcription
        let languageArg: UnsafePointer<CChar>? = language == "auto" ? nil : (language as NSString).utf8String
        var transcribeError: UnsafeMutablePointer<CChar>?
        let resultPtr = audioPath.withCString { cAudio in
            orangenote_transcribe_file(transcriber, cAudio, languageArg, translate, &transcribeError)
        }
        guard let resultPtr else {
            let message = Self.consumeErrorString(transcribeError)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(resultPtr) }

        return try Self.decodeTranscriptionResult(String(cString: resultPtr))
    }

    /// Performs a blocking chunked transcription with progress callback.
    private func performChunkedTranscription(
        audioPath: String,
        modelPath: String,
        language: String,
        translate: Bool,
        chunkSeconds: Int,
        overlapSeconds: Int,
        progressCallback: @escaping @Sendable (Float) -> Void
    ) throws -> TranscriptionResult {
        // Create transcriber
        var errorPtr: UnsafeMutablePointer<CChar>?
        let transcriber = modelPath.withCString { cModel in
            orangenote_transcriber_new(cModel, Int32(ProcessInfo.processInfo.activeProcessorCount), &errorPtr)
        }
        guard let transcriber else {
            let message = Self.consumeErrorString(errorPtr)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_transcriber_free(transcriber) }

        // Set up progress callback context
        let context = ProgressContext(callback: progressCallback)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<ProgressContext>.fromOpaque(contextPtr).release() }

        let languageArg: UnsafePointer<CChar>? = language == "auto" ? nil : (language as NSString).utf8String
        var transcribeError: UnsafeMutablePointer<CChar>?

        let resultPtr = audioPath.withCString { cAudio in
            orangenote_transcribe_file_chunked(
                transcriber,
                cAudio,
                languageArg,
                translate,
                Int32(chunkSeconds),
                Int32(overlapSeconds),
                { currentChunk, totalChunks, userData in
                    guard let userData else { return }
                    let ctx = Unmanaged<ProgressContext>.fromOpaque(userData)
                        .takeUnretainedValue()
                    let progress = totalChunks > 0
                        ? Float(currentChunk + 1) / Float(totalChunks)
                        : 0.0
                    ctx.callback(progress)
                },
                contextPtr,
                &transcribeError
            )
        }

        guard let resultPtr else {
            let message = Self.consumeErrorString(transcribeError)
            throw OrangeNoteFFIError.ffiError(message)
        }
        defer { orangenote_string_free(resultPtr) }

        return try Self.decodeTranscriptionResult(String(cString: resultPtr))
    }

    /// Decodes a JSON string into a `TranscriptionResult`.
    private static func decodeTranscriptionResult(_ jsonString: String) throws -> TranscriptionResult {
        guard let data = jsonString.data(using: .utf8) else {
            throw OrangeNoteFFIError.decodingError("Failed to convert result JSON to data")
        }
        let ffiResult = try decoder.decode(FFITranscriptionResult.self, from: data)

        let segments = ffiResult.segments.map { segment in
            TranscriptionSegment(
                id: UUID(),
                startTime: Double(segment.startMs) / 1000.0,
                endTime: Double(segment.endMs) / 1000.0,
                text: segment.text
            )
        }

        let fullText = segments.map(\.text).joined(separator: " ")

        let duration: Double
        if let lastSegment = ffiResult.segments.last {
            duration = Double(lastSegment.endMs) / 1000.0
        } else {
            duration = 0.0
        }

        return TranscriptionResult(
            segments: segments,
            fullText: fullText,
            language: ffiResult.language,
            duration: duration
        )
    }

    /// Consumes an FFI error string pointer and returns a Swift string.
    private static func consumeErrorString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "Unknown error" }
        let message = String(cString: ptr)
        orangenote_string_free(ptr)
        return message
    }

    /// Formats a size in megabytes to a human-readable string.
    private static func formatSize(mb: Int) -> String {
        if mb >= 1024 {
            let gb = Double(mb) / 1024.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }
}

// MARK: - Progress Context

/// Reference type used to pass a Swift closure through a C void pointer.
private final class ProgressContext: @unchecked Sendable {
    let callback: @Sendable (Float) -> Void

    init(callback: @escaping @Sendable (Float) -> Void) {
        self.callback = callback
    }
}
