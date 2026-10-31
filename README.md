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
- **Folder** `~/ScreenJournal`: `profile.md` (what Claude has learned about the owner, consent included), `index.md`, `week.md` (last 7 days), `reviews/` (results Claude saves, `candidates.jsonl` with a status per automation idea), `days/<date>/{summary.md, .digest.json, sessions.jsonl, frames.jsonl, events.jsonl, frames/*.heic}`, plus a `CLAUDE.md` and five skills written by the app (`Sources/JournalCore/JournalGuide.swift`): `find-automations`, `time-report`, `forget`, `tidy-journal` and `autopilot` (an unattended daily pass, optionally on a local launchd schedule, that labels, updates the profile and candidates, and writes a Monday digest). Keys and tokens in known formats are replaced with `[redacted]` in screen text before it is written (`Sources/JournalCore/Secrets.swift`); IDs and hashes stay, since automations match on them. OCR reads the whole display, but a frame's text is only the lines inside the window it's filed under (`WindowPlacement.lines`), so a terminal behind a small dialog doesn't leak into it; a key spotted anywhere on the display still marks the frame `secretOnScreen`. With the optional Accessibility grant (an onboarding step), each focused frame gets a `place` (a terminal's folder, a browser's page or site) and WhatsApp titles carry the open chat, `Forgia LFG! — WhatsApp`, read from its header in the OCR (`Sources/JournalCore/ChatHeader.swift`). Today's summary refreshes every 15 minutes; past days missing `summary.md` or `.digest.json` are rebuilt at launch. The app only appends to `frames.jsonl` and `events.jsonl`; only the command line below rewrites them. A row's `image` may point at a screenshot that `forget` or `tidy` deleted. Notes record the app, window and frame on screen when the owner pressed ⌥Space (or chose "Note This Moment…"); the note panel floats over their app without activating Screen Journal, so it records no app switch.
- **Cost**: about 4% of one core on average while she works (was ~15–17%, mostly OCR language correction and title spinners that made every tick a "new window"), ~250 MB memory. Unchanged screens cost almost nothing; OCR on changed frames is most of it.
- **Command line** (what the `forget` and `tidy-journal` skills call). Every command is a dry run until `--apply`:
  ```bash
  SJ=~/ScreenJournal/.claude/sj   # the app links this to itself at launch
  "$SJ" forget --from 2026-10-21T18:57 --to 2026-10-21T19:00 [--apply]  # local time, half-open, may span days
  "$SJ" forget --term WhatsApp --term wnatsap [--apply]                 # whole visits, every day
  "$SJ" tidy --keep-days 7 [--apply]                                    # drop redundant screenshots of older days
  "$SJ" rebuild                                                         # sessions, summaries, index.md, week.md
  "$SJ" label [--day 2026-10-21] [--titles-only] [--apply]              # work / automatable / task → days/<date>/labels.jsonl
  "$SJ" dictate --audio clip.wav [--selection "…"] [--word Forgia] [--language automatic]  # prints, pastes nothing
  "$SJ" whatsapp [--chat "Bru"] [--last 200] [--out ~/Downloads]                    # the open chat when no --chat
  ```
  `forget --apply` and `rebuild` quit the app, rewrite the day files (temp file, then move), rebuild the summaries and reopen it. After a term forget, every text file is checked again; exit 1 lists anything still mentioning a term. `tidy --apply` leaves the app running and never touches today. For development, `--root <copy>` points at another folder and leaves the running app alone.
