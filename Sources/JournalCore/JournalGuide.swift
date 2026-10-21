/// Files the app keeps in the journal root so a Claude Code session there knows how to read it.
/// Bump `version` whenever the text changes; the app rewrites stale copies on launch.
public enum JournalGuide {
    public static let version = 2
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
    The person talking to you is that person. She is not a developer: speak plainly, skip jargon, and say what you are about to do before running anything that deletes or changes files.

    ## Privacy
    - Everything here stays on this Mac. Screenshots and screen text never go to any website, API, or other service.
    - Skip anything personal, medical, financial, or other people's private messages unless she raises it herself.
    - Gaps in time mean paused, idle, locked, or a private app or private browsing window was in front. Password managers and apps she excluded are never captured. Leave gaps unexplained.

    ## Skills
    - `find-automations`: find repetitive work worth automating, then build the helpers she picks.
    - `time-report`: where her time went over a day or week, or what she was doing at a given moment.
    - `forget`: permanently remove a time range, or everything mentioning a word, from the journal.
    - `tidy-journal`: see how much space the journal uses and slim down old days.

    ## Layout
    ```
    index.md                one line per day, newest first: active time, notes, top apps. Start here.
    week.md                 last 7 days: time per app, windows seen on 2+ days, frequent app switches, notes by day
    reviews/                saved results of earlier sessions (e.g. 2026-10-27-automations.md). Read before repeating work; save new results here.
    days/YYYY-MM-DD/
      summary.md            the day in prose: time per app, top windows, app switches, her notes
      .digest.json          the same, machine-readable: activeSeconds, apps/windows [{name, seconds}] (window name is "App — Title", or just "App"), transitions [{from, to, count}], notes
      sessions.jsonl        focused stretches in one window: start, end, app, bundleID, windowTitle, frames, representativeFrame (image path)
      frames.jsonl          one row per distinct screen state per display (below)
      events.jsonl          one row per event (below)
      frames/HHMMSS-dN.heic screenshot of display N
    ```
    `frames.jsonl` and `events.jsonl` are the source of truth. The app rebuilds `sessions.jsonl`, `summary.md`, `.digest.json`, `index.md` and `week.md` from them: today's every 15 minutes, and any past day whose `.digest.json` is missing at launch and every hour.

    Fields with no value are left out of a row rather than written as null; use `// default` in jq.

