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

# Updates install silently, so a release must pass the tests before it can reach her.
swift test
scripts/bundle.sh
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/ScreenJournal.app "$ZIP"

SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="…" length="…"
# The installed app rejects any zip its embedded public key can't verify; catch that here, not on her Mac.
ED_SIGNATURE="$(sed -E 's/.*edSignature="([^"]+)".*/\1/' <<<"$SIGNATURE")"
"$SPARKLE_BIN/sign_update" --verify "$ZIP" "$ED_SIGNATURE"
[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' build/ScreenJournal.app/Contents/Info.plist)" = "$ED_PUBLIC_KEY" ] \
  || { echo "Bundle's public key doesn't match the signing key."; exit 1; }
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

git tag "v$VERSION"
# The tag goes up first, or `gh release create` tags whatever the remote's main is.
git push origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Screen Journal $VERSION" --notes "$NOTES"
git add docs/appcast.xml
git commit -m "Release $VERSION"
git push origin HEAD
echo "Released $VERSION. Appcast: $FEED_URL"
