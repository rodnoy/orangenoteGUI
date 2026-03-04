#!/bin/bash
# Build Rust FFI library as a universal binary (arm64 + x86_64).
#
# This script is intended to be called from an Xcode "Run Script" build phase
# or from the Makefile. It compiles the orangenote-ffi crate as a static
# library for both architectures and creates a universal binary via lipo.
set -euo pipefail

# Resolve paths
RUST_PROJECT_DIR="${SRCROOT:-.}"
UNIVERSAL_DIR="${RUST_PROJECT_DIR}/target/universal/release"

cd "${RUST_PROJECT_DIR}"

# Ensure cargo is in PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Install x86_64 target if not present
rustup target add x86_64-apple-darwin 2>/dev/null || true

echo "Building orangenote-ffi for aarch64-apple-darwin…"
cargo build --release --target aarch64-apple-darwin -p orangenote-ffi

echo "Building orangenote-ffi for x86_64-apple-darwin…"
cargo build --release --target x86_64-apple-darwin -p orangenote-ffi

# Create universal binary
mkdir -p "${UNIVERSAL_DIR}"
lipo -create \
  "target/aarch64-apple-darwin/release/liborangenote_ffi.a" \
  "target/x86_64-apple-darwin/release/liborangenote_ffi.a" \
  -output "${UNIVERSAL_DIR}/liborangenote_ffi.a"

echo "Universal library created at ${UNIVERSAL_DIR}/liborangenote_ffi.a"

# Copy the C header to a known location for the bridging header
HEADER_SRC="${RUST_PROJECT_DIR}/orangenote-ffi/include/orangenote_ffi.h"
if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -f "${HEADER_SRC}" ]; then
    HEADER_DST="${BUILT_PRODUCTS_DIR}/include"
    mkdir -p "${HEADER_DST}"
    cp "${HEADER_SRC}" "${HEADER_DST}/orangenote_ffi.h"
    echo "Copied C header to ${HEADER_DST}/orangenote_ffi.h"
fi

echo "Rust build complete."
