<p align="center">
  <!-- TODO: Replace with actual logo -->
  <img src="OrangeNote/Assets.xcassets/AppIcon.appiconset/icon.png" alt="OrangeNote Logo" width="128" height="128">
  <br>
  <strong>OrangeNote</strong>
  <br>
  <em>Beautiful offline audio transcription for macOS</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-blue?logo=apple" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/rust-2021-brown?logo=rust" alt="Rust 2021">
  <img src="https://img.shields.io/badge/whisper.cpp-integrated-green" alt="whisper.cpp">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
  <img src="https://img.shields.io/badge/version-0.2.0-informational" alt="Version 0.2.0">
</p>

---

## ✨ Features

- 🎧 **Drag & Drop** — Drop audio files directly into the app to start transcription
- 🧠 **Multiple Whisper Models** — Choose from tiny, base, small, medium, and large models
- 🌍 **Language Auto-Detection** — Automatically detects the spoken language
- 🔀 **Chunked Transcription** — Processes long audio files in chunks for reliability
- 📤 **Export Formats** — Save results as Plain Text, SRT, WebVTT, or JSON
- 📊 **Real-Time Progress** — Live progress tracking with segment-level updates
- 🌙 **Dark Mode** — Full native dark mode support
- 🔒 **100% Offline** — All processing happens locally on your Mac

## 📸 Screenshots

<!-- TODO: Add screenshots of the application -->

| Transcription View | Results View | Model Manager |
|:---:|:---:|:---:|
| *Coming soon* | *Coming soon* | *Coming soon* |

## 📋 Requirements

| Requirement | Version |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 15.0+ |
| Rust toolchain | stable (2021 edition) |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | latest |

## 🚀 Quick Start

```bash
# Clone with submodules (whisper.cpp)
git clone --recursive https://github.com/your-org/orangenote.git
cd orangenote

# Install dependencies, generate Xcode project, and open it
make init
```

This single command will:
1. Install XcodeGen and Rust toolchain if missing
2. Generate the Xcode project from [`project.yml`](project.yml)
3. Open the project in Xcode

Then press **⌘R** in Xcode to build and run.

## 📁 Project Structure

OrangeNote is organized as a **Cargo workspace mono-repo** with an Xcode project overlay:

```
orangenoteUI/
├── Cargo.toml                # Workspace root
├── project.yml               # XcodeGen project configuration
├── Makefile                  # Build automation commands
│
├── orangenote-core/          # 🦀 Rust transcription library
│   ├── build.rs              #    whisper.cpp compilation
│   └── src/
│       └── infrastructure/   #    Audio processing + Whisper engine
│
├── orangenote-ffi/           # 🔗 C-ABI FFI bridge
│   ├── cbindgen.toml         #    Header generation config
│   ├── include/
│   │   └── orangenote_ffi.h  #    Generated C header
│   └── src/lib.rs            #    FFI function exports
│
├── OrangeNote/               # 🍎 SwiftUI macOS application
│   ├── Bridge/               #    Swift ↔ Rust FFI wrappers
│   ├── Models/               #    Data models
│   ├── ViewModels/           #    MVVM view models
│   ├── Views/                #    SwiftUI views & components
│   └── Scripts/              #    Build scripts
│
├── vendor/
│   └── whisper.cpp           # 📦 Git submodule
│
├── reference/
│   └── orangenote-cli.rs     # CLI reference implementation
│
└── docs/
    └── ARCHITECTURE.md       # Detailed architecture documentation
```

## 🔨 Building

### Prerequisites

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install XcodeGen
brew install xcodegen

# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add aarch64 target (Apple Silicon)
rustup target add aarch64-apple-darwin
```

### Using Make

```bash
# Install all prerequisites automatically
make setup

# Generate Xcode project from project.yml
make generate

# Build Rust FFI library
make rust-build

# Build the full macOS app (Release)
make build

# Build and run (Debug)
make run

# Clean all build artifacts
make clean

# Full setup: install deps → generate project → open Xcode
make init
```

### Manual Build Steps

```bash
# 1. Build the Rust FFI library
cargo build --release -p orangenote-ffi --target aarch64-apple-darwin

# 2. Generate the Xcode project
xcodegen generate

