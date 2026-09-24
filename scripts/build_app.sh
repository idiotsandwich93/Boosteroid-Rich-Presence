#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/Boosteroid Presence.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="/private/tmp/boosteroid-presence-swift-build"
CLANG_CACHE_DIR="$BUILD_DIR/clang-module-cache"
SWIFTPM_CACHE_DIR="$BUILD_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$BUILD_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$BUILD_DIR/swiftpm-security"
ZIP_PATH="$OUTPUT_DIR/Boosteroid-Presence-macOS.zip"
mkdir -p "$BUILD_DIR" "$CLANG_CACHE_DIR" "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR"

export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_CACHE_DIR"

cd "$ROOT_DIR"
swift build -c debug --disable-sandbox \
    --scratch-path "$BUILD_DIR" \
    --cache-path "$SWIFTPM_CACHE_DIR" \
    --config-path "$SWIFTPM_CONFIG_DIR" \
    --security-path "$SWIFTPM_SECURITY_DIR"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/debug/BoosteroidPresence" "$CONTENTS_DIR/MacOS/BoosteroidPresence"
cp -R "$BUILD_DIR/debug/BoosteroidPresence_BoosteroidPresence.bundle" "$CONTENTS_DIR/Resources/"
cp "assets/BoosteroidPresence.iconset/icon_512x512@2x.png" "$CONTENTS_DIR/Resources/AppIcon.png"
cp "packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
# Cloud/file-provider workspaces can immediately add Finder metadata after
# signing. It is not part of the signature and must not enter the ZIP.
xattr -cr "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
    "$APP_DIR" "$ZIP_PATH"
echo "$APP_DIR"
