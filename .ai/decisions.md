# Technical Decisions (D001–D028)

## D001: Native macOS SwiftUI + Rust FFI Architecture
- **Status**: Accepted
- **Decision**: Keep the native macOS architecture using SwiftUI for the user interface and Rust via C FFI (`orangenote-ffi`) for computation. Reject web-based shells such as Tauri or Electron.
- **Rationale**: Delivers native macOS performance, low memory footprint, first-class Metal acceleration, and responsive desktop UI.
- **Consequences**: UI components are written in Swift; bridging is maintained via C headers.

## D002: Preserve Rust Whisper Pipeline for Phases 1–3
- **Status**: Accepted
- **Decision**: Retain the existing Rust audio decoding (`symphonia`) and `whisper.cpp` inference pipeline without modifying Rust code during Phases 1–3. Future Phase 4/5/6 remain unaffected by this restriction.
- **Rationale**: The Rust pipeline is already operational and achieves high performance with Metal acceleration. Isolating changes to Swift avoids cross-language regression risks during frontend and batch feature delivery.
- **Consequences**: Rust codebase remains stable and unmodified across Phases 1–3.

## D003: Whisper as Default Engine
- **Status**: Accepted
- **Decision**: Make local offline Whisper the primary and default transcription engine for all transcription flows.
- **Rationale**: Prioritizes privacy, offline capability, zero external cost, and reliable baseline operation.
- **Consequences**: Cloud transcription options remain opt-in additions.

## D004: Swift Abstraction Layer for Transcription Engines
- **Status**: Accepted
- **Decision**: Introduce a clean Swift protocol (`TranscriptionEngineProtocol`) in the Swift layer without modifying the Rust C FFI ABI.
- **Rationale**: Allows adding alternative transcription providers (e.g., Gemini) or mocking engines for unit testing without altering Rust code.
- **Consequences**: `OrangeNoteEngine` is wrapped by an adapter conforming to `TranscriptionEngineProtocol`.

## D005: Gemini Cloud Engine via Pure Swift
- **Status**: Accepted
- **Decision**: Implement the Gemini cloud transcription engine entirely in Swift (using `URLSession` / standard networking) rather than adding HTTP clients into Rust.
- **Rationale**: Simplifies dependency management, eliminates Rust network dependencies, and keeps the Rust static library minimal.
- **Consequences**: Cloud network requests, payload serialization, and API authentication reside solely in the Swift layer.

## D006: BYOK (Bring Your Own Key) Model
- **Status**: Accepted
- **Decision**: Use a Bring Your Own Key (BYOK) model for all cloud AI integrations. Do not bundle shared backend credentials or proxy servers.
- **Rationale**: Eliminates backend hosting costs, simplifies legal compliance, and ensures user privacy and billing transparency.
- **Consequences**: Users configure their personal API keys in Settings.

## D007: macOS Keychain for API Key Storage
- **Status**: Accepted
- **Decision**: Store user-provided API keys in the macOS Keychain (`Security.framework`), never in `UserDefaults` or plaintext files.
- **Rationale**: Adheres to macOS security standards and protects secrets within a sandboxed environment.
- **Consequences**: Requires a lightweight Swift Keychain helper for saving, reading, and clearing credentials.

## D008: Defer Exact Cloud API & Model Selection to Phase 4 Spike
- **Status**: Accepted
- **Decision**: Keep the exact Gemini API endpoint (specialized Gemini Transcribe vs Flash multimodal `generateContent`) and model identifier marked as UNDECIDED until the Phase 4 capability spike.
- **Rationale**: Audio duration limits, timestamp granularity, pricing, and API capabilities differ significantly between specialized audio transcription and multimodal models; spike empirical data will determine the best choice.
- **Consequences**: Phase 1–3 development is strictly isolated from cloud API specifics.

## D009: Drag-and-Drop Fix Prioritized Before Batch Processing
- **Status**: Accepted
- **Decision**: Resolve single-file drag-and-drop lifecycle issues (persistent page drop overlay, drop validation, and state cleanup) in Phase 1 before building Phase 3 Batch Processing.
- **Rationale**: Fixes an immediate user-facing UX bug and establishes reusable file-drop utilities for subsequent batch ingestion.
- **Consequences**: Phase 1 focuses entirely on drop stability and single-file lifecycle robustness.

## D010: Reject Drag-and-Drop Ingestion While Transcribing
- **Status**: Accepted
- **Decision**: Explicitly reject or ignore drag-and-drop operations while a transcription job is actively running (`isTranscribing == true`).
- **Rationale**: Prevents race conditions, corrupted state, and unintended job preemption.
- **Consequences**: Drop handlers ignore incoming drops during active transcription and provide appropriate user feedback.

