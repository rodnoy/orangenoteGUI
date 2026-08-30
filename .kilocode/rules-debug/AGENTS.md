# Project Debug Rules (Non-Obvious Only)
- Running `./scripts/regression-gate.sh` validates the complete pipeline: Rust, XcodeGen, version consistency, Swift tests, macOS app build, codesign, and sandbox entitlements.
- Entitlement checks require `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, and `com.apple.security.network.client`.
- If `Info.plist` version reverts, check `project.yml` `CFBundleShortVersionString` as XcodeGen regenerates `Info.plist` on every run.
