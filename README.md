# Screen Journal

A menu-bar Mac app that saves a snapshot of the screen every N seconds (default 10), but only when something changed. After a week or two, open Claude Code in `~/ScreenJournal` and ask it to `find-automations`.

## For her

```bash
curl -fsSL https://pippofantozzi.github.io/screen-journal/install.sh | bash
```

Follow the welcome window. After that it opens at login, updates itself, and lives in the menu bar (pause, note this moment, settings).

## How it works

- **Capture**: ScreenCaptureKit stills of every display, with password managers blanked out. Nothing is captured while paused, locked, idle for 2 minutes or more, or when an excluded app is in front.
- **Signal over noise**: a 96×60 grayscale diff decides whether a frame is new. Unchanged screens just extend the previous frame's `end`. OCR (Apple Vision, on-device) runs only on new frames, and repeated text becomes a `textSameAs` reference.
- **Folder** `~/ScreenJournal`: `index.md`, `days/<date>/{summary.md, sessions.jsonl, frames.jsonl, events.jsonl, frames/*.heic}`, plus a `CLAUDE.md` and the `find-automations` skill written by the app (`Sources/JournalCore/JournalGuide.swift`).
- **Code**: `JournalCore` is pure logic with tests (`swift test`). `Sources/ScreenJournal/Effects` holds thin adapters over the macOS APIs.

## Develop

```bash
swift test                    # pure core
scripts/bundle.sh             # build/ScreenJournal.app (dev build, no updater)
open build/ScreenJournal.app
```

## Release

There's no paid Apple Developer account, so:
- Every build is signed with the self-signed **Screen Journal Signing** identity (`scripts/create-signing-identity.sh`, one-time; back up `~/.screen-journal-signing/signing.p12`). The same identity across releases is what keeps her Screen Recording permission through updates. **Don't lose it.**
- The install is a `curl` one-liner, which skips the Gatekeeper quarantine. Sparkle updates also skip it.

One-time per Mac, so `codesign` stops asking for your login password for each nested Sparkle binary:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -D "Screen Journal Signing" -t private ~/Library/Keychains/login.keychain-db
```

```bash
scripts/release.sh 0.2.0 "What changed"
```

This builds and signs, creates a GitHub release with `ScreenJournal.zip`, prepends an item to `docs/appcast.xml` (served by GitHub Pages from `/docs`), and pushes. Sparkle checks daily and installs on the next relaunch.

## Known fog

- macOS Sequoia+ re-asks for screen-recording consent periodically. When access is lost, the menu shows a ⚠︎ icon with "Turn Screen Access Back On…".
- Storage is roughly 100–300 MB/day. Retention defaults to 30 days (Settings).