## D011: Swift Task Cancellation Boundary
- **Status**: Accepted
- **Decision**: Acknowledge that Swift `Task.cancel()` cancels Swift-side awaiting and UI updates, but does NOT stop an in-flight blocking Rust C FFI execution.
- **Rationale**: Modifying Rust threading and whisper.cpp interrupt handlers introduces cross-language safety risks and is deferred to Phase 6.
- **Consequences**: Background FFI continues until the current file completes. Because late completion can otherwise mutate state, Swift-side `jobID` verification guards are required to discard stale results.

## D012: Canonical JSON Schema Before Batch Processing
- **Status**: Accepted
- **Decision**: Standardize and implement a versioned canonical JSON schema (`CanonicalTranscriptionDocument` v1) in Phase 2 before implementing Phase 3 Batch export/import.
- **Rationale**: Eliminates format mismatches between Rust FFI structs, Swift Codable models, and exported files before batch writes multiple files.
- **Consequences**: Guarantees deterministic serialization across single-file and batch workflows.

## D013: New Exports Use Canonical v1 Schema
- **Status**: Accepted
- **Decision**: All newly generated JSON exports must strictly adhere to the Canonical JSON v1 schema including metadata (audio file name, duration, language, timestamps).
- **Rationale**: Ensures interoperability, future schema migration paths, and schema validation.
- **Consequences**: Legacy ad-hoc JSON format is deprecated for export.

## D014: Backwards-Compatible Legacy Schema Import Support
- **Status**: Accepted
- **Decision**: The import service (`TranscriptionImportService`) attempts decoding Canonical JSON v1 first. Fallback to legacy decoders occurs ONLY when `schemaVersion` is absent (unversioned); unknown or newer `schemaVersion` values must fail without fallback.
- **Rationale**: Prevents breaking existing user transcripts saved with earlier application versions while preventing corrupt decoding of future versioned schemas.
- **Consequences**: Decoding logic checks version presence before deciding whether legacy fallback is permitted.

## D015: Sequential Batch Processing
- **Status**: Accepted
- **Decision**: Batch queue execution must process audio files strictly sequentially (one at a time), not concurrently in parallel threads.
- **Rationale**: Local Whisper inference utilizes Metal GPU acceleration; running parallel inferences creates resource contention, excessive memory consumption, and thermal throttling.
- **Consequences**: Predictable progress reporting, lower memory footprint, and reliable completion times.

## D016: Continue Batch on Individual File Failure
- **Status**: Accepted
- **Decision**: If a single audio file fails during batch transcription, record its failure status and error message, and immediately continue processing the remaining queue items.
- **Rationale**: A corrupted or unsupported audio file must not abort an entire multi-hour batch job.
- **Consequences**: Batch completion summary reports both successful and failed files.

## D017: Exact Output File Naming `<audio-basename>.json`
- **Status**: Accepted
- **Decision**: Batch transcription results are written to `<outputDirectory>/<audio-basename>.json`, matching the exact base name of the input audio file without inventing extra sanitization rules.
- **Rationale**: Provides predictable, deterministic output file locations that users and automated tools can easily associate with source media.
- **Consequences**: Output filenames strictly mirror the input file base name with a `.json` extension.

## D018: Skip Existing Output Files Without Overwriting
- **Status**: Accepted
- **Decision**: If `<outputDirectory>/<audio-basename>.json` already exists, skip processing that file and mark it as skipped without overwriting it.
- **Rationale**: Prevents accidental data loss of existing transcripts and avoids redundant computation.
- **Consequences**: Atomic non-overwriting write behavior skips existing files before or during execution.

## D019: In-Memory Queue for Batch Processing
- **Status**: Accepted
- **Decision**: Implement the batch queue as an in-memory observable state structure without an SQLite or CoreData database layer.
- **Rationale**: Meets all functional requirements for batch runs with minimal architectural complexity and zero migration overhead.
- **Consequences**: Batch queue does not persist across application restarts; completed output files persist on disk.

## D020: Top-Level Folder Ingestion
- **Status**: Accepted
- **Decision**: Dropping or selecting a folder for batch processing discovers audio files located directly in the top-level directory only (non-recursive).
- **Rationale**: Avoids unexpected ingestion of huge nested directory trees and matches user expectations for batch directories.
- **Consequences**: Subdirectories are ignored during audio file collection.

