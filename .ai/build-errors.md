# Build Errors

## Quality Gate Status (2026-08-30)

**Verdict**: `PHASE 2 FORMALLY APPROVED / CLOSED; PHASE 3 / CHUNK J / TASK 3.1 AUTHORIZED (NOT STARTED)`.
- **Version Metadata**:
  - `project.yml` and `OrangeNote/Info.plist` both verified as `CFBundleShortVersionString` = `0.1.6`, zero diff. Task 2.28 complete.
- **Orchestrator Final Verification Run (2026-08-30)**:
  - Swift full suite: **185/185 tests passed, 0 failures** (`** TEST SUCCEEDED **`).
  - Rust workspace: `orangenote-core` **42/42 tests passed**, `orangenote-ffi` 0/0; 2 doc-tests ignored (pre-existing, observational, non-fatal).
- **Manual Verification Status**:
  - User confirmed both final manual checks passed on 2026-08-30 (canonical export/import repeat verification and valid document busy import global alert). Manual gate 100% **COMPLETE**.
- **Phase 2 Status**: **FORMALLY CLOSED & APPROVED**.
- **Phase 3 Status**: Opened. Chunk J / Task 3.1 authorized (not started).

---

## Active Defect Blockers

(None currently.)

---

## Resolved Findings (Verified & Closed)

**Task 3.1 Build Failure (2026-08-30) — RESOLVED**:
- **Root Cause**: `UTType` does not have built-in static members for `.flac`, `.ogg`, `.aac`, `.opus`. These are not standard UTType constants in UniformTypeIdentifiers framework.
- **Affected File**: `OrangeNote/Models/AudioTypeCatalog.swift` lines 32-35.
- **Error Messages**:
  - `error: type 'UTType' has no member 'flac'`
  - `error: type 'UTType' has no member 'ogg'`
  - `error: type 'UTType' has no member 'aac'`
  - `error: type 'UTType' has no member 'opus'`
- **Resolution**: Replaced non-existent `UTType.flac`, `UTType.ogg`, `UTType.aac`, `UTType.opus` static members with `UTType(filenameExtension:)` fallback.
- **Verification**: `xcodebuild test` — 191/191 Swift tests passed, 0 failures; `cargo test --workspace` — 42/42 Rust tests passed, 0 failures.
- **Status**: **RESOLVED** — Task 3.1 verification complete.

---

## Resolved Findings (Verified & Closed)

1. **Phase 2 Closure Gate Audit & Release Fixes (Chunk I-R4, Resolved 2026-08-30)**:
   - **B1 (Version Metadata Baseline 0.1.6, Task 2.28)**: Fixed `project.yml` (`0.1.5` → `0.1.6`) and restored `OrangeNote/Info.plist` to baseline `0.1.6`; `xcodegen generate` regeneration verified without drift.
   - **G1 (Job Ownership & Provenance Terminal Transfer, Task 2.23)**: `TranscriptionViewModel` validates job ownership (`runningJobID == jobID`) at completion time; matching running provenance transfers atomically to terminal context; `runningJobID` and running provenance cleanly cleared on completion, failure, cancellation, and replacement. Verified with concurrency tests.
   - **G2-parse (Global Presentation for Parse/Read Import Errors, Task 2.24)**: `ContentView` catch block routes unparseable / unreadable file errors to `AppState.importErrorMessage` global alert when Results/Models/Settings is active, and to `transcriptionVM.reportImportError(_:)` inline when Transcribe is active, with mutually exclusive routing (zero duplicate alerts).
   - **G2-busy (Busy Import Rejection Global Presentation, Task 2.26)**: `ContentView.openTranscriptionFile()` pre-checks `transcriptionVM.isBusy` before calling `applyImportedResult`, routing busy rejection through `transcriptionVM.reportImportError(_:)` inline on Transcribe tab and `AppState.importErrorMessage` global alert on Results/Models/Settings tabs. Verified with 4 unit tests covering running and draining states; defensive VM guard retained; zero state mutation and no automatic tab switch.
   - **Task 2.29 (Final Closure Gate & Verification)**: Regression suites green, manual checks passed, zero blocker regressions. Phase 2 formally closed.

