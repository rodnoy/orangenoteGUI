# Execution Plan

- **Status**: APPROVED
- **Planning version**: 2.0 (Phase 3 Formally Closed / Phase 4 Pending Authorization)
- **Current implementation phase**: Phase 3: Batch Transcription Core + Batch UI (Phase 1: COMPLETE; Phase 2: COMPLETE / CLOSED; Phase 3: COMPLETE / CLOSED)
- **Current execution chunk**: Chunk R — Signed Sandbox & Regression Gate (Task 3.19: COMPLETE / VERIFIED)
- **Current task**: Task 3.19 (Signed Sandbox & Regression Gate) — COMPLETE / VERIFIED
- **Implementation started**: Yes (Global: Yes; Phase 1: COMPLETE; Phase 2: COMPLETE / CLOSED; Phase 3: COMPLETE / CLOSED; Phase 4: NOT STARTED / NOT AUTHORIZED)

---

## IMPORTANT INSTRUCTIONS & CONSTRAINTS

> **CRITICAL WARNING**: Agents MUST execute incrementally, strictly one atomic task at a time as designated in `.ai/handoff.md`. Never start subsequent tasks, combine chunks, or run ahead without explicit user authorization and state update in `handoff.md`. Architectural decisions in `.ai/decisions.md` (D001–D028) strictly override ad-hoc speculation.
>
> The global prohibition on Rust modifications applies strictly to **Phases 1–3**. Future Phases 4–6 are unaffected by this restriction.

### General Execution Rules
1. **Zero Rust changes in Phases 1–3**: All work in Phases 1, 2, and 3 is strictly confined to Swift, project configuration (`project.yml`), entitlements, and resources. No edits in `orangenote-ffi/` or `orangenote-core/`.
2. **SwiftUI State Conventions**: Adhere to repository conventions using `ObservableObject` and `@Published` properties. Do not introduce `@Observable` macro patterns not present in the codebase.
3. **Task Boundaries**: Tasks must never be combined or skipped. Each task requires inspection, implementation, test verification, and handoff synchronization.
4. **Validation Command Conventions**:
   - First discover schemes/targets: `xcodebuild -list`
   - Generate Xcode project: `xcodegen generate`
   - Test target execution: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`
   - Single test execution: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:<TestClass>/<testMethod>`
   - Rust regression verification (gate check only, no claim that it was run prior to execution): `cargo test`

---

## Dependency Graph

```
Phase 1: Persistent Drag & Drop + Single-File State Cleanup
├── Chunk A
│   ├── Task 1.1 (Test Target Infrastructure)
│   └── Task 1.2 (Single-File Validation & Audio Audit) [depends on 1.1]
├── Chunk B
│   ├── Task 1.3 (Minimal Conceptual Lifecycle) [depends on 1.2]
│   └── Task 1.4 (Stale Async Completion jobID Guard) [depends on 1.3]
├── Chunk C
│   ├── Task 1.5 (Single-Item Drop Resolver & Multi Reject) [depends on 1.2]
│   └── Task 1.6 (Page-Level DnD Overlay) [depends on 1.5]
└── Chunk D
    └── Task 1.7 (Phase 1 Localization & Regression Gate) [depends on 1.4, 1.6]
           │
           ▼
Phase 1 Remediation Gate
└── Chunk D-R
    ├── Task 1.8 (Drop Provider Cardinality, Fallback & Extraction Errors) [depends on 1.7]
    ├── Task 1.9 (Native-Busy Guard & Overlapping Start Protection) [depends on 1.8]
    ├── Task 1.10 (Deterministic Lifecycle Projections & Testing Seam Cleanup) [depends on 1.9]
    └── Task 1.11 (Remediation Regression & Manual Verification Gate) [depends on 1.10]
           │
           ▼
Phase 1 Remediation Final Corrections
└── Chunk D-R3
    ├── Task 1.12 (Import Lifecycle/Busy Safety & Imported Result Representation) [depends on 1.11]
    ├── Task 1.13 (Pre-FFI Cancellation & Execution Identity Guard with Drop Recheck) [depends on 1.12]
    ├── Task 1.14 (Final Remediation Regression & Quality Review Gate) [depends on 1.13]
    ├── Task 1.15 (Close Remaining Lifecycle Mutation Bypasses) [depends on 1.14]
    └── Task 1.16 (Phase 1 Final Gate & Regression Verification) [depends on 1.15]
           │
           ▼
Phase 2: Canonical JSON Schema & Swift Engine Protocol
├── Chunk E
│   ├── Task 2.1 (Canonical Transcription Document DTO) [depends on 1.16]
│   └── Task 2.2 (Document Serializer & Mapper) [depends on 2.1]
├── Chunk F
│   ├── Task 2.3 (Version-Aware Canonical Import) [depends on 2.2]
│   └── Task 2.4 (Unversioned Legacy Fallback) [depends on 2.3]
├── Chunk G
│   ├── Task 2.5 (Switch JSON Export to Canonical v1) [depends on 2.2]
│   └── Task 2.6 (Cross-Version Compatibility Test Suite) [depends on 2.4, 2.5]
├── Chunk H
│   ├── Task 2.7 (TranscriptionRequest & Engine Protocol) [depends on 2.2]
│   └── Task 2.8 (Whisper Engine Adapter) [depends on 2.7]
└── Chunk I
    ├── Task 2.9 (Engine Injection in ViewModel) [depends on 2.8]
    └── Task 2.10 (Phase 2 Integration Gate) [depends on 2.6, 2.9]
           │
           ▼
Phase 2 Remediation Gate
└── Chunk I-R (Phase 2 Remediation Gate)
    ├── Task 2.11 (Engine Semantic Contract & Concurrency-Safe Test Doubles) [depends on 2.10]
    ├── Task 2.12 (WhisperEngineClient Seam & Adapter Orchestration Tests) [depends on 2.11]
    ├── Task 2.13 (Execution Provenance & Honest Canonical Export Metadata Wiring) [depends on 2.10]
    ├── Task 2.14 (Numeric Validation Hardening & Legacy Duration Max) [depends on 2.10]
    └── Task 2.15 (Phase 2 Intermediate Regression Gate) [depends on 2.12, 2.13, 2.14]
           │
           ▼
Phase 2 Remediation Final Corrections
├── Chunk I-R2 (Phase 2 Remediation Final Corrections)
│   ├── Task 2.16 (Atomic DisplayedTranscription + Import Metadata Preservation & Honest Unknown Export) [depends on 2.15]
│   ├── Task 2.17 (Engine Identity Protocol & Injected Engine Snapshot) [depends on 2.15]
│   ├── Task 2.18 (Strengthen Drain/Concurrency Contract Tests & Legacy View/Replacement Coverage) [depends on 2.16, 2.17]
│   └── Task 2.19 (Phase 2 Final Gate & Manual Verification) [depends on 2.18]
├── Chunk I-R3 (Phase 2 Final Closure Corrections)
│   ├── Task 2.20 (Atomic Displayed/Job Provenance Ownership + ResultsView Wiring + SourceFileName/URL Correction) [depends on 2.19]
│   ├── Task 2.21 (Complete Adapter Drain/Error/Cancellation Matrix & Representative Lifecycle/Import UX Tests) [depends on 2.20]
│   └── Task 2.22 (Phase 2 Final Review & Test Gate) [depends on 2.21]
└── Chunk I-R4 (Phase 2 Closure Gate)
    ├── Task 2.23 (Fix job-owned provenance terminal transfer) [depends on 2.22]
    ├── Task 2.24 (Make document import errors globally visible) [depends on 2.23]
    ├── Task 2.25 (Phase 2 intermediate review & import audit) [depends on 2.24]
    ├── Task 2.26 (Route busy import rejection through global error presenter) [depends on 2.25]
    ├── Task 2.27 (Phase 2 intermediate review & regression review) [depends on 2.26]
    ├── Task 2.28 (Restore intended app version metadata) [depends on 2.27]
    └── Task 2.29 (Final Phase 2 closure gate, regression review & manual verification) [depends on 2.28]
           │
           ▼
Phase 3: Batch Processing Engine & UI
├── Chunk J
│   ├── Task 3.1 (Audio Type Catalog & Audit) [depends on 2.29]
│   ├── Task 3.2 (BatchItem Model & Statuses) [depends on 3.1]
│   └── Task 3.3 (File Collector) [depends on 3.1, 3.2]
├── Chunk K
│   ├── Task 3.4 (Top-Level Folder Ingestion) [depends on 3.3]
│   └── Task 3.5 (Normalize, Deduplicate, Full-Path Sort) [depends on 3.4]
├── Chunk L
│   ├── Task 3.6 (Output Planner `<basename>.json` & Skip) [depends on 3.5]
│   └── Task 3.7 (Atomic Non-Overwriting Writer) [depends on 3.6, 2.2]
├── Chunk M
│   ├── Task 3.8 (Sequential Batch Coordinator) [depends on 3.7, 2.8]
│   ├── Task 3.9 (Per-Item Failure Isolation & Continuation) [depends on 3.8]
│   └── Task 3.10 (Stop-After-Current Cancellation) [depends on 3.9]
├── Chunk N
│   ├── Task 3.11 (User-Selected Read-Write Entitlement & Scopes) [depends on 3.10]
│   └── Task 3.12 (Output Directory Policy) [depends on 3.11]
├── Chunk O
│   ├── Task 3.13 (Document & Directory Pickers) [depends on 3.12]
│   └── Task 3.14 (Multi-File/Folder DnD Evolution) [depends on 3.13, 1.5, 3.4]
├── Chunk P
│   ├── Task 3.15 (ViewModel Batch Orchestration) [depends on 3.8–3.14]
│   └── Task 3.16 (Transcribe View Batch UI Integration) [depends on 3.15]
├── Chunk Q
│   └── Task 3.17 (Results Routing via AppState) [depends on 3.16]
└── Chunk R
    ├── Task 3.18 (Batch Integration Test Suite) [depends on 3.1–3.17]
    └── Task 3.19 (Signed Sandbox & Final Quality Gate) [depends on 3.18]
           │
           ▼
Future Phases:
├── Phase 4 (Cloud Engine Capability Spike: Specialized vs Multimodal)
├── Phase 5 (BYOK Cloud Transcription: Pure Swift Gemini Engine & Keychain)
└── Phase 6 (Hardening, Signed Sandbox, E2E Audit, Native Cancellation)
```

---

### Task Specification Contract

Each atomic task specification in this plan uses bold bullet labels as its required standard sections:
- **Goal**: Clear statement of the task objective.
- **Dependencies**: Prerequisite tasks that must be completed first.
- **Files to inspect**: Code and config files to read before changes.
- **Files likely to modify**: Existing files targeted for modification.
- **Files likely to add**: New source or test files to create.
- **Implementation details**: Technical requirements and constraints.
- **Tests / validation**: Exact tests and commands to verify completion.
- **Acceptance criteria**: Measurable conditions for passing the task.
- **Do not change**: Scope boundaries and untouchable files.

All 64 atomic tasks (Tasks 1.1–1.7, 1.8–1.11, 1.12–1.16, 2.1–2.10, 2.11–2.15, 2.16–2.19, 2.20–2.22, 2.23–2.29, 3.1–3.19) strictly include all 9 required label sections.

---

## PHASE 1: Persistent Drag & Drop + Single-File State Cleanup

### Task 1.1: Swift unit-test infrastructure via project.yml/XcodeGen
- **Goal**: Add an automated unit test target (`OrangeNoteTests`) to `project.yml` so that XcodeGen configures a dedicated test bundle runnable via `xcodebuild test`.
- **Dependencies**: None.
- **Files to inspect**: `project.yml`.
- **Files likely to modify**: `project.yml`.
- **Files likely to add**: `OrangeNoteTests/OrangeNoteTests.swift`.
- **Implementation details**: Add target `OrangeNoteTests` of type `bundle.unit-test` targeting platform `macOS` with deployment target `14.0`. Link against the `OrangeNote` target. Include test sources under directory `OrangeNoteTests/`.
- **Tests / validation**: Run `xcodegen generate` and verify `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` builds and executes the test bundle cleanly.
- **Acceptance criteria**: Test suite executes via command line and passes with 0 failures.
- **Do not change**: Production target source structure, entitlements, or Rust build scripts (`OrangeNote/Scripts/build_rust.sh`).

### Task 1.2: Centralized single-file validation
- **Goal**: Create a centralized single-file audio validator in Swift that audits and enforces supported audio formats based on the actual audio pipeline (`mp3`, `wav`, `m4a`, `flac`, `ogg`, `aac`, `opus`), verifying readable permissions, non-directory status, and path existence without unproven assumptions.
- **Dependencies**: Task 1.1.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Bridge/FFITypes.swift`, `orangenote-core/src/infrastructure/audio/processor.rs`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`.
- **Files likely to add**: `OrangeNote/Services/AudioFileValidator.swift`, `OrangeNoteTests/AudioFileValidatorTests.swift`.
- **Implementation details**: Audit the actual audio pipeline allowlist (`mp3`, `wav`, `m4a`, `flac`, `ogg`, `aac`, `opus`). Do not invent `aiff` or unverified zero-byte rejections. Implement `AudioFileValidator` returning `Result<URL, AudioValidationError>` for unreadable paths, directories, and unsupported extensions.
- **Tests / validation**: Unit tests covering valid audio extensions (`mp3`, `wav`, `m4a`, `flac`, `ogg`, `aac`, `opus`), uppercase/mixed-case variants, missing files, directory paths, and unsupported extensions: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/AudioFileValidatorTests`.
- **Acceptance criteria**: File validation is centralized in `AudioFileValidator` and used by `TranscriptionViewModel`; errors yield localized failure descriptions.
- **Do not change**: Rust audio decoder source code or FFI bindings.

### Task 1.3: Minimal lifecycle
- **Goal**: Standardize the single-file transcription view model lifecycle around explicit conceptual states: `empty`, `ready(file)`, `running(file,jobID)`, `completed(file,result)`, and `failed(file,error)`, preserving existing published convenience properties while ensuring clean state transitions.
- **Dependencies**: Task 1.2.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`.
- **Implementation details**: Refactor `TranscriptionViewModel` state tracking to reflect the 5 conceptual states (`empty`, `ready(file)`, `running(file,jobID)`, `completed(file,result)`, `failed(file,error)`). Maintain existing `@Published` properties (`selectedFileURL`, `isTranscribing`, `progress`, `result`, `errorMessage`, `statusMessage`) as synchronized convenience properties. Ensure resetting or changing files cleanly clears old errors, progress, and results. Do not create an overengineered separate state framework.
- **Tests / validation**: Unit tests asserting state properties when selecting a file, clearing selection, starting transcription, finishing successfully, or receiving an error.
- **Acceptance criteria**: State transitions are deterministic; selecting a replacement file resets prior error/result states cleanly.
- **Do not change**: Blocking FFI dispatch mechanism or view hierarchy in other tabs.

