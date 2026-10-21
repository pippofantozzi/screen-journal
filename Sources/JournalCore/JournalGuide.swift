/// Files the app keeps in the journal root so a Claude Code session there knows how to read it.
/// Bump `version` whenever the text changes; the app rewrites stale copies on launch.
public enum JournalGuide {
    public static let version = 3
    public static let marker = "<!-- screen-journal-guide v\(version) -->"

    public static let skills: [(name: String, contents: String)] = [
        ("find-automations", findAutomationsSkill),
        ("time-report", timeReportSkill),
        ("forget", forgetSkill),
        ("tidy-journal", tidyJournalSkill),
    ]

    public static let files: [(path: String, contents: String)] =
        [("CLAUDE.md", claudeMD)] + skills.map { (".claude/skills/\($0.name)/SKILL.md", $0.contents) }

    public static func isCurrent(_ contents: String) -> Bool { contents.contains(marker) }

    static let claudeMD = #"""
    \#(marker)
    # Screen Journal

    This folder is a passive record of one person's computer work, captured by the Screen Journal app on this Mac.
    The person talking to you is its owner. She is not a developer: speak plainly, skip jargon, and say what you are about to do before running anything that deletes or changes files.

    ## Privacy
    - Everything here stays on this Mac. Screenshots and screen text never go to any website, API, or other service.
    - Her own work data (dashboards, product metrics, invoices she handles) is fine to summarize. Skip anything personal or medical, and never quote personal banking, card numbers or salaries. Describe money figures without quoting exact amounts unless she asks for them.
    - Other people's messages in chats, mail and any inbox (CRM consoles, support tools) are never quoted or summarized; describe them at window level: who, when, how often.
    - Skip anything else personal unless she raises it herself.
    - Gaps in time mean paused, idle, locked, or a private app or private browsing window was in front. Password managers and apps she excluded are never captured. Leave gaps unexplained.

    ## Skills
    - `find-automations`: find repetitive work worth automating, then build the helpers she picks.
    - `time-report`: where her time went over a day or week, what she was doing at a moment, or when she saw something.
    - `forget`: permanently remove a time range, or everything mentioning a word, from the journal.
    - `tidy-journal`: see how much space the journal uses and slim down old days.

    ## Tools
    The app binary has commands for changing the journal. Use them through the `forget` and `tidy-journal` skills.
    ```sh
    SJ="/Applications/ScreenJournal.app/Contents/MacOS/ScreenJournal"
    "$SJ" forget --from 2026-10-21T18:57 --to 2026-10-21T19:00 [--apply]   # half-open local times; may span days
    "$SJ" forget --term WhatsApp --term wnatsap [--apply]                  # case/diacritic-insensitive; removes whole window visits containing a term
    "$SJ" tidy --keep-days 7 [--apply]                                      # per-day sizes; slims days older than N (never today) to session/visit/note images
    "$SJ" rebuild                                                            # regenerates sessions, summaries, digests, index.md, week.md
    ```
    Without `--apply` every command is a dry run that prints what it would do. With `--apply` it quits the app, makes the change, rebuilds the affected summaries, prints what changed and the space freed, and reopens the app.

    ## Layout
    ```
    index.md                one line per day, newest first: active time, notes, top apps. Start here.
    week.md                 last 7 days: time per app, windows seen on 2+ days, frequent app and window switches, notes by day
    reviews/                saved results of earlier sessions (e.g. 2026-10-27-automations.md). Read before repeating work; save new results here.
    days/YYYY-MM-DD/
      summary.md            the day in prose: time per app, top windows, app and window switches, her notes
      .digest.json          the same, machine-readable (below)
      sessions.jsonl        focused stretches in one window: start, end, app, bundleID, windowTitle, frames, representativeFrame (image path)
      frames.jsonl          one row per distinct screen state per display (below)
      events.jsonl          one row per event (below)
      frames/HHMMSS-dN.heic screenshot of display N
    ```
    `frames.jsonl` and `events.jsonl` are the source of truth. The app rebuilds everything else from them: today's every 15 minutes, past days whose `.digest.json` is missing at launch and every hour, and all of it on `"$SJ" rebuild`.

