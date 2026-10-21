# Screen Journal

A menu-bar Mac app that saves a snapshot of the screen every N seconds (default 10), but only when something changed. After a week or two, open Claude Code in `~/ScreenJournal` and ask it to `find-automations`.

## For her

```bash
curl -fsSL https://pippofantozzi.github.io/screen-journal/install.sh | bash
```

Follow the welcome window. After that it opens at login, updates itself, and lives in the menu bar (pause, note this moment, settings).

## How it works

- **Capture**: ScreenCaptureKit stills of every display at 1.5× point size, with password managers and system overlays (notification banners, Control Center, Spotlight) blanked out. Nothing is captured while paused, locked, idle for 2 minutes or more, when an excluded app is in front, or when the front window is a private browsing window. Frames are labeled with the frontmost app's window on the focused display; system dialogs (SecurityAgent and friends) never label a frame or count as an app switch.
- **Signal over noise**: a 96×60 grayscale diff decides whether a frame is new. Unchanged screens just extend the previous row's `end`. OCR (Apple Vision, on-device) runs only on new rows: the full `text` on the first row of a window, then only `newLines`: lines not yet seen during this visit to the window (scrolling back or flipping between chats in one tab adds nothing). Small changes reuse the display's latest screenshot (`image` can be shared by several rows) and save a fresh one at most once a minute or when a lot of new text appears; a new window, a big change or a new day always saves one.
- **Folder** `~/ScreenJournal`: `index.md`, `week.md` (last 7 days), `reviews/` (results Claude saves), `days/<date>/{summary.md, .digest.json, sessions.jsonl, frames.jsonl, events.jsonl, frames/*.heic}`, plus a `CLAUDE.md` and four skills written by the app (`Sources/JournalCore/JournalGuide.swift`): `find-automations`, `time-report`, `forget` and `tidy-journal`. Today's summary refreshes every 15 minutes; past days missing `summary.md` or `.digest.json` are rebuilt at launch. The app only appends to `frames.jsonl` and `events.jsonl`; only the command line below rewrites them. A row's `image` may point at a screenshot that `forget` or `tidy` deleted. Notes record the app, window and frame on screen when she clicked "Note This Moment…".
- **Cost**: about 4% of one core on average while she works (was ~15–17%, mostly OCR language correction and title spinners that made every tick a "new window"), ~250 MB memory. Unchanged screens cost almost nothing; OCR on changed frames is most of it.
- **Command line** (what the `forget` and `tidy-journal` skills call). Every command is a dry run until `--apply`:
  ```bash
  SJ=/Applications/ScreenJournal.app/Contents/MacOS/ScreenJournal
  "$SJ" forget --from 2026-10-21T18:57 --to 2026-10-21T19:00 [--apply]  # local time, half-open, may span days
  "$SJ" forget --term WhatsApp --term wnatsap [--apply]                 # whole visits, every day
  "$SJ" tidy --keep-days 7 [--apply]                                    # drop redundant screenshots of older days
  "$SJ" rebuild                                                         # sessions, summaries, index.md, week.md
  ```
  `forget --apply` and `rebuild` quit the app, rewrite the day files (temp file, then move), rebuild the summaries and reopen it. After a term forget, every text file is checked again; exit 1 lists anything still mentioning a term. `tidy --apply` leaves the app running and never touches today. For development, `--root <copy>` points at another folder and leaves the running app alone.
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
