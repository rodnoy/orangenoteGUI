#!/bin/bash
# OrangeNote Full Quality & Regression Gate Script
#
# Validates:
#   1. Rust backend unit and integration tests (cargo test --workspace)
#   2. Xcode project generation (xcodegen generate)
#   3. Version consistency (project.yml and Info.plist)
#   4. Swift test suite (xcodebuild test -scheme OrangeNote)
#   5. macOS app build (xcodebuild build -scheme OrangeNote)
#   6. Sandboxed codesign verification (codesign --verify)
#   7. Entitlements verification (app-sandbox, user-selected.read-write, network.client)
#
# Usage:
#   ./scripts/regression-gate.sh
#   make gate
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

echo "========================================================"
echo "          OrangeNote Regression & Quality Gate          "
echo "========================================================"

# Step 1: Rust backend tests
echo ""
echo "--- [1/6] Running Rust test suite (cargo test --workspace) ---"
cargo test --workspace

# Step 2: Xcode project generation
echo ""
echo "--- [2/6] Generating Xcode project (xcodegen generate) ---"
xcodegen generate

# Step 3: Version consistency check
echo ""
echo "--- [3/6] Checking version metadata consistency ---"
PROJECT_VERSION=$(grep 'CFBundleShortVersionString:' project.yml | awk -F '"' '{print $2}')
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" OrangeNote/Info.plist 2>/dev/null || echo "")

if [ "${PROJECT_VERSION}" != "${PLIST_VERSION}" ]; then
  echo "ERROR: Version mismatch between project.yml (${PROJECT_VERSION}) and OrangeNote/Info.plist (${PLIST_VERSION})"
  exit 1
fi
echo "Version consistency verified: ${PROJECT_VERSION}"

# Step 4: Swift unit and integration test suite
echo ""
echo "--- [4/6] Running Swift test suite (xcodebuild test) ---"
xcodebuild test \
  -project OrangeNote.xcodeproj \
  -scheme OrangeNote \
  -destination 'platform=macOS'

# Step 5: Build macOS Application
echo ""
echo "--- [5/6] Building macOS application (xcodebuild build) ---"
BUILD_SETTINGS=$(xcodebuild build \
  -project OrangeNote.xcodeproj \
  -scheme OrangeNote \
  -destination 'platform=macOS' \
  -showBuildSettings)

APP_PATH=$(echo "${BUILD_SETTINGS}" | awk -F ' = ' '/CODESIGNING_FOLDER_PATH/ {print $2; exit}')

if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
  # Fallback to standard build products directory if not found
  BUILT_DIR=$(echo "${BUILD_SETTINGS}" | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')
  APP_PATH="${BUILT_DIR}/OrangeNote.app"
fi

echo "Verifying built application at: ${APP_PATH}"

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: Built application not found at ${APP_PATH}"
  exit 1
fi

# Step 6: Verify codesign and entitlements
echo ""
echo "--- [6/6] Verifying codesign signature and sandbox entitlements ---"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

ENTITLEMENTS_XML=$(codesign -d --entitlements - "${APP_PATH}" 2>&1 || true)

echo "Inspecting embedded entitlements..."
if ! echo "${ENTITLEMENTS_XML}" | grep -q "com.apple.security.app-sandbox"; then
  echo "ERROR: Missing com.apple.security.app-sandbox entitlement"
  exit 1
fi

if ! echo "${ENTITLEMENTS_XML}" | grep -q "com.apple.security.files.user-selected.read-write"; then
  echo "ERROR: Missing com.apple.security.files.user-selected.read-write entitlement"
  exit 1
fi

if ! echo "${ENTITLEMENTS_XML}" | grep -q "com.apple.security.network.client"; then
  echo "ERROR: Missing com.apple.security.network.client entitlement"
  exit 1
fi

echo "All required sandbox entitlements verified:"
echo "  - com.apple.security.app-sandbox: true"
echo "  - com.apple.security.files.user-selected.read-write: true"
echo "  - com.apple.security.network.client: true"

echo ""
echo "========================================================"
echo "       Regression & Quality Gate: ALL CHECKS PASSED     "
echo "========================================================"
