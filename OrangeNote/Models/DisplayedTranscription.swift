//
//  DisplayedTranscription.swift
//  OrangeNote
//
//  Atomic pairing of a domain `TranscriptionResult` with its `ExecutionProvenance`,
//  representing the single currently-displayed transcription context (Task 2.16 /
//  Finding R2).
//

import Foundation

/// The single currently-displayed transcription result and its execution provenance,
/// committed together as one atomic unit.
///
/// Prior to this type, `TranscriptionViewModel`/`AppState`/`ContentView` synchronized a
/// domain `TranscriptionResult` and its `ExecutionProvenance` via two independently
/// published properties. Because SwiftUI dispatches `@Published` changes as separate
/// publish events, downstream observers (`ContentView`'s `.onChange` handlers writing
/// into `AppState`) could momentarily observe one half updated without the other,
/// risking export/UI state tearing. `DisplayedTranscription` bundles both into a single
/// value type behind a single `@Published` property, so the pairing is always read and
/// written as one atomic unit.
///
/// `provenance` is `nil` when no honest execution metadata is available for the
/// displayed result (e.g. legacy/SRT imports that carry no model/engine metadata) —
/// consumers must never fabricate placeholder provenance to fill this gap.
struct DisplayedTranscription: Equatable, Sendable {
    /// The transcription result currently displayed to the user.
    let result: TranscriptionResult

    /// Execution provenance (source file, model, engine) for `result`, if known.
    let provenance: ExecutionProvenance?
}
