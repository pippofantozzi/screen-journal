/// Files the app keeps in the journal root so a Claude Code session there knows how to read it.
/// Bump `version` whenever the text changes; the app rewrites stale copies on launch.
public enum JournalGuide {
    public static let version = 1
    public static let marker = "<!-- screen-journal-guide v\(version) -->"

    public static let files: [(path: String, contents: String)] = [
        ("CLAUDE.md", claudeMD),
        (".claude/skills/find-automations/SKILL.md", findAutomationsSkill),
    ]

    public static func isCurrent(_ contents: String) -> Bool { contents.contains(marker) }

    static let claudeMD = """
    \(marker)
    # Screen Journal

    This folder is a passive record of one person's computer work, captured by the Screen Journal app.
    Treat everything as private. Never upload or quote it outside this machine without asking.
    The point is to find work worth automating. Use the `find-automations` skill.

    ## Layout

    ```
    index.md                      one line per day: active time, notes, top apps (start here)
    days/YYYY-MM-DD/
      summary.md                  time per app, top windows, frequent app switches, her notes
      sessions.jsonl              focused stretches in one window: start, end, app, windowTitle, frames, representativeFrame
      frames.jsonl                one row per distinct screen state per display (see below)
      events.jsonl                appSwitch, note; gaps: paused, idle, locked, skipped (private app frontmost), active (capture resumed)
      frames/HHMMSS-dN.heic       screenshot of display N, only when the screen changed
    ```

    ## frames.jsonl fields

    - `start`/`end`: how long this exact screen stayed up. Unchanged screens are not saved twice; `end` just extends.
    - `focused`: true for the display with the frontmost app. Time totals use focused frames only.
    - `app`, `bundleID`, `windowTitle`: the top window on that display.
    - `text`: on-device OCR of the whole display. When OCR matches an earlier frame, `text` is absent and `textSameAs` names that frame.
    - `image`: path relative to the day folder.

    ## Reading cheaply

    - Text first, images last. A week is tens of thousands of frames. Never open images in bulk.
    - `rg -i 'invoice' days/*/frames.jsonl` finds every moment a word was on screen.
    - `jq -c 'select(.app=="Microsoft Excel") | {start,windowTitle}' days/*/sessions.jsonl` lists sessions per app.
    - Notes (`"kind":"note"` in events.jsonl) are things she flagged on purpose. Weight them heavily.
    - Open a `representativeFrame` only to confirm what a session actually involved.
    - Gaps in time mean paused, idle, locked, or a private app was frontmost. Don't guess what happened then.
    """

    static let findAutomationsSkill = """
    ---
    name: find-automations
    description: Analyze this screen journal to find repetitive work worth automating, rank it, and draft skills or scripts. Use when asked what to automate, where time goes, or to build helpers from observed work.
    ---
    \(marker)

    # Find automations

    Goal: a short, ranked list of concrete automations grounded in evidence from this journal, then build the ones she picks.

    ## 1. Orient (text only)
    - Read `index.md` and every `days/*/summary.md`. Note the apps and windows that dominate, plus every note she left.
    - Ask her two or three questions about her role and the tools she can't change. Keep it brief.

    ## 2. Find repetition
    Look for patterns, not single events:
    - **Ping-pong**: frequent `A → B → A` app switches in summaries and sessions (copying between a spreadsheet and a web form, an email and a CRM).
    - **Recurring windows**: the same window title pattern at similar times on several days (daily reports, weekly exports).
    - **Rekeying**: the same strings (names, IDs, amounts) appearing in OCR text of two different apps within minutes. Use `rg` on `frames.jsonl`.
    - **Long, low-variety sessions**: many frames in one window with OCR changing a little each time (manual data entry).
    - **Flagged moments**: each note, plus what was on screen five minutes before it.

    For each candidate, collect: days seen, total minutes, apps involved, two or three timestamps, and one representative image you actually opened.

    ## 3. Rank
    Score each candidate as weekly minutes × repeatability × feasibility. Feasibility means the data is reachable via an API, CLI, AppleScript/Shortcuts, browser automation, or files. Present the top 5–10 as a table, plus one sentence each on how it would be automated. Be honest about which ones look hard.

    ## 4. Build what she picks
    Prefer the simplest thing that works: a Claude Code skill, a shell/Python script, a macOS Shortcut, or a text expander snippet. Put new skills in `~/.claude/skills/<name>/SKILL.md` so they work in every project. Walk her through a first run.

    ## Rules
    - Quote evidence with timestamps; don't invent workflows the data doesn't show.
    - Skip anything that looks personal, medical, financial, or about other people's private messages unless she raises it.
    - Never send screenshots or OCR text to any external service.
    """
}
