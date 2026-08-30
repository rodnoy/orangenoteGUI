//
//  SendableProgressRecorder.swift
//  OrangeNoteTests
//
//  Thread-safe recorder for progress values observed via `@Sendable` progress
//  handler closures in tests (Finding R5). Replaces the previous pattern of
//  mutating a plain `[Float]` captured by reference inside a `@Sendable`
//  closure, which is an unsynchronized data race under Swift strict
//  concurrency even when tests happen not to trigger it in practice.
//
//  Progress handler closures in `TranscriptionEngineProtocol` and
//  `WhisperEngineClient` are synchronous (`@Sendable (Float) -> Void`), so a
//  pure `actor` (whose methods are all `async`) cannot be called directly
//  from inside them without spawning an unstructured `Task` that would
//  reorder concurrent recordings. Instead, this recorder uses a lock
//  (`NSLock`) to guarantee mutual exclusion synchronously, matching the
//  synchronous call site while remaining safe under `@Sendable` closures.
//
import Foundation

final class SendableProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float] = []

    /// Records a single progress value. Safe to call concurrently and
    /// synchronously from any thread, including directly inside a
    /// `@Sendable` progress handler closure.
    func record(_ value: Float) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    /// Returns a snapshot of all values recorded so far, in order.
    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    /// The number of values recorded so far.
    var count: Int {
        snapshot().count
    }
}
