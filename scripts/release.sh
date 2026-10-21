#!/usr/bin/env bash
# Ships a version: build, sign, GitHub release, appcast entry. Her app picks it up within a day.
#   scripts/release.sh 0.2.0 "What changed, in one line"
# Needs: "Screen Journal Signing" identity + Sparkle EdDSA key in the login keychain, gh auth.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh VERSION [notes]}"
NOTES="${2:-Improvements and fixes.}"
REPO="${REPO:-pippofantozzi/screen-journal}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
ZIP="build/ScreenJournal.zip"

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash changes first."; exit 1; }

OWNER="${REPO%%/*}"
export VERSION
export FEED_URL="https://$OWNER.github.io/${REPO#*/}/appcast.xml"
export ED_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"

git tag "v$VERSION"
scripts/bundle.sh
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/ScreenJournal.app "$ZIP"

SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="…" length="…"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/ScreenJournal.app/Contents/Info.plist)"
ITEM="    <item>
      <title>$VERSION</title>
      <description><![CDATA[$NOTES]]></description>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url=\"https://github.com/$REPO/releases/download/v$VERSION/ScreenJournal.zip\" type=\"application/octet-stream\" $SIGNATURE/>
    </item>"

# Newest item goes first, right after the marker line.
ITEM="$ITEM" perl -0pi -e 's/(<!-- items -->\n)/$1$ENV{ITEM}\n/' docs/appcast.xml

gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Screen Journal $VERSION" --notes "$NOTES"
git add docs/appcast.xml
git commit -m "Release $VERSION"
git push origin HEAD "v$VERSION"
echo "Released $VERSION. Appcast: $FEED_URL"
