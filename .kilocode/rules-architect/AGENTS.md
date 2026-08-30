# Project Architecture Rules (Non-Obvious Only)
- Batch audio queue runs strictly sequentially to prevent Metal GPU resource contention.
- Outputs are saved atomically as `<basename>.json` using `AtomicFileWriter` without overwriting existing files.
- `AppState` is a lightweight in-memory observable model for the current user session, not a persistent historical database.
