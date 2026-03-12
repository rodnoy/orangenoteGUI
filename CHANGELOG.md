# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2026-03-12

### Added
- **Model Download/Delete**: Download and delete Whisper models directly from the app
  - New Rust FFI functions: `orangenote_download_model` (with progress callback) and `orangenote_delete_model`
  - Download progress bar in Model Manager UI
  - Delete confirmation dialog
  - Added `ureq` dependency for blocking HTTP downloads
- **Transcription Import**: Open previously saved transcription files (JSON/SRT) for viewing and translation
  - New menu item "File > Open Transcription..." (⌘O)
  - SRT parser with timestamp support
  - JSON import for native format
- **Translation Progress Bar**: Linear progress indicator showing segment-by-segment translation progress
- **Test Notification**: Menu item to verify notification delivery ("OrangeNote > Test Notification")
- **Notification Foreground Delivery**: Notifications now appear even when the app is in foreground
- 13 new localization keys across all 3 language files (en/fr/ru)

### Fixed
- **Translation**: Fixed observation chain — `TranslationTaskModifier` now uses `@ObservedObject` for proper SwiftUI reactivity
- **Export Menu**: "File > Export Transcription" now opens save panel directly instead of just switching tabs
- **Notifications**: Added `UNUserNotificationCenterDelegate` for foreground banner display

### Changed
- Model Manager now shows all models (downloaded and available) with download/delete actions
- Redesigned model rows with three states: downloading (progress bar), cached (path + actions), available (download button)

## [0.1.4] - 2026-03-12

### Fixed
- Fixed localization mechanism: replaced all `String(localized:)` with `LocalizedStringKey` (SwiftUI) and `L10n.localizedString()` (non-SwiftUI) to properly respect in-app language switching
- Fixed `LocalizedStringKey` interpolation issue causing language keys like `lang.fr` to display instead of localized names
- Fixed "System Default" language option not being localized
- Fixed hardcoded time suffixes (h/m/s) in duration display — now properly localized
- Fixed hardcoded "s" suffix in chunk/overlap duration settings
- Fixed Save/Export menu items not triggering actions (added `initial: true` to onChange synchronization)
- Fixed TranslationViewModel not being properly observed by SwiftUI (changed from `let` to `@State`)
- Fixed translation language picker being too narrow (added `minWidth: 140`)
- Fixed "Show in Finder" not working due to sandbox restrictions (added file access entitlement)

### Added
- Model Manager redesigned to show only downloaded/cached models
- File path display for each cached model with "Show in Finder" button
- Cache directory display with "Open Cache Directory" button
- Translation completion notification via NotificationService
- `L10n.localizedString(_:)` helper for imperative localization with app-selected locale
- 12 new localization keys across all 3 language files (en/fr/ru)
- Informative empty state in Model Manager when no models are cached

### Changed
- Model Manager no longer shows "Not downloaded" models (download from app is not supported)
- Removed unused download stub properties from ModelManagerViewModel

### Removed
- Removed `downloadingModel` and `downloadProgress` stubs from ModelManagerViewModel

## [0.1.3] - 2026-03-11

### Added
- Full app localization (English, French, Russian) with system language detection and manual override in Settings
- "Save Transcription" (⌘S) and "Export Transcription" (⌘⇧E) menu items in File menu
- Apple Translation integration (macOS 15+) for translating transcription results to 20+ languages
- "Translate to English" toggle using Whisper's built-in translate mode
- AppState for shared state management between menu commands and views

## [0.1.2] - 2026-03-11

### Fixed
- Fixed stale export data bug: JSON/SRT copy now always regenerates content from current transcription result instead of using cached data

### Added
- macOS Notification Center notifications after successful transcription completion
- Translation option for non-English audio transcriptions
- Toggle for translating transcriptions to English in settings

## [0.1.1] - 2026-03-11

### Added
- Update checking functionality with GitHub releases integration ("Check for Update" menu item)
- File validation for dropped files to ensure accessibility and supported formats
- TODO.md task tracker for project management
- Download badge and real GitHub URLs in README

### Fixed
- Improved drag-and-drop file handling by prioritizing URL loading and enhancing error handling

## [0.1.0] - 2026-03-04

### Added
- Initial OrangeNote macOS GUI application
- Audio transcription using Whisper.cpp via Rust FFI bridge
- Drag-and-drop audio file import
- Transcription results view with segment timestamps
- Export to JSON and SRT formats
- Model selection for Whisper models
- Settings view with transcription parameters (chunk size, overlap, language)
- GitHub Actions CI/CD release workflow for universal macOS app

### Fixed
- CI build compatibility with macOS 15 runner and Xcode 16
- Whisper.cpp submodule checkout in CI

[0.1.5]: https://github.com/rodnoy/OrangeNote/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/rodnoy/OrangeNote/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/rodnoy/OrangeNote/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/rodnoy/OrangeNote/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/rodnoy/OrangeNote/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rodnoy/OrangeNote/releases/tag/v0.1.0
