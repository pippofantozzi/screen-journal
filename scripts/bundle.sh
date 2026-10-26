#!/usr/bin/env bash
# Builds a universal, signed ScreenJournal.app into build/.
#   VERSION=0.2.0 scripts/bundle.sh
# Without FEED_URL/ED_PUBLIC_KEY the Sparkle keys are dropped (dev build, no updater).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${SIGN_IDENTITY:-Screen Journal Signing}"
APP="build/ScreenJournal.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN_DIR/ScreenJournal" "$APP/Contents/MacOS/"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"

sed -e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD|" \
    -e "s|__FEED_URL__|${FEED_URL:-}|" -e "s|__ED_PUBLIC_KEY__|${ED_PUBLIC_KEY:-}|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -z "${FEED_URL:-}" ]; then
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" -c "Delete :SUPublicEDKey" "$APP/Contents/Info.plist"
fi

# One stable identity for every build keeps the Screen Recording grant across updates.
# No hardened runtime: library validation would reject Sparkle under a team-less self-signed cert.
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