2. **Phase 2 Final Closure Corrections (Chunk I-R3, Resolved 2026-08-29)**:
   - **F1 (ResultsView Atomic DisplayedTranscription Wiring)**: `ResultsView` accepts single `DisplayedTranscription` snapshot for rendering, clipboard copying, and export actions.
   - **F3 (Honest Source Metadata Split)**: `ExecutionProvenance` separates `sourceFileName: String` from optional real `sourceURL: URL?`; canonical import sets `sourceURL = nil` without fake URL synthesis.
   - **F4 (Adapter Drain/Error/Cancel Matrix)**: `WhisperTranscriptionEngineTests` covers standard/chunked execution across normal return, caller cancellation drain, and gated error throw with zero post-error progress callbacks.
   - **F5 (Production-Representative Replacement Tests)**: Added sequential completion and file replacement test flow; verified public ViewModel invariants.
   - **F6 (Import Error Reporting Intent)**: Added `reportImportError(_:)` ViewModel intent called by `ContentView` catch block with localized `import.error.failed` message.

3. **Phase 2 Remediation Findings (Chunk I-R2, Resolved 2026-08-29)**:
   - **R1 (Honest Unknown Engine ID & Canonical Import Metadata)**: `ExportViewModel` defaults to `"unknown"`; `TranscriptionImportService` preserves safe document metadata with `path = nil`.
   - **R2 (Atomic DisplayedTranscription Introduction)**: Introduced `DisplayedTranscription` pairing result and provenance; synchronized in `TranscriptionViewModel` and `AppState`.
   - **R3 (Engine Identity Protocol)**: Added `engineID` requirement to `TranscriptionEngineProtocol`; `WhisperTranscriptionEngine` provides `"whisper-local"`; dynamic snapshot per job.
   - **R4 (Drain Contract & Concurrency Test Doubles)**: Added `CompletionGate` (actor-based, non-cancellation-sensitive) and adapter drain tests.
   - **R5 (Thread-Safe Progress Recording in Tests)**: Added `SendableProgressRecorder` (`NSLock`-protected) to eliminate `@Sendable` closure capture races.
   - **R6 (Legacy ExportView Retirement)**: Removed unreferenced `OrangeNote/Views/ExportView.swift`.
   - **R7 (Replacement Concurrency Test)**: Added replacement concurrency test for `displayedTranscription` update.

4. **Part A & Task 2.14 Hardening (Resolved 2026-08-29)**:
   - Tasks 2.1–2.6 (Canonical JSON DTO, Serializer, Version-Aware Import, Legacy Fallback, Canonical Export, Compatibility Suite) and Task 2.14 (Numeric Validation Hardening, Finite/Non-Negative Validation, Legacy Duration Max) approved.

5. **Phase 1 Findings (Resolved 2026-08-28)**:
   - All Phase 1 findings (Tasks 1.8–1.10, Tasks 1.12–1.13, Task 1.15) verified and resolved.

---

## Non-Blocking Observations & Backlog Items

1. **Routing Test Helper & Presenter Reset Style (Low Backlog)**:
   - Unit tests in `TranscriptionImportLifecycleTests` duplicate the route helper branch rather than testing an extracted production routing method; opposite presenter state is not explicitly cleared. Documented for future cleanup without blocking.
2. **Adapter Test Matrix Sufficiency**:
   - The adapter test suite in `WhisperTranscriptionEngineTests` satisfies requirements; non-blocking observation.
3. **Synthetic Seam Test in Job Concurrency Suite**:
   - Internal seam test in `TranscriptionJobConcurrencyTests` models synthetic stale completion; retained alongside production replacement tests.
4. **App Sandbox Read-Write Entitlement**:
   - `com.apple.security.files.user-selected.read-write` configured in `OrangeNote.entitlements` and `project.yml` aligns with Task 3.11 requirements.
5. **Linker & Xcode Service Warnings**:
   - Universal library linker warning (macOS 26.2 vs deployment target 14.0) and Xcode `linkd`/`AppIntents` service warnings remain non-fatal.

---

## Manual Testing & Verification Status

- **User Compiled-App 6-Case DnD Matrix (PASSED 2026-08-28)**: Complete and accepted.
- **Valid-Model Single-File Transcription Smoke Test (PASSED 2026-08-28)**: Complete and accepted.
- **Standard & Chunked Whisper Smoke Tests (PASSED 2026-08-29)**: Complete and accepted.
- **Phase 2 Closure Manual Verification Items (PASSED 2026-08-30)**:
  1. Canonical JSON export/import repeat verification confirming Task 2.20 metadata changes (`sourceFileName` + nil `sourceURL`) — **PASSED**.
  2. Valid document (canonical JSON or SRT) import while transcription is running from Results/Models/Settings tabs verifying global alert presentation — **PASSED**.
- **Manual Gate Verdict**: **100% COMPLETE**.
