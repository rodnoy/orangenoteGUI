//
//  TranscriptionEngineProtocolTests.swift
//  OrangeNoteTests
//
//  Unit tests verifying the TranscriptionEngineProtocol contract using a mock conformer.
//
//  The mock conformer (`MockTranscriptionEngine`, defined in
//  `Helpers/MockTranscriptionEngine.swift`) is an `actor`, ensuring all
//  mutable state accessed across the test/async boundary is synchronized by
//  the Swift runtime rather than relying on an unsynchronized
//  `@unchecked Sendable` class (Task 2.11 / Finding B4).
//

import XCTest
@testable import OrangeNote

final class TranscriptionEngineProtocolTests: XCTestCase {

    private func makeSampleRequest(
        sourceURL: URL = URL(fileURLWithPath: "/tmp/audio.wav"),
        modelName: String = "base",
        language: String? = "en",
        translateToEnglish: Bool = false,
        chunkingEnabled: Bool = true,
        chunkDurationSeconds: Double? = 30.0,
        overlapDurationSeconds: Double? = 5.0
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            sourceURL: sourceURL,
            modelName: modelName,
            language: language,
            translateToEnglish: translateToEnglish,
            chunkingEnabled: chunkingEnabled,
            chunkDurationSeconds: chunkDurationSeconds,
            overlapDurationSeconds: overlapDurationSeconds
        )
    }

    private func makeSampleResult() -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(id: UUID(), startTime: 0.0, endTime: 2.0, text: "Hello world.")
            ],
            fullText: "Hello world.",
            language: "en",
            duration: 2.0
        )
    }

    // MARK: - Request parameter passing

    func testTranscribe_passesRequestFieldsUnchangedToEngine() async throws {
        let request = makeSampleRequest()
        let mock = MockTranscriptionEngine(resultToReturn: makeSampleResult())

        _ = try await mock.transcribe(request: request) { _ in }

        let received = await mock.receivedRequest
        XCTAssertEqual(received, request)
        XCTAssertEqual(received?.sourceURL, request.sourceURL)
        XCTAssertEqual(received?.modelName, "base")
        XCTAssertEqual(received?.language, "en")
        XCTAssertEqual(received?.translateToEnglish, false)
        XCTAssertEqual(received?.chunkingEnabled, true)
        XCTAssertEqual(received?.chunkDurationSeconds, 30.0)
        XCTAssertEqual(received?.overlapDurationSeconds, 5.0)
    }

    func testTranscribe_passesNilLanguageAndChunkingOptionsCorrectly() async throws {
        let request = makeSampleRequest(
            language: nil,
            chunkingEnabled: false,
            chunkDurationSeconds: nil,
            overlapDurationSeconds: nil
        )
        let mock = MockTranscriptionEngine(resultToReturn: makeSampleResult())

        _ = try await mock.transcribe(request: request) { _ in }

        let received = await mock.receivedRequest
        XCTAssertNil(received?.language)
        XCTAssertEqual(received?.chunkingEnabled, false)
        XCTAssertNil(received?.chunkDurationSeconds)
        XCTAssertNil(received?.overlapDurationSeconds)
    }

    // MARK: - Progress handler invocation

    func testTranscribe_invokesProgressHandlerWithExpectedValues() async throws {
        let mock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            progressValuesToEmit: [0.0, 0.5, 1.0]
        )
        // Uses `SendableProgressRecorder` (Finding R5) instead of mutating a plain
        // `[Float]` captured inside a `@Sendable` closure, which is an unsynchronized
        // data race under Swift strict concurrency.
        let recorder = SendableProgressRecorder()

        _ = try await mock.transcribe(request: makeSampleRequest()) { progress in
            recorder.record(progress)
        }

        XCTAssertEqual(recorder.snapshot(), [0.0, 0.5, 1.0])
    }

    // MARK: - Error propagation

    func testTranscribe_propagatesThrownError() async {
        let expectedError = MockTranscriptionEngineError(message: "transcription failed")
        let mock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            errorToThrow: expectedError
        )

        do {
            _ = try await mock.transcribe(request: makeSampleRequest()) { _ in }
            XCTFail("Expected transcribe to throw")
        } catch let error as MockTranscriptionEngineError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Expected MockTranscriptionEngineError, got \(error)")
        }
    }

    // MARK: - Result return

    func testTranscribe_returnsExpectedResultOnSuccess() async throws {
        let expectedResult = makeSampleResult()
        let mock = MockTranscriptionEngine(resultToReturn: expectedResult)

        let result = try await mock.transcribe(request: makeSampleRequest()) { _ in }

        XCTAssertEqual(result, expectedResult)
    }

    // MARK: - Contract: drain semantics (Task 2.11 / Finding B1)

    /// Verifies that all configured progress values are fully reported
    /// ("drained") strictly before `transcribe` returns successfully.
    func testTranscribe_drainsAllProgressValuesBeforeReturningSuccessfully() async throws {
        let expectedResult = makeSampleResult()
        let mock = MockTranscriptionEngine(
            resultToReturn: expectedResult,
            progressValuesToEmit: [0.1, 0.4, 0.7, 1.0]
        )

        let result = try await mock.transcribe(request: makeSampleRequest()) { _ in }

        // By the time `await transcribe` has returned, the contract guarantees
        // the mock has already reported every configured progress value.
        let reported = await mock.reportedProgressValues
        XCTAssertEqual(reported, [0.1, 0.4, 0.7, 1.0])
        XCTAssertEqual(result, expectedResult)
    }

    /// Verifies that progress values are fully drained even when the
    /// operation ultimately throws, per the protocol's drain guarantee.
    func testTranscribe_drainsProgressValuesBeforeThrowing() async {
        let expectedError = MockTranscriptionEngineError(message: "failed after progress")
        let mock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            progressValuesToEmit: [0.2, 0.6],
            errorToThrow: expectedError
        )

        do {
            _ = try await mock.transcribe(request: makeSampleRequest()) { _ in }
            XCTFail("Expected transcribe to throw")
        } catch {
            // Expected.
        }

        let reported = await mock.reportedProgressValues
        XCTAssertEqual(reported, [0.2, 0.6])
    }

    /// Verifies that no `progressHandler` invocation occurs after `transcribe`
    /// has returned. This is checked by asserting that the number of
    /// progress values observed by the caller equals the number reported by
    /// the engine at the moment `await transcribe` completes, with no
    /// further invocations arriving afterward (polled via a short delay).
    func testTranscribe_doesNotInvokeProgressHandlerAfterReturn() async throws {
        let mock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            progressValuesToEmit: [0.5, 1.0]
        )
        let recorder = SendableProgressRecorder()

        _ = try await mock.transcribe(request: makeSampleRequest()) { progress in
            recorder.record(progress)
        }

        let countAtReturn = recorder.count

        // Give any (contract-violating) asynchronous progress callback a
        // window to fire; a compliant mock must not add further values here.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(recorder.count, countAtReturn)
        XCTAssertEqual(recorder.snapshot(), [0.5, 1.0])
    }

    /// Verifies that no `progressHandler` invocation occurs after `transcribe`
    /// has thrown (Finding R4). Complements
    /// `testTranscribe_doesNotInvokeProgressHandlerAfterReturn`, which only
    /// covers the successful-return path; the error path must uphold the same
    /// "no progress after terminal event" guarantee.
    func testTranscribe_doesNotInvokeProgressHandlerAfterThrow() async {
        let expectedError = MockTranscriptionEngineError(message: "failed after progress")
        let mock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            progressValuesToEmit: [0.3, 0.6],
            errorToThrow: expectedError
        )
        let recorder = SendableProgressRecorder()

        do {
            _ = try await mock.transcribe(request: makeSampleRequest()) { progress in
                recorder.record(progress)
            }
            XCTFail("Expected transcribe to throw")
        } catch {
            // Expected.
        }

        let countAtThrow = recorder.count

        // Give any (contract-violating) asynchronous progress callback a
        // window to fire; a compliant mock must not add further values here.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(recorder.count, countAtThrow)
        XCTAssertEqual(recorder.snapshot(), [0.3, 0.6])
    }

    // MARK: - Contract: drain waits for non-cooperative resources (Finding R4)

    /// Verifies that the engine drain contract holds even when the caller's
    /// enclosing `Task` is cancelled while the underlying "native" work is
    /// still in flight and does not itself respond to cancellation — mirroring
    /// a genuinely non-cooperative resource such as a blocking Rust FFI call
    /// (D011). Uses `CompletionGate` (rather than the cancellable
    /// `delaySeconds`/`Task.sleep` fake) so cancelling the caller's `Task`
    /// cannot race past the in-flight operation: `transcribe` must not return
    /// until the test explicitly opens the gate.
    func testTranscribe_drainWaitsForNonCooperativeResourceDespiteTaskCancellation() async throws {
        let gate = CompletionGate()
        let expectedResult = makeSampleResult()
        let mock = MockTranscriptionEngine(
            resultToReturn: expectedResult,
            completionGate: gate
        )

        let hasReturned = SendableProgressRecorder() // reused as a simple thread-safe flag-ish counter
        let task = Task<TranscriptionResult, Error> {
            let result = try await mock.transcribe(request: makeSampleRequest()) { _ in }
            hasReturned.record(1.0)
            return result
        }

        // Give the task a chance to enter `transcribe` and suspend on the gate.
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "transcribe must still be suspended on the completion gate")

        // Cancelling the caller's Task must NOT cause the underlying mock call to
        // resolve early — a genuinely non-cooperative resource keeps running.
        task.cancel()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hasReturned.count, 0, "Task.cancel() must not unblock a non-cooperative completion gate")

        // Only explicitly opening the gate allows the operation to finish.
        await gate.open()
        let result = try await task.value

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(hasReturned.count, 1)
    }

    // MARK: - Engine identity (Finding R3)

    /// `WhisperTranscriptionEngine.engineID` must expose the same stable
    /// value as `WhisperTranscriptionEngine.stableEngineID`, so both the
    /// protocol-level identity and the pre-existing static constant remain a
    /// single, consolidated source of truth ("whisper-local").
    func testWhisperTranscriptionEngine_engineIDMatchesStableEngineID() {
        let engine = WhisperTranscriptionEngine(
            engine: WhisperEngineMockClient(resultToReturn: makeSampleResult())
        )

        XCTAssertEqual(engine.engineID, "whisper-local")
        XCTAssertEqual(engine.engineID, WhisperTranscriptionEngine.stableEngineID)
    }

    /// A distinct `TranscriptionEngineProtocol` conformer must expose its own
    /// `engineID`, not the Whisper engine's, so callers snapshotting
    /// `engine.engineID` dynamically observe the actual injected engine's
    /// identity (no global registry).
    func testMockTranscriptionEngine_engineIDIsConfigurableAndDistinctFromWhisper() {
        let defaultMock = MockTranscriptionEngine(resultToReturn: makeSampleResult())
        let customMock = MockTranscriptionEngine(
            resultToReturn: makeSampleResult(),
            engineID: "custom-cloud-engine"
        )

        XCTAssertEqual(defaultMock.engineID, "mock-engine")
        XCTAssertNotEqual(defaultMock.engineID, WhisperTranscriptionEngine.stableEngineID)
        XCTAssertEqual(customMock.engineID, "custom-cloud-engine")
    }
}
