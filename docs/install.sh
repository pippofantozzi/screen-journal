#!/usr/bin/env bash
# Installs (or reinstalls) Screen Journal into /Applications and opens it.
#   curl -fsSL https://pippofantozzi.github.io/screen-journal/install.sh | bash
# Downloading with curl skips the Gatekeeper quarantine that a browser download would add.
set -euo pipefail

URL="https://github.com/pippofantozzi/screen-journal/releases/latest/download/ScreenJournal.zip"
APP="/Applications/ScreenJournal.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Screen Journal…"
curl -fsSL "$URL" -o "$TMP/ScreenJournal.zip"
ditto -x -k "$TMP/ScreenJournal.zip" "$TMP"

pkill -x ScreenJournal 2>/dev/null || true
rm -rf "$APP"
mv "$TMP/ScreenJournal.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "Done. Follow the welcome window ✨"