# 3. Build via xcodebuild
xcodebuild -project OrangeNote.xcodeproj -scheme OrangeNote -configuration Release build
```

## 🏗️ Architecture

OrangeNote follows **Clean Architecture** with three distinct layers:

```
┌─────────────────────────────────┐
│     SwiftUI Presentation        │  Swift / MVVM
│  Views → ViewModels → Bridge    │
├─────────────────────────────────┤
│        FFI Bridge Layer         │  C-ABI boundary
│     orangenote-ffi (Rust)       │
├─────────────────────────────────┤
│         Rust Core Engine        │  Business logic
│  Audio Processing │ Whisper     │
│  Model Management │ Chunking    │
└─────────────────────────────────┘
```

| Layer | Crate / Module | Responsibility |
|---|---|---|
| **Rust Core** | [`orangenote-core`](orangenote-core/) | Audio decoding, chunked processing, whisper.cpp transcription, model management |
| **FFI Bridge** | [`orangenote-ffi`](orangenote-ffi/) | C-ABI function exports, memory-safe data marshalling, callback-based progress reporting |
| **SwiftUI App** | [`OrangeNote`](OrangeNote/) | Native macOS UI, MVVM architecture, drag & drop, settings, export |

> 📖 For the full architecture deep-dive, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## 🛠️ Development

### Opening the Project

```bash
make open   # Generates Xcode project and opens it
```

### Project Generation

The Xcode project is generated from [`project.yml`](project.yml) using XcodeGen. **Do not edit `OrangeNote.xcodeproj` directly** — changes will be overwritten. Instead, modify `project.yml` and run:

```bash
make generate
```

### Rust Development

The Rust FFI library is automatically built as a **pre-build script** in Xcode (configured in [`project.yml`](project.yml:56)). When you press ⌘R in Xcode, it will:

1. Detect the target architecture (arm64 / x86_64)
2. Build `orangenote-ffi` via Cargo
3. Link the static library into the Swift app

For standalone Rust development:

```bash
# Build and check
cargo build -p orangenote-core
cargo check --workspace

# Run clippy lints
cargo clippy --workspace
```

### Regenerating FFI Headers

The C header [`orangenote_ffi.h`](orangenote-ffi/include/orangenote_ffi.h) is generated by [cbindgen](https://github.com/mozilla/cbindgen). To regenerate:

```bash
cd orangenote-ffi
cbindgen --config cbindgen.toml --crate orangenote-ffi --output include/orangenote_ffi.h
```

### Debugging Tips

- **Rust panics**: Check Xcode console for panic messages from the Rust layer
- **FFI issues**: Enable `RUST_LOG=debug` environment variable in Xcode scheme
- **Audio processing**: The core uses chunked processing — check chunk boundaries if segments are missing
- **Model loading**: Models are downloaded to `~/Library/Application Support/OrangeNote/models/`

## 🗺️ Roadmap

### MVP (Current)

- [x] Audio file transcription with whisper.cpp
- [x] Drag & drop file input
- [x] Multiple Whisper model support
- [x] Language auto-detection
- [x] Chunked audio processing
- [x] Export to TXT, SRT, VTT, JSON
- [x] Real-time progress tracking
- [x] Model download & management
- [x] Settings persistence

### Future Plans

- [ ] Microphone live recording & transcription
- [ ] Batch file processing
- [ ] Speaker diarization
- [ ] Translation mode (any language → English)
- [ ] Keyboard shortcuts & accessibility
- [ ] Menu bar quick-access widget
- [ ] Apple Silicon GPU acceleration (Metal)
- [ ] Homebrew Cask distribution

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Here's how to get started:

1. **Fork** the repository
2. **Create a feature branch** from `develop`:
   ```bash
   git checkout -b feature/my-feature develop
   ```
3. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/):
   ```bash
   git commit -m "feat: add microphone recording support"
   ```
4. **Push** and open a **Pull Request** against `develop`

### Guidelines

- Follow [Gitflow](https://nvie.com/posts/a-successful-git-branching-model/) branching model
- Write commit messages in English using [Conventional Commits](https://www.conventionalcommits.org/)
- Squash commits and rebase upon parent branch before merging
- Rust code: run `cargo clippy` and `cargo fmt` before committing
- Swift code: follow Swift API Design Guidelines
- All code comments and documentation must be in English

---

<p align="center">
  Made with 🍊 by the OrangeNote Team
</p>
