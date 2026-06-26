#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Catch"
BUNDLE_ID="xyz.block.catch"
MIN_SYSTEM_VERSION="26.0"
VERSION="${1:-${VERSION:-}}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "refusing to package non-semver version: $VERSION" >&2
  exit 2
fi
BUNDLE_VERSION="${VERSION%%[-+]*}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
WORK_DIR="$ROOT_DIR/.build/release-package"
UNIVERSAL_BINARY="$WORK_DIR/$APP_NAME"
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
EMBED_DIR="$WORK_DIR/embed"
DMG_STAGING_DIR="$WORK_DIR/dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-v$VERSION-macos-universal.dmg"
EMBED_TAR_PATH="$DIST_DIR/catch-v$VERSION-macos-universal.tar.gz"

cd "$ROOT_DIR"

rm -rf "$WORK_DIR" "$DIST_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR"

echo "Building arm64 release binary"
swift build -c release --triple arm64-apple-macosx
ARM64_BINARY="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)/$APP_NAME"

echo "Building x86_64 release binary"
swift build -c release --triple x86_64-apple-macosx
X86_64_BINARY="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)/$APP_NAME"

echo "Creating universal binary"
lipo -create -output "$UNIVERSAL_BINARY" "$ARM64_BINARY" "$X86_64_BINARY"
chmod +x "$UNIVERSAL_BINARY"
lipo -info "$UNIVERSAL_BINARY"

echo "Creating $APP_NAME.app"
mkdir -p "$APP_MACOS"
cp "$UNIVERSAL_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null

echo "Creating sidecar tarball"
mkdir -p "$EMBED_DIR"
cp "$UNIVERSAL_BINARY" "$EMBED_DIR/catch"
chmod +x "$EMBED_DIR/catch"
tar -C "$EMBED_DIR" -czf "$EMBED_TAR_PATH" catch

echo "Creating DMG"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/$APP_NAME.app"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Release artifacts:"
ls -lh "$DIST_DIR"
