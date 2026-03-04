#!/bin/bash
# Create a release DMG locally.
#
# Usage:
#   ./scripts/create-release.sh [version]
#
# Examples:
#   ./scripts/create-release.sh v0.1.0
#   ./scripts/create-release.sh          # defaults to "dev"
set -euo pipefail

VERSION="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA="${PROJECT_DIR}/build/DerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/OrangeNote.app"
DMG_NAME="OrangeNote-${VERSION}-universal.dmg"
DMG_DIR="${PROJECT_DIR}/build/dmg_contents"

cd "${PROJECT_DIR}"

echo "=== Building OrangeNote ${VERSION} ==="

# Step 1: Build Rust FFI universal binary
echo ""
echo "--- Building Rust FFI (arm64) ---"
cargo build --release --target aarch64-apple-darwin -p orangenote-ffi

echo ""
echo "--- Building Rust FFI (x86_64) ---"
cargo build --release --target x86_64-apple-darwin -p orangenote-ffi

echo ""
echo "--- Creating universal binary ---"
mkdir -p target/universal/release
lipo -create \
  target/aarch64-apple-darwin/release/liborangenote_ffi.a \
  target/x86_64-apple-darwin/release/liborangenote_ffi.a \
  -output target/universal/release/liborangenote_ffi.a
lipo -info target/universal/release/liborangenote_ffi.a

# Step 2: Generate Xcode project
echo ""
echo "--- Generating Xcode project ---"
xcodegen generate

# Step 3: Build macOS app
echo ""
echo "--- Building macOS app ---"
xcodebuild -project OrangeNote.xcodeproj \
  -scheme OrangeNote \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  build

# Step 4: Verify the app exists
if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: App not found at ${APP_PATH}"
  exit 1
fi

echo ""
echo "--- App built at ${APP_PATH} ---"

# Step 5: Create DMG
echo ""
echo "--- Creating DMG ---"
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "OrangeNote" \
  -srcfolder "${DMG_DIR}" \
  -ov -format UDZO \
  "${PROJECT_DIR}/${DMG_NAME}"

rm -rf "${DMG_DIR}"

echo ""
echo "=== Release DMG created: ${DMG_NAME} ==="
ls -lh "${PROJECT_DIR}/${DMG_NAME}"
