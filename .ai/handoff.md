# Session Handoff

- **Status**: **PHASE 3 COMPLETE AND REMEDIATED**. Release `release/v0.2.0` prepared, validated, committed, pushed, and Pull Request created awaiting **USER MANUAL MERGE** in GitHub UI.
- **Current Phase**: Release v0.2.0 (Phase 1: COMPLETE; Phase 2: COMPLETE / CLOSED; Phase 3: COMPLETE / CLOSED; Phase 4: NOT STARTED / NOT AUTHORIZED).
- **Active Release Branch**: `release/v0.2.0`
- **Release PR**: Open on GitHub against base `main`.
- **Git Tag Status**: **TAG NOT CREATED**. Tag creation must NOT happen until after manual PR merge into `main`.
- **Next Required User Action**:
  1. Manually review and merge the PR into `main` in the GitHub UI.
  2. After merge, checkout and pull `main` locally (`git checkout main && git pull origin main`).
  3. Inspect exact merge commit on `main`.
  4. Create and push annotated tag `v0.2.0` (`git tag -a v0.2.0 -m "Release v0.2.0" && git push origin v0.2.0`) to trigger the GitHub release CI workflow.
- **Phase 4 Status**: **NOT STARTED / NOT AUTHORIZED** — future scope, do not start without explicit user authorization.

---

## Release v0.2.0 Summary

- **Version Bump**: `CFBundleShortVersionString` bumped from `0.1.6` to `0.2.0` in `project.yml` (source of truth) and synchronized in `OrangeNote/Info.plist` via `xcodegen generate`.
- **Release Contents**:
  - Phase 1: Robust single-file Drag & Drop lifecycle, `AudioFileValidator`, `DropItemResolver`, stale async completion `jobID` guards, `isNativeBusy` execution guards, projection encapsulation.
  - Phase 2: Canonical JSON v1 schema (`CanonicalTranscriptionDocument`), `CanonicalTranscriptionSerializer`, version-aware import & legacy fallback, `TranscriptionEngineProtocol` Swift abstraction, `WhisperTranscriptionEngine` adapter, `DisplayedTranscription` and `ExecutionProvenance` domain models.
  - Phase 3: Sequential batch transcription pipeline (`BatchTranscriptionCoordinator`), top-level folder and multi-file ingestion, natural path sorting, output directory policies & non-overwriting atomic persistence (`AtomicFileWriter` with `renamex_np`), App Sandbox user-selected read-write security scopes (`SecurityScopeHelper`), Batch UI on Transcribe tab, centralized results routing via `AppState`, dynamic runtime language bundle resolution (`L10n` / `LocalizedText`) & `AppleLanguages` UserDefaults synchronization, complete 420-test automated suite, and `./scripts/regression-gate.sh` regression gate.
- **Validation**: Full regression gate (`./scripts/regression-gate.sh`) passed 100% (42/42 Rust tests, 420/420 Swift tests, xcodegen generation, version consistency, macOS app build, codesign, sandbox entitlements).
