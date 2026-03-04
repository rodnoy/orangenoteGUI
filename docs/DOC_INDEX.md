# 📚 OrangeNote Documentation Index

> Central index of all project documentation.

## Documents

| Document | Description |
|---|---|
| [`README.md`](../README.md) | Project overview, quick start, building instructions |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Detailed architecture: layers, FFI bridge design, MVVM, build pipeline |

## Configuration Files

| File | Description |
|---|---|
| [`Cargo.toml`](../Cargo.toml) | Rust workspace configuration |
| [`project.yml`](../project.yml) | XcodeGen project definition |
| [`Makefile`](../Makefile) | Build automation commands |
| [`orangenote-ffi/cbindgen.toml`](../orangenote-ffi/cbindgen.toml) | C header generation configuration |

## Key Source References

| File | Description |
|---|---|
| [`orangenote-core/build.rs`](../orangenote-core/build.rs) | whisper.cpp build logic |
| [`orangenote-ffi/include/orangenote_ffi.h`](../orangenote-ffi/include/orangenote_ffi.h) | Generated C-ABI header |
| [`OrangeNote/Bridge/OrangeNoteFFI.swift`](../OrangeNote/Bridge/OrangeNoteFFI.swift) | Swift FFI wrapper |
| [`OrangeNote/Scripts/build_rust.sh`](../OrangeNote/Scripts/build_rust.sh) | Rust build script for Xcode |
