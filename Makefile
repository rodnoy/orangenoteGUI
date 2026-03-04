.PHONY: setup generate build build-debug run clean open init \
       rust-build rust-build-arm64 rust-build-x86 rust-build-universal \
       release dmg

# Install xcodegen if not present
setup:
	@which xcodegen > /dev/null 2>&1 || brew install xcodegen
	@which cargo > /dev/null 2>&1 || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	@rustup target add x86_64-apple-darwin 2>/dev/null || true
	@echo "Setup complete"

# Generate Xcode project from project.yml
generate:
	xcodegen generate
	@echo "Xcode project generated. Open OrangeNote.xcodeproj"

# Build Rust FFI library — universal binary (arm64 + x86_64)
rust-build: rust-build-universal

# Build for arm64 only (faster for development on Apple Silicon)
rust-build-arm64:
	cargo build --release --target aarch64-apple-darwin -p orangenote-ffi
	mkdir -p target/universal/release
	cp target/aarch64-apple-darwin/release/liborangenote_ffi.a target/universal/release/liborangenote_ffi.a
	@echo "arm64 library copied to target/universal/release/"

# Build for x86_64 only
rust-build-x86:
	cargo build --release --target x86_64-apple-darwin -p orangenote-ffi
	mkdir -p target/universal/release
	cp target/x86_64-apple-darwin/release/liborangenote_ffi.a target/universal/release/liborangenote_ffi.a
	@echo "x86_64 library copied to target/universal/release/"

# Build universal binary (arm64 + x86_64) via lipo
rust-build-universal:
	cargo build --release --target aarch64-apple-darwin -p orangenote-ffi
	cargo build --release --target x86_64-apple-darwin -p orangenote-ffi
	mkdir -p target/universal/release
	lipo -create \
		target/aarch64-apple-darwin/release/liborangenote_ffi.a \
		target/x86_64-apple-darwin/release/liborangenote_ffi.a \
		-output target/universal/release/liborangenote_ffi.a
	@echo "Universal library created at target/universal/release/liborangenote_ffi.a"

# Build the macOS app via xcodebuild
build: rust-build
	xcodebuild -project OrangeNote.xcodeproj -scheme OrangeNote -configuration Release build

# Build debug (arm64 only for speed)
build-debug: rust-build-arm64
	xcodebuild -project OrangeNote.xcodeproj -scheme OrangeNote -configuration Debug build

# Run the app
run: build-debug
	open build/Debug/OrangeNote.app

# Clean everything
clean:
	cargo clean
	rm -rf build/
	xcodebuild -project OrangeNote.xcodeproj -scheme OrangeNote clean 2>/dev/null || true

# Generate and open in Xcode
open: generate
	open OrangeNote.xcodeproj

# Full setup: install deps, generate project, open
init: setup generate open

# Build a release DMG (universal binary)
release:
	@./scripts/create-release.sh $(VERSION)

# Create DMG from an already-built app (expects build/DerivedData to exist)
dmg:
	$(eval VERSION ?= dev)
	$(eval APP_PATH := build/DerivedData/Build/Products/Release/OrangeNote.app)
	$(eval DMG_NAME := OrangeNote-$(VERSION)-universal.dmg)
	@test -d "$(APP_PATH)" || (echo "ERROR: App not found. Run 'make build' first." && exit 1)
	@rm -rf build/dmg_contents
	@mkdir -p build/dmg_contents
	@cp -R "$(APP_PATH)" build/dmg_contents/
	@ln -s /Applications build/dmg_contents/Applications
	@hdiutil create -volname "OrangeNote" \
		-srcfolder build/dmg_contents \
		-ov -format UDZO \
		"$(DMG_NAME)"
	@rm -rf build/dmg_contents
	@echo "Created: $(DMG_NAME)"