- **Labels** (hosted): `label` asks three questions about every unlabelled session in one System One pass to `baseten/mammoth-1` on the Vercel AI Gateway, ~1 s per session, 16 at a time: `work` (probability, judged against the owner's own description), `automatable` (0–1, assuming coding agents with skills and scripts, browser and computer use, scheduled jobs) and `task` (a choice among the kinds the owner picked, suggestions or their own, plus `other`; every suggestion until they pick). The description and kinds are set in Settings → Your work and saved to `labels.json` (`Sources/JournalCore/Labels.swift`). It sends that description, app, window title, duration, the windows either side and ≤600 characters of screen text with keys redacted (`--titles-only`: no text). Every request sets `disallowPromptTraining` and `zeroDataRetention` (`DecisionGateway.zeroRetention`), so only providers that keep nothing answer; that needs the key's Vercel team on Pro (Hobby gets 403 on every request). The key is saved in Settings → General to the login Keychain (`Sources/ScreenJournal/Effects/GatewayKey.swift`), where `label`, being the same signed binary, reads it without a prompt; `AI_GATEWAY_API_KEY` in the environment overrides it. With "Send screenshots too" on (`screenshots` in `labels.json`, on by default), sessions with nothing redacted anywhere on screen (`FrameRecord.secretOnScreen`) go to `typesafe-ai/jev-1.14.0` with the screenshot as a 1024 px JPEG instead, answered as `source: look`, which beats a text-only answer; pixels can't be redacted. On the graded eval set (`scripts/jev-eval.py`) that got 80% of sessions right on all three answers, against 64% from text alone. Once a key is saved, the app runs the same pass hourly on the last 8 days (`SessionSorter`), skipping sessions that ended in the last 5 minutes, reading days in parallel and skipping past days already fully sorted under the current setup; editing Settings → Your work runs it two minutes later. Answers carry a fingerprint of everything the model was told, so editing the description or kinds relabels every session. The output ranks windows by duration × automatable × work ("Where to look first"), which is where Claude starts looking for automations. `forget` drops labels of removed sessions.
- **Dictation** (Settings → Dictation, on from the start): tap Right ⌘ (or Right ⌥) alone, speak, tap again, and the text is pasted where the cursor is; Esc cancels. With text highlighted at the first tap, what's said is an instruction and the highlight is replaced with the rewrite. Audio (16 kHz WAV, in memory) from the Mac's own microphone (a Bluetooth headset's takes seconds to wake into call mode, so it isn't used; a Mac without one records from the default input) goes to `mistral/voxtral-small-transcribe-3` with the dictation language (Portuguese by default, English, or Automatic to detect; separate from the app's language); the transcript goes to `deepseek/deepseek-v4.1-flash-1017` (reasoning off, fastest provider first) to tidy it or apply the instruction (`Sources/JournalCore/Dictation.swift`). Both requests are zero data retention, through the same key as labels (`SpeechGateway`). The owner's words (names, jargon) bias the transcriber and fix spellings. A silent recording isn't sent; the pill points at the microphone setting. The selection is read through Accessibility, falling back to ⌘C; the text is pasted with ⌘V in any app and stays on the clipboard. Soft, low wooden knocks (`Resources/Sounds`, made with earshot's sound bank in one key) mark listening, writing and pasted. Unlike screenshots, dictation audio leaves the Mac, and nothing of it reaches the journal.
- **WhatsApp export**: tap Left ⌘ alone while the WhatsApp Mac app is in front (or choose "Export WhatsApp Chat…") and a floating panel offers the open chat, read from its header button through Accessibility (`NavigationBar_HeaderViewButton`), and how many messages (200, then the last used). Export writes `~/Downloads/<chat> <date time>.zip`: `chat.txt` in WhatsApp's own export format plus each photo, video, voice note, document and sticker, named as WhatsApp names them (`Sources/JournalCore/WhatsApp.swift`). Each downloaded voice note goes through dictation's transcriber (language detected, the owner's words as bias, zero data retention, 6 at a time): its transcript follows the note in `chat.txt` as a `Transcript:` line and sits beside the audio as a `.txt` of the same name (`00000007-AUDIO-….opus` → `00000007-AUDIO-….txt`). Without a gateway key, or when one fails, the export still saves and the panel counts the notes left untranscribed. It reads the Mac app's `ChatStorage.sqlite` read-only (group members named from `ContactsV2.sqlite`, else their profile name), so macOS asks once to let Screen Journal see another app's data. Only media the Mac app downloaded is on disk: the rest is written "image omitted" and counted in the panel; history synced when the Mac was linked has none. Voice notes leave the Mac to be transcribed; nothing of the export reaches the journal.
- **Agent prompt** (Settings → Journal → Prompt for your agent → Copy): copies a prompt for any coding agent with the journal's absolute paths, the reading order and lenses, the privacy rules, and four gates: understand the data, interview the owner one question at a time, propose agents, skills, routines and connections with evidence and wait for approval by name, then build one at a time, pausing for the owner to connect services (`Sources/JournalCore/AgentBrief.swift`).
- **Code**: `JournalCore` is pure logic with tests (`swift test`). `Sources/ScreenJournal/Effects` holds thin adapters over the macOS APIs.

## Develop

```bash
swift test                    # pure core
scripts/bundle.sh             # build/ScreenJournal.app (dev build, no updater)
open build/ScreenJournal.app
```

## Release

There's no paid Apple Developer account, so:
- Every build is signed with the self-signed **Screen Journal Signing** identity (`scripts/create-signing-identity.sh`, one-time; back up `~/.screen-journal-signing/signing.p12`). The same identity across releases is what keeps her Screen Recording and Accessibility permissions through updates. **Don't lose it.**
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