    Fields with no value are left out of a row rather than written as null; use `// default` in jq.

    ### .digest.json
    `day`, `activeSeconds`, `sessionCount`, `apps` and `windows` as `[{name, seconds}]`, `transitions` (app to app) and `windowTransitions` (window to window, including browser tabs) as `[{from, to, count}]`, and `notes`. A window name is "App — Title", or just "App" without a title.

    ### frames.jsonl
    - `id`, `start`, `end`: how long this screen state lasted. `display`: which screen.
    - `focused`: true on the display with the frontmost app; false on a display where that app has no window. Time totals use focused rows only.
    - `app`, `bundleID`, `windowTitle`: the frontmost window on that display.
    - `image`: latest saved screenshot for that display, relative to the day folder. Consecutive rows may share one, so it can be up to a minute older than the row's text when little changed visually. A row owns its image when the filename matches its `id`. Images can be missing on slimmed or edited days.
    - `text`: full on-device OCR of the display, only on the first row after the window changed. It includes browser tabs, menus and popups; the content she was looking at is usually in the middle.
    - `newLines`: lines first seen in this window since its row with `text` (a line that scrolls away and back isn't repeated). Older days may have `textSameAs` instead.

    ### events.jsonl
    `at`, `kind`, and per kind: `started` (`version`), `stopped`, `appSwitch` (`app`, `bundleID`), `note` (`text`, plus the `app`, `bundleID`, `windowTitle` and `frameID` on screen when she wrote it). Gap markers: `paused`, `idle`, `locked`, `skipped` (private app or window in front), `active` (capture resumed).

    A `stopped` followed by `started` is the app restarting (an update or a quit), not a gap in her work. An `idle` at the same second as `started` means she was away when it relaunched.

    Notes are moments she flagged on purpose: the strongest signal in the journal.

    ## Reading cheaply
    Text first, images last. A week holds tens of thousands of rows; open a screenshot only to confirm something specific, a handful at a time. Timestamps are local ISO-8601 with offset, so plain string comparison orders them: compare to the second with `.start[0:19]`, or to the minute with `.start[0:16]`.

    ```sh
    # Notes with where she was
    jq -r 'select(.kind == "note") | "\(.at[0:16])  \(.app // "?") — \(.windowTitle // "")\n    \(.text)"' days/*/events.jsonl

    # Minutes per app between two dates (inclusive); the $(ls … awk …) part lists those days' digests for any recipe
    jq -rs '[.[].apps[]] | group_by(.name) | map({app: .[0].name, min: (map(.seconds) | add / 60 | round)}) | sort_by(-.min)[] | "\(.min)m\t\(.app)"' \
      $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}')

    # When something was on screen, as time ranges (q is a case-insensitive regex: list variants with |)
    jq -rs --arg q 'whats ?app|wnatsap' 'def t: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;
      [.[] | select([.windowTitle // "", .text // "", (.newLines // [])[]] | join("\n") | test($q; "i"))]
      | sort_by(.start)
      | reduce .[] as $r ([]; if length > 0 and ($r.start | t) - (.[-1].end | t) <= 120
          then .[-1].end = ([.[-1].end, $r.end] | max) | .[-1].where += [$r.app // "?"]
          else . + [{start: $r.start, end: $r.end, where: [$r.app // "?"]}] end)
      | .[] | "\(.start[0:10])  \(.start[11:16])–\(.end[11:16])  \(.where | unique | join(", "))"' days/*/frames.jsonl

    # Sessions in one app
    jq -r 'select(.app == "Microsoft Excel") | [.start[0:16], .end[11:16], .windowTitle] | @tsv' days/*/sessions.jsonl

    # The screen in front of her at a moment (to the second): the focused row covering it, or else the last one before it,
    # then that window's text so far (last row with `text` on that display, plus every later `newLines`)
    jq -rs --arg at 2026-10-21T15:00:00 '
      (map(select(.focused and .start[0:19] <= $at)) | (map(select(.end[0:19] >= $at)) | last) // last) as $row
      | if $row == null then "nothing captured yet at that time" else
          [.[] | select(.display == $row.display and .start <= $row.start)]
          | (map(has("text")) | rindex(true)) as $i
          | "\($row.start[11:19])–\($row.end[11:19])  \($row.app // "?") — \($row.windowTitle // "")\(if $row.end[0:19] < $at then "  (last screen before that time)" else "" end)",
            (if $i == null then "(no text)" else .[$i:] | .[0].text, (.[1:][].newLines // [] | .[]) end)
        end' days/2026-10-21/frames.jsonl

    # Durations from timestamps (the offset is the same on both ends, so drop it)
    jq -rs 'def t: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;
      group_by(.app) | map({app: (.[0].app // "Unknown"), min: (map((.end | t) - (.start | t)) | add / 60 | round)}) | sort_by(-.min)[] | "\(.min)m\t\(.app)"' \
      days/2026-10-21/sessions.jsonl

    # View a screenshot: Read can't open .heic, so convert a temporary local copy, Read it, then delete it.
    # A row's `image` may come from an earlier row in the same visit; its time is in the filename (HHMMSS).
    # Prefer rows that own their image: select(.image == "frames/\(.id).heic")
    mkdir -p /tmp/sj-view && sips -s format jpeg -Z 1600 days/2026-10-21/frames/185442-d1.heic --out /tmp/sj-view/185442-d1.jpg >/dev/null
    rm -rf /tmp/sj-view   # when done
    ```
    Use `.digest.json` for whole days and the duration recipe for part of a day.
    """#

    static let findAutomationsSkill = #"""
    ---
    name: find-automations
    description: Find repetitive computer work in this screen journal worth automating, rank it, and build the helpers she picks. Use when she asks what to automate, what's repetitive or boring, how to save time, or to build a shortcut, script, or skill for something she does.
    ---
    \#(marker)

    # Find automations

    Goal: a short ranked list of concrete automations, each backed by evidence from the journal, then working helpers for the ones she picks.

    ## 1. Orient
    - If `reviews/` exists, read every file in it. Carry forward what she already picked, built, or rejected; this run adds to it.
    - Count the captured days (`ls days | wc -l`). Under 3 days, tell her up front that this is an early look, and suggest coming back after a week of capture.
    - Read `index.md`, all notes (recipe in `CLAUDE.md`), and `week.md` (with one day of data, `week.md` repeats `summary.md`: skip it).
    - Ask her two or three short questions: what her job involves, which tools she must use as-is, what feels most tedious. Then end your turn and wait for her answers before step 2.

    ## 2. Find repetition
    Look for patterns across days. Check every lens:
    - **Ping-pong**: frequent A→B→A switches between windows, including browser tabs: `windowTransitions` in `.digest.json` and "Frequent window switches" in `summary.md` and `week.md`. Typical: copying between a spreadsheet and a web form, an email and a CRM.
    - **Recurring windows**: the same window title pattern at similar times on several days (`week.md` lists windows seen on 2+ days): daily reports, weekly exports.
    - **Rekeying**: the same email, ID, or amount showing up in two different windows within minutes. Per day, this prints each value seen in 2+ windows, with when and where:
      ```sh
      jq -r 'select(.focused and ((.app // "Unknown") | IN("Unknown", "UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "CoreServicesUIAgent", "loginwindow", "Screen Journal") | not))
        | "\(.app) — \(.windowTitle // "")" as $win | .start[11:16] as $t
        | [.text // "", (.newLines // [])[]] | join("\n")
        | (scan("[[:alnum:]._%+-]+@[[:alnum:]-]+\\.[[:alnum:].-]+"),
           scan("(?:R\\$|US\\$|\\$|€|£) ?[0-9][0-9.,]*[0-9]"),
           (scan("[[:alnum:]]{6,}") | select(test("[0-9]") and test("[^0-9]"))),
           scan("[0-9][0-9./-]{5,}[0-9]"))
        | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$|^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$|…") | not)
        | [., $win, $t] | @tsv' days/DAY/frames.jsonl \
      | sort -u | awk -F'\t' '!seen[$1 FS $2]++ { wins[$1]++; where[$1] = where[$1] "  " $3 " " $2 } END { for (k in wins) if (wins[k] > 1) print wins[k] "\t" k "\t" where[k] }' | sort -rn | head -40
      ```
      It skips system popups, version numbers, dates and short numbers. Add any other system popup apps you notice to the `IN(...)` list. Amounts are evidence: describe them ("the same amounts in the console and in WhatsApp"), don't quote them.
    - **Data entry**: one window visit with many frames, most of them adding `newLines` (form filling, spreadsheets). Per day:
      ```sh
      jq -rs 'def t: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;
        [.[] | select(.focused)] | sort_by(.start)
        | reduce .[] as $r ([]; ("\($r.app // "?") — \($r.windowTitle // "")") as $w | ($r.newLines // [] | length) as $n
            | if length > 0 and .[-1].window == $w
              then .[-1].end = $r.end | .[-1].frames += 1 | .[-1].lines += $n | .[-1].growing += (if $n > 0 then 1 else 0 end)
              else . + [{window: $w, start: $r.start, end: $r.end, frames: 1, lines: $n, growing: (if $n > 0 then 1 else 0 end)}] end)
        | map(select(.frames >= 6 and .growing >= .frames / 2))
        | sort_by(-.frames)[] | "\(.start[0:16])–\(.end[11:16])  \(((.end | t) - (.start | t)) / 60 | round)m  \(.frames) frames, \(.lines) new lines  \(.window)"' days/DAY/frames.jsonl
      ```
      Chats and terminals scroll too; keep visits where the new lines look like typed-in or pasted values.
    - **Flagged moments**: each note, plus what she did in the five minutes before it. Per day:
      ```sh
      jq -rn 'def t: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;
        [inputs] | map(select(.focused and .id)) as $frames
        | .[] | select(.kind == "note") | (.at | t) as $at
        | "\(.at[0:16])  NOTE: \(.text)",
          ($frames[] | select((.start | t) < $at and (.end | t) > $at - 300)
            | "    \(.start[11:19])  \(.app // "?") — \(.windowTitle // "")  \((.newLines // []) | join(" / ") | .[0:100])")' \
        days/DAY/events.jsonl days/DAY/frames.jsonl
      ```

    For each candidate collect: days seen, minutes per week, apps involved, two or three timestamps, and one screenshot you actually opened to confirm it (recipe in `CLAUDE.md`). Screenshots can show other people's chats; those stay unquoted.

    ## 3. Rank and save
    Score each candidate as weekly minutes × repeatability × feasibility. Feasibility means the data is reachable through an API, AppleScript, Shortcuts, browser automation, or files. Show her the top 5–10 as a table with one plain sentence each on how it would work, and say which look hard.

    Under 3 days of data, skip the score: list observed minutes and how many times each was seen, label each "early signal", and still say how it would work.

    `mkdir -p reviews`, then save the table and the evidence to `reviews/YYYY-MM-DD-automations.md` (today's date). Done when the file exists and she has seen the list.

    ## 4. Build what she picks
    Choose the simplest thing that works: a Claude Code skill in `~/.claude/skills/<name>/SKILL.md` (works from any folder), a script, a macOS Shortcut, or a text-replacement snippet. Walk her through the first run, step by step, until it worked once on her real work. Then add what was built, and how to start it, to the review file.

    ## Rules
    - Quote evidence with timestamps; propose only workflows the data shows.
    - Privacy rules in `CLAUDE.md` apply: screen text stays on this Mac, including inside anything you build.
    """#

    static let timeReportSkill = #"""
    ---
    name: time-report
    description: Report where her time went from the screen journal, by app, project, or window, for a day, a week, or any range; say what she was doing at a moment; or find when she saw something. Use when she asks where her time went, what she did last week or on Tuesday, how long she spent on something, what she was doing at 3pm, or when she last saw a page, person, or word.
    ---
    \#(marker)

    # Time report

    Turn the journal into a plain-language answer about her time. Recipes are in `CLAUDE.md`.

    ## Pick the branch
    - **A period** ("last week", "Tuesday", "this month") → Report.
    - **A moment** ("what was I doing at 3pm Tuesday") → Moment.
    - **A thing** ("when did I see the invoice from Rossi") → Seen.

    Turn named days into dates with `date` (e.g. `date -v-1w +%F`), and select those days' files with the date-range part of the minutes-per-app recipe in `CLAUDE.md`. Today's numbers can lag up to 15 minutes.

    ## Report
    1. Sum time per app from `.digest.json` across the days in range; for part of a day, sum `sessions.jsonl` durations instead.
    2. Group windows into projects. Two views help (set `from`/`to` to the period):
       ```sh
       # Minutes per window across the period
       jq -rs '[.[].windows[]] | group_by(.name) | map({name: .[0].name, min: (map(.seconds) | add / 60)}) | sort_by(-.min)[] | "\(.min | round)m\t\(.name)"' \
         $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}')

       # Keywords shared by 2+ window titles, with their minutes: candidate projects and clients
       jq -rs '[.[].windows[] | .seconds as $s | .name | sub("^[^—]+ — "; "") | ascii_downcase | [scan("[[:alpha:]]{4,}")] | unique[] | {word: ., s: $s}]
         | group_by(.word) | map({word: .[0].word, min: (map(.s) | add / 60 | round), titles: length}) | map(select(.titles > 1)) | sort_by(-.min)[:25][] | "\(.min)m\t\(.titles) titles\t\(.word)"' \
         $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}')
       ```
       Propose groups from recurring keywords (a client, a document, a site), show which windows fall in each, and ask her to confirm or rename them. Wait for her answer before step 3.
    3. Answer in a few plain sentences, then one small table (at most 10 rows: name, hours:minutes, share). Mention her notes from the period and the days with no capture.
    4. If an earlier `reviews/*-time.md` covers a comparable period, add one line on what changed.
    5. Save it with her confirmed groups: `mkdir -p reviews`, then `reviews/YYYY-MM-DD-time.md`. Save weekly or longer reports by default, day reports when she agrees.

    ## Moment
    1. List every session overlapping that minute, plus the one just before:
       ```sh
       jq -r --arg m 2026-10-21T15:00 'select(.start[0:16] <= $m and .end[0:16] >= $m) | "\(.start[11:19])–\(.end[11:19])  \(.app // "?") — \(.windowTitle // "")"' days/2026-10-21/sessions.jsonl
       ```
    2. Reconstruct the screen at that second with the moment recipe in `CLAUDE.md` (`--arg at 2026-10-21T15:00:00`).
    3. Describe it in one or two sentences. Open the screenshot only if she asks or the text is unclear.
    4. If the moment falls in a gap, say capture was off (paused, idle, locked, or private) and what came before and after.

    ## Seen
    1. Run the "when something was on screen" recipe in `CLAUDE.md`, with a few spelling and OCR variants joined by `|` (dropped or swapped letters, `rn`/`m`, `l`/`I`, spaces, accents).
    2. Answer with the days and time ranges and the apps, newest or most relevant first. Show the matching window titles if she wants detail.
    """#

    static let forgetSkill = #"""
    ---
    name: forget
    description: Permanently remove part of the screen journal, either a time range or everything about a word, including screenshots. Use when she asks to delete, forget, erase, or remove something: "forget yesterday between 2 and 3", "remove anything about my bank", "delete that conversation".
    ---
    \#(marker)

    # Forget

    Deletion is permanent. The app's `forget` command does the work (see Tools in `CLAUDE.md`); every step below is required, in order.

    ```sh
    SJ="/Applications/ScreenJournal.app/Contents/MacOS/ScreenJournal"
    ```

    ## 1. Pin down exactly what to remove
    - **Range**: restate it as local minutes, start included and end excluded. "Through 18:59" or "until 7" usually means the end minute is included, so suggest `--to` one minute later (`--to 2026-10-21T19:00`). A range may span days.
    - **Term**: restate the word or phrase. Tell her the command removes each whole visit to a window where it appears, not just the word.

    Confirmed when she says yes to your exact wording.

    ## 2. Find the variants (terms only)
    Screen text is OCR and has misreadings. Brainstorm spelling variants and OCR near-misses (`whatsap`, `wnatsap`, `whats app`; dropped or swapped letters, `rn`/`m`, `l`/`I`, `0`/`O`, accents), then count each:
    ```sh
    for v in whatsapp whatsap wnatsap 'whats app'; do printf '%s\t' "$v"; cat days/*/frames.jsonl | grep -i -F -c -- "$v"; done
    ```
    Then hunt OCR misreads with fragments of the term:
    ```sh
    jq -r '.windowTitle // empty, .text // empty, (.newLines // [])[]' days/*/frames.jsonl \
      | grep -ioE '[[:alnum:]]*(hatsap|atsapp|whats)[[:alnum:]]*' | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn
    ```
    For variants that hit, show her when and where with the "when something was on screen" recipe in `CLAUDE.md`. Add only clear misreads of the term; she picks which to include, and each becomes a `--term`.

    ## 3. Dry run
    ```sh
    "$SJ" forget --from 2026-10-21T18:57 --to 2026-10-21T19:00
    "$SJ" forget --term WhatsApp --term wnatsap
    ```
    Tell her in plain words:
    - the counts and the actual time edges, especially extra minutes removed because moments overlap the edges;
    - in one line per day, how much active time that day loses (the dry run lists the window visits);
    - for terms, that every whole visit mentioning it goes, including work windows.

    Ask for a clear yes.

    ## 4. Apply
    Run the same command with `--apply`. It quits and reopens the app and rebuilds the summaries itself. A non-zero exit means something still matches: show her what, and offer to run it again with a wider range or more variants.

    ## 5. Verify
    For terms, every variant she chose, with an `-e` each:
    ```sh
    grep -r -i -l -e whatsapp -e wnatsap days index.md week.md $(ls -d reviews 2>/dev/null)
    ```
    Expect no output. For a range, rerun the dry run: expect nothing left to remove. `grep -i` doesn't fold accents, so add accented variants as extra `-e`.

    If `reviews/` mentions it, show her those lines and offer to edit the files. Done when the check is clean; tell her what was removed in one or two sentences.

    Say what forget can't reach: copies outside this folder (Time Machine, other backups), and this folder's own instruction files (`CLAUDE.md`, `.claude/skills/`), which mention app names generically.
    """#

    static let tidyJournalSkill = #"""
    ---
    name: tidy-journal
    description: Show how much disk space the screen journal uses and slim down old days by deleting screenshots while keeping all text. Use when she says the folder is too big, her disk is full, or asks to clean up the journal.
    ---
    \#(marker)

    # Tidy journal

    The app's `tidy` command does the work (see Tools in `CLAUDE.md`).
    ```sh
    SJ="/Applications/ScreenJournal.app/Contents/MacOS/ScreenJournal"
    ```

    ## 1. Show the size
    ```sh
    du -sh days/* | sort -rh; du -sh .
    ```
    Tell her the total and the biggest days; screenshots are almost all of it. Mention **Settings → retention** in the app, which deletes whole days after that many days.

    ## 2. Pick what to keep in full
    Slimming a day keeps all its text, notes and summaries, and one screenshot per session, window visit and note; it deletes the rest. Ask how many recent days to keep in full (suggest 7). "Keep the last N days" means N full days before today, plus today.

    Check whether anything is older than that (`N` days):
    ```sh
    ls days | awk -v c="$(date -v-${N}d +%F)" '$0 < c'
    ```
    No output means nothing to slim yet: say so and stop.

    ## 3. Dry run, confirm, apply
    ```sh
    "$SJ" tidy --keep-days 7
    ```
    Tell her which days it slims and the space it would free, and wait for a yes. Then run the same command with `--apply` and tell her the space freed.
    """#
}
