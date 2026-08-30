//
//  WhisperTranscriptionEngineTests.swift
//  OrangeNoteTests
//
//  Verifies both the pure request -> FFI parameter mapping logic and the
//  full `transcribe(request:progressHandler:)` orchestration behavior of
//  `WhisperTranscriptionEngine`.
//
//  Since Task 2.12, `WhisperTranscriptionEngine` depends on the narrow
//  `WhisperEngineClient` protocol seam (rather than the concrete
//  `OrangeNoteEngine` FFI wrapper directly), so orchestration —
//  standard vs. chunked dispatch selection, `modelPath` resolution,
//  parameter forwarding, progress callback bridging, domain result
//  mapping, and error propagation — is now fully unit-testable via
//  `WhisperEngineMockClient`, without invoking the real native library.
//

import XCTest
@testable import OrangeNote

final class WhisperTranscriptionEngineTests: XCTestCase {

    // MARK: - Language Mapping

    func testMakeFFIParameters_explicitLanguage_isPassedThrough() {
        let request = TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            modelName: "base",
            language: "ru",
            translateToEnglish: false,
            chunkingEnabled: false,
            chunkDurationSeconds: nil,
            overlapDurationSeconds: nil
        )

        let params = WhisperTranscriptionEngine.makeFFIParameters(request: request, modelPath: "/models/base.bin")