### Task 1.4: Stale async completion jobID
- **Goal**: Guard asynchronous transcription callbacks against stale completion events using unique job IDs (`UUID`), acknowledging that Swift `Task.cancel()` does not stop blocking Rust FFI calls.
- **Dependencies**: Task 1.3.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Bridge/OrangeNoteFFI.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionJobConcurrencyTests.swift`.
- **Implementation details**: Assign a unique `activeJobID: UUID` upon initiating transcription. When the asynchronous FFI call returns, verify `activeJobID` has not changed or been cleared before mutating `result`, `isTranscribing`, or `statusMessage`. Discard completions if the user cancelled or initiated a new file transcription.
- **Tests / validation**: Unit tests simulating overlapping or stale job completions and asserting that discarded jobs do not overwrite active state.
- **Acceptance criteria**: Late completion from a cancelled or replaced job is safely ignored without UI corruption.
- **Do not change**: C ABI callback signature (`ProgressCallback`) or Rust FFI threading.

### Task 1.5: Single-item drop resolver/multi reject
- **Goal**: Implement a robust drag-and-drop provider resolver that extracts a single audio file from `NSItemProvider` drops and rejects multi-file drops in single-file mode with clear localized user feedback.
- **Dependencies**: Task 1.2.
- **Files to inspect**: `OrangeNote/Views/Components/FileDropZone.swift`.
- **Files likely to modify**: `OrangeNote/Views/Components/FileDropZone.swift`.
- **Files likely to add**: `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNoteTests/DropItemResolverTests.swift`.
- **Implementation details**: Extract file URLs from `kUTTypeFileURL` / `UTType.fileURL`. When drop item count is 1, validate audio extension via `AudioFileValidator`. If drop count > 1, reject the drop and display a localized notice that single-file mode accepts only 1 file. Reject drops immediately when `isTranscribing == true` (D010).
- **Tests / validation**: Unit tests verifying single audio file extraction, non-audio file rejection, and multi-file drop rejection.
- **Acceptance criteria**: Single valid file drops populate selection; multi-item drops are rejected with user-facing explanation; drops during active transcription are ignored.
- **Do not change**: Views in other tabs (`ResultsView`, `SettingsView`, `ModelManagerView`).

### Task 1.6: Page-level DnD overlay
- **Goal**: Keep the Drag & Drop target active across the entire `TranscriptionView` even after a file has been selected, evolving the drop target so it never disappears from the view hierarchy.
- **Dependencies**: Task 1.5.
- **Files to inspect**: `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Views/Components/FileDropZone.swift`.
- **Files likely to modify**: `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Views/Components/FileDropZone.swift`.
- **Files likely to add**: None.
- **Implementation details**: Attach drop handling to the root container of `TranscriptionView` with a visual drop-target overlay indicator during drag-hover (`isTargeted`). Allow dragging a replacement audio file when idle (`!isTranscribing`).
- **Tests / validation**: Manual verification of dragging a file over empty state, dragging over an already-selected file state, and dragging while transcribing.
- **Acceptance criteria**: Users can drag and drop a new audio file at any time while idle to replace the current file selection without clicking a clear button.
- **Do not change**: Navigation split view sidebar or menu command triggers in `AppState`.

### Task 1.7: Localization/regression gate
- **Goal**: Add and verify all new Phase 1 localized strings across English, Russian, and French, ensuring 100% test pass on the full suite.
- **Dependencies**: Tasks 1.1–1.6.
- **Files to inspect**: `OrangeNote/Resources/en.lproj/Localizable.strings`, `OrangeNote/Resources/ru.lproj/Localizable.strings`, `OrangeNote/Resources/fr.lproj/Localizable.strings`.
- **Files likely to modify**: `OrangeNote/Resources/en.lproj/Localizable.strings`, `OrangeNote/Resources/ru.lproj/Localizable.strings`, `OrangeNote/Resources/fr.lproj/Localizable.strings`.
- **Files likely to add**: None.
- **Implementation details**: Add missing localization keys for validation errors, multi-drop rejection notices, and replacement drop tooltips across `en`, `ru`, and `fr`. Run complete test suite.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Acceptance criteria**: All unit tests pass; zero missing localization keys across all 3 language bundles.
- **Do not change**: Existing legacy localization keys without backwards compatibility.

---

## PHASE 1 REMEDIATION GATE

### Task 1.8: Drop provider cardinality, thread safety, fallback, and typed extraction errors
- **Goal**: Harden `DropItemResolver` and `TranscriptionView` drag-and-drop handling to evaluate provider cardinality prior to async extraction, eliminate data races on shared state, support `UTType.fileURL` fallback, and surface typed extraction errors to the user.
- **Dependencies**: Task 1.7.
- **Files to inspect**: `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Views/Components/FileDropZone.swift`, `OrangeNote/Resources/*.lproj/Localizable.strings`.
- **Files likely to modify**: `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Resources/en.lproj/Localizable.strings`, `OrangeNote/Resources/ru.lproj/Localizable.strings`, `OrangeNote/Resources/fr.lproj/Localizable.strings`.
- **Files likely to add**: `OrangeNoteTests/DropItemResolverRemediationTests.swift`.
- **Implementation details**: Check `providers.count` before initiating asynchronous item loading. If `providers.count > 1`, reject immediately as `.rejectedMultipleItems(count:)` without loading items. If `providers.count == 0`, reject cleanly. When `providers.count == 1`, load the single provider directly without an unsynchronized shared `Dictionary`, eliminating any collection data race across async completion handlers. Implement fallback from `loadObject(ofClass: URL.self)` to `loadItem(forTypeIdentifier: UTType.fileURL.identifier)` (or equivalent data/security-scoped URL resolution) when `loadObject` fails or returns `nil`. Introduce typed extraction failure cases (e.g., `.extractionFailed`) with user-facing localized error messages rather than silently ignoring failed provider loads.
- **Tests / validation**: Unit tests validating single provider load, multi-provider pre-extraction rejection, unsupported type handling, and `UTType.fileURL` fallback: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/DropItemResolverTests,OrangeNoteTests/DropItemResolverRemediationTests`.
- **Acceptance criteria**: Provider count checked before async loading; no shared dictionary data race; single file drops load with `UTType.fileURL` fallback; provider load failures surface localized feedback; drops during active transcription remain rejected immediately.
- **Do not change**: Batch processing architecture, Rust FFI bindings, or `ResultsView`.

### Task 1.9: Native-busy cancellation and repeated-start guard
- **Goal**: Prevent overlapping Whisper engine operations by introducing a native-busy execution guard on `TranscriptionViewModel` that distinguishes logical cancellation from in-flight blocking FFI execution and enforces at most one active native call.
- **Dependencies**: Task 1.8.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Resources/*.lproj/Localizable.strings`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Resources/en.lproj/Localizable.strings`, `OrangeNote/Resources/ru.lproj/Localizable.strings`, `OrangeNote/Resources/fr.lproj/Localizable.strings`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionNativeBusyTests.swift`.
- **Implementation details**: Track whether a native FFI background operation is currently executing (e.g. `isNativeBusy: Bool`). When the user cancels transcription (`cancelTranscription()`), mark the task logically cancelled (clearing `activeJobID` so late results are suppressed) while keeping `isNativeBusy == true` until the background FFI thread returns. Guard `startTranscription`, drop ingestion, and file changes so they are blocked while `isNativeBusy` is true. Present truthful, clear status messaging to the user when cancellation is pending/draining (e.g., status indicating cancellation in progress until native engine completes). Add guard in `startTranscription` preventing re-triggering if already running or native-busy.
- **Tests / validation**: Unit tests verifying that initiating transcription while busy is rejected, cancellation suppresses result delivery while holding busy state until completion, and subsequent start is permitted only after native execution drains: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionNativeBusyTests`.
- **Acceptance criteria**: At most one native Whisper operation executes at any time; cancellation truthfully reflects engine status without allowing concurrent start; late FFI completions from cancelled runs remain suppressed.
- **Do not change**: C ABI headers, Rust FFI runtime, or `orangenote-core`.

### Task 1.10: Deterministic lifecycle projections and testing seam cleanup
- **Goal**: Secure `TranscriptionViewModel` state integrity with `private(set)` projections, an explicit error dismissal intent, deterministic reset of progress and results on failure, and clean production lifecycle transition primitives.
- **Dependencies**: Task 1.9.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`.
- **Files likely to add**: None.
- **Implementation details**: Mark `@Published` convenience projections (`errorMessage`, `result`, `progress`, `isTranscribing`, `statusMessage`) as `private(set)` where appropriate, providing explicit intent methods such as `dismissError()` / `clearError()` for view interactions. Ensure lifecycle transitions into `.failed(file:error:)` deterministically reset `progress` to `0.0` and `result` to `nil`. Replace or refactor `startTranscriptionForTesting` with a clean internal lifecycle state transition primitive that models legitimate state changes without faking unencapsulated side-effects, preserving unit testability while deferring full protocol dependency injection to Task 2.9.
- **Tests / validation**: Unit tests verifying deterministic error dismissals, state failure transitions, and lifecycle state invariants: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionViewModelLifecycleTests`.
- **Acceptance criteria**: View projections are read-only to external callers; view mutations route through explicit intent methods; failure transitions deterministically reset progress/result; test seams do not violate production state encapsulation.
- **Do not change**: Phase 2 `TranscriptionEngineProtocol` or `CanonicalTranscriptionDocument` models (deferred to Phase 2).

### Task 1.11: Remediation regression and manual verification gate
- **Goal**: Execute full test suite across Swift and Rust, execute and document the complete manual Finder drag-and-drop verification matrix, verify working-model transcription smoke, and conduct formal quality review to unblock Phase 2.
- **Dependencies**: Tasks 1.8–1.10.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run `xcodebuild -list` to verify targets and schemes. Run full Swift test suite via `xcodebuild test`. Run full Rust test suite via `cargo test --workspace`. Perform structured manual Finder drag-and-drop verification across all permutations in the compiled app: (1) empty state drop, (2) selected state replacement drop, (3) completed state replacement drop, (4) active transcription drop rejection, (5) unsupported format rejection, (6) multi-file drop rejection. Perform manual single-file transcription smoke test with a verified, complete local model (e.g. `ggml-base.bin` or re-downloaded `ggml-large-v3.bin`). Prepare remediation report for quality review. Phase 2 remains blocked until review is approved.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (0 failures); manual drag-and-drop verification matrix and verified-model transcription smoke pass; quality review confirms Phase 1 ready for closure.
- **Do not change**: Production business logic or architectural decisions.
---

## PHASE 1 REMEDIATION FINAL CORRECTIONS

### Task 1.12: Import lifecycle/busy safety and imported result representation
- **Goal**: Prevent transcript import from bypassing `isBusy` lifecycle protection and represent imported results cleanly without a fake source URL placeholder (`URL(fileURLWithPath: "")`), preserving prior import semantics and preventing start against invalid URLs.
- **Dependencies**: Task 1.11.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/Resources/*.lproj/Localizable.strings`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/ContentView.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Implementation details**: Reject or defer `applyImportedResult(_:)` when `isBusy` (`isTranscribing` or `isNativeBusy`) is true. Represent imported result without using a fake directory/empty-path source URL (e.g. optional source URL or distinct imported state/metadata), ensuring `selectedFileURL` does not point to an invalid path that could enable invalid start. Add unit tests covering import rejection while running/draining, state consistency, and selection/start invariants for imported results.
- **Tests / validation**: Unit tests covering import rejection while running/draining and imported result selection/start semantics: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionImportLifecycleTests`.
- **Acceptance criteria**: Import while `isBusy` is safely rejected/blocked; imported results do not set fake file URLs; start cannot be triggered with an invalid imported URL placeholder.
- **Do not change**: Phase 2 canonical JSON schema or export formats.

### Task 1.13: Pre-FFI cancellation and execution identity guard with drop recheck
- **Goal**: Close the pre-FFI race condition where cancellation occurs before background task execution, bind native cleanup to execution identity / jobID, and normalize drop resolver completions and busy rechecks.
- **Dependencies**: Task 1.12.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionPreFFICancellationTests.swift`.
- **Implementation details**: In `TranscriptionViewModel.startTranscription`, check `Task.isCancelled` and `isActiveJob(jobID)` immediately before status assignment and before invoking the native engine call. If cancellation occurred before engine invocation, clean up state immediately without calling into native FFI. Bind `finishNativeOperation` to execution token / jobID so a stale operation cannot clear busy for a newer operation; ensure testing seams cannot bypass busy state. Normalize `DropItemResolver` completion handlers to ensure consistent asynchronous dispatch on MainActor/main to prevent reentrancy and dispatch timing mismatches. In `TranscriptionView.handlePageDrop`, recheck `isBusy` at commit time upon async provider resolution and surface user-facing rejection feedback if busy state changed during resolution instead of silently ignoring. Keep zero Rust modifications / no native cancellation.
- **Tests / validation**: Unit tests covering immediate cancellation before engine entry, truthful cancelling status, and normalized drop commit rechecks: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionPreFFICancellationTests`.
- **Acceptance criteria**: Immediate cancellation before engine entry halts without entering FFI and reflects truthful state; cleanup is identity-bound; drop completion is normalized and rechecks busy at commit with rejection feedback.
- **Do not change**: Rust FFI bindings, C ABI headers, or `orangenote-core`.

### Task 1.14: Final remediation regression and quality review gate
- **Goal**: Verify full Swift and Rust test suites, incorporate previously accepted Finder drag-and-drop manual verification matrix evidence, execute a verified-model single-file transcription smoke test if not yet confirmed, and complete formal code review to unlock Phase 2.
- **Dependencies**: Tasks 1.12–1.13.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full automated Swift (`xcodebuild test`) and Rust (`cargo test --workspace`) suites. Accept and record the completed 6-case Finder drag-and-drop manual verification matrix previously passed by the user. Require confirmed end-to-end single-file transcription smoke test with a valid local model. Conduct code review of all Phase 1 and Remediation changes. Phase 2 unlocks only upon formal approval.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (0 failures); manual 6-case DnD matrix and verified-model transcription smoke confirmed; code review formally approves unblocking Phase 2.
- **Do not change**: Production business logic or architectural decisions.

### Task 1.15: Close remaining lifecycle mutation bypasses
- **Goal**: Close remaining lifecycle mutation bypasses by converting `selectedFileURL` to `private(set)` and adding an `isBusy` guard to `clearResult()`.
- **Dependencies**: Task 1.14.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNoteTests/`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`.
- **Files likely to add**: None.
- **Implementation details**: Convert `@Published var selectedFileURL: URL?` to `@Published private(set) var selectedFileURL: URL?` on `TranscriptionViewModel` to complete projection encapsulation from Task 1.10 and prevent external writes from desynchronizing authoritative lifecycle state. Guard `clearResult()` with `guard !isBusy else { return }` (deterministic no-op/rejection when `isTranscribing || isNativeBusy` is true) to prevent clearing/resetting state while native Whisper execution is running or draining. Inspect any other public lifecycle mutating methods on `TranscriptionViewModel` and enforce consistent busy policy. Add unit tests asserting `clearResult()` is safely rejected/no-oped while busy and verify external compile/mutation invariants for `selectedFileURL`. Do not implement Phase 2 DI; do not change Rust/FFI.
- **Tests / validation**: Unit tests validating `clearResult()` busy guard during running and draining states and lifecycle projection integrity: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionViewModelLifecycleTests`.
- **Acceptance criteria**: `selectedFileURL` is `private(set)`; `clearResult()` safely no-ops/rejects while `isBusy`; all public lifecycle mutators enforce busy policy; 100% test pass rate with zero regressions; zero Rust/FFI changes.
- **Do not change**: Rust FFI bindings, C ABI headers, `orangenote-core`, or Phase 2 engine protocol/models.

### Task 1.16: Phase 1 final gate and regression verification
- **Goal**: Perform final gate review and full regression testing across Swift and Rust test suites, incorporate accepted user 6-case Finder drag-and-drop matrix evidence, confirm valid-model end-to-end single-file transcription smoke test result, and formally approve unblocking Phase 2.
- **Dependencies**: Task 1.15.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Execute full automated Swift (`xcodebuild test`) and Rust (`cargo test --workspace`) suites. Accept and record the completed 6-case Finder drag-and-drop manual verification matrix passed by the user. Require confirmed end-to-end single-file transcription smoke test with a valid local model (`base`). Conduct formal code review confirming all findings are resolved and unblock Phase 2.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (0 failures); manual 6-case DnD matrix and verified-model transcription smoke confirmed; formal code review approves unblocking Phase 2.
- **Do not change**: Production business logic or architectural decisions.

---

## PHASE 2: Canonical JSON Schema & Swift Engine Protocol

### Task 2.1: Canonical DTO
- **Goal**: Define the exact Canonical JSON schema document (`CanonicalTranscriptionDocument` v1) with full metadata, segment timing, and engine/source information under `OrangeNote/Persistence/`.
- **Dependencies**: Task 1.16.
- **Files to inspect**: `OrangeNote/Models/TranscriptionResult.swift`, `OrangeNote/Models/TranscriptionSegment.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Persistence/CanonicalTranscriptionDocument.swift`.
- **Implementation details**: Define `CanonicalTranscriptionDocument` (v1) conforming to `Codable, Sendable, Equatable`:
  - `schemaVersion: Int = 1`
  - `createdAt: String` (ISO 8601 timestamp)
  - `source: SourceMetadata` (`fileName: String`, `fileSizeBytes: Int64`, `path: String?`)
  - `engine: EngineMetadata` (`id: String`, `model: String`)
  - `transcription: TranscriptionBody` (`language: String`, `durationSeconds: Double`, `fullText: String`, `segments: [CanonicalSegment]`)
  - `CanonicalSegment`: `index: Int`, `startMilliseconds: Int`, `endMilliseconds: Int`, `text: String`, `confidence: Double?`
  - Do NOT invent speaker fields. Keep runtime `TranscriptionResult` and `TranscriptionSegment` unchanged.
- **Tests / validation**: Unit tests encoding and decoding the Canonical v1 schema against sample JSON fixtures.
- **Acceptance criteria**: Schema matches exact approved canonical shape (D012, D013); runtime domain models remain unchanged.
- **Do not change**: `OrangeNote/Models/TranscriptionResult.swift`, `OrangeNote/Models/TranscriptionSegment.swift`.

### Task 2.2: Mapper/serializer
- **Goal**: Implement `CanonicalTranscriptionSerializer` under `OrangeNote/Persistence/` providing bidirectional mapping between domain `TranscriptionResult` and `CanonicalTranscriptionDocument` v1, along with formatted JSON serialization.
- **Dependencies**: Task 2.1.
- **Files to inspect**: `OrangeNote/Persistence/CanonicalTranscriptionDocument.swift`, `OrangeNote/Models/TranscriptionResult.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNoteTests/CanonicalTranscriptionSerializerTests.swift`.
- **Implementation details**: Implement mapper functions converting `(TranscriptionResult, sourceURL, modelName, engineID) -> CanonicalTranscriptionDocument` and `CanonicalTranscriptionDocument -> TranscriptionResult`. Implement encoder with sorted keys and pretty printing, and decoder with strict date formatting.
- **Tests / validation**: Unit tests verifying bidirectional fidelity (`domain -> canonical -> JSON -> canonical -> domain`) preserving segments, timestamps, text, and metadata.
- **Acceptance criteria**: Roundtrip serialization retains 100% data fidelity without timing drift.
- **Do not change**: In-memory `TranscriptionResult` properties.

### Task 2.3: Version-aware import
- **Goal**: Upgrade `TranscriptionImportService` to decode Canonical JSON v1 documents when `schemaVersion` is present.
- **Dependencies**: Task 2.2.
- **Files to inspect**: `OrangeNote/Services/TranscriptionImportService.swift`.
- **Files likely to modify**: `OrangeNote/Services/TranscriptionImportService.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionImportServiceTests.swift`.
- **Implementation details**: Parse JSON envelope. If `schemaVersion == 1`, decode `CanonicalTranscriptionDocument` via `CanonicalTranscriptionSerializer` and return `TranscriptionResult`. If `schemaVersion` is present but unsupported (> 1), throw an explicit unsupported schema version error and do NOT fall back to legacy format.
- **Tests / validation**: Unit tests importing valid Canonical v1 JSON files, and rejecting unsupported future `schemaVersion` numbers.
- **Acceptance criteria**: Valid Canonical v1 files import cleanly; future version numbers fail with clear error.
- **Do not change**: SRT import parser in `TranscriptionImportService`.

### Task 2.4: Legacy fallback
- **Goal**: Implement unversioned fallback decoding in `TranscriptionImportService` supporting legacy Swift Codable JSON and FFI-like exporter shapes ONLY when `schemaVersion` is absent (D014).
- **Dependencies**: Task 2.3.
- **Files to inspect**: `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/Bridge/FFITypes.swift`.
- **Files likely to modify**: `OrangeNote/Services/TranscriptionImportService.swift`.
- **Files likely to add**: `OrangeNoteTests/Fixtures/legacy_codable.json`, `OrangeNoteTests/Fixtures/legacy_ffi.json`, `OrangeNoteTests/LegacyImportTests.swift`.
- **Implementation details**: When `schemaVersion` key is absent from the JSON document, attempt decoding via legacy Swift `TranscriptionResult` Codable shape; if that fails, attempt decoding FFI exporter shape (`FFITranscriptionResult` / `FFITranscriptionSegment` with `start_ms`, `end_ms`). Convert to `TranscriptionResult`.
- **Tests / validation**: Unit tests loading legacy Swift Codable JSON fixtures and legacy FFI exporter JSON fixtures, asserting identical domain object construction.
- **Acceptance criteria**: Unversioned legacy JSON files import without error; versioned files never trigger legacy fallback.
- **Do not change**: Canonical v1 export format.

### Task 2.5: Switch JSON export
- **Goal**: Update `ExportViewModel` so that single-file JSON export produces Canonical JSON v1 output (D013).
- **Dependencies**: Task 2.2.
- **Files to inspect**: `OrangeNote/ViewModels/ExportViewModel.swift`, `OrangeNote/Models/ExportFormat.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/ExportViewModel.swift`.
- **Files likely to add**: `OrangeNoteTests/ExportViewModelCanonicalTests.swift`.
- **Implementation details**: Route `.json` export case in `ExportViewModel` through `CanonicalTranscriptionSerializer` to produce Canonical v1 JSON string.
- **Tests / validation**: Unit tests asserting `.json` export contains `schemaVersion: 1`, populated metadata, and correct segment structure.
- **Acceptance criteria**: Exported `.json` files strictly follow Canonical v1 schema.
- **Do not change**: Text (`.txt`), SubRip (`.srt`), or VTT (`.vtt`) export formatters.

### Task 2.6: Compatibility suite
- **Goal**: Comprehensive cross-version test suite validating Canonical v1 encoding/decoding, legacy import fallback, edge cases (empty segments, Unicode, long text), and invalid JSON handling.
- **Dependencies**: Tasks 2.1–2.5.
- **Files to inspect**: `OrangeNoteTests/`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNoteTests/TranscriptionCompatibilityTests.swift`.
- **Implementation details**: Add test suite covering roundtrips, missing metadata handling, invalid syntax, unversioned vs versioned documents, and boundary timestamp values.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionCompatibilityTests`.
- **Acceptance criteria**: 100% pass rate across all schema compatibility tests.
- **Do not change**: Production business logic.

### Task 2.7: Minimal request/protocol
- **Goal**: Define `TranscriptionEngineProtocol` and `TranscriptionRequest` in Swift to decouple transcription consumers from concrete backend implementations (D004).
- **Dependencies**: Task 2.2.
- **Files to inspect**: `OrangeNote/Bridge/OrangeNoteFFI.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`, `OrangeNote/Engine/TranscriptionRequest.swift`.
- **Implementation details**: Define `TranscriptionRequest` containing:
  - `sourceURL: URL`
  - `modelName: String`
  - `language: String?`
  - `translateToEnglish: Bool`
  - `chunkingEnabled: Bool`
  - `chunkDurationSeconds: Double?`
  - `overlapDurationSeconds: Double?`
  (Do NOT add invented `temperature` or `modelPath` fields).
  Define protocol `TranscriptionEngineProtocol: Sendable` with method:
  `func transcribe(request: TranscriptionRequest, progressHandler: @escaping @Sendable (Float) -> Void) async throws -> TranscriptionResult`.
- **Tests / validation**: Unit tests with a mock conforming engine verifying protocol contract and parameter passing.
- **Acceptance criteria**: Clean Swift protocol interface abstracting transcription execution.
- **Do not change**: Rust FFI bindings or C headers (`orangenote_ffi.h`).

### Task 2.8: Whisper adapter
- **Goal**: Implement `WhisperTranscriptionEngine` conforming to `TranscriptionEngineProtocol` by wrapping an instantiated `OrangeNoteEngine` instance (no singleton assumption).
- **Dependencies**: Task 2.7.
- **Files to inspect**: `OrangeNote/Bridge/OrangeNoteFFI.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Engine/WhisperTranscriptionEngine.swift`, `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`.
- **Implementation details**: Implement `WhisperTranscriptionEngine: TranscriptionEngineProtocol` holding an instance of `OrangeNoteEngine()` (or injected engine client). Resolve model cache path, dispatch standard or chunked FFI calls based on `request.chunkingEnabled`, and forward progress callbacks.
- **Tests / validation**: Unit tests verifying request translation and progress forwarding with mock engine.
- **Acceptance criteria**: `WhisperTranscriptionEngine` provides clean protocol-based access to local Whisper FFI.
- **Do not change**: C ABI function names or signatures.

### Task 2.9: Inject engine VM
- **Goal**: Refactor `TranscriptionViewModel` to accept an injected `TranscriptionEngineProtocol` dependency (defaulting to `WhisperTranscriptionEngine()`).
- **Dependencies**: Task 2.8.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`.
- **Files likely to add**: `OrangeNoteTests/TranscriptionViewModelEngineMockTests.swift`.
- **Implementation details**: Add initializer parameter `init(engine: TranscriptionEngineProtocol = WhisperTranscriptionEngine())`. Replace direct FFI calls in view model with `engine.transcribe(request:progressHandler:)`.
- **Tests / validation**: Unit tests executing view model flows using a mock transcription engine.
- **Acceptance criteria**: `TranscriptionViewModel` is fully testable without invoking native Rust binaries.
- **Do not change**: SwiftUI view call sites (`TranscriptionView`).

### Task 2.10: Integration gate
- **Goal**: Run complete test suite across all Phase 1 and Phase 2 components, ensuring zero regressions.
- **Dependencies**: Tasks 2.1–2.9.
- **Files to inspect**: All files in `OrangeNoteTests/`.
- **Files likely to modify**: None.
- **Files likely to add**: None.
- **Implementation details**: Execute full test target, verify zero build warnings, check coverage of schema and engine layers.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Acceptance criteria**: Complete test suite passes with 0 failures.
- **Do not change**: Existing functional code.

---


## PHASE 2 REMEDIATION GATE

### Task 2.11: Engine semantic contract + concurrency-safe test doubles
- **Goal**: Explicitly document and enforce the semantic lifetime, drain, cancellation, and progress contract on `TranscriptionEngineProtocol` and replace unsynchronized `@unchecked Sendable` mock engines with thread-safe / actor / lock-based / MainActor-safe test doubles.
- **Dependencies**: Task 2.10.
- **Files to inspect**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`, `OrangeNote/Engine/TranscriptionRequest.swift`, `OrangeNoteTests/TranscriptionEngineProtocolTests.swift`, `OrangeNoteTests/TranscriptionViewModelEngineMockTests.swift`.
- **Files likely to modify**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`, `OrangeNoteTests/TranscriptionEngineProtocolTests.swift`, `OrangeNoteTests/TranscriptionViewModelEngineMockTests.swift`.
- **Files likely to add**: `OrangeNoteTests/Helpers/MockTranscriptionEngine.swift`.
- **Implementation details**: Document contract on `TranscriptionEngineProtocol`: (1) returning or throwing guarantees underlying operations and resources are completely drained and finished; (2) caller `Task.cancel()` does not imply native or provider cancellation unless explicitly coordinated; (3) progress handlers must never be invoked after `transcribe` returns or throws. Replace `@unchecked Sendable` mock engines with actor-based, lock-protected, or MainActor-safe test doubles to eliminate data-race risks. Add contract unit tests with controllable mock engine behavior (verifying drain semantics, no-progress-after-completion, error propagation).
- **Tests / validation**: Unit tests validating protocol drain contract and mock thread safety: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionEngineProtocolTests,OrangeNoteTests/TranscriptionViewModelEngineMockTests`.
- **Acceptance criteria**: Protocol lifetime contract formally documented; mock engines are concurrency-safe without unsynchronized mutable state; contract unit tests pass cleanly.
- **Do not change**: Rust FFI code, C ABI, or Batch processing code.

### Task 2.12: WhisperEngineClient seam and adapter-level orchestration tests
- **Goal**: Introduce a narrow Swift engine client protocol seam (`WhisperEngineClient`) adapted/conformed by `OrangeNoteEngine` without C ABI or Rust changes, and add full adapter orchestration unit tests for `WhisperTranscriptionEngine`.
- **Dependencies**: Task 2.11.
- **Files to inspect**: `OrangeNote/Engine/WhisperTranscriptionEngine.swift`, `OrangeNote/Bridge/OrangeNoteFFI.swift`, `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`.
- **Files likely to modify**: `OrangeNote/Engine/WhisperTranscriptionEngine.swift`, `OrangeNote/Bridge/OrangeNoteFFI.swift`, `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`.
- **Files likely to add**: `OrangeNoteTests/WhisperEngineMockClient.swift`.
- **Implementation details**: Define a narrow protocol `WhisperEngineClient: Sendable` capturing `modelPath(name:)`, `transcribeFile(...)`, and `transcribeFileChunked(...)`. Extend/conform `OrangeNoteEngine` to `WhisperEngineClient` (without any Rust or C header modifications). Update `WhisperTranscriptionEngine` to accept `WhisperEngineClient` via dependency injection (defaulting to `OrangeNoteEngine()`). Add unit tests in `WhisperTranscriptionEngineTests` testing: standard vs chunked dispatch selection, modelPath resolution/request, FFI parameter construction, progress callback forwarding, domain result mapping, and error propagation.
- **Tests / validation**: Unit tests covering `WhisperTranscriptionEngine` orchestration paths with mock client: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/WhisperTranscriptionEngineTests`.
- **Acceptance criteria**: `WhisperTranscriptionEngine` is 100% unit-tested for standard and chunked execution, model path querying, parameter forwarding, progress callback bridging, and error handling; zero C ABI or Rust changes.
- **Do not change**: `orangenote-ffi/`, `orangenote-core/`, C ABI signatures, or Rust build scripts.

### Task 2.13: Execution provenance and honest canonical export metadata wiring
- **Goal**: Capture transcription execution provenance (source URL, model name, engine ID) at orchestration level without overloading runtime `TranscriptionResult`, wire real metadata to `ExportViewModel`, and implement privacy-safe honest export behavior for imported/missing metadata.
- **Dependencies**: Task 2.10.
- **Files to inspect**: `OrangeNote/ViewModels/ExportViewModel.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNote/Persistence/CanonicalTranscriptionDocument.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/ExportViewModel.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`.
- **Files likely to add**: `OrangeNoteTests/ExecutionProvenanceExportTests.swift`.
- **Implementation details**: Capture execution provenance metadata (source file URL/name, model name, stable engine ID e.g. `"whisper-local"`) at the ViewModel / AppState orchestration layer alongside the domain `TranscriptionResult` without modifying domain structs `TranscriptionResult`/`TranscriptionSegment`. Wire active provenance into `ExportViewModel` during export flows (save, copy, batch prep). For imported results, preserve available document metadata or use honest optional/unknown representations without fabricating fake file paths. Respect privacy: path in `SourceMetadata` should preferably be omitted (`nil`) or handled privacy-safely by default unless explicitly configured. Ensure engine ID uses a single stable identifier source.
- **Tests / validation**: Unit tests validating provenance tracking, export metadata wiring for transcribed vs imported results, and privacy-safe path handling: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/ExportViewModelCanonicalTests,OrangeNoteTests/ExecutionProvenanceExportTests`.
- **Acceptance criteria**: Exported Canonical JSON documents contain real source filename, model name, and stable engine ID instead of hardcoded placeholders; imported results reflect honest metadata without fake paths; path privacy requirement satisfied.
- **Do not change**: Domain model struct definitions (`TranscriptionResult`, `TranscriptionSegment`), Rust code, or C ABI.

### Task 2.14: Numeric validation hardening + legacy duration max
- **Goal**: Harden `CanonicalTranscriptionSerializer` against invalid/non-finite numeric values (NaN/Infinity) with typed validation errors, validate chunk duration constraints from a single default source, and fix legacy FFI import duration calculation to compute max endTime across all segments.
- **Dependencies**: Task 2.10.
- **Files to inspect**: `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/Engine/WhisperTranscriptionEngine.swift`.
- **Files likely to modify**: `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNote/Services/TranscriptionImportService.swift`.
- **Files likely to add**: `OrangeNoteTests/NumericValidationHardeningTests.swift`.
- **Implementation details**: In `CanonicalTranscriptionSerializer`, add finite/range checks before converting timestamps (`Double` to `Int` milliseconds) to prevent traps on `Double.nan`, `Double.infinity`, or negative values; throw typed `CanonicalTranscriptionSerializerError.invalidNumericValue` / `outOfRange` instead of trapping or silently coercing invalid values. Validate chunk and overlap duration ranges with single-source constraints. In `TranscriptionImportService.makeResult(fromFFI:)`, calculate `duration` as `segments.map(\.endTime).max() ?? 0.0` rather than relying on `segments.last?.endTime`. Add unsorted segments fixture test.
- **Tests / validation**: Unit tests with NaN/Infinity timestamps, negative values, out-of-order segments legacy import fixture: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/NumericValidationHardeningTests,OrangeNoteTests/LegacyImportTests`.
- **Acceptance criteria**: Serializer safely rejects non-finite/invalid numeric values with typed errors without crashing; legacy FFI import handles unsorted segments correctly using maximum endTime.
- **Do not change**: Rust code or C ABI.

### Task 2.15: Final Phase 2 remediation regression and manual verification gate
- **Goal**: Execute full test suites across Swift and Rust, perform manual verification of canonical JSON export/import metadata fidelity, execute standard and chunked Whisper smoke tests, and conduct formal review to close Phase 2 and unblock Phase 3.
- **Dependencies**: Tasks 2.12, 2.13, 2.14.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full automated Swift test suite (`xcodebuild test`) and Rust test suite (`cargo test --workspace`). Perform manual verification in compiled macOS app: (1) Export transcribed file to Canonical JSON, verify actual model name, source file name, and engine ID in JSON output; (2) Import Canonical JSON and verify segment rendering and honest metadata handling; (3) Run single-file standard transcription smoke test; (4) Run single-file chunked transcription smoke test. Conduct quality review to approve Phase 2 closure and unblock Phase 3.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (0 failures); manual JSON export/import metadata and standard/chunked smoke tests verified; Phase 2 formal review approved.
- **Do not change**: Production code or architectural decisions.

---

---

## PHASE 2 REMEDIATION FINAL CORRECTIONS

### Task 2.16: Atomic DisplayedTranscription + import metadata preservation & honest unknown export
- **Goal**: Introduce an atomic displayed result context (`DisplayedTranscription` pairing `TranscriptionResult` and associated provenance/import metadata) for export and UI presentation, and preserve safe canonical metadata on import while using honest `"unknown"` for unknown/legacy provenance without fake local engine IDs or fake source paths.
- **Dependencies**: Task 2.15.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/ViewModels/ExportViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Models/ExecutionProvenance.swift`, `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/Persistence/CanonicalTranscriptionDocument.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/ResultsView.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/ViewModels/ExportViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Models/ExecutionProvenance.swift`, `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/ResultsView.swift`.
- **Files likely to add**: `OrangeNote/Models/DisplayedTranscription.swift`, `OrangeNoteTests/DisplayedTranscriptionTests.swift`.
- **Implementation details**: (R1, R2) Create atomic `DisplayedTranscription` pairing domain `TranscriptionResult` with its `ExecutionProvenance`. In `TranscriptionViewModel`, represent displayed completion atomically; running provenance remains separate during active execution and publishes to `displayedTranscription` only upon successful completion. Update `AppState.currentDisplayedTranscription` atomically in a single property (eliminating separate desynchronized `result` and `provenance` properties/observers). AppState remains current displayed transcription only (no transcript history store). Update `TranscriptionImportService` so that importing canonical documents (`schemaVersion == 1`) preserves safe metadata (`source.fileName`, `engine.model`, `engine.id`) into the imported context while keeping `path = nil` (no fake path reconstruction); unversioned legacy imports report honest `"unknown"` metadata. In `ExportViewModel` (`saveToFile`, `copyToClipboard`, `generateExport`), eliminate defaulting `engineID` to `"whisper-local"` when provenance is nil/unknown — fallback must be honest `"unknown"`.
- **Tests / validation**: Unit tests validating atomic displayed result updates, canonical import metadata preservation (filename, model, engine ID, nil path), legacy import unknown metadata, and export fallback to `"unknown"` engineID: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/ExportViewModelCanonicalTests,OrangeNoteTests/ExecutionProvenanceExportTests,OrangeNoteTests/TranscriptionImportServiceTests,OrangeNoteTests/DisplayedTranscriptionTests`.
- **Acceptance criteria**: Result and provenance are updated atomically as a single context; canonical import preserves safe document metadata; unknown/legacy export uses honest `"unknown"` engine ID; no fake local source paths or fake engine IDs; AppState holds current context only.
- **Do not change**: Rust FFI bindings, C ABI, or `orangenote-core`.

### Task 2.17: Engine identity protocol + provenance snapshot actual engine
- **Goal**: Add stable engine identity requirement to `TranscriptionEngineProtocol` / descriptor and snapshot the actual injected engine's identity per job execution, eliminating hardcoded engine ID assumptions without building a global engine registry.
- **Dependencies**: Task 2.15.
- **Files to inspect**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`, `OrangeNote/Engine/WhisperTranscriptionEngine.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNoteTests/Helpers/MockTranscriptionEngine.swift`.
- **Files likely to modify**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`, `OrangeNote/Engine/WhisperTranscriptionEngine.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNoteTests/Helpers/MockTranscriptionEngine.swift`.
- **Files likely to add**: `OrangeNoteTests/EngineIdentityTests.swift`.
- **Implementation details**: (R3) Extend `TranscriptionEngineProtocol` with `var engineID: String { get }` (or engine descriptor containing stable ID). Conform `WhisperTranscriptionEngine` with `engineID = "whisper-local"`. Update `MockTranscriptionEngine` (and any other test doubles) to provide configurable/custom engine IDs. In `TranscriptionViewModel`, snapshot the actual injected `engine.engineID` at job start instead of hardcoding `WhisperTranscriptionEngine.stableEngineID`. Do not construct an overengineered engine registry or service locator.
- **Tests / validation**: Unit tests verifying `engineID` protocol requirement, `WhisperTranscriptionEngine` stable identity, custom injected mock engine identity propagation to execution provenance, and export verification with custom engine IDs: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/EngineIdentityTests,OrangeNoteTests/WhisperTranscriptionEngineTests`.
- **Acceptance criteria**: `TranscriptionEngineProtocol` exposes engine identity; `TranscriptionViewModel` captures actual injected engine ID dynamically; custom engines correctly reflect their own ID in provenance and export; zero global engine registry overhead.
- **Do not change**: C ABI headers, Rust FFI, or Batch processing code.

### Task 2.18: Strengthen drain/concurrency contract tests and legacy ExportView/replacement coverage
- **Goal**: Strengthen `TranscriptionEngineProtocol` drain and concurrency contract tests with controllable non-cancellation-sensitive gates, add no-progress-after-throw tests, fix Sendable progress recording in tests, wire atomic context to legacy `ExportView` (or retire if unused), and add real replacement provenance tests.
- **Dependencies**: Tasks 2.16, 2.17.
- **Files to inspect**: `OrangeNoteTests/TranscriptionEngineProtocolTests.swift`, `OrangeNoteTests/Helpers/MockTranscriptionEngine.swift`, `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`, `OrangeNoteTests/TranscriptionViewModelEngineMockTests.swift`, `OrangeNote/Views/ExportView.swift`.
- **Files likely to modify**: `OrangeNoteTests/TranscriptionEngineProtocolTests.swift`, `OrangeNoteTests/Helpers/MockTranscriptionEngine.swift`, `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`, `OrangeNoteTests/TranscriptionViewModelEngineMockTests.swift`, `OrangeNote/Views/ExportView.swift`.
- **Files likely to add**: `OrangeNoteTests/Helpers/SendableProgressRecorder.swift`.
- **Implementation details**: (R4, R5, R6, R7) In test doubles, introduce a controllable non-cancellation-sensitive completion gate / drain resource to verify that engine drain waits for actual resource release regardless of caller `Task.cancel()`. Add unit tests explicitly verifying no progress callbacks are invoked after `transcribe` throws an error. Add adapter drain tests for standard and chunked execution paths. Replace mutable array captures in `@Sendable` progress closures with a concurrency-safe `SendableProgressRecorder` (actor or lock-based). Wire atomic `DisplayedTranscription` context into `ExportView` (or explicitly retire `ExportView` if completely superseded). Add unit test verifying that replacing a running or completed transcription with a new job captures the new job's provenance and context deterministically.
- **Tests / validation**: Unit tests verifying drain contract under cancellation, no progress after throw, thread-safe progress recording, `ExportView` atomic context, and job replacement provenance: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionEngineProtocolTests,OrangeNoteTests/WhisperTranscriptionEngineTests,OrangeNoteTests/TranscriptionViewModelEngineMockTests`.
- **Acceptance criteria**: Contract tests prove non-cancellation-sensitive drain; no-progress-after-throw verified; Sendable progress recorder eliminates data-race warnings; `ExportView` properly wired or retired; real replacement provenance tested.
- **Do not change**: Rust FFI code, C ABI, or Batch processing code.

### Task 2.19: Final Phase 2 regression / manual verification gate & quality review
- **Goal**: Execute full test suites across Swift and Rust, perform formal human manual verification across all 4 key scenarios (canonical export metadata fidelity, canonical import rendering/metadata fidelity, standard Whisper smoke, chunked Whisper smoke), and conduct formal quality review to close Phase 2 and unblock Phase 3.
- **Dependencies**: Task 2.18.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full automated Swift test suite (`xcodebuild test`) and Rust test suite (`cargo test --workspace`). Complete formal human manual verification in the compiled macOS app across 4 scenarios: (1) Export real transcribed audio to Canonical JSON and verify real model name, source filename, and engine ID in JSON output; (2) Import Canonical JSON and verify segment rendering and honest preserved metadata; (3) Run single-file standard transcription smoke test with real local model; (4) Run single-file chunked transcription smoke test with real local model. Conduct formal review confirming resolution of findings B1–B6 and R1–R7 to approve Phase 2 closure and authorize Phase 3 (Task 3.1).
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass across Swift and Rust suites (0 failures); all 4 manual verification scenarios confirmed by human/orchestrator; formal review approves Phase 2 closure and unblocks Phase 3.
- **Do not change**: Production code or architectural decisions.

## PHASE 2 FINAL CLOSURE CORRECTIONS

### Task 2.20: Atomic displayed/job provenance ownership + ResultsView wiring + sourceFileName/URL model correction
- **Goal**: Enforce atomic `DisplayedTranscription` presentation and export by wiring `ResultsView` directly to a single displayed context snapshot, bind running execution provenance to active `jobID` / running state in `TranscriptionViewModel` (eliminating side-channel staleness), and correct `ExecutionProvenance` to separate `sourceFileName` from optional real `sourceURL` with honest canonical import metadata.
- **Dependencies**: Task 2.19.
- **Files to inspect**: `OrangeNote/Models/ExecutionProvenance.swift`, `OrangeNote/Models/DisplayedTranscription.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/ResultsView.swift`, `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/ViewModels/ExportViewModel.swift`.
- **Files likely to modify**: `OrangeNote/Models/ExecutionProvenance.swift`, `OrangeNote/Models/DisplayedTranscription.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/ResultsView.swift`, `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`, `OrangeNote/Services/TranscriptionImportService.swift`, `OrangeNote/ViewModels/ExportViewModel.swift`.
- **Files likely to add**: `OrangeNoteTests/DisplayedTranscriptionWiringTests.swift`.
- **Implementation details**: (F1, F2, F3)
  1. (F1) Refactor `ResultsView` to accept a single `displayedTranscription: DisplayedTranscription` context (or binding) rather than taking `result: TranscriptionResult` and pulling `appState.currentExecutionProvenance` out-of-band; ensure all export, copy-to-clipboard, and display actions use the exact same snapshot. Update `ContentView` accordingly.
  2. (F2) In `TranscriptionViewModel`, replace the separate side-channel `executionProvenance` property with job-owned running provenance keyed by `jobID` or held directly within running lifecycle context. Upon successful transcription completion, construct and publish `DisplayedTranscription` atomically. On failure, cancellation, or file replacement, discard and clear the running context cleanly without leaving stale provenance. Keep implementation simple and avoid overengineered frameworks.
  3. (F3) Update `ExecutionProvenance` to define `sourceFileName: String` and optional `sourceURL: URL?`. On canonical import in `TranscriptionImportService`, set `sourceURL = nil` and `sourceFileName = doc.source.fileName` instead of constructing a fake file URL. Update `CanonicalTranscriptionSerializer` to accept honest source metadata (non-nil `sourceFileName`, optional `sourceURL`) without requiring fake path construction.
- **Tests / validation**: Unit tests verifying `ResultsView` atomic wiring, job-owned provenance lifecycle, error/cancellation provenance cleanup, honest import metadata preservation with nil `sourceURL`, and export serialization: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS -only-testing:OrangeNoteTests/DisplayedTranscriptionWiringTests,OrangeNoteTests/DisplayedTranscriptionAtomicityTests,OrangeNoteTests/ExecutionProvenanceExportTests,OrangeNoteTests/TranscriptionImportServiceTests`.
- **Acceptance criteria**: `ResultsView` renders and exports strictly from atomic `DisplayedTranscription`; provenance is job-owned and cleared on failure/cancellation; canonical import does not construct fake URLs; all unit tests pass with zero regressions.
- **Do not change**: Rust FFI bindings, C ABI, or `orangenote-core`.

### Task 2.21: Complete adapter drain/error/cancellation matrix and production-representative replacement/import-error UX tests
- **Goal**: Complete the `WhisperTranscriptionEngine` adapter drain and concurrency test matrix under normal completion, caller cancellation, and error throwing with post-error callback assertions, replace non-representative testing seams with production-representative replacement tests, and add user-facing UI error handling for document import failures in `ContentView`.
- **Dependencies**: Task 2.20.
- **Files to inspect**: `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`, `OrangeNoteTests/Helpers/CompletionGate.swift`, `OrangeNoteTests/TranscriptionJobConcurrencyTests.swift`, `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Resources/*.lproj/Localizable.strings`.
- **Files likely to modify**: `OrangeNoteTests/WhisperTranscriptionEngineTests.swift`, `OrangeNoteTests/TranscriptionJobConcurrencyTests.swift`, `OrangeNoteTests/TranscriptionViewModelLifecycleTests.swift`, `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Resources/en.lproj/Localizable.strings`, `OrangeNote/Resources/ru.lproj/Localizable.strings`, `OrangeNote/Resources/fr.lproj/Localizable.strings`.
- **Files likely to add**: None.
- **Implementation details**: (F4, F5, F6)
  1. (F4) In `WhisperTranscriptionEngineTests`, expand adapter drain tests using non-cancellation-sensitive `CompletionGate` across standard and chunked execution paths: verify drain completion under normal return, verify adapter drain continues until mock client finishes even if caller `Task` is cancelled, and verify gated error throwing asserts zero progress callbacks occur after error is thrown.
  2. (F5) In concurrency/lifecycle test suites, replace test-seam-based active job replacement with production-representative tests: verify replacing a completed result with a new file selection and transcription updates context deterministically, and verify stale async completion via injectable mock engine respects public ViewModel APIs and busy invariants without bypassing encapsulation.
  3. (F6) In `ContentView.swift` (lines 163–165 catch block), replace the console-only `print(...)` statement with an explicit ViewModel intent (e.g. `transcriptionVM.reportImportError(...)`) surfacing localized user feedback in `errorMessage` / UI. Ensure localization keys across `en`, `ru`, `fr` do not misuse drag-and-drop phrasing for file picker import errors.
  4. Do not touch Rust, C ABI, Gemini cloud engine, or Batch processing code.
- **Tests / validation**: Unit tests verifying complete adapter drain/error/cancellation matrix, representative replacement flows, and import error UI feedback: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS -only-testing:OrangeNoteTests/WhisperTranscriptionEngineTests,OrangeNoteTests/TranscriptionJobConcurrencyTests,OrangeNoteTests/TranscriptionViewModelLifecycleTests,OrangeNoteTests/TranscriptionImportLifecycleTests`.
- **Acceptance criteria**: Adapter drain matrix fully tested for standard/chunked/cancel/error paths; no progress callbacks after error verified at adapter boundary; replacement tests model production-valid invariants; import errors surface clear localized user feedback; zero regressions.
- **Do not change**: Rust FFI code, C ABI, `orangenote-core`, or Batch processing models.

### Task 2.22: Phase 2 final review and test gate
- **Goal**: Execute full automated Swift and Rust test suites, confirm regression-free quality, verify whether Task 2.20 serialization changes require repeating manual canonical import/export check (carrying standard and chunked Whisper smoke evidence forward), and conduct formal quality review to close Phase 2 and unblock Phase 3.
- **Dependencies**: Task 2.21.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full automated Swift (`xcodebuild test`) and Rust (`cargo test --workspace`) suites. Note that the 4-scenario manual verification evidence from 2026-08-29 was already accepted by user; repeat only the impacted canonical JSON import/export manual verification if Task 2.20 changes serialized metadata fields; standard and chunked Whisper smoke evidence carries forward since Task 2.21 affects only tests and import error UX. Conduct formal code and quality review to approve Phase 2 closure and authorize Task 3.1.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (0 failures); impacted canonical import/export manual verification confirmed if required; formal review approves Phase 2 closure and unblocks Phase 3.
- **Do not change**: Production business logic or architectural decisions.

---

## PHASE 2 CLOSURE GATE (CHUNK I-R4)

### Task 2.23: Fix job-owned provenance terminal transfer
- **Goal**: Fix the real job ownership defect (G1) where `runningJobID` is written but never validated at completion, and success builds `DisplayedTranscription` from side-channel `executionProvenance` while `runningJobID` remains set after terminal state transitions.
- **Dependencies**: Task 2.22.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/DisplayedTranscription.swift`, `OrangeNote/Models/ExecutionProvenance.swift`, `OrangeNoteTests/TranscriptionJobConcurrencyTests.swift`, `OrangeNoteTests/DisplayedTranscriptionWiringTests.swift`.
- **Files likely to modify**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNoteTests/TranscriptionJobConcurrencyTests.swift`, `OrangeNoteTests/DisplayedTranscriptionWiringTests.swift`.
- **Files likely to add**: None.
- **Implementation details**: (G1) In `TranscriptionViewModel`, read and validate job ownership at completion time (`isActiveJob(jobID)` / matching running job token). Atomically move matching running provenance into the completed terminal context (preferring `TranscriptionLifecycleState.completed(file:displayed:)` or atomic construction at completion), and clear running job ownership (`runningJobID = nil`, running provenance = nil) upon terminal completion, failure, cancellation, or replacement. Ensure wrong-job provenance cannot attach to active results and that `runningJobID` is cleared after terminal state transitions.
- **Tests / validation**: Unit tests asserting wrong-job provenance cannot attach to results, successful completion atomically sets `displayedTranscription` and clears running job ownership, and failure/cancellation clears running provenance and `runningJobID`: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS -only-testing:OrangeNoteTests/TranscriptionJobConcurrencyTests,OrangeNoteTests/DisplayedTranscriptionWiringTests`.
- **Acceptance criteria**: Job ownership validated at completion; `displayedTranscription` constructed atomically from validated job provenance; `runningJobID` and running provenance cleared on all terminal transitions; zero regressions.
- **Do not change**: Rust FFI code, C ABI, `orangenote-core`, or Batch processing models.

### Task 2.24: Make document import errors globally visible
- **Goal**: Resolve the hidden document import error presentation defect (G2) by providing application-level alert or navigation behavior so that import failures triggered from any tab (Results, Models, Settings, Transcribe) are visibly presented to the user without duplicate alerts.
- **Dependencies**: Task 2.23.
- **Files to inspect**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to modify**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to add**: None.
- **Implementation details**: (G2) `reportImportError` stores VM error state, but `TranscriptionView` is currently the only alert presenter. When document import is triggered from menu/shortcut while viewing Results, Models, or Settings, the user receives no visible feedback. Add application-level alert or navigation behavior using dedicated import error state in `AppState` / `ContentView`, ensuring exactly one visible alert is presented on error and no duplicate alert appears when `TranscriptionView` is active.
- **Tests / validation**: Unit tests validating import error state routing across app state and view model, and verify clean dismissal: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS -only-testing:OrangeNoteTests/TranscriptionImportLifecycleTests`.
- **Acceptance criteria**: Import errors triggered while any view is selected present a visible alert; no duplicate alert on Transcribe tab; error state clears cleanly upon dismissal; all unit tests pass.
- **Do not change**: Rust code, C ABI, single-file drop resolver logic, or Batch processing components.

### Task 2.25: Phase 2 intermediate review & import audit
- **Goal**: Execute full automated regression suites, audit Task 2.23 job ownership resolution (G1) and Task 2.24 global error routing (G2), and verify import error presentation across view tabs.
- **Dependencies**: Task 2.24.
- **Files to inspect**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to modify**: None (review/gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full Swift and Rust test suites. Audit G1 resolution (job ownership token validated at completion, atomic terminal transfer, cleanup paths). Audit G2 global import error presentation: confirm parse/read failure catch block routes to `AppState.importErrorMessage` on Results/Models/Settings tabs and `transcriptionVM.reportImportError` on Transcribe tab. Identify remaining unhandled busy import rejection path (`applyImportedResult` setting only VM error message on valid doc import while busy without throwing).
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift and Rust suites (181/181 Swift, 42/42 Rust); G1 confirmed resolved; unhandled G2 busy rejection path documented for remediation in Task 2.26.
- **Do not change**: Production business logic or architectural decisions.

### Task 2.26: Route busy import rejection through global error presenter
- **Goal**: Route document import busy rejections through the global error presenter so that attempting to import a valid document while transcription is running or draining from non-Transcribe tabs (Results, Models, Settings) displays a visible application-level alert, while maintaining inline error presentation on the Transcribe tab without state mutation or tab switching.
- **Dependencies**: Task 2.25.
- **Files to inspect**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to modify**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to add**: None.
- **Implementation details**: In `ContentView.openTranscriptionFile()` / `TranscriptionViewModel.applyImportedResult`, handle busy-state rejection consistently across tabs. When `isBusy` (`isTranscribing` or `isNativeBusy`) is true during document import, do not rely solely on `transcriptionVM.errorMessage` when a non-Transcribe tab is selected. ContentView should decide the error route using pre-checked busy state before apply, or `applyImportedResult` should return a typed admission result (e.g. `.admitted` vs `.rejectedBusy`). On busy rejection, route localized busy error message (`error.transcription_in_progress` or dedicated busy import message) to `transcriptionVM.errorMessage` inline when `selectedItem == .transcribe`, or to `appState.importErrorMessage` global alert when `selectedItem != .transcribe`. Ensure exactly one visible error is presented with no alert duplication, no state mutation of active/displayed transcription, and no automatic tab switch. Do not redesign the underlying lifecycle.
- **Tests / validation**: Unit tests validating route helper / admission result across all tabs (Transcribe vs Results/Models/Settings) under both running (`isTranscribing`) and draining (`isNativeBusy`) states, asserting exactly one error target is populated, active results are untouched, and dismissal clears cleanly: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS -only-testing:OrangeNoteTests/TranscriptionImportLifecycleTests`.
- **Acceptance criteria**: Valid document import attempted while busy presents an inline error on Transcribe tab and a global alert on Results/Models/Settings tabs; exactly one error presenter is populated per attempt; active/displayed transcription state is untouched; all unit tests pass with zero regressions.
- **Do not change**: Rust FFI code, C ABI, `orangenote-core`, drop resolver logic, or lifecycle state machine architecture.

### Task 2.27: Phase 2 intermediate review & regression review
- **Goal**: Execute automated regression test suites, audit Task 2.26 busy-import routing resolution (G2-busy), and document remaining release blockers and low backlog items.
- **Dependencies**: Task 2.26.
- **Files to inspect**: `OrangeNote/Views/ContentView.swift`, `OrangeNote/ViewModels/TranscriptionViewModel.swift`, `OrangeNote/Models/AppState.swift`, `OrangeNoteTests/TranscriptionImportLifecycleTests.swift`.
- **Files likely to modify**: None (audit/gate task).
- **Files likely to add**: None.
- **Implementation details**: Audit Task 2.26 implementation: pre-check before apply, inline vs global alert routing, no tab switch, no state mutation, defensive VM guard retained. Verify passing automated suites (Swift 181/181, Rust 42/42). Document low-priority test style backlog items (duplicate routing branch in test helper, stale opposite presenter state not explicitly cleared) without adding speculative remediation. Record release blocker: `OrangeNote/Info.plist` `CFBundleShortVersionString` accidental downgrade to 0.1.5 to be addressed in Task 2.28.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS` and `cargo test --workspace`.
- **Acceptance criteria**: Task 2.26 confirmed functionally accepted; automated test results verified; version metadata blocker identified for Task 2.28; no speculative tasks added.
- **Do not change**: Production business logic or architectural decisions.

### Task 2.28: Restore intended app version metadata
- **Goal**: Restore repository baseline app version metadata (`CFBundleShortVersionString` 0.1.6) across project configuration and `Info.plist` without accidental downgrade to 0.1.5 or arbitrary version bump.
- **Dependencies**: Task 2.27.
- **Files to inspect**: `project.yml`, `OrangeNote/Info.plist`, `.ai/context.md`, git history / baseline.
- **Files likely to modify**: `project.yml`, `OrangeNote/Info.plist`.
- **Files likely to add**: None.
- **Implementation details**: Inspect `project.yml`, `OrangeNote/Info.plist`, and version sources to determine why `xcodegen generate` repeatedly downgrades `CFBundleShortVersionString` from 0.1.6 to 0.1.5. Restore consistent version metadata matching repository baseline `0.1.6` (and corresponding build number/version definitions in `project.yml` or `Info.plist`). Ensure regenerating via XcodeGen or building preserves `CFBundleShortVersionString` as `0.1.6`. Do not bump to a new arbitrary version (e.g. 0.1.7). No production Swift or Rust changes.
- **Tests / validation**: Inspect `OrangeNote/Info.plist` or run `xcodegen generate` and verify `CFBundleShortVersionString` equals `0.1.6`; verify `xcodebuild build` / `xcodebuild test` succeeds.
- **Acceptance criteria**: `CFBundleShortVersionString` is consistently `0.1.6`; no uncommitted accidental version downgrade in `Info.plist`; zero production Swift or Rust changes; all tests pass.
- **Do not change**: Production Swift or Rust code, entitlements, or audio pipeline.

### Task 2.29: Final Phase 2 closure gate, regression review & manual verification
- **Goal**: Execute full automated regression suites across Swift and Rust, verify absence of blocker regressions, confirm clean version metadata baseline (0.1.6), and formally close Phase 2 to authorize Phase 3 (manual checks confirmed passed on 2026-08-30).
- **Dependencies**: Task 2.28.
- **Files to inspect**: All files in `OrangeNote/`, `OrangeNoteTests/`, `orangenote-core/`, `orangenote-ffi/`.
- **Files likely to modify**: None (gate task).
- **Files likely to add**: None.
- **Implementation details**: Run full automated Swift (`xcodebuild test`) and Rust (`cargo test --workspace`) test suites. Confirm version metadata is clean (`0.1.6`). Retain user previous manual verification evidence. User manual checks (canonical export/import repeat and valid document busy import global alert) confirmed passed on 2026-08-30 and manual gate is complete. Explicit rule: NO further speculative remediation tasks may be added absent blocker-severity regressions. Upon review approval, formally close Phase 2 and authorize Task 3.1.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS` and `cargo test --workspace`.
- **Acceptance criteria**: 100% test pass on Swift (181/181+) and Rust (42/42) suites; manual canonical export/import repeat and busy import global alert confirmed by user (complete); version metadata verified as 0.1.6; formal review closes Phase 2 and authorizes Task 3.1.
- **Do not change**: Production business logic or architectural decisions.

---

## PHASE 3: Batch Processing Engine & UI

### Task 3.1: Audio type catalog
- **Goal**: Centralize supported audio UTI types and file extensions (`mp3`, `wav`, `m4a`, `flac`, `ogg`, `aac`, `opus`) in a unified `AudioTypeCatalog` auditing the real audio pipeline.
- **Dependencies**: Task 2.29.
- **Files to inspect**: `OrangeNote/Services/AudioFileValidator.swift`.
- **Files likely to modify**: `OrangeNote/Services/AudioFileValidator.swift`.
- **Files likely to add**: `OrangeNote/Models/AudioTypeCatalog.swift`, `OrangeNoteTests/AudioTypeCatalogTests.swift`.
- **Implementation details**: Provide static helpers `AudioTypeCatalog.isSupported(url:) -> Bool`, `allowedUTTypes: [UTType]`, `allowedExtensions: Set<String>`. Audit against pipeline formats: `mp3`, `wav`, `m4a`, `flac`, `ogg`, `aac`, `opus`.
- **Tests / validation**: Unit tests testing all audio extensions, uppercase variants, and unsupported files.
- **Acceptance criteria**: Single source of truth for audio type validation shared between single-file and batch modes.
- **Do not change**: Rust audio decoding libraries.

### Task 3.2: BatchItem
- **Goal**: Define `BatchItem` model representing individual file progress and outcome in the batch queue with exact approved statuses (D019).
- **Dependencies**: Task 3.1.
- **Files to inspect**: `OrangeNote/Models/TranscriptionResult.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Models/BatchItem.swift`, `OrangeNoteTests/BatchItemTests.swift`.
- **Implementation details**: Struct `BatchItem: Identifiable, Equatable`:
  - `id: UUID`
  - `sourceURL: URL`
  - `outputURL: URL?`
  - `status: BatchItemStatus` with exact cases: `.queued`, `.transcribing`, `.saving`, `.succeeded`, `.failed`, `.skipped`, `.cancelled` (no generic pending/processing/completed).
  - `progress: Float`
  - `errorMessage: String?`
  - `result: TranscriptionResult?`
- **Tests / validation**: Unit tests asserting status transitions and property mutation.
- **Acceptance criteria**: `BatchItem` matches exact status enum and state requirements.
- **Do not change**: Single-file models or view models.

### Task 3.3: File collector
- **Goal**: Build `BatchFileCollector` service to extract and validate audio files from an array of dropped or picked file URLs.
- **Dependencies**: Tasks 3.1, 3.2.
- **Files to inspect**: `OrangeNote/Models/AudioTypeCatalog.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Services/BatchFileCollector.swift`, `OrangeNoteTests/BatchFileCollectorTests.swift`.
- **Implementation details**: Accept an array of URLs; filter using `AudioTypeCatalog.isSupported(url:)`; instantiate `BatchItem` with status `.queued`.
- **Tests / validation**: Unit tests collecting from mixed arrays of valid audio, non-audio, and inaccessible URLs.
- **Acceptance criteria**: Non-audio files filtered out; valid audio files converted to queued `BatchItem` entries.
- **Do not change**: UI drop zone.

### Task 3.4: Top-level folder
- **Goal**: Extend `BatchFileCollector` to discover audio files located directly in the top-level directory of a selected folder (non-recursive, D020).
- **Dependencies**: Task 3.3.
- **Files to inspect**: `OrangeNote/Services/BatchFileCollector.swift`.
- **Files likely to modify**: `OrangeNote/Services/BatchFileCollector.swift`.
- **Files likely to add**: `OrangeNoteTests/BatchFolderCollectorTests.swift`.
- **Implementation details**: Read directory contents using `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])`. Filter top-level items with `AudioTypeCatalog.isSupported(url:)`. Subdirectories are strictly ignored.
- **Tests / validation**: Unit tests with mock directory structure containing audio files, nested subfolders with audio, and hidden files.
- **Acceptance criteria**: Only top-level audio files are collected; nested folder contents are ignored.
- **Do not change**: Sandbox file access model.

### Task 3.5: Normalize/dedup/sort
- **Goal**: Implement deterministic URL normalization, duplicate removal (by standardized URL path), and sorting by normalized FULL PATH using `localizedStandardCompare` with literal full-path tie breaker.
- **Dependencies**: Task 3.4.
- **Files to inspect**: `OrangeNote/Services/BatchFileCollector.swift`.
- **Files likely to modify**: `OrangeNote/Services/BatchFileCollector.swift`.
- **Files likely to add**: `OrangeNoteTests/BatchQueueNormalizationTests.swift`.
- **Implementation details**: Standardize URLs (`url.standardizedFileURL`). Deduplicate based on standardized path string. Sort by normalized full path using `path.localizedStandardCompare` with a literal string comparison tie-breaker. Do not sort by filename only.
- **Tests / validation**: Unit tests verifying duplicate elimination and deterministic full-path sorting order.
- **Acceptance criteria**: Queue contains unique items in deterministic natural full-path order.
- **Do not change**: State of items currently transcribing.

### Task 3.6: Output planner exact basename.json
- **Goal**: Implement `BatchOutputPlanner` generating destination paths matching `<outputDirectory>/<audio-basename>.json` (D017) and detecting existing files to mark as skipped without overwriting (D018).
- **Dependencies**: Task 3.5, Task 2.1.
- **Files to inspect**: `OrangeNote/Models/BatchItem.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Services/BatchOutputPlanner.swift`, `OrangeNoteTests/BatchOutputPlannerTests.swift`.
- **Implementation details**: For each item, compute `outputURL = outputDir.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent).appendingPathExtension("json")`. Check `FileManager.default.fileExists(atPath:)`. If the output file already exists, mark `item.status = .skipped` (D018).
- **Tests / validation**: Unit tests testing path computation matching exact base name and skip detection for existing files.
- **Acceptance criteria**: Output paths match `<audio-basename>.json`; existing files marked skipped without overwriting.
- **Do not change**: Input media files.

### Task 3.7: Atomic writer (COMPLETE / VERIFIED)
- **Goal**: Implement `AtomicFileWriter` to safely write Canonical JSON v1 documents to disk using temporary files in the same directory and non-overwriting moves, ensuring late collisions skip without replacing existing output.
- **Dependencies**: Task 3.6, Task 2.2.
- **Files to inspect**: `OrangeNote/Persistence/CanonicalTranscriptionSerializer.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Services/AtomicFileWriter.swift`, `OrangeNoteTests/AtomicFileWriterTests.swift`.
- **Implementation details**: Serialize document to JSON `Data`. Write data to a unique temporary file in the destination directory. Move/rename temporary file to target path using non-overwriting semantics (e.g. `link` + `unlink` or `moveItem` with pre-check). If target file was created concurrently, discard temp file and report skipped/collision rather than overwriting.
- **Tests / validation**: Unit tests verifying atomic write, permissions, cleanup of temp files, and collision handling.
- **Acceptance criteria**: Writes are atomic; existing output files are NEVER overwritten or corrupted.
- **Do not change**: Single-file export view model.

### Task 3.8: Sequential coordinator (COMPLETE / VERIFIED)
- **Goal**: Build `BatchTranscriptionCoordinator` executing batch queue items strictly sequentially (D015).
- **Dependencies**: Task 3.7, Task 2.8.
- **Files to inspect**: `OrangeNote/Engine/TranscriptionEngineProtocol.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Services/BatchTranscriptionCoordinator.swift`, `OrangeNoteTests/BatchTranscriptionCoordinatorTests.swift`.
- **Implementation details**: Loop over items sequentially. For each queued item: update status to `.transcribing`, call `engine.transcribe(...)`, update status to `.saving`, write output via `AtomicFileWriter`, and update status to `.succeeded`.
- **Tests / validation**: Unit tests with mock engine verifying sequential invocation and accurate status transitions.
- **Acceptance criteria**: Files are transcribed strictly one at a time with live progress reporting.
- **Do not change**: Rust inference threading.

### Task 3.9: Continue failure (COMPLETE / VERIFIED)
- **Goal**: Enhance `BatchTranscriptionCoordinator` to capture per-file errors, mark the item `.failed`, record the error message, and continue processing remaining items without aborting the batch (D016).
- **Dependencies**: Task 3.8.
- **Files to inspect**: `OrangeNote/Services/BatchTranscriptionCoordinator.swift`.
- **Files likely to modify**: `OrangeNote/Services/BatchTranscriptionCoordinator.swift`.
- **Files likely to add**: `OrangeNoteTests/BatchErrorContinuationTests.swift`.
- **Implementation details**: Wrap per-item transcription and saving in `do-catch`. On error: record `item.errorMessage = error.localizedDescription`, `item.status = .failed`, emit item completion event, and proceed to next item in the queue.
- **Tests / validation**: Unit test with failing mock item in the middle of a queue; verify subsequent items complete successfully.
- **Acceptance criteria**: Batch execution completes all remaining items even if individual files fail.
- **Do not change**: Single-file error handling in `TranscriptionViewModel`.

### Task 3.10: Stop-after-current (COMPLETE / VERIFIED)
- **Goal**: Implement stop-after-current cancellation policy in `BatchTranscriptionCoordinator` (D021, D022).
- **Dependencies**: Task 3.9.
- **Files to inspect**: `OrangeNote/Services/BatchTranscriptionCoordinator.swift`.
- **Files likely to modify**: `OrangeNote/Services/BatchTranscriptionCoordinator.swift`.
- **Files likely to add**: `OrangeNoteTests/BatchCancellationTests.swift`.
- **Implementation details**: Maintain cancellation state flag. When `cancel()` is called: the active item finishes its current transcription and atomic save; remaining queued items are marked as `.cancelled`; no subsequent items are started. All successfully written files are preserved (D022).
- **Tests / validation**: Unit test triggering cancellation during item execution; verify active item finishes and saves, pending items marked `.cancelled`, and written files survive.
- **Acceptance criteria**: Cancellation halts queue cleanly after active item; completed files remain intact on disk.
- **Do not change**: File deletion logic (no output deletions).

### Task 3.11: Read-write entitlement/security scope (COMPLETE / VERIFIED)
- **Goal**: Update App Sandbox entitlement from read-only to `com.apple.security.files.user-selected.read-write` (not both) and implement `SecurityScopeHelper` managing folder access scopes for the batch lifetime without bookmarks (D023).
- **Dependencies**: Task 3.10.
- **Files to inspect**: `OrangeNote/OrangeNote.entitlements`, `project.yml`.
- **Files likely to modify**: `OrangeNote/OrangeNote.entitlements`, `project.yml`.
- **Files likely to add**: `OrangeNote/Helpers/SecurityScopeHelper.swift`, `OrangeNoteTests/SecurityScopeHelperTests.swift`.
- **Implementation details**: Replace `com.apple.security.files.user-selected.read-only` with `com.apple.security.files.user-selected.read-write` in `OrangeNote.entitlements`. Keep `com.apple.security.network.client`. Implement `SecurityScopeHelper` to wrap batch execution within `startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()`.
- **Tests / validation**: Unit tests validating security scope lifecycle management during operation blocks.
- **Acceptance criteria**: Read-write entitlement configured; security scope active during batch operation and released on completion.
- **Do not change**: Network client entitlement or code signing configuration.

### Task 3.12: Output directory policy — COMPLETE / VERIFIED
- **Goal**: Implement output directory policy where a source folder may be proposed as output ONLY when a single folder was explicitly selected with folder grant; multi-file / mixed directory selections require choosing an explicit output directory.
- **Dependencies**: Task 3.11.
- **Files to inspect**: `OrangeNote/Services/BatchOutputPlanner.swift`.
- **Files likely to modify**: `OrangeNote/Services/BatchOutputPlanner.swift`.
- **Files likely to add**: `OrangeNote/Models/BatchOutputPolicy.swift`, `OrangeNoteTests/BatchOutputPolicyTests.swift`.
- **Implementation details**: Remove simplistic `.sameAsSource` default. For single explicitly-selected folder with security grant, allow proposing that folder. For individual files or mixed locations, require an explicit user-selected destination directory.
- **Tests / validation**: Unit tests planning outputs under single-folder grant vs multi-file explicit directory scenarios.
- **Acceptance criteria**: Output paths validated against active security grants; prevents assuming file parent directories are writable.
- **Do not change**: Output file naming convention (`<audio-basename>.json`).

### Task 3.13: Pickers
- **Goal**: Build SwiftUI picker helpers for selecting multiple files, folders, and output destination directories using `NSOpenPanel`.
- **Dependencies**: Task 3.12.
- **Files to inspect**: `OrangeNote/Helpers/`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/Helpers/DocumentPickerHelper.swift`.
- **Implementation details**: Implement helper methods `openMultipleAudioFiles()`, `openFolder()`, and `openOutputDirectory()` using `NSOpenPanel` with appropriate `canChooseDirectories`, `allowsMultipleSelection`, and `allowedContentTypes` based on `AudioTypeCatalog`.
- **Tests / validation**: Manual verification of file and folder selection panels on macOS.
- **Acceptance criteria**: Open panels allow multi-file, single folder, and destination directory selection.
- **Do not change**: Single-file picker in `TranscriptionViewModel`.

### Task 3.14: Batch DnD (COMPLETE / VERIFIED)
- **Goal**: Evolve the page-level drag-and-drop handler to support multi-file and folder drops: dropping a single file preserves single-file replacement, while dropping multiple files or a folder creates a batch draft; drops while batch is running are rejected (D010).
- **Dependencies**: Tasks 3.13, 1.5, 3.4.
- **Files to inspect**: `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to modify**: `OrangeNote/Helpers/DropItemResolver.swift`, `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to add**: `OrangeNoteTests/BatchDropItemResolverTests.swift`.
- **Implementation details**: Update `DropItemResolver` to handle 1 vs N items. If 1 audio file dropped, treat as single-file replacement. If multiple audio files or a folder dropped, extract audio files via `BatchFileCollector` and prepare batch draft. If a batch is actively running, reject drops.
- **Tests / validation**: Unit tests resolving single file drop, multi-file drop, and folder drop providers.
- **Acceptance criteria**: Drop resolver seamlessly distinguishes single vs multi-item/folder drops.
- **Do not change**: Dedicated tab structure (keeps unified Transcribe screen).

### Task 3.15: View-model orchestration
- **Goal**: Implement `BatchTranscriptionViewModel` (or integrate into transcription view model) using `ObservableObject` / `@Published` coordinating batch queue, output directory selection, sequential execution, progress metrics, and cancellation.
- **Dependencies**: Tasks 3.8–3.14.
- **Files to inspect**: `OrangeNote/ViewModels/TranscriptionViewModel.swift`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNote/ViewModels/BatchTranscriptionViewModel.swift`, `OrangeNoteTests/BatchTranscriptionViewModelTests.swift`.
- **Implementation details**: Define `BatchTranscriptionViewModel: ObservableObject` with `@Published var items: [BatchItem]`, `@Published var isRunning: Bool`, `@Published var activeIndex: Int?`, `@Published var outputDirectory: URL?`, `@Published var overallProgress: Float`. Coordinate `BatchFileCollector`, `BatchOutputPlanner`, and `BatchTranscriptionCoordinator`.
- **Tests / validation**: Unit tests covering queue lifecycle, item addition, destination setting, start, progress updates, and cancellation.
- **Acceptance criteria**: Observable view model driving batch UI state with clean separation.
- **Do not change**: Single-file `TranscriptionViewModel` public interface.

### Task 3.16: UI (COMPLETE / VERIFIED)
- **Goal**: Integrate batch transcription UI consistently on the existing Transcribe screen (reusing `TranscriptionView` patterns rather than creating a speculative separate tab), providing queue table, item progress rows, output folder selector, and start/cancel controls.
- **Dependencies**: Task 3.15.
- **Files to inspect**: `OrangeNote/Views/TranscriptionView.swift`, `OrangeNote/Views/ContentView.swift`.
- **Files likely to modify**: `OrangeNote/Views/TranscriptionView.swift`.
- **Files likely to add**: `OrangeNote/Views/Components/BatchQueueSection.swift`, `OrangeNote/Views/Components/BatchItemRow.swift`.
- **Implementation details**: Add batch mode section / toggle on `TranscriptionView`. When multiple files/folder are loaded, show `BatchQueueSection` with item list, status badges, destination folder picker, start button, and stop button.
- **Tests / validation**: SwiftUI preview verification and manual UI test on macOS.
- **Acceptance criteria**: Transcribe screen smoothly handles single-file and batch modes with native macOS styling.
- **Do not change**: Navigation sidebar items in `ContentView.swift` (transcribe, results, models, settings).

### Task 3.17: Results routing (COMPLETE / VERIFIED)
- **Goal**: Allow clicking a completed `BatchItem` in the batch queue to load its transcript into `AppState.currentTranscriptionResult` and switch to the Results tab (D028).
- **Dependencies**: Task 3.16.
- **Files to inspect**: `OrangeNote/Views/ResultsView.swift`, `OrangeNote/Models/AppState.swift`.
- **Files likely to modify**: `OrangeNote/Views/Components/BatchItemRow.swift`, `OrangeNote/Models/AppState.swift`.
- **Files likely to add**: None.
- **Implementation details**: Add tap action on completed `BatchItemRow` to set `appState.currentTranscriptionResult = item.result` and request navigation to `.results` tab.
- **Tests / validation**: Unit test verifying `AppState` updates and tab switch on item selection.
- **Acceptance criteria**: User can click any completed batch item to inspect its full transcript in Results view.
- **Do not change**: In-memory nature of `AppState`.

### Task 3.18: Integration suite (COMPLETE / VERIFIED)
- **Goal**: Comprehensive end-to-end integration test suite validating the complete batch processing pipeline with mock engines.
- **Dependencies**: Tasks 3.1–3.17.
- **Files to inspect**: `OrangeNoteTests/`.
- **Files likely to modify**: None.
- **Files likely to add**: `OrangeNoteTests/BatchIntegrationPipelineTests.swift`.
- **Implementation details**: Test full pipeline: folder ingestion -> normalization/dedup -> path planning -> sequential execution -> error isolation -> atomic writing -> results routing.
- **Tests / validation**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchIntegrationPipelineTests`.
- **Acceptance criteria**: 100% pass rate on full batch pipeline integration suite.
- **Do not change**: Production code.

### Task 3.19: Signed sandbox/regression gate (COMPLETE / VERIFIED)
- **Goal**: Comprehensive Phase 3 quality gate: full localization verification (EN, RU, FR), sandbox entitlement verification, signed build check, and regression test pass.
- **Dependencies**: Tasks 3.1–3.18.
- **Files to inspect**: `OrangeNote/Resources/*.lproj/Localizable.strings`, `OrangeNote/OrangeNote.entitlements`, `Makefile`, `scripts/regression-gate.sh`.
- **Files likely to modify**: `OrangeNote/Resources/*.lproj/Localizable.strings`, `Makefile`.
- **Files likely to add**: `scripts/regression-gate.sh`.
- **Implementation details**: Ensure all batch UI strings, error messages, and tooltips are localized across `en`, `ru`, `fr`. Verify project compiles and passes all unit and integration tests under macOS sandbox. Provide automated `make gate` and `scripts/regression-gate.sh` targets.
- **Tests / validation**: `make gate` / `./scripts/regression-gate.sh` running `cargo test --workspace`, `xcodegen generate`, `xcodebuild test`, `xcodebuild build`, and `codesign --verify --deep --strict --verbose=2`.
- **Acceptance criteria**: Zero test failures (407/407 Swift, 42/42 Rust), zero missing localization keys (240/240 EN/RU/FR), valid sandboxed codesign signature and entitlements verified.
- **Do not change**: Bundle identifier, team, provisioning profile, or introduce Developer ID / notarization steps that require credentials.

---

## Execution Chunks (A–R)

### Chunk A (Tasks 1.1, 1.2)
- **Scope**: Swift unit-test infrastructure + centralized single-file validation & audio audit.
- **Expected Repo State**: `OrangeNoteTests` target configured in `project.yml`; `AudioFileValidator` and validator tests added under `OrangeNoteTests/`.
- **Commands / Tests**: `xcodegen generate; xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Review before next chunk**: Test target compiles and executes with 0 failures before proceeding to Chunk B.
- **Recommended commit message**: `test(infra): configure xcodegen test target and add single-file validator`

### Chunk B (Tasks 1.3, 1.4)
- **Scope**: Minimal conceptual lifecycle + stale async completion jobID guard.
- **Expected Repo State**: `TranscriptionViewModel` standardized on 5 conceptual states; `activeJobID` UUID verification guards added.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionViewModelLifecycleTests,OrangeNoteTests/TranscriptionJobConcurrencyTests`.
- **Review before next chunk**: Lifecycle transitions and stale completion rejection verified by unit tests.
- **Recommended commit message**: `fix(transcription): harden viewmodel lifecycle and stale async completion handling`

### Chunk C (Tasks 1.5, 1.6)
- **Scope**: Single-item drop resolver / multi reject + page-level DnD overlay.
- **Expected Repo State**: `DropItemResolver` extracts single audio files and rejects multi-drops; page-level drop target attached to `TranscriptionView`.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/DropItemResolverTests`.
- **Review before next chunk**: Drop target never disappears after file selection; multi-drops rejected cleanly.
- **Recommended commit message**: `feat(ui): add persistent page-level drag and drop overlay and single item validation`

### Chunk D (Task 1.7)
- **Scope**: Phase 1 Localization and regression gate.
- **Expected Repo State**: `en`, `ru`, `fr` strings updated; all Phase 1 tests passing.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Review before next chunk**: 100% test pass across full test target; zero missing localization keys.
- **Recommended commit message**: `chore(i18n): update localizations and verify phase 1 regression gate`

### Chunk D-R (Tasks 1.8, 1.9, 1.10, 1.11)
- **Scope**: Phase 1 Remediation Gate — provider cardinality & thread safety, native-busy guards, deterministic lifecycle projections, and full verification gate.
- **Expected Repo State**: Drop provider data race eliminated; pre-extraction cardinality check; UTType.fileURL fallback; native-busy guard preventing concurrent FFI runs; private(set) projections with dismissError intent; deterministic failure reset; full test suite and manual verification passing.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; manual DnD matrix and verified-model transcription smoke completed and reviewed. Phase 2 remains blocked until review passes.
- **Recommended commit message**: `fix(transcription): resolve phase 1 quality audit findings and verify remediation gate`

### Chunk D-R3 (Tasks 1.12, 1.13, 1.14, 1.15, 1.16)
- **Scope**: Phase 1 Remediation Final Corrections — import lifecycle/busy safety & URL representation, pre-FFI cancellation & execution identity guards, drop completion normalization & commit recheck, lifecycle mutation bypass closure (`selectedFileURL` private(set) and `clearResult` busy guard), and final quality review gate.
- **Expected Repo State**: Import guarded against busy bypass and represented without fake source URL; pre-FFI cancellation checked before engine entry; identity-bound native cleanup; normalized drop completion; `selectedFileURL` private(set); `clearResult` busy-guarded; full test suites passing; code review approval.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; manual DnD evidence accepted; working-model transcription smoke verified; formal code review approval. Phase 2 unlocks only after code review.
- **Recommended commit message**: `fix(transcription): close remaining lifecycle mutation bypasses and verify phase 1 remediation gate`

### Chunk E (Tasks 2.1, 2.2)
- **Scope**: Canonical DTO + Document Serializer & Mapper.
- **Expected Repo State**: `CanonicalTranscriptionDocument` v1 and `CanonicalTranscriptionSerializer` implemented with roundtrip tests.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/CanonicalTranscriptionSerializerTests`.
- **Review before next chunk**: Strict adherence to Canonical JSON v1 schema and 100% serialization fidelity.
- **Recommended commit message**: `feat(schema): introduce canonical v1 transcription document and serializer`

### Chunk F (Tasks 2.3, 2.4)
- **Scope**: Version-aware import + Unversioned legacy fallback.
- **Expected Repo State**: `TranscriptionImportService` decodes Canonical v1 and falls back to legacy formats only when unversioned.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/TranscriptionImportServiceTests,OrangeNoteTests/LegacyImportTests`.
- **Review before next chunk**: Backward compatibility verified without data loss; future version numbers rejected without fallback.
- **Recommended commit message**: `feat(import): support canonical v1 schema with unversioned legacy fallback`

### Chunk G (Tasks 2.5, 2.6)
- **Scope**: Switch JSON export to Canonical v1 + Compatibility test suite.
- **Expected Repo State**: Single-file export writes Canonical v1 JSON; compatibility test suite passing.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/ExportViewModelCanonicalTests,OrangeNoteTests/TranscriptionCompatibilityTests`.
- **Review before next chunk**: All JSON exports produce Canonical v1; compatibility suite passes.
- **Recommended commit message**: `feat(export): switch json export to canonical v1 schema and add compatibility suite`

### Chunk H (Tasks 2.7, 2.8)
- **Scope**: Minimal request/protocol + Whisper engine adapter.
- **Expected Repo State**: `TranscriptionEngineProtocol` and `TranscriptionRequest` defined; `WhisperTranscriptionEngine` wraps instantiated engine.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/WhisperTranscriptionEngineTests`.
- **Review before next chunk**: Swift layer decoupled from concrete Rust FFI calls.
- **Recommended commit message**: `refactor(engine): introduce transcription engine protocol and whisper adapter`

### Chunk I (Tasks 2.9, 2.10)
- **Scope**: Engine injection in ViewModel + Phase 2 Integration gate.
- **Expected Repo State**: `TranscriptionViewModel` accepts injected engine protocol; full test pass.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Review before next chunk**: 100% passing tests for Phase 1 & 2.
- **Recommended commit message**: `refactor(viewmodel): inject transcription engine dependency and verify phase 2 gate`

### Chunk I-R (Tasks 2.11, 2.12, 2.13, 2.14, 2.15) — Phase 2 Remediation Gate
- **Scope**: Engine semantic contract & concurrency-safe test doubles + WhisperEngineClient seam & adapter orchestration tests + Execution provenance & honest canonical export metadata wiring + Numeric validation hardening & legacy duration max + Phase 2 Intermediate Gate.
- **Expected Repo State**: `TranscriptionEngineProtocol` contract documented and tested; `WhisperEngineClient` seam implemented and 100% unit tested; provenance captured and wired to export; serializer protected against non-finite values; legacy import calculates max endTime; intermediate regression suite passing.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; proceed to Chunk I-R2 for final corrections.
- **Recommended commit message**: `fix(engine): implement initial phase 2 remediation tasks and contract test doubles`

### Chunk I-R2 (Tasks 2.16, 2.17, 2.18, 2.19) — Phase 2 Remediation Final Corrections
- **Scope**: Atomic DisplayedTranscription + import metadata preservation & honest unknown export + Engine identity protocol & snapshot + Strengthen drain/concurrency contract tests & legacy view/replacement coverage + Phase 2 Final Gate & manual verification.
- **Expected Repo State**: `DisplayedTranscription` pairing result and provenance atomically updated without UI/export race; canonical import preserves safe document metadata; honest unknown metadata on legacy/unknown export; `TranscriptionEngineProtocol` exposes engine identity dynamically captured without registry; contract tests verify non-cancellation-sensitive drain and thread-safe progress recording; full test suites and 4-scenario manual verification passed.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; 4 manual verification scenarios confirmed by human; formal review approves Phase 2 closure and unblocks Phase 3.
- **Recommended commit message**: `fix(transcription): resolve phase 2 remediation audit findings and verify final gate`

### Chunk I-R3 (Tasks 2.20, 2.21, 2.22) — Phase 2 Final Closure Corrections
- **Scope**: Atomic displayed/job provenance ownership + ResultsView wiring + sourceFileName/URL model correction + Complete adapter drain/error/cancellation matrix & representative lifecycle/import UX tests + Phase 2 final review and test gate.
- **Expected Repo State**: `ResultsView` wired to single `DisplayedTranscription` snapshot; job-owned provenance in `TranscriptionViewModel`; `ExecutionProvenance` separates `sourceFileName` from optional `sourceURL`; adapter drain matrix complete for cancellation and error paths; production-representative replacement tests; import error localized UI feedback; full automated test suites passing.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; impacted canonical import/export verification confirmed if required; formal review approves Phase 2 closure and unblocks Phase 3.
- **Recommended commit message**: `fix(transcription): resolve phase 2 final closure code findings and verify quality gate`

### Chunk I-R4 (Tasks 2.23, 2.24, 2.25, 2.26, 2.27, 2.28, 2.29) — Phase 2 Closure Gate
- **Scope**: Fix job-owned provenance terminal transfer + Make document import errors globally visible + Phase 2 intermediate review + Route busy import rejection through global error presenter + Phase 2 intermediate review & regression review + Restore intended app version metadata + Final Phase 2 closure gate, regression review & manual verification.
- **Expected Repo State**: Job ownership validated at completion; `runningJobID` and running provenance cleared after terminal state; document import parse and busy rejection errors globally visible from all tabs without alert duplication or state mutation; version metadata cleanly restored to 0.1.6; full automated test suites passing; manual canonical export/import repeat and non-Transcribe tab busy import verified; Phase 2 closed.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination platform=macOS; cargo test --workspace`.
- **Review before next chunk**: 100% test pass across Swift and Rust; version metadata 0.1.6 verified; manual verification confirmed; formal review approves Phase 2 closure and authorizes Phase 3 (Task 3.1). No further speculative remediation added absent blocker regressions.
- **Recommended commit message**: `fix(transcription): resolve phase 2 closure defects, restore version metadata, and verify final gate`

### Chunk J (Tasks 3.1, 3.2, 3.3)
- **Scope**: Audio type catalog + BatchItem model + File collector.
- **Expected Repo State**: `AudioTypeCatalog`, `BatchItem`, and `BatchFileCollector` implemented.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/AudioTypeCatalogTests,OrangeNoteTests/BatchItemTests,OrangeNoteTests/BatchFileCollectorTests`.
- **Review before next chunk**: Accurate filtering of audio vs non-audio files.
- **Recommended commit message**: `feat(batch): add audio type catalog, batch item model, and file collector`

### Chunk K (Tasks 3.4, 3.5)
- **Scope**: Top-level folder collector + Normalize, deduplicate, full-path sort.
- **Expected Repo State**: Top-level folder ingestion (non-recursive) and full-path sorting/deduplication implemented.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchFolderCollectorTests,OrangeNoteTests/BatchQueueNormalizationTests`.
- **Review before next chunk**: Subdirectories ignored; items deduplicated and sorted by normalized full path.
- **Recommended commit message**: `feat(batch): add top-level folder collector with full-path normalization and sorting`

### Chunk L (Tasks 3.6, 3.7)
- **Scope**: Output planner `<basename>.json` & skip + Atomic non-overwriting writer.
- **Expected Repo State**: `BatchOutputPlanner` and `AtomicFileWriter` implemented.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchOutputPlannerTests,OrangeNoteTests/AtomicFileWriterTests`.
- **Review before next chunk**: Output matches `<basename>.json`; existing files skipped without overwriting.
- **Recommended commit message**: `feat(batch): add batch output planner and atomic non-overwriting file writer`

### Chunk M (Tasks 3.8, 3.9, 3.10)
- **Scope**: Sequential coordinator + Continue on failure + Stop-after-current cancellation.
- **Expected Repo State**: `BatchTranscriptionCoordinator` executing queue sequentially with failure isolation and cancellation.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchTranscriptionCoordinatorTests,OrangeNoteTests/BatchErrorContinuationTests,OrangeNoteTests/BatchCancellationTests`.
- **Review before next chunk**: Failures do not halt queue; cancellation finishes active item and retains all written files.
- **Recommended commit message**: `feat(batch): implement sequential coordinator with error isolation and stop-after-current cancellation`

### Chunk N (Tasks 3.11, 3.12)
- **Scope**: Read-write entitlement/security scope + Output directory policy.
- **Expected Repo State**: `OrangeNote.entitlements` updated to read-write; `SecurityScopeHelper` and `BatchOutputPolicy` integrated.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/SecurityScopeHelperTests,OrangeNoteTests/BatchOutputPolicyTests`.
- **Review before next chunk**: Sandboxed write permissions and security scoping validated.
- **Recommended commit message**: `feat(batch): configure read-write entitlement and security-scoped output policy`

### Chunk O (Tasks 3.13, 3.14)
- **Scope**: Pickers + Batch DnD evolution.
- **Expected Repo State**: Document picker helpers and multi-item/folder drag-and-drop resolution integrated into Transcribe view.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchDropItemResolverTests`.
- **Review before next chunk**: Dragging single file, multiple files, or folder handled correctly; running batch rejects drops.
- **Recommended commit message**: `feat(batch): add document pickers and multi-item/folder drag and drop resolution`

### Chunk P (Tasks 3.15, 3.16)
- **Scope**: ViewModel orchestration + Transcribe view batch UI integration.
- **Expected Repo State**: `BatchTranscriptionViewModel`, `BatchQueueSection`, and `BatchItemRow` integrated into `TranscriptionView`.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS' -only-testing:OrangeNoteTests/BatchTranscriptionViewModelTests`.
- **Review before next chunk**: Unified Transcribe screen displays responsive batch controls and queue table.
- **Recommended commit message**: `feat(batch): implement batch viewmodel and integrate batch queue ui into transcribe screen`

### Chunk Q (Task 3.17)
- **Scope**: Results routing via AppState.
- **Expected Repo State**: Clicking completed batch item routes transcript to `ResultsView` via `AppState.currentTranscriptionResult`.
- **Commands / Tests**: Unit tests asserting `AppState` mutation and navigation trigger.
- **Review before next chunk**: Seamless transcript inspection for completed batch items.
- **Recommended commit message**: `feat(batch): add transcript inspection routing from batch item to results`

### Chunk R (Tasks 3.18, 3.19)
- **Scope**: Batch integration suite + Signed sandbox & regression gate.
- **Expected Repo State**: Complete end-to-end integration test suite; full EN/RU/FR localizations; signed sandbox verification.
- **Commands / Tests**: `xcodebuild test -project OrangeNote.xcodeproj -scheme OrangeNote -destination 'platform=macOS'`.
- **Review before next chunk**: 100% pass across all unit and integration tests; zero missing localization strings; clean build.
- **Recommended commit message**: `test(batch): add end-to-end integration suite and verify phase 3 regression gate`

---

## FUTURE PHASES (HIGH-LEVEL OUTLINE)

### Phase 4: Cloud Engine Capability Spike (UNDECIDED)
- **Scope**: Empirical investigation and comparative benchmarking between specialized Gemini Transcribe vs Flash multimodal (`generateContent`) audio capabilities.
- **Status**: API endpoint and model selection remain strictly UNDECIDED (D008) until spike completion.
- **Deliverables**: Benchmark evaluation comparing timestamp accuracy, audio duration limits, pricing, and latency.

### Phase 5: BYOK Cloud Transcription Integration
- **Scope**: Implement `GeminiTranscriptionEngine` conforming to `TranscriptionEngineProtocol` using pure Swift networking (D005).
- **Security**: macOS Keychain storage for user API keys (D006, D007).
- **Error Handling**: Explicit user error reporting without automatic retries (D026).
- **Engine Selection**: Direct Whisper vs Gemini engine selection in UI without over-engineered registry (D027).

### Phase 6: Production Hardening & Quality Audit
- **Scope**:
  - Signed sandbox audit and verification.
  - End-to-end single and batch test execution across Whisper and Gemini.
  - Security audit: ensure zero secret leakage and sanitize logs.
  - API revalidation and quota handling.
  - Large audio file upload cleanup and temporary resource reclamation.
  - Localization audit across all supported languages.
  - Import/export regression testing.
  - Separate future research for model context caching (D024) and native FFI interrupt handlers (D025).

---

## RISK MANAGEMENT & MITIGATIONS

1. **App Sandbox File Access & Output Permissions**:
   - *Risk*: Sandboxed app cannot write output JSON files to arbitrary disk locations.
   - *Mitigation*: Update entitlement to `com.apple.security.files.user-selected.read-write` (D023). User-selected destination folders are accessed via `NSOpenPanel` and wrapped in `startAccessingSecurityScopedResource()`.
2. **Blocking FFI vs UI Responsiveness**:
   - *Risk*: Blocking Whisper FFI calls freezing the SwiftUI main runloop.
   - *Mitigation*: Existing `OrangeNoteEngine` dispatches blocking FFI off the main actor/queue, and implementation tasks must preserve UI responsiveness without changing FFI.
3. **Data Loss on Cancellation or Collisions**:
   - *Risk*: Cancelling batch deletes files or overwrites existing transcripts.
   - *Mitigation*: Output files are written atomically (`AtomicFileWriter`) with non-overwriting semantics (D018); completed files survive cancellation (D022).
4. **Scope Creep & Tasks Combination**:
   - *Rule*: Never combine atomic tasks or chunks without explicit user approval. Complete, validate, and document each unit of work before updating handoff.