## D021: Stop-After-Current Cancellation Policy for Batch
- **Status**: Accepted
- **Decision**: When the user cancels an active batch job, the active item finishes its current transcription and atomic save, and no subsequent queue items are started.
- **Rationale**: Respects the blocking Rust FFI boundary (D011) while halting further batch progress predictably.
- **Consequences**: Remaining queued items are marked as cancelled; active item finishes cleanly.

## D022: Retain Successfully Written Batch Output Files on Cancellation
- **Status**: Accepted
- **Decision**: Any JSON transcript files successfully written to disk before batch cancellation must be retained and not deleted or rolled back.
- **Rationale**: Preserves completed computation and allows the user to benefit from partially completed batch runs.
- **Consequences**: Output files on disk remain valid and intact.

## D023: No Security-Scoped Bookmarks Persistence
- **Status**: Accepted
- **Decision**: Do not persist security-scoped URL bookmarks to disk across application restarts in Phase 3. Maintain security scopes in memory for the duration of the batch operation.
- **Rationale**: Avoids stale bookmark management and complexity without a persistent database.
- **Consequences**: Permissions are held in memory during the app lifecycle and requested via standard open panels as needed.

## D024: Defer Model Instance Reuse to Future Phase
- **Status**: Accepted
- **Decision**: Defer Rust Whisper model context caching and persistent in-memory instance reuse across batch items to a future optimization phase.
- **Rationale**: Keeps the Rust C FFI simple and avoids introducing unsafe global mutable state across the FFI boundary.
- **Consequences**: Each batch item initiates transcription via the standard FFI call.

## D025: Defer Native Cancellation to Future Phase
- **Status**: Accepted
- **Decision**: Defer adding C ABI interrupt handlers / atomic cancellation flags to `orangenote-ffi` and `whisper.cpp` to a future hardening phase.
- **Rationale**: Keeps the C ABI simple and avoids cross-language race conditions across the FFI boundary.
- **Consequences**: Swift-side job IDs and queue management enforce cancellation semantics.

## D026: No Automatic Retry for Gemini Cloud Engine
- **Status**: Accepted
- **Decision**: Do not implement complex exponential backoff or automatic retry loops for Gemini cloud transcription in initial implementations.
- **Rationale**: API errors (quota exceeded, invalid key, unsupported audio) are best surfaced directly to the user for immediate action.
- **Consequences**: Errors are reported clearly in the UI and batch error log.

## D027: Explicit Engine Selection Without Over-Engineered Registry
- **Status**: Accepted
- **Decision**: Keep engine selection explicit and direct in Swift rather than building an over-engineered dynamic plugin registry.
- **Rationale**: Avoids unnecessary abstraction layers when only two concrete engines (Whisper, Gemini) are planned.
- **Consequences**: Clean, direct engine construction and selection in Swift.

## D028: AppState In-Memory State, Not Persistent History
- **Status**: Accepted
- **Decision**: Maintain `AppState` as a lightweight in-memory observable model for the current user session, not a persistent historical database.
- **Rationale**: Fits the file-oriented workflow where transcription artifacts are stored as files on disk.
- **Consequences**: No database schema migrations or storage bloat.

## D029: Mixed Folder and Multi-Folder Drop Rejection Policy
- **Status**: Accepted
- **Decision**: Reject drag-and-drop payloads that contain mixed items (both folder(s) and file(s)) or multiple folders. A valid drop must either be a single folder or a collection consisting purely of files.
- **Rationale**: Single-folder drops establish a single directory security scope and output proposal (D020, Task 3.12), whereas file drops establish explicit individual item paths. Combining folders with files or multiple folders creates ambiguous scoping, output planning, and traversal semantics.
- **Consequences**: `DropItemResolver` rejects mixed folder+files and multi-folder drops with a clear localized error message (`.rejectedMixedItems`).

## D030: BatchTranscriptionViewModel Public API Surface & Dependency Protocol
- **Status**: Accepted
- **Decision**: Define `BatchTranscriptionViewModel` as a `@MainActor ObservableObject` with `private(set)` published state projections (`items`, `outputDirectory`, `outputResolutionSource`, `inputSource`, `isRunning`, `isCancelling`, `overallProgress`, `activeIndex`, `activeItemID`, `summary`, `errorMessage`, `statusMessage`) and command intents (`ingestFiles`, `ingestFolder`, `ingestResult`, `setOutputDirectory`, `start`, `cancel`, `clear`, `removeItem`, `removeItems`, `dismissError`), abstracting coordinator interactions behind `BatchTranscriptionCoordinatorProtocol`.
- **Rationale**: Follows the established ViewModel patterns in `TranscriptionViewModel` (Task 1.10, Task 1.15) for unidirectional state flow and deterministic unit testability via dependency injection without coupling views directly to actor internals.
- **Consequences**: SwiftUI views observe projections read-only and trigger operations via explicit intent methods; unit tests inject mock coordinators conforming to `BatchTranscriptionCoordinatorProtocol`.