        XCTAssertEqual(params.language, "ru")
    }

    func testMakeFFIParameters_nilLanguage_mapsToAuto() {
        let request = TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            modelName: "base",
            language: nil,
            translateToEnglish: false,
            chunkingEnabled: false,
            chunkDurationSeconds: nil,
            overlapDurationSeconds: nil
        )

        let params = WhisperTranscriptionEngine.makeFFIParameters(request: request, modelPath: "/models/base.bin")

        XCTAssertEqual(params.language, "auto")
    }

    // MARK: - Path & Translate Passthrough

    func testMakeFFIParameters_pathAndTranslate_arePassedThrough() {
        let request = TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/interview.mp3"),
            modelName: "small",
            language: "en",
            translateToEnglish: true,
            chunkingEnabled: false,
            chunkDurationSeconds: nil,
            overlapDurationSeconds: nil
        )

        let params = WhisperTranscriptionEngine.makeFFIParameters(request: request, modelPath: "/models/small.bin")

        XCTAssertEqual(params.path, "/tmp/interview.mp3")
        XCTAssertTrue(params.translate)
    }

    // MARK: - Chunking Defaults

    func testMakeFFIParameters_chunkingEnabledWithoutExplicitDurations_usesDefaults() {
        let request = TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            modelName: "base",
            language: "en",
            translateToEnglish: false,
            chunkingEnabled: true,
            chunkDurationSeconds: nil,
            overlapDurationSeconds: nil
        )

        let params = WhisperTranscriptionEngine.makeFFIParameters(request: request, modelPath: "/models/base.bin")

        XCTAssertEqual(params.chunkSeconds, WhisperTranscriptionDefaults.chunkDurationSeconds)
        XCTAssertEqual(params.overlapSeconds, WhisperTranscriptionDefaults.overlapDurationSeconds)
    }

    func testMakeFFIParameters_chunkingEnabledWithExplicitDurations_usesRequestValues() {
        let request = TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            modelName: "base",
            language: "en",
            translateToEnglish: false,
            chunkingEnabled: true,
            chunkDurationSeconds: 60,
            overlapDurationSeconds: 10
        )

        let params = WhisperTranscriptionEngine.makeFFIParameters(request: request, modelPath: "/models/base.bin")

        XCTAssertEqual(params.chunkSeconds, 60)
        XCTAssertEqual(params.overlapSeconds, 10)
    }

    // MARK: - Initialization

    func testInit_defaultEngine_producesUsableInstance() {
        // Verifies the adapter can be constructed with the default
        // `OrangeNoteEngine()` dependency (no singleton assumption, per
        // Task 2.8 spec) without invoking any FFI calls.
        let sut = WhisperTranscriptionEngine()
        XCTAssertNotNil(sut)
    }

    // MARK: - Orchestration Fixtures

    private static func makeRequest(
        chunkingEnabled: Bool = false,
        language: String? = "en",
        translateToEnglish: Bool = false,
        chunkDurationSeconds: Double? = nil,
        overlapDurationSeconds: Double? = nil
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            modelName: "base",
            language: language,
            translateToEnglish: translateToEnglish,
            chunkingEnabled: chunkingEnabled,
            chunkDurationSeconds: chunkDurationSeconds,
            overlapDurationSeconds: overlapDurationSeconds
        )
    }

    private static func makeResult(fullText: String = "hello world") -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0, endTime: 1, text: fullText)
            ],
            fullText: fullText,
            language: "en",
            duration: 1.0
        )
    }

    // MARK: - Orchestration: modelPath Resolution

    func testTranscribe_requestsModelPathForRequestedModelName() async throws {
        let mockClient = WhisperEngineMockClient(resultToReturn: Self.makeResult())
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest()

        _ = try await sut.transcribe(request: request, progressHandler: { _ in })

        let requestedName = await mockClient.requestedModelName
        XCTAssertEqual(requestedName, "base")
    }

    func testTranscribe_modelPathThrows_propagatesError() async {
        let mockClient = WhisperEngineMockClient(
            modelPathErrorToThrow: WhisperEngineMockClientError(message: "model not found"),
            resultToReturn: Self.makeResult()
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest()

        do {
            _ = try await sut.transcribe(request: request, progressHandler: { _ in })
            XCTFail("Expected modelPath error to propagate")
        } catch let error as WhisperEngineMockClientError {
            XCTAssertEqual(error.message, "model not found")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // Neither transcription entry point should have been invoked.
        let fileCount = await mockClient.transcribeFileInvocationCount
        let chunkedCount = await mockClient.transcribeFileChunkedInvocationCount
        XCTAssertEqual(fileCount, 0)
        XCTAssertEqual(chunkedCount, 0)
    }

    // MARK: - Orchestration: Dispatch Selection

    func testTranscribe_chunkingDisabled_dispatchesToTranscribeFile() async throws {
        let mockClient = WhisperEngineMockClient(resultToReturn: Self.makeResult())
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        _ = try await sut.transcribe(request: request, progressHandler: { _ in })

        let fileCount = await mockClient.transcribeFileInvocationCount
        let chunkedCount = await mockClient.transcribeFileChunkedInvocationCount
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(chunkedCount, 0)
    }

    func testTranscribe_chunkingEnabled_dispatchesToTranscribeFileChunked() async throws {
        let mockClient = WhisperEngineMockClient(resultToReturn: Self.makeResult())
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        _ = try await sut.transcribe(request: request, progressHandler: { _ in })

        let fileCount = await mockClient.transcribeFileInvocationCount
        let chunkedCount = await mockClient.transcribeFileChunkedInvocationCount
        XCTAssertEqual(fileCount, 0)
        XCTAssertEqual(chunkedCount, 1)
    }

    // MARK: - Orchestration: Parameter Forwarding

    func testTranscribe_standardDispatch_forwardsResolvedParameters() async throws {
        let mockClient = WhisperEngineMockClient(
            modelPathToReturn: "/models/base.bin",
            resultToReturn: Self.makeResult()
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false, language: "ru", translateToEnglish: true)

        _ = try await sut.transcribe(request: request, progressHandler: { _ in })

        let call = await mockClient.transcribeFileCall
        XCTAssertEqual(call, WhisperEngineMockClient.TranscribeFileCall(
            path: "/tmp/audio.wav",
            modelPath: "/models/base.bin",
            language: "ru",
            translate: true
        ))
    }

    func testTranscribe_chunkedDispatch_forwardsResolvedParametersIncludingDurations() async throws {
        let mockClient = WhisperEngineMockClient(
            modelPathToReturn: "/models/base.bin",
            resultToReturn: Self.makeResult()
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(
            chunkingEnabled: true,
            language: "en",
            translateToEnglish: false,
            chunkDurationSeconds: 45,
            overlapDurationSeconds: 8
        )

        _ = try await sut.transcribe(request: request, progressHandler: { _ in })

        let call = await mockClient.transcribeFileChunkedCall
        XCTAssertEqual(call, WhisperEngineMockClient.TranscribeFileChunkedCall(
            path: "/tmp/audio.wav",
            modelPath: "/models/base.bin",
            language: "en",
            translate: false,
            chunkSeconds: 45,
            overlapSeconds: 8
        ))
    }

    // MARK: - Orchestration: Progress Forwarding

    func testTranscribe_standardDispatch_forwardsProgressValuesInOrder() async throws {
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            progressValuesToEmit: [0.1, 0.5, 1.0]
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        // Uses `SendableProgressRecorder` (Finding R5) instead of mutating a plain
        // `[Float]` captured inside a `@Sendable` closure.
        let recorder = SendableProgressRecorder()
        _ = try await sut.transcribe(request: request, progressHandler: { value in
            recorder.record(value)
        })

        XCTAssertEqual(recorder.snapshot(), [0.1, 0.5, 1.0])
    }

    func testTranscribe_chunkedDispatch_forwardsProgressValuesInOrder() async throws {
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            progressValuesToEmit: [0.25, 0.75]
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        let recorder = SendableProgressRecorder()
        _ = try await sut.transcribe(request: request, progressHandler: { value in
            recorder.record(value)
        })

        XCTAssertEqual(recorder.snapshot(), [0.25, 0.75])
    }

    // MARK: - Orchestration: Domain Result Mapping

    func testTranscribe_standardDispatch_returnsClientResultUnmodified() async throws {
        let expectedResult = Self.makeResult(fullText: "standard result")
        let mockClient = WhisperEngineMockClient(resultToReturn: expectedResult)
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        let result = try await sut.transcribe(request: request, progressHandler: { _ in })

        XCTAssertEqual(result, expectedResult)
    }

    func testTranscribe_chunkedDispatch_returnsClientResultUnmodified() async throws {
        let expectedResult = Self.makeResult(fullText: "chunked result")
        let mockClient = WhisperEngineMockClient(resultToReturn: expectedResult)
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        let result = try await sut.transcribe(request: request, progressHandler: { _ in })

        XCTAssertEqual(result, expectedResult)
    }

    // MARK: - Orchestration: Error Propagation

    func testTranscribe_standardDispatch_errorPropagates() async {
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            transcribeErrorToThrow: WhisperEngineMockClientError(message: "transcription failed")
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        do {
            _ = try await sut.transcribe(request: request, progressHandler: { _ in })
            XCTFail("Expected transcribeFile error to propagate")
        } catch let error as WhisperEngineMockClientError {
            XCTAssertEqual(error.message, "transcription failed")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTranscribe_chunkedDispatch_errorPropagates() async {
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            transcribeErrorToThrow: WhisperEngineMockClientError(message: "chunked transcription failed")
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        do {
            _ = try await sut.transcribe(request: request, progressHandler: { _ in })
            XCTFail("Expected transcribeFileChunked error to propagate")
        } catch let error as WhisperEngineMockClientError {
            XCTAssertEqual(error.message, "chunked transcription failed")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Orchestration: Drain Behavior (Finding R4)

    /// Verifies that `WhisperTranscriptionEngine.transcribe` on the standard
    /// (non-chunked) dispatch path genuinely awaits the underlying
    /// `WhisperEngineClient.transcribeFile` call to fully complete before
    /// returning, using a `CompletionGate` that only resolves when explicitly
    /// opened by the test (rather than a cancellable `Task.sleep` fake).
    func testTranscribe_standardDispatch_awaitsClientCompletionBeforeReturning() async throws {
        let gate = CompletionGate()
        let expectedResult = Self.makeResult(fullText: "standard drain result")
        let mockClient = WhisperEngineMockClient(
            resultToReturn: expectedResult,
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        let hasReturned = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            let result = try await sut.transcribe(request: request, progressHandler: { _ in })
            hasReturned.record(1.0)
            return result
        }

        // Give the adapter a chance to dispatch into the client and suspend on the gate.
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "Adapter must not return before the underlying client completes")

        await gate.open()
        let result = try await task.value

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(hasReturned.count, 1)
    }

    /// Verifies the same drain behavior as
    /// `testTranscribe_standardDispatch_awaitsClientCompletionBeforeReturning`
    /// for the chunked dispatch path (`transcribeFileChunked`).
    func testTranscribe_chunkedDispatch_awaitsClientCompletionBeforeReturning() async throws {
        let gate = CompletionGate()
        let expectedResult = Self.makeResult(fullText: "chunked drain result")
        let mockClient = WhisperEngineMockClient(
            resultToReturn: expectedResult,
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        let hasReturned = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            let result = try await sut.transcribe(request: request, progressHandler: { _ in })
            hasReturned.record(1.0)
            return result
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "Adapter must not return before the underlying chunked client call completes")

        await gate.open()
        let result = try await task.value

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(hasReturned.count, 1)
    }

    // MARK: - Orchestration: Cancellation During Drain (Task 2.21 / Finding F4)

    /// Verifies that cancelling the *caller's* `Task` while the standard dispatch path
    /// is suspended on the underlying client's `CompletionGate` does not make the
    /// adapter return early: per D011, a blocking Rust FFI call is not interrupted by
    /// Swift `Task.cancel()`, so the mock client (standing in for that non-cooperative
    /// resource) must still fully drain and the adapter must still await it, regardless
    /// of the caller's cancellation state.
    func testTranscribe_standardDispatch_callerCancellationDoesNotShortCircuitDrain() async throws {
        let gate = CompletionGate()
        let expectedResult = Self.makeResult(fullText: "standard cancel-drain result")
        let mockClient = WhisperEngineMockClient(
            resultToReturn: expectedResult,
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        let hasReturned = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            let result = try await sut.transcribe(request: request, progressHandler: { _ in })
            hasReturned.record(1.0)
            return result
        }

        // Let the adapter dispatch into the client and suspend on the gate, then cancel
        // the caller's Task while the (simulated) blocking FFI call is still draining.
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "Caller cancellation must not make the adapter return before the underlying client completes")

        await gate.open()
        let result = try await task.value

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(hasReturned.count, 1)
    }

    /// Verifies the same caller-cancellation-does-not-short-circuit-drain behavior for
    /// the chunked dispatch path (`transcribeFileChunked`).
    func testTranscribe_chunkedDispatch_callerCancellationDoesNotShortCircuitDrain() async throws {
        let gate = CompletionGate()
        let expectedResult = Self.makeResult(fullText: "chunked cancel-drain result")
        let mockClient = WhisperEngineMockClient(
            resultToReturn: expectedResult,
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        let hasReturned = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            let result = try await sut.transcribe(request: request, progressHandler: { _ in })
            hasReturned.record(1.0)
            return result
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "Caller cancellation must not make the adapter return before the underlying chunked client call completes")

        await gate.open()
        let result = try await task.value

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(hasReturned.count, 1)
    }

    // MARK: - Orchestration: No Progress After Error (Task 2.21 / Finding F4)

    /// Verifies that once the underlying client throws (after fully draining via the
    /// gate), no further progress callbacks are ever invoked — the progress values
    /// configured to be emitted are all reported strictly before the gate is opened and
    /// the error is thrown, so the recorder must contain exactly those values and never
    /// grow afterward, at the standard dispatch path.
    func testTranscribe_standardDispatch_gatedError_noProgressCallbacksAfterThrow() async throws {
        let gate = CompletionGate()
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            progressValuesToEmit: [0.2, 0.6],
            transcribeErrorToThrow: WhisperEngineMockClientError(message: "gated standard failure"),
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: false)

        let recorder = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            try await sut.transcribe(request: request, progressHandler: { value in
                recorder.record(value)
            })
        }

        // Progress is emitted by the mock before it suspends on the gate, so by the time
        // the adapter dispatch has had a chance to run, both values should already be
        // recorded even though the call has not yet thrown.
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(recorder.snapshot(), [0.2, 0.6], "Progress must already be reported before the gated error is thrown")

        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected gated error to propagate")
        } catch let error as WhisperEngineMockClientError {
            XCTAssertEqual(error.message, "gated standard failure")
        }

        // No progress callback may occur after the error was thrown.
        XCTAssertEqual(recorder.snapshot(), [0.2, 0.6], "No progress callbacks may occur after the error is thrown")
    }

    /// Verifies the same no-progress-after-error behavior for the chunked dispatch path
    /// (`transcribeFileChunked`).
    func testTranscribe_chunkedDispatch_gatedError_noProgressCallbacksAfterThrow() async throws {
        let gate = CompletionGate()
        let mockClient = WhisperEngineMockClient(
            resultToReturn: Self.makeResult(),
            progressValuesToEmit: [0.3, 0.8],
            transcribeErrorToThrow: WhisperEngineMockClientError(message: "gated chunked failure"),
            completionGate: gate
        )
        let sut = WhisperTranscriptionEngine(engine: mockClient)
        let request = Self.makeRequest(chunkingEnabled: true)

        let recorder = SendableProgressRecorder()
        let task = Task<TranscriptionResult, Error> {
            try await sut.transcribe(request: request, progressHandler: { value in
                recorder.record(value)
            })
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(recorder.snapshot(), [0.3, 0.8], "Progress must already be reported before the gated error is thrown")

        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected gated error to propagate")
        } catch let error as WhisperEngineMockClientError {
            XCTAssertEqual(error.message, "gated chunked failure")
        }

        XCTAssertEqual(recorder.snapshot(), [0.3, 0.8], "No progress callbacks may occur after the error is thrown")
    }
}
