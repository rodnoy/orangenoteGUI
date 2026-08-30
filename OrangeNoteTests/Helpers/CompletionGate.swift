//
//  CompletionGate.swift
//  OrangeNoteTests
//
//  A controllable, non-cancellation-sensitive completion gate for test doubles
//  (Finding R4). Unlike `Task.sleep`, which is cancellable and therefore lets a
//  cancelled caller's `Task` race ahead of a "delay fake" prematurely, this gate
//  only resumes when a test explicitly calls `open()`. This models a genuinely
//  non-cooperative underlying resource — such as a blocking Rust C FFI call
//  (D011) — that keeps running regardless of Swift-side `Task.cancel()`, so
//  tests can verify that the engine drain contract (Task 2.11) truly waits for
//  the underlying operation to finish rather than merely for cancellation to
//  propagate.
//
import Foundation

actor CompletionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until `open()` is called. Intentionally does not check
    /// `Task.isCancelled` or respond to task cancellation, so callers cannot
    /// race past this point by cancelling the enclosing `Task` — mirroring a
    /// non-cooperative underlying resource.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases all current and future callers of `wait()`.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }
}
