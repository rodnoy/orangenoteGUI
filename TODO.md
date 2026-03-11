# OrangeNote — Task Tracker

> A lightweight project task tracker. Keep this file up to date as you work on the project.

---

## How to Use

1. **Add a task**: Write a new `- [ ]` item under the appropriate section with a priority emoji and date.
2. **Start working**: Move the task from **📋 Backlog** to **🔄 In Progress**.
3. **Complete a task**: Move it to **✅ Done**, check the box `- [x]`, and add the completion date.
4. **Log an idea**: Drop rough thoughts into **💡 Ideas** — no format required.

### Priority Markers

| Marker | Meaning |
|--------|---------|
| 🔴     | High    |
| 🟡     | Medium  |
| 🟢     | Low     |

### Date Format

Use ISO 8601 dates: `YYYY-MM-DD`. Track *added* and optionally *done* dates.

```
- [ ] 🔴 Example task — *added: 2026-03-10*
- [x] 🟢 Completed task — *added: 2026-03-01, done: 2026-03-05*
```

---

## 📋 Backlog

- [ ] 🔴 Add unit tests for `orangenote-core` transcription pipeline — *added: 2026-03-10*
- [ ] 🟡 Implement drag-and-drop reordering in transcription segments view — *added: 2026-03-10*
- [ ] 🟢 Improve error messages shown to the user on FFI failures — *added: 2026-03-10*


## 🔄 In Progress


## ✅ Done

<!-- Newest first -->

### v0.1.3 — *2026-03-11*

- [x] 🟡 Added full app localization (English, French, Russian) with system language detection and manual override in Settings — *done: 2026-03-11*
- [x] 🟡 Added "Save Transcription" (⌘S) and "Export Transcription" (⌘⇧E) menu items in File menu — *done: 2026-03-11*
- [x] 🟡 Added Apple Translation integration (macOS 15+) for translating transcription results to 20+ languages — *done: 2026-03-11*
- [x] 🟢 Added "Translate to English" toggle using Whisper's built-in translate mode — *done: 2026-03-11*
- [x] 🟢 Added AppState for shared state management between menu commands and views — *done: 2026-03-11*

### v0.1.2 — *2026-03-11*

- [x] 🟡 Fixed stale export data bug: JSON/SRT copy now always regenerates content from current transcription result instead of using cached data (`ExportViewModel.swift`) — *done: 2026-03-11*
- [x] 🟢 Added macOS Notification Center notifications after successful transcription completion (`NotificationService.swift`, `TranscriptionViewModel.swift`, `OrangeNoteApp.swift`) — *done: 2026-03-11*

### Previous

- [x] 🟡 I want to update drag and drop interface because it doesn't work when I drop items there.
- [x] 🔴 We should add the menu item check for update and link it to the GitHub release version to fetch the newest one.
- [x] 🔴 Define project architecture and document in `docs/ARCHITECTURE.md` — *added: 2026-03-01, done: 2026-03-10*
- [x] 🟡 Scaffold Swift UI views and view models — *added: 2026-03-01, done: 2026-03-08*
- [x] 🟢 Create initial `README.md` — *added: 2026-03-01, done: 2026-03-03*
- [x] 🔴 Set up CI/CD pipeline with GitHub Actions — *added: 2026-03-10*

## 💡 Ideas

- Explore real-time microphone transcription as a future feature.
- Consider a menu-bar-only mode for quick access.
- Investigate smaller quantized Whisper models for faster cold-start.
- Add app icon
- We should add the translation function. And we should check if it's possible for free with Whisper.
- Meta NLLB-200 или M2M-100
===
Рекомендация: CTranslate2 + NLLB-200 Distilled 600M (INT8)

Модель	Размер (INT8)	Языков	Качество	RAM
NLLB-200 600M ⭐	~600 MB	200	Хорошее	~2 GB
NLLB-200 1.3B	~1.3 GB	200	Очень хорошее	~4 GB
M2M-100 418M	~420 MB	100	Среднее	~1.5 GB
Opus-MT	~50-150 MB/пара	~200 пар	Хорошее	~1 GB
Почему NLLB-200 600M: одна модель на 200 языков, ~600 MB (сопоставимо с whisper-моделями), CTranslate2 имеет C++ API для интеграции через Rust FFI (аналогично whisper.cpp). Альтернатива — Apple Translation Framework (macOS 15+, ~20 языков, Swift-only, без скачивания модели).