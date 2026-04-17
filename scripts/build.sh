#!/usr/bin/env bash
set -euo pipefail

WHISPERBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$WHISPERBOX_DIR/app"
BUILD_DIR="$WHISPERBOX_DIR/build"

echo "=== Building WhisperBox ==="

# Build Swift app in release mode
cd "$APP_DIR"
swift build -c release 2>&1

# Copy binary to build dir
mkdir -p "$BUILD_DIR"
BINARY=$(swift build -c release --show-bin-path)/WhisperBox
cp "$BINARY" "$BUILD_DIR/WhisperBox"

# Create .app bundle
APP_BUNDLE="$BUILD_DIR/WhisperBox.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/WhisperBox"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WhisperBox</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisperbox.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>WhisperBox</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperBox needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign so macOS persists permissions across rebuilds
codesign --force --sign - "$APP_BUNDLE"

echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or: $APP_BUNDLE/Contents/MacOS/WhisperBox"