## D031: Results Routing via AppState
- **Status**: Accepted
- **Decision**: Manage UI navigation and results inspection state centrally through `AppState`, binding sidebar tab selection (`selectedNavigationItem`) and active batch item selection (`selectedBatchItemID`) directly to `AppState`. When a completed `BatchItem` is selected, `AppState` populates `displayedTranscription` (pairing domain `TranscriptionResult` with honest `ExecutionProvenance`) and switches active tab to `.results`, maintaining complete isolation from single-file execution state and respecting D010/D028.
- **Rationale**: Eliminates fractured navigation state between `ContentView` local state and child components, enables deep-linking of batch items to results inspection, and allows menu commands (Save, Export) to seamlessly operate on both single-file and batch item transcripts without duplicating view logic.
- **Consequences**: `BatchItemRow` triggers selection callback for succeeded items; `ResultsView` renders `AppState.displayedTranscription`; single-file and batch modes preserve clean isolation.

## D032: Automated Regression Gate & Sandboxed Ad-Hoc Codesign Verification
- **Status**: Accepted
- **Decision**: Standardize automated regression gate verification via `make gate` / `./scripts/regression-gate.sh` that validates Rust tests, Xcode project generation, full Swift unit/integration test suite, macOS application compilation, ad-hoc codesigning, and sandbox entitlements (`com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.network.client`) locally without credential-dependent Developer ID or external notarization requirements.
- **Rationale**: Ensures deterministic CI and developer gate validation of sandboxed macOS capabilities and zero regressions across both Rust backend and Swift UI layers.
- **Consequences**: All future development phases must pass `make gate` before milestone closure.

## D033: Reactive AppSettings & Dynamic Environment Locale for Language Switching
- **Status**: Accepted
- **Decision**: Make `AppSettings` properties reactive using `@Published` with `didSet` persistence to `UserDefaults`, propagate `.environment(\.locale, localeFromSettings)` and view `.id(settings.appLanguage)` at the root, declare `CFBundleLocalizations: [en, ru, fr]` in project settings, and use `LocalizedStringKey` in views so in-app language switches update all UI components dynamically.
- **Rationale**: `@AppStorage` within `ObservableObject` does not trigger `objectWillChange` or view tree invalidation; static `String` localization bypasses SwiftUI environment locale updates; explicit bundle localizations ensure correct resource resolution in macOS application bundles.
- **Consequences**: Setting `appLanguage` triggers immediate reactive UI re-rendering across all screens without requiring application restart.

## D034: Default Non-Nil AppKit Document Picker Wiring
- **Status**: Accepted
- **Decision**: Default `DocumentPickerHelper` initializer `picker` parameter to `OpenPanelDocumentPicker()` under `#if canImport(AppKit)`, preserving protocol-based dependency injection for unit tests.
- **Rationale**: Resolves regression where default initialization resulted in a `nil` picker that silently no-oped user modal prompts (Add Files, Add Folder, Change Output).
- **Consequences**: Standard interactive batch UI controls function out-of-the-box on macOS while test suites can inject deterministic mock pickers without AppKit UI dependencies.

## D035: Dynamic Language Bundle Resolver & AppleLanguages Synchronization
- **Status**: Accepted
- **Decision**: Implement dynamic language bundle resolution via `L10n.string` / `LocalizedText` in place of macOS SwiftUI `LocalizedStringKey` / `Bundle.main` startup-locked localization, combined with reactive `AppSettings` and `AppleLanguages` UserDefaults synchronization (`[code]` for explicit `en`, `ru`, `fr`; key removal for `system`).
- **Rationale**: On macOS SwiftUI, `LocalizedStringKey` and `Bundle.main` resolve strings based on `AppleLanguages` fixed at process launch; `.environment(\.locale, ...)` modifies system formatting but does not switch app string resource lookups dynamically. Enhancing `L10n` to cache and query explicit `.lproj` bundles dynamically updates all visible strings immediately at runtime when `appLanguage` changes, while synchronizing `AppleLanguages` ensures persistence across process restarts without fragile Objective-C bundle swizzling.
- **Consequences**: All user-facing SwiftUI views use `L10n.string(...)` / `LocalizedText`; switching language in Settings updates the entire application UI instantly in the same session, and System mode respects OS preferred localizations.