    ### frames.jsonl
    - `id`, `start`, `end`: how long this screen state lasted. `display`: which screen.
    - `focused`: true on the display with the frontmost app. Time totals use focused rows only.
    - `app`, `bundleID`, `windowTitle`: the frontmost window on that display.
    - `image`: latest saved screenshot for that display, relative to the day folder. Consecutive rows may share one; a row owns its image when the filename matches its `id`. Images can be missing on slimmed or edited days.
    - `text`: full on-device OCR of the display, only on the first row after the window changed.
    - `newLines`: lines first seen in this window since its row with `text` (a line that scrolls away and back isn't repeated). Older days may have `textSameAs` instead.

    ### events.jsonl
    `at`, `kind`, and per kind: `started` (`version`), `stopped`, `appSwitch` (`app`, `bundleID`), `note` (`text`, plus the `app`, `bundleID`, `windowTitle` and `frameID` on screen when she wrote it). Gap markers: `paused`, `idle`, `locked`, `skipped` (private app or window in front), `active` (capture resumed).

    Notes are moments she flagged on purpose: the strongest signal in the journal.

    ## Reading cheaply
    Text first, images last. A week holds tens of thousands of rows; open a screenshot only to confirm something specific, a handful at a time. Timestamps are local ISO-8601 with offset, so plain string comparison orders them (`.start < "2026-10-21T15:00"`).

    ```sh
    # Notes with where she was
    jq -r 'select(.kind == "note") | "\(.at[0:16])  \(.app // "?") — \(.windowTitle // "")\n    \(.text)"' days/*/events.jsonl

    # Minutes per app over the last 7 days
    jq -rs '[.[].apps[]] | group_by(.name) | map({app: .[0].name, min: (map(.seconds) | add / 60 | round)}) | sort_by(-.min)[] | "\(.min)m\t\(.app)"' \
      $(ls -d days/* | tail -7 | sed 's|$|/.digest.json|')

    # Every moment a word was on screen
    grep -i -F -h 'invoice' days/*/frames.jsonl | jq -r '[.start[0:16], .app, .windowTitle] | @tsv'

    # Sessions in one app
    jq -r 'select(.app == "Microsoft Excel") | [.start[0:16], .end[11:16], .windowTitle] | @tsv' days/*/sessions.jsonl

    # Everything seen in the window on display 1 so far at a moment: last row with `text`, plus every later `newLines`
    jq -rs --arg at 2026-10-21T15:00 --argjson display 1 '
      [.[] | select(.display == $display and .start <= $at)]
      | (map(has("text")) | rindex(true)) as $i
      | .[$i:] | (.[0].text, (.[1:][].newLines // [] | .[]))' days/2026-10-21/frames.jsonl

    # Durations from timestamps (the offset is the same on both ends, so drop it)
    jq -rs 'def t: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;
      group_by(.app) | map({app: .[0].app, min: (map((.end | t) - (.start | t)) | add / 60 | round)}) | sort_by(-.min)[] | "\(.min)m\t\(.app)"' \
      days/2026-10-21/sessions.jsonl
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
    - Read every file in `reviews/` named `*-automations.md`. Carry forward what she already picked, built, or rejected; this run adds to it.
    - Read `week.md`, `index.md`, and all notes (recipe in `CLAUDE.md`).
    - Ask her two or three short questions: what her job involves, which tools she must use as-is, what feels most tedious. Done when you know her role and her fixed tools.

    ## 2. Find repetition
    Look for patterns across days. Check every lens:
    - **Ping-pong**: frequent A→B→A switches (`transitions` in `.digest.json`, `appSwitch` events): copying between a spreadsheet and a web form, an email and a CRM.
    - **Recurring windows**: the same window title pattern at similar times on several days (`week.md` lists windows seen on 2+ days): daily reports, weekly exports.
    - **Rekeying**: the same ID, email, or amount appearing in two different apps within minutes. Per day:
      ```sh
      jq -r 'select(.focused) | [.app, .start[11:16]] as [$app, $t]
        | ((.text // "") + "\n" + ((.newLines // []) | join("\n")))
        | scan("[[:alnum:]._%+-]+@[[:alnum:].-]+|[0-9][0-9.,/-]{3,}")
        | [., $app, $t] | @tsv' days/DAY/frames.jsonl \
      | sort -u | awk -F'\t' '!seen[$1 FS $2]++ { apps[$1]++; where[$1] = where[$1] "  " $2 " " $3 } END { for (k in apps) if (apps[k] > 1) print k "\t" where[k] }'
      ```
    - **Data entry**: long sessions in one window with many frames, each adding a few `newLines`.
    - **Flagged moments**: each note, plus the focused rows from the five minutes before it (`select(.focused and .start < $at and .end > $fiveMinutesBefore)`).

    For each candidate collect: days seen, minutes per week, apps involved, two or three timestamps, and one screenshot you actually opened to confirm it.

    ## 3. Rank and save
    Score each candidate as weekly minutes × repeatability × feasibility. Feasibility means the data is reachable through an API, AppleScript, Shortcuts, browser automation, or files. Show her the top 5–10 as a table with one plain sentence each on how it would work, and say which look hard.

    Save the table and the evidence to `reviews/YYYY-MM-DD-automations.md` (today's date). Done when the file exists and she has seen the list.

    ## 4. Build what she picks
    Choose the simplest thing that works: a Claude Code skill in `~/.claude/skills/<name>/SKILL.md` (works from any folder), a script, a macOS Shortcut, or a text-replacement snippet. Walk her through the first run, step by step, until it worked once on her real work. Then add what was built, and how to start it, to the review file.

    ## Rules
    - Quote evidence with timestamps; propose only workflows the data shows.
    - Privacy rules in `CLAUDE.md` apply: screen text stays on this Mac, including inside anything you build.
    """#

    static let timeReportSkill = #"""
    ---
    name: time-report
    description: Report where her time went from the screen journal, by app, project, or window, for a day, a week, or any range, or say what she was doing at a specific moment. Use when she asks where her time went, what she did last week or on Tuesday, how long she spent on something, or what she was doing at 3pm.
    ---
    \#(marker)

    # Time report

    Turn the journal into a plain-language answer about her time. Recipes are in `CLAUDE.md`.

    ## Pick the branch
    - **A period** ("last week", "Tuesday", "this month") → Report.
    - **A moment** ("what was I doing at 3pm Tuesday") → Moment.

    Turn named days into dates with `date` (e.g. `date -v-1w +%F`). Today's numbers can lag up to 15 minutes.

    ## Report
    1. Sum time per app from `.digest.json` across the days in range; for part of a day, sum `sessions.jsonl` durations instead.
    2. Group windows into projects: clients, documents, or sites that recur in `windowTitle`. Ask her to confirm or rename the groups when they are guesses.
    3. Answer in a few plain sentences, then one small table (at most 10 rows: name, hours:minutes, share). Mention her notes from the period and the days with no capture.
    4. If an earlier `reviews/*-time.md` covers a comparable period, add one line on what changed.
    5. Offer to save it as `reviews/YYYY-MM-DD-time.md`; save weekly or longer reports by default.

    ## Moment
    1. Find the session that spans the moment in that day's `sessions.jsonl` (`.start <= $at and .end > $at`), plus the ones just before and after.
    2. Reconstruct the screen text at that moment (recipe in `CLAUDE.md`) for the focused display.
    3. Describe it in one or two sentences. Open the screenshot only if she asks or the text is unclear.
    4. If the moment falls in a gap, say capture was off (paused, idle, locked, or private) and what came before and after.
    """#

    static let forgetSkill = #"""
    ---
    name: forget
    description: Permanently remove part of the screen journal, either a time range or every moment a word appears, including screenshots. Use when she asks to delete, forget, erase, or remove something: "forget yesterday between 2 and 3", "remove anything about my bank", "delete that conversation".
    ---
    \#(marker)

    # Forget

    Deletion here is permanent. Every step below is required, in order.

    ## 1. Pin down exactly what to remove
    Restate it back to her as a precise **range** (day plus start and end time, e.g. `2026-10-21T14:00` to `2026-10-21T15:00`) or **term** (exact word or phrase; check spelling variants and accents with her). Confirmed when she says yes to your exact wording.

    If the range or term touches today, ask her to choose **Pause** in the Screen Journal menu bar first, and to resume when you are done.

    ## 2. Show what will go
    Per affected day, count matching rows in `frames.jsonl`, `events.jsonl` and `sessions.jsonl`, plus screenshots. List the screenshots that will be deleted: every `image` named by a matching frames row.

    Range, in the day folder (`FROM`/`TO` set to the confirmed times):
    ```sh
    jq -c --arg from "$FROM" --arg to "$TO" 'select(.start < $to and .end > $from)' frames.jsonl | wc -l
    jq -c --arg from "$FROM" --arg to "$TO" 'select(.at >= $from and .at < $to)' events.jsonl | wc -l
    jq -r --arg from "$FROM" --arg to "$TO" 'select(.start < $to and .end > $from) | .image' frames.jsonl | sort -u
    ```
    Term (`TERM_` set to the confirmed term):
    ```sh
    grep -i -F -c -- "$TERM_" frames.jsonl events.jsonl sessions.jsonl
    grep -i -F -h -- "$TERM_" frames.jsonl | jq -r .image | sort -u
    ```
    Tell her the counts in plain words and ask her to confirm the deletion.

    ## 3. Remove it
    Work one day folder at a time, deleting screenshots first (their list comes from the rows about to go). Each command writes a temp file and only replaces the original if the filter succeeded.

    Range:
    ```sh
    jq -r --arg from "$FROM" --arg to "$TO" 'select(.start < $to and .end > $from) | .image' frames.jsonl | sort -u | while read -r img; do rm -f -- "$img"; done
    for f in frames sessions; do jq -c --arg from "$FROM" --arg to "$TO" 'select((.start < $to and .end > $from) | not)' $f.jsonl > $f.jsonl.tmp && mv $f.jsonl.tmp $f.jsonl; done
    jq -c --arg from "$FROM" --arg to "$TO" 'select((.at >= $from and .at < $to) | not)' events.jsonl > events.jsonl.tmp && mv events.jsonl.tmp events.jsonl
    ```
    Term:
    ```sh
    grep -i -F -h -- "$TERM_" frames.jsonl | jq -r .image | sort -u | while read -r img; do rm -f -- "$img"; done
    for f in frames events sessions; do grep -v -i -F -- "$TERM_" $f.jsonl > $f.jsonl.tmp; [ $? -le 1 ] && mv $f.jsonl.tmp $f.jsonl; done
    ```

    ## 4. Refresh the summaries
    - Today: the app rebuilds the summaries within 15 minutes of resuming.
    - Past days: delete that day's `summary.md`, `.digest.json` and `sessions.jsonl`, the app rebuilds them within the hour, or right away if she quits Screen Journal from the menu bar and opens it again.
    - A term can also sit in `reviews/` or in files you or she wrote. Show her those lines and offer to edit them.

    ## 5. Verify
    ```sh
    grep -r -i -F -l -- "$TERM_" .     # term: expect no output
    ```
    For a range, re-run the step 2 counts: expect 0 rows and no listed screenshots left on disk. Done when the check is clean; tell her what was removed, in one or two sentences, and remind her to resume capture if she paused it.

    A screenshot can show text that OCR missed, so a term search can miss some; say so if the term matters a lot to her, and offer to remove the whole time range instead.
    """#

    static let tidyJournalSkill = #"""
    ---
    name: tidy-journal
    description: Show how much disk space the screen journal uses and slim down old days by deleting screenshots while keeping all text. Use when she says the folder is too big, her disk is full, or asks to clean up the journal.
    ---
    \#(marker)

    # Tidy journal

    ## 1. Show the size
    ```sh
    du -sh days/* | sort -k2 -r; du -sh .
    ```
    Tell her the total, the biggest days, and that screenshots are almost all of it. Mention the app's **Settings → keep days** option, which deletes whole days after that many days.

    ## 2. Offer to slim old days
    Slimming a day keeps all its text, notes and summaries, and keeps one screenshot per session plus the screenshot at each note; it deletes the other screenshots. Ask her how many recent days to keep in full (suggest 7). Today is always kept in full.

    ## 3. Slim, after she confirms
    Show the list of days and the space it frees, and wait for a yes. Then, per day folder older than the cutoff:
    ```sh
    if [ -s sessions.jsonl ]; then
      { jq -r '.representativeFrame' sessions.jsonl
        jq -rn --slurpfile ev events.jsonl '[$ev[] | select(.kind == "note") | .frameID] as $ids | inputs | select(.id | IN($ids[])) | .image' frames.jsonl
      } | sort -u > .keep
      find frames -name '*.heic' | grep -v -x -F -f .keep | while read -r img; do rm -f -- "$img"; done
      rm .keep
    else
      echo "skipped $(basename "$PWD"): no sessions.jsonl"
    fi
    ```
    Tell her about any skipped day.

    ## 4. Clean the rest
    `find . -name .DS_Store -delete` and remove leftover `*.tmp` files under `days/`.

    Done when `du -sh .` shows the new total; tell her how much space was freed.
    """#
}
