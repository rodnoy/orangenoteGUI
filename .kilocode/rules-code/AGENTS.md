# Project Coding Rules (Non-Obvious Only)
- Dynamic UI localization requires `L10n.string(...)` or `LocalizedText` from `OrangeNote/Helpers/LocalizationHelper.swift` instead of static `LocalizedStringKey`.
- User-selected file/folder access must be wrapped with `SecurityScopeHelper.withSecurityScope` to maintain sandbox permissions.
- All JSON document exports must serialize via `CanonicalTranscriptionSerializer` in `OrangeNote/Persistence/` (Canonical v1 schema).
- Blocking Rust FFI calls cannot be interrupted by `Task.cancel()`; use `jobID` identity checks and `isNativeBusy` guards in ViewModels.
- Always regenerate project with `xcodegen generate` after adding new source or test files.
