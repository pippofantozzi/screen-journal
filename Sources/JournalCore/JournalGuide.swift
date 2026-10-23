/// Files the app keeps in the journal root so a Claude Code session there knows how to read it.
/// Bump `version` whenever the text changes; the app rewrites stale copies on launch.
public enum JournalGuide {
    public static let version = 14
    public static let marker = "<!-- screen-journal-guide v\(version) -->"
    /// A link the app refreshes at every launch to its own binary.
    public static let commandPath = ".claude/sj"

    public static let skills: [(name: String, contents: String)] = [
        ("find-automations", findAutomationsSkill),
        ("time-report", timeReportSkill),
        ("forget", forgetSkill),
        ("tidy-journal", tidyJournalSkill),
        ("autopilot", autopilotSkill),
    ]

    public static let files: [(path: String, contents: String)] =
        [("CLAUDE.md", claudeMD), (".claude/journal.jq", journalJQ)]
            + skills.map { (".claude/skills/\($0.name)/SKILL.md", $0.contents) }

    public static func isCurrent(_ contents: String) -> Bool { contents.contains(marker) }

    /// True for an older guide or a file without a marker; a newer guide stays.
    public static func shouldReplace(_ contents: String) -> Bool {
        guard let match = contents.firstMatch(of: /screen-journal-guide v(\d+) -->/), let found = Int(match.1) else { return true }
        return found < version
    }

    static let claudeMD = #"""
    \#(marker)
    # Screen Journal

    This folder is a passive record of one person's computer work, captured by the Screen Journal app on this Mac.
    The person talking to you is its owner. Read `profile.md` first when it exists: who they are, what they work on, the people and tools involved, and what they have agreed to. Without it, assume they are not a developer: speak plainly and skip jargon. Either way, say what you are about to do before running anything that deletes or changes files, and call the owner "they" unless the profile says otherwise.

    The app may be in Portuguese (the default). When you point them to it, use the names they see: Settings is Ajustes, Connect AI categorization is Conectar categorização por IA, Keep the last N days is Manter os últimos N dias, task kinds are Tipos de tarefa. The journal itself (kinds, labels, files) stays in English.

    ## Privacy
    - Everything here stays on this Mac. Screenshots and screen text never go to any website, API, or other service.
      The one exception is `label` (see Labels): it sends their own description of their work, each session's app, window title, duration, a short excerpt of its screen text (keys redacted) and the titles of the windows either side to a hosted decision model (`baseten/mammoth-1` through the Vercel AI Gateway; every request refuses providers that train on prompts). Unless they turned off "Send screenshots too" in Settings → Connect AI categorization, sessions with nothing redacted on screen go to `typesafe-ai/jev-1.14.0` with their screenshot instead. Once they save a key in Settings, the app runs the same labelling itself every hour on the last week, so most sessions are already labelled when you arrive. The key is the one they saved in Settings (the Keychain), or `AI_GATEWAY_API_KEY` in the environment; `label` reads it itself. Never look for it, print it, or ask them to paste it to you: if it's missing, send them to Settings → Connect AI categorization. Run it with `--apply` only after they have said yes to that and the yes is recorded under Consent in `profile.md`; `--titles-only` sends no screen text.
    - Keys and tokens in known formats (API keys, access tokens, JWTs) are replaced with `[redacted]` before screen text is written; IDs, hashes and order numbers are kept. Days captured before that change may still hold some: never repeat one, and tell the owner when you see one.
    - Their own work data (dashboards, product metrics, invoices they handle) is fine to summarize. Skip anything personal or medical, and never quote personal banking, card numbers or salaries. Describe money figures without quoting exact amounts unless they ask for them.
    - Other people's messages in chats, mail and any inbox (CRM consoles, support tools) are never quoted or summarized; describe them at window level: who, when, how often.
    - Skip anything else personal unless they raise it themselves.
    - Gaps in time mean paused, idle, locked, or a private app or private browsing window was in front. Password managers and apps they excluded are never captured. Leave gaps unexplained.

    ## Skills
    - `find-automations`: find repetitive work worth automating, then build the helpers they pick.
    - `time-report`: where their time went over a day or week, what they were doing at a moment, or when they saw something.
    - `forget`: permanently remove a time range, or everything mentioning a word, from the journal.
    - `tidy-journal`: see how much space the journal uses and slim down old days.
    - `autopilot`: the unattended daily pass that keeps `profile.md` and `reviews/candidates.jsonl` current and writes a short weekly digest; run by hand or on a schedule the owner approved.

    ## Tools
    The app binary has commands for changing the journal; use them through the skills. Run every command and recipe from the journal folder: `.claude/sj` is a link the app points at itself at every launch, so it is always the copy that is recording.
    ```sh
    .claude/sj forget --from 2026-10-21T18:57 --to 2026-10-21T19:00 [--apply]   # half-open local times; may span days
    .claude/sj forget --term "<word>" --term "<variant>" [--apply]              # case/diacritic-insensitive; removes whole window visits containing a term
    .claude/sj tidy --keep-days 7 [--apply]                                      # per-day sizes; slims days older than N (never today) to session/visit/note images
    .claude/sj rebuild                                                            # regenerates sessions, summaries, digests, index.md, week.md
    .claude/sj label [--day 2026-10-21] [--titles-only] [--apply]                # labels unlabelled sessions; prints time by task and where to look first
    ```
    `label` leaves the app running. Without `--apply` every command is a dry run that prints what it would do. With `--apply` it quits the app, makes the change, rebuilds the affected summaries, prints what changed and the space freed, and reopens the app.

    ## Layout
    ```
    profile.md              what Claude has learned about the owner (below). Read it first; missing until a skill writes it.
    projects.json           the owner's projects and the windows that belong to each (below)
    index.md                one line per day, newest first: active time, notes, top apps. Start here for the data.
    week.md                 last 7 days: time per app, windows seen on 2+ days, frequent app and window switches, notes by day
    reviews/                saved results of earlier sessions (e.g. 2026-10-27-automations.md). Read before repeating work; save new results here (`mkdir -p reviews` first: it may not exist yet).
    reviews/candidates.jsonl  automation candidates across every run, one per line with a status (below)
    days/YYYY-MM-DD/
      summary.md            the day in prose: time per app, top windows, app and window switches, their notes
      .digest.json          the same, machine-readable (below)
      sessions.jsonl        focused stretches in one window: start, end, app, bundleID, windowTitle, frames, representativeFrame (image path)
      frames.jsonl          one row per distinct screen state per display (below)
      events.jsonl          one row per event (below)
      frames/HHMMSS-dN.heic screenshot of display N
    labels.json             `about` (their words about their work) and `tasks` (their task kinds), both set in Settings (see Labels)
    days/YYYY-MM-DD/labels.jsonl   the model's answers per session (see Labels)
    .claude/journal.jq      shared jq helpers for the recipes below
    ```
    `frames.jsonl` and `events.jsonl` are the source of truth. The app rebuilds everything else from them: today's every 15 minutes, past days whose `.digest.json` is missing at launch and every hour, and all of it on `.claude/sj rebuild`.

    Fields with no value are left out of a row rather than written as null; use `// default` in jq.

    ### .digest.json
    `day`, `activeSeconds`, `sessionCount`, `apps` and `windows` as `[{name, seconds}]`, `transitions` (app to app) and `windowTransitions` (window to window, including browser tabs) as `[{from, to, count}]`, and `notes`. A window name is "App — Title", or just "App" without a title. Titles are stable: leading spinners and status glyphs and unread counters like "(3) " are stripped.

    ### frames.jsonl
    - `id`, `start`, `end`: how long this screen state lasted. `display`: which screen.
    - `focused`: true on the display with the frontmost app; false on a display where that app has no window. Time totals come from sessions (the digest is built from them); focused rows on two displays can overlap, so don't sum frames.
    - `app`, `bundleID`, `windowTitle`: the frontmost window on that display, title as captured (use `window` from `journal.jq` to match the summaries). A chat app's title adds the open chat from its header, `<chat> — <app>`, so each chat is its own window and session (`chatName` in `journal.jq` reads it); the app's name alone means no chat was open, or a day captured before this. No `app` means the desktop or a system screen, shown as "Unknown" in summaries.
    - `place`: what the focused window shows, when the owner allowed Accessibility: a terminal's or editor's folder or file (`~/code/verify`), or the page address a browser reports (Firefox-based browsers like Zen give only the site, `mail.google.com`). Absent on unfocused rows, on apps that don't say, and on days before this.
    - `image`: latest saved screenshot for that display, relative to the day folder. Consecutive rows may share one, so it can be up to a minute older than the row's text when little changed visually. A row owns its image when the filename matches its `id`. Images can be missing on slimmed or edited days.
    - `text`: full on-device OCR of the display, only on the first row after the window changed. It includes browser tabs, menus and popups; the content they were looking at is usually in the middle.
    - `newLines`: lines first seen in this window since its row with `text` (a line that scrolls away and back isn't repeated). Older days may have `textSameAs` instead.

    ### events.jsonl
    `at`, `kind`, and per kind: `started` (`version`), `stopped`, `appSwitch` (`app`, `bundleID`), `note` (`text`, plus the `app`, `bundleID`, `windowTitle` and `frameID` on screen when they wrote it). Gap markers: `paused`, `idle`, `locked`, `skipped` (private app or window in front), `active` (capture resumed).

    A `stopped` followed by `started` is the app restarting (an update or a quit), not a gap in their work. An `idle` at the same second as `started` means they were away when it relaunched.

    ### Labels
    `label` asks a decision model three questions about each session in one pass, about a second each. It sees `about` from `labels.json`, the session's app, window, duration and some screen text, and the windows just before and after it. Rows in `labels.jsonl`:
    - `session`: that session's `start`.
    - `work`: probability it is their work, judged against `about` (a client's Instagram can be work).
    - `automatable`: 0 to 1, how much of their effort agents could take over: 0 needs them, 1 could run unattended. Asked as if they had coding agents with skills and scripts, browser-use and computer-use agents, and scheduled jobs.
    - `task`: one kind from the defaults (design, content, planning, meeting, communication, outreach, research, admin, building, leisure) plus `tasks` in `labels.json`.
    - `def`: fingerprint of everything the model was told; editing `about` or `tasks` asks every session again.
    - `source`: `model` (text only), `look` (answered with the screenshot), or `agent` for your corrections.

    Per session a correction stands, else a `look` answer, else the latest line; `standing` in `journal.jq` does this.

    The dry run, `.claude/sj label`, prints time by task and **Where to look first**: windows ranked by duration × automatable × work. Start every search for automations there. It says which windows to read, not what happened: read their frames before claiming anything, and expect a few wrong answers.

    Sharpen it as you learn their work:
    - Work answers wrong for a kind of window: suggest a sentence for `about` to them ("Instagram and TikTok are client work"). They change it in Settings.
    - A recurring kind of work hiding inside a broad kind (reels inside design, invoices inside admin): suggest adding it to their task kinds in Settings.
    - To correct one session, append its line to that day's `labels.jsonl` with your change, the same `def`, and `"source": "agent"`.

    ```sh
    # One day's sessions by work time agents could take over, most first
    jq -L .claude -rn 'include "journal";
      [inputs] as $rows | ($rows | map(select(has("automatable"))) | standing | map({key: .session, value: .}) | from_entries) as $l
      | [$rows[] | select(has("frames")) | {s: ., l: $l[.start]} | select(.l)]
      | sort_by(-((.s.end | epoch) - (.s.start | epoch)) * .l.automatable * .l.work) | .[:20][]
      | "\(.s.start[11:16])–\(.s.end[11:16])  \(.l.task)  automatable \(.l.automatable * 100 | floor)%  work \(.l.work * 100 | floor)%  \(.s | window)"' days/DAY/labels.jsonl days/DAY/sessions.jsonl
    ```

    ### profile.md
    The memory between sessions: what the data showed and the owner confirmed, so no session has to ask again. Keep these headings, each a few short lines; mark anything not yet confirmed with "(guess)":
    ```
    # Profile
    Updated YYYY-MM-DD
    ## Owner                 role, kind of work, languages, whether they write code, how they like answers
    ## Consent               labelling: yes (YYYY-MM-DD) | titles only (YYYY-MM-DD) | no; schedule: approved (YYYY-MM-DD) | no
    ## Projects              per project: what it is, its folders and sites; which windows belong to it lives in `projects.json`
    ## People and channels   per person or group: kind (team, client, partner, personal), where (app, group), how often. Chat names come from window titles (`chatName` in `journal.jq`); a group's members are the line under its name in the screen text. Never message content
    ## Tools                 apps and sites they must use as they are
    ## Built                 helpers already built: what, where it lives, how it starts
    ## Open questions        at most five, newest first
    ```
    Any skill that learns something updates it. Write only what the data shows or the owner said; personal contacts go in as "personal" without a name.

    ### projects.json
    `{"projects": [{"name": "Verify", "match": "verify|doppler"}]}`: `match` is a case-insensitive regex over window names ("App — Title"). Terminal titles are often an agent's task name, so add task keywords and repo names as they show up. Keep it current whenever you group windows into projects; mark new ones `"confirmed": false` until the owner agrees. Minutes per project, and the biggest windows no project matches yet (a window matching two projects counts in both):
    ```sh
    jq -L .claude -rs --slurpfile p projects.json 'include "journal";
      [.[].windows[]] | group_by(.name) | map({name: .[0].name, s: (map(.seconds) | add)}) as $w
      | ($p[0].projects | map(.match as $m | {name, s: ($w | map(select(.name | test($m; "i")) | .s) | add // 0)}) | sort_by(-.s)[] | "\(.s | minutes)m\t\(.name)"),
        "Unassigned:", ($w | map(select(.name as $n | $p[0].projects | all(.match as $m | $n | test($m; "i") | not))) | sort_by(-.s)[:10][] | "  \(.s | minutes)m\t\(.name)")' days/*/.digest.json
    ```
    Swap `days/*/.digest.json` for a date range (minutes-per-app recipe) to cover a period.

    ### reviews/candidates.jsonl
    One automation candidate per line, rewritten in place: `id` (kebab-case), `title`, `status` (`seen`, `proposed`, `picked`, `built`, `rejected`), `firstSeen`, `lastSeen`, `days` (days seen), `timesSeen`, `observedMinutes` (total so far), `minutesPerWeek` (`observedMinutes` × 7 ÷ days captured, once 3+ days are captured), `apps`, `evidence` (`[{at, window}]`, at most five), `how` (one plain sentence), `measure` (`{metric, before, latest, at, goal}`, `at` the day of `latest`: the number a built helper should move, as a recipe or one-line command, and its values). Never pitch a `rejected` one again unless new evidence changed it; say what changed.

    Notes are moments they flagged on purpose: the strongest signal in the journal. A note made in Screen Journal itself (its `app`), or clearly about the app, is feedback on the app: pass it on as that, never as a work signal.

    ## Reading cheaply
    Text first, images last. A week holds tens of thousands of rows; open a screenshot only to confirm something specific, a handful at a time. Timestamps are local ISO-8601 with offset, so plain string comparison orders them: compare to the second with `.start[0:19]`, or to the minute with `.start[0:16]`.

    Recipes that need them load `.claude/journal.jq` with `jq -L .claude 'include "journal"; …'`: `epoch` (timestamp to seconds, for durations), `minutes` (seconds to whole minutes, rounded down like the summaries), `stableTitle` and `window` (a row's "App — Title" as the summaries name it), `terminal`, `chat` (a chat or mail window: never print its text), `chatOrTerminal`, `feed` (a social feed or video site), `standing` (labels).

    ```sh
    # Notes with where they were
    jq -L .claude -r 'include "journal"; select(.kind == "note") | "\(.at[0:16])  \(window)\n    \(.text)"' days/*/events.jsonl

    # Minutes per app between two dates (inclusive); the $(ls … awk …) part lists those days' digests for any recipe
    jq -L .claude -rs 'include "journal"; [.[].apps[]] | group_by(.name) | map({app: .[0].name, s: (map(.seconds) | add)}) | sort_by(-.s)[] | "\(.s | minutes)m\t\(.app)"' \
      $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}') < /dev/null

    # When something was on screen, as time ranges (q is a case-insensitive regex: the word and its variants joined with |).
    # Window-title matches come first; text-only matches can come from a tab bar or sidebar rather than what they were reading.
    # In terminals the OCR includes the tab bar, so a text-only match there is usually just another tab's name.
    jq -L .claude -rs --arg q '<word>|<variant>' 'include "journal";
      def ranges: sort_by(.start)
        | reduce .[] as $r ([]; if length > 0 and ($r.start | epoch) - (.[-1].end | epoch) <= 120
            then .[-1].end = ([.[-1].end, $r.end] | max) | .[-1].where += [$r | window]
            else . + [{start: $r.start, end: $r.end, where: [$r | window]}] end)
        | .[] | "  \(.start[0:10])  \(.start[11:16])\(if .end[11:16] == .start[11:16] then "" else "–" + .end[11:16] end)  \(.where | unique | join(", "))";
      [.[] | select(.focused)] | map(.inTitle = (.windowTitle // "" | test($q; "i"))) as $rows
      | "In window titles:", ($rows | map(select(.inTitle)) | ranges),
        "Only in screen text (may be a tab bar or sidebar):",
        ($rows | map(select((.inTitle | not) and ([.text // "", (.newLines // [])[]] | join("\n") | test($q; "i")))) | ranges)' days/*/frames.jsonl

    # Sessions in one app
    jq -r 'select((.app // "Unknown") == "<App>") | [.start[0:16], .end[11:16], .windowTitle] | @tsv' days/*/sessions.jsonl

    # The screen in front of them at a moment (to the second): the focused row covering it, or else the last one before it,
    # then that window's text so far (last row with `text` on that display, plus every later `newLines`)
    jq -L .claude -rs --arg at 2026-10-21T15:00:00 'include "journal";
      (map(select(.focused and .start[0:19] <= $at)) | (map(select(.end[0:19] >= $at)) | last) // last) as $row
      | if $row == null then "nothing captured yet at that time" else
          [.[] | select(.display == $row.display and .start <= $row.start)]
          | (map(has("text")) | rindex(true)) as $i
          | "\($row.start[11:19])–\($row.end[11:19])  \($row | window)\(if $row.end[0:19] < $at then "  (last screen before that time)" else "" end)",
            (if $i == null then "(no text)" else .[$i:] | .[0].text, (.[1:][].newLines // [] | .[]) end)
        end' days/2026-10-21/frames.jsonl

    # Minutes per app for part of a day, from session durations
    jq -L .claude -rs 'include "journal"; map(select(.start[0:16] >= "2026-10-21T14:00" and .start[0:16] < "2026-10-21T17:00"))
      | group_by(.app) | map({app: (.[0].app // "Unknown"), s: (map((.end | epoch) - (.start | epoch)) | add)}) | sort_by(-.s)[] | "\(.s | minutes)m\t\(.app)"' \
      days/2026-10-21/sessions.jsonl

    # View a screenshot: Read can't open .heic, so convert a temporary local copy, Read it, then delete it.
    # A row's `image` may come from an earlier row in the same visit; its time is in the filename (HHMMSS).
    # Prefer rows that own their image: select(.image == "frames/\(.id).heic")
    mkdir -p /tmp/sj-view && sips -s format jpeg -Z 1600 days/2026-10-21/frames/185442-d1.heic --out /tmp/sj-view/185442-d1.jpg >/dev/null
    rm -rf /tmp/sj-view   # when done
    ```
    Use `.digest.json` for whole days and session durations for part of a day.
    """#

    static let journalJQ = #"""
    # \#(marker)
    # Shared jq helpers for this journal. From the journal folder: jq -L .claude 'include "journal"; …'

    # Seconds for a local timestamp; the difference of two is a duration.
    def epoch: sub("[-+][0-9]{2}:[0-9]{2}$"; "Z") | fromdate;

    # Whole minutes, rounded down like the summaries.
    def minutes: . / 60 | floor;

    # A window title without what apps animate in it: leading spinners and status glyphs, and unread counters like "(3) " or " (12)".
    def stableTitle:
      if . == null then null else
        sub("^[\\s\\p{So}\\p{Mn}]+"; "") as $rest
        | if $rest == "" then null else
            ($rest | sub("^\\(\\d+\\+?\\)\\s+"; "") | sub("\\s+\\(\\d+\\)$"; "")) as $name
            | if $name == "" then $rest else $name end
          end
      end;

    # A row's window as the summaries name it: "App — Title", or "App"; "Unknown" is the desktop or a system screen.
    def window: [.app // "Unknown", (.windowTitle | stableTitle)] | map(select(. != null and . != "")) | join(" — ");

    # The answer that stands per session, from slurped labels.jsonl rows asked like the latest one: a correction, else one that saw the screenshot, else the latest line.
    def standing: (last.def) as $def | map(select(.def == $def)) | group_by(.session) | map((map(select(.source == "agent")) | last) // (map(select(.source == "look")) | last) // last);

    # A row in a terminal.
    def terminal: [.app, .bundleID] | map(. // "") | join(" ") | test("terminal|iterm|ghostty|warp"; "i");

    # A row in a chat or mail app, including web chats in a browser tab: other people's words, never shown.
    def chat:
      ([.app, .bundleID] | map(. // "") | join(" ") | test("whatsapp|telegram|slack|discord|signal|teams|MobileSMS|\\bmessages\\b|\\bmail\\b|outlook"; "i"))
      or (.windowTitle // "" | test("whatsapp|telegram|slack|discord|messenger|gmail|outlook|inbox"; "i"));

    def chatOrTerminal: chat or terminal;

    # The open chat's name from a title the app filled in from the chat's header ("Design team — WhatsApp"); empty otherwise.
    def chatName: .windowTitle // "" | capture("^(?<name>.+) — WhatsApp$").name // empty;

    # A row in a social feed or video site: scrolling, not typing.
    def feed: .windowTitle // "" | test(" / X$|^X$|LinkedIn|Instagram|Facebook|Reddit|YouTube|TikTok"; "i");
    """#

    static let findAutomationsSkill = #"""
    ---
    name: find-automations
    description: Find repetitive computer work in this screen journal worth automating, rank it, and build the helpers they pick. Use when they ask what to automate, what's repetitive or boring, how to save time, or to build a shortcut, script, or skill for something they do.
    ---
    \#(marker)

    # Find automations

    Goal: a short ranked list of concrete automations, each backed by evidence from the journal, then working helpers for the ones they pick.

    ## 1. Orient
    - Read `profile.md` and `reviews/candidates.jsonl` if they exist, then the other files in `reviews/`. Carry forward what they already picked, built, or rejected; this run adds to it.
    - Count the captured days first (`ls days | wc -l`). Under 3 days, tell them up front that this is an early look, and suggest coming back after a week of capture.
    - Read `index.md` and all notes (recipe in `CLAUDE.md`). Read `week.md` only with 2+ days; with one day it repeats `summary.md`.
    - If any `days/*/labels.jsonl` exists, run `.claude/sj label` (a dry run) for time by task, where to look first, and how many sessions are still unlabelled. Offer to label those only if they have already agreed to labelling (Privacy in `CLAUDE.md`).
    - Unattended (nobody to answer): don't ask; work from `profile.md` and add your questions to its Open questions. Otherwise ask only what `profile.md` doesn't answer yet, at most three short questions: what their job involves, which tools they must use as they are, what feels most tedious. Then end your turn and wait for their answers before step 2, and write the answers into `profile.md`.

    ## 2. Find repetition
    Look for patterns across days. Check every lens:
    - **Ping-pong**: frequent A→B→A switches between windows, including browser tabs: `windowTransitions` in `.digest.json` and "Frequent window switches" in `summary.md` and `week.md`. Typical: copying between a spreadsheet and a web form, an email and a CRM.
    - **People**: who they spend time with and how it's spread: minutes and visits per chat. A chat they visit many times a day, briefly, is a channel worth a digest or a notification rule; a chat that follows a work window (a console, an inbox) is part of that flow. Record people and groups in `profile.md`.
      ```sh
      jq -L .claude -rs 'include "journal";
        map(select(chatName)) | group_by(chatName)
        | map({chat: (.[0] | chatName), visits: length, s: (map((.end | epoch) - (.start | epoch)) | add)})
        | sort_by(-.s)[] | "\(.s | minutes)m  \(.visits) visits  \(.chat)"' days/*/sessions.jsonl
      ```
    - **Places**: the folders and sites work happens in, which tie terminal tabs and browser tabs to projects better than titles do:
      ```sh
      jq -L .claude -rs 'include "journal";
        map(select(.focused and .place)) | group_by(.place)
        | map({p: .[0].place, s: (map((.end | epoch) - (.start | epoch)) | add)})
        | sort_by(-.s)[:15][] | "\(.s | minutes)m  \(.p)"' days/*/frames.jsonl
      ```
    - **Glances**: a short visit (under a minute) to another window and straight back. Many glances to one chat from work windows usually mean waiting on something (an agent, a build, a reply) or watching for messages; a notification when the thing finishes removes them. Across days:
      ```sh
      jq -L .claude -rs 'include "journal";
        sort_by(.start) | [range(1; length - 1) as $i | {a: .[$i - 1], b: .[$i], c: .[$i + 1]}
          | select((.a | window) == (.c | window) and (.b | window) != (.a | window) and ((.b.end | epoch) - (.b.start | epoch)) < 60
            and ((.c.start | epoch) - (.a.end | epoch)) < 120)
          | {to: (.b | window), s: ((.b.end | epoch) - (.b.start | epoch)), from: (.a | window), at: .b.start[5:16]}]
        | group_by(.to) | map({to: .[0].to, n: length, s: (map(.s) | add), from: (map(.from) | unique | length), at: (map(.at) | .[:3] | join(", "))})
        | sort_by(-.n)[:10][] | "\(.n)×  \(.s | floor)s  \(.to)  from \(.from) windows, e.g. \(.at)"' days/*/sessions.jsonl
      ```
    - **Recurring windows**: the same window title pattern at similar times on several days (`week.md` lists windows seen on 2+ days): daily reports, weekly exports. With one day of data, skip it and say in one line that it needs a second day.
    - **Rekeying**: the same email, ID, or amount showing up in two different windows within minutes. Per day, this prints each value seen in 2+ windows, with time, window and row id per window (a row that owns its screenshot when there is one):
      ```sh
      jq -L .claude -r 'include "journal";
        select(.focused and ((.app // "Unknown") | IN("Unknown", "UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "CoreServicesUIAgent", "loginwindow", "Screen Journal") | not))
        | window as $win | .start[11:16] as $t | .id as $id | (if .image == "frames/\(.id).heic" then 0 else 1 end) as $borrowed
        | [.text // "", (.newLines // [])[]] | join("\n")
        | scan("[[:alnum:]._%+-]+@[[:alnum:]-]+\\.[[:alnum:].-]+|(?:R\\$|US\\$|\\$|€|£) ?[0-9][0-9.,]*[0-9]|[0-9][0-9./-]{5,}[0-9]|[[:alnum:]]{6,}")
        | select(test("[0-9]") and (test("^[0-9]+\\.[0-9]+\\.[0-9]+$|^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$") | not))
        | [., $win, $borrowed, $t, $id] | @tsv' days/DAY/frames.jsonl \
      | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3n -k4,4 \
      | awk -F'\t' '!seen[$1 FS $2]++ { wins[$1]++; where[$1] = where[$1] "  " $4 " " $2 " [" $5 "]" }
          END { for (k in wins) if (wins[k] > 1) { m = substr(k, 3); gsub(/[[:alnum:]]/, "*", m); print wins[k] "\t" substr(k, 1, 2) m "\t" where[k] } }' | sort -rn | head -40
      ```
      It matches each value once (a whole amount, never its bare digits) and prints it masked after its first two characters, so the shape (an amount, an email, an ID) shows but the value doesn't; it skips system popups, version numbers, dates and short numbers. To confirm, open the image of the printed row id. Add any other system popup apps you notice to the `IN(...)` list. Amounts are evidence: describe them ("the same amounts in the console and in a chat"), don't quote them.
    - **Data entry**: one window visit with many frames, most of them adding `newLines` (form filling, spreadsheets). Terminals, chat apps and social feeds scroll rather than fill forms, so `chatOrTerminal` and `feed` leave them out. Per day:
      ```sh
      jq -L .claude -rs 'include "journal";
        [.[] | select(.focused)] | sort_by(.start)
        | reduce .[] as $r ([]; ($r | window) as $w | ($r.newLines // [] | length) as $n
            | if length > 0 and .[-1].window == $w
              then .[-1].end = $r.end | .[-1].frames += 1 | .[-1].lines += $n | .[-1].growing += (if $n > 0 then 1 else 0 end)
              else . + [{window: $w, start: $r.start, end: $r.end, frames: 1, lines: $n, growing: (if $n > 0 then 1 else 0 end), skip: ($r | chatOrTerminal or feed), new: []}] end
            | .[-1].new += ($r.newLines // []))
        | map(select(.frames >= 6 and .growing >= .frames / 2 and (.skip | not)))
        | sort_by(-.frames)[] | "\(.start[0:16])–\(.end[11:16])  \((.end | epoch) - (.start | epoch) | minutes)m  \(.frames) frames, \(.lines) new lines  \(.window)",
          (.new | [.[0], .[length / 2 | floor], .[-1]] | unique[] | "    \(.[0:80])")' days/DAY/frames.jsonl
      ```
      Each visit prints up to 3 sample new lines. Keep the visit only if the samples look like values they entered (names, amounts, codes, sentences); hover tooltips, menus and scrolled-in page text mean it isn't data entry. The samples are for your judgement; describe them to them, don't quote them.
    - **Labels** (days with `labels.jsonl`): start from Where to look first in `.claude/sj label`, then the day's top sessions with the labels recipe in `CLAUDE.md`. Read their text and frames; a label alone is never evidence.
    - **Flagged moments**: each note, with up to 3 screens with text from the five minutes before it and 1 after. Per day:
      ```sh
      jq -L .claude -rn 'include "journal";
        [inputs] | (map(select(.focused and .id and (has("text") or has("newLines")))) | sort_by(.start)) as $frames
        | .[] | select(.kind == "note") | (.at | epoch) as $at
        | "\(.at[0:16])  NOTE: \(.text)",
          ((($frames | map(select((.start | epoch) < $at and (.end | epoch) > $at - 300)) | .[-3:])
            + ($frames | map(select((.start | epoch) >= $at)) | .[:1]))[]
          | "    \(.start[11:19])  \(window)  \(if chat then "(chat: text not shown)" else .newLines // [(.text // "") | split("\n")[0]] | join(" / ") | .[0:100] end)")' \
        days/DAY/events.jsonl days/DAY/frames.jsonl
      ```

    For each candidate collect: days seen, minutes per week, apps involved, two or three timestamps, and one screenshot you actually opened to confirm it (recipe in `CLAUDE.md`). Screenshots can show other people's chats; those stay unquoted.

    ## 3. Rank and save
    Score each candidate as weekly minutes × repeatability × feasibility. Feasibility means the data is reachable through an API, AppleScript, Shortcuts, browser automation, or files. Show them the top 5–10 as a table with one plain sentence each on how it would work, and say which look hard.

    Under 3 days of data, skip the score: list observed minutes and how many times each was seen, label each "early signal", and still say how it would work.

    `mkdir -p reviews`, then save the table and the evidence to `reviews/YYYY-MM-DD-automations.md` (today's date), and add or update each candidate in `reviews/candidates.jsonl` (`proposed` once they have seen it). Done when both files are written and they have seen the list.

    If a label was wrong in a way a sentence would fix, or a recurring task deserves its own kind, suggest the `about` sentence or task kind to them (see Labels in `CLAUDE.md`).

    ## 4. Build what they pick
    Choose the simplest thing that works: a Claude Code skill in `~/.claude/skills/<name>/SKILL.md` (works from any folder), a script, a macOS Shortcut, or a text-replacement snippet. If the profile says they write code, Claude Code hooks, command-line tools and small local apps are on the menu too. Before building, write the candidate's `measure`: the number from the journal it should move (glances to a chat per active hour, minutes in a window) and its value now. Test it where it lives first (run it by hand on a real case from the journal), install it only after their yes, then walk them through the first run, step by step, until it worked once on their real work. Put the install and first-run steps in a README beside it. Then add what was built, and how to start it, to the review file and to Built in `profile.md`, and set the candidate to `built`.

    ## Rules
    - Quote evidence with timestamps; propose only workflows the data shows.
    - Privacy rules in `CLAUDE.md` apply: screen text stays on this Mac, including inside anything you build.
    """#

    static let timeReportSkill = #"""
    ---
    name: time-report
    description: Report where their time went from the screen journal, by app, project, or window, for a day, a week, or any range; say what they were doing at a moment; or find when they saw something. Use when they ask where their time went, what they did last week or on Tuesday, how long they spent on something, what they were doing at 3pm, or when they last saw a page, person, or word.
    ---
    \#(marker)

    # Time report

    Turn the journal into a plain-language answer about their time. Recipes are in `CLAUDE.md`.

    ## Pick the branch
    - **A period** ("last week", "Tuesday", "this month") → Report.
    - **A moment** ("what was I doing at 3pm Tuesday") → Moment.
    - **A thing** ("when did I see the invoice from Rossi") → Seen.

    Turn named days into dates with `date` (e.g. `date -v-1w +%F`), and select those days' files with the date-range part of the minutes-per-app recipe in `CLAUDE.md`. Today's numbers can lag up to 15 minutes.

    ## Report
    1. Sum time per app from `.digest.json` across the days in range; for part of a day, sum `sessions.jsonl` durations instead.
    2. Group windows into projects. If `projects.json` exists, run its recipe in `CLAUDE.md` and only propose groups for the unassigned windows. Two views help (set `from`/`to` to the period):
       ```sh
       # Minutes per window across the period
       jq -L .claude -rs 'include "journal"; [.[].windows[]] | group_by(.name) | map({name: .[0].name, s: (map(.seconds) | add)}) | sort_by(-.s)[] | "\(.s | minutes)m\t\(.name)"' \
         $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}') < /dev/null

       # Keywords shared by 2+ window titles, with their minutes: candidate projects and clients
       jq -L .claude -rs 'include "journal"; [.[].windows[]] | group_by(.name) | map(select(.[0].name | test(" — "))) | [.[] | (map(.seconds) | add) as $s | .[0].name | sub("^[^—]+ — "; "") | ascii_downcase | [scan("[[:alpha:]]{4,}")] | unique[] | {word: ., s: $s}]
         | group_by(.word) | map({word: .[0].word, min: (map(.s) | add | minutes), titles: length}) | map(select(.titles > 1)) | sort_by(-.min)[:25][] | "\(.min)m\t\(.titles) titles\t\(.word)"' \
         $(ls -d days/* | awk -v from=2026-10-15 -v to=2026-10-21 '{d = substr($0, 6)} d >= from && d <= to {print $0 "/.digest.json"}') < /dev/null
       ```
       Propose groups from recurring keywords (a client, a document, a site) and show which windows fall in each.
       With labels, `.claude/sj label --day <day>` prints time by task: a second view by kind of work beside projects.
       - Several days: ask them to confirm or rename the groups, and wait for their answer before step 3.
       - One day: go straight on; show the groups and the table together in step 3.
    3. Answer in a few plain sentences, then one small table (at most 10 rows: name, hours:minutes, share). Mention their notes from the period and the days with no capture.
    4. If an earlier `reviews/*-time.md` covers a comparable period, add one line on what changed.
    5. Save it with the groups they confirmed: `mkdir -p reviews`, then `reviews/YYYY-MM-DD-time.md`, and write the groups to `projects.json`. Save reports of several days by default; for one day, offer to save.

    ## Moment
    1. List the session just before that minute and every session overlapping it:
       ```sh
       jq -L .claude -rs --arg m 2026-10-21T15:00 'include "journal"; (map(select(.end[0:16] < $m)) | last // empty), (.[] | select(.start[0:16] <= $m and .end[0:16] >= $m))
         | "\(.start[11:19])–\(.end[11:19])  \(window)"' days/2026-10-21/sessions.jsonl
       ```
    2. Reconstruct the screen at that second with the moment recipe in `CLAUDE.md` (`--arg at 2026-10-21T15:00:00`).
    3. Describe it in one or two sentences. Open the screenshot only if they ask or the text is unclear.
    4. If the moment is before the first day in `days/`, say the journal hadn't started yet. If it falls in a gap, say capture was off (paused, idle, locked, or private) and what came before and after.

    ## Seen
    1. Run the "when something was on screen" recipe in `CLAUDE.md`, with a few spelling and OCR variants joined by `|` (dropped or swapped letters, `rn`/`m`, `l`/`I`, spaces, accents).
    2. Answer with the days and time ranges and the windows, newest or most relevant first. Lead with window-title matches; present text-only matches as "also visible on screen", since they can be a tab bar or sidebar.
    """#

    static let forgetSkill = #"""
    ---
    name: forget
    description: Permanently remove part of the screen journal, either a time range or everything about a word, including screenshots. Use when they ask to delete, forget, erase, or remove something: "forget yesterday between 2 and 3", "remove anything about my bank", "delete that conversation".
    ---
    \#(marker)

    # Forget

    Deletion is permanent. The app's `forget` command does the work (see Tools in `CLAUDE.md`); every step below is required, in order.

    ## 1. Pin down exactly what to remove
    - **Range**: restate it as local minutes, start included and end excluded. "Through 18:59" or "until 7" usually means the end minute is included, so suggest `--to` one minute later (`--to 2026-10-21T19:00`). A range may span days.
    - **Term**: restate the word or phrase. Tell them the command removes each whole visit to a window where it appears, not just the word.

    Confirmed when they say yes to your exact wording.

    ## 2. Find the variants (terms only)
    Screen text is OCR and has misreadings. Brainstorm variants of `<word>` and OCR near-misses (dropped or swapped letters, a split into two words, `rn`/`m`, `n`/`h`, `l`/`I`, `0`/`O`, accents), then count each:
    ```sh
    for v in '<word>' '<variant>' '<variant 2>'; do printf '%s\t' "$v"; cat days/*/frames.jsonl | grep -i -F -c -- "$v"; done
    ```
    Then hunt OCR misreads with overlapping fragments of the term (its first half, its second half, its middle):
    ```sh
    jq -r '.windowTitle // empty, .text // empty, (.newLines // [])[]' days/*/frames.jsonl \
      | grep -ioE '[[:alnum:]]*(<fragment>|<fragment>|<fragment>)[[:alnum:]]*' | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn
    ```
    For a hit that is cut off (the term missing its first letter, say), show them the line around it so they can judge:
    ```sh
    jq -r '.windowTitle // empty, .text // empty, (.newLines // [])[]' days/*/frames.jsonl | grep -i -w -m 3 -B1 -A1 -- '<hit>'
    ```
    For variants that hit, show them when and where with the "when something was on screen" recipe in `CLAUDE.md`. Add only clear misreads of the term; they pick which to include, and each becomes a `--term`.

    ## 3. Dry run
    ```sh
    .claude/sj forget --from 2026-10-21T18:57 --to 2026-10-21T19:00
    .claude/sj forget --term "<word>" --term "<variant>"
    ```
    Tell them in plain words:
    - the counts and the actual time edges, especially extra minutes removed because moments overlap the edges;
    - in one line per day, how much active time that day loses (each day's line reads "Xm active → Ym");
    - for terms, that every whole visit mentioning it goes, including work windows (the dry run lists them).

    If a day loses more than a quarter of its active time, say so plainly and offer narrower options: a more specific term (a group or contact name rather than the app name), or forgetting only a time range. Then ask for a clear yes.

    ## 4. Apply
    Run the same command with `--apply`. It quits and reopens the app and rebuilds the summaries itself. A non-zero exit means something still matches: show them what, and offer to run it again with a wider range or more variants.

    ## 5. Verify
    For terms, every variant they chose, with an `-e` each:
    ```sh
    grep -r -i -l --exclude=CLAUDE.md --exclude=labels.json --exclude=profile.md --exclude=projects.json --exclude-dir=.claude --exclude-dir=reviews -e '<word>' -e '<variant>' .
    ```
    Expect no output. Forget also drops the labels of every removed session. If the word is in `labels.json`, tell them where, so they can change it in Settings. It leaves out `CLAUDE.md` and `.claude/` on purpose: they are this guide, not their journal, and `.claude/journal.jq` names chat and terminal apps in order to skip them. If they search the whole folder themselves, tell them that. For a range, rerun the dry run: expect nothing left to remove. `grep -i` doesn't fold accents, so add accented variants as extra `-e`.

    If `reviews/`, `profile.md` or `projects.json` mention it (`grep -r -i -n -e '<word>' reviews profile.md projects.json`), show them those lines and offer to edit the files. Done when the check is clean; tell them what was removed in one or two sentences.

    Say what forget can't reach: copies outside this folder (Time Machine, other backups), and this folder's own instruction files (`CLAUDE.md`, `.claude/skills/`), which mention app names generically.
    """#

    static let autopilotSkill = #"""
    ---
    name: autopilot
    description: The unattended daily pass over the screen journal. It labels new sessions, updates the profile and the automation candidates, and on Mondays writes a short weekly digest, so after a week or two Claude knows what to focus on and what to automate. Use when run on a schedule ("/autopilot"), when they ask what Claude has learned about their work so far, or to set up or stop the schedule.
    ---
    \#(marker)

    # Autopilot

    No one is there to answer: never ask and wait. Write questions to Open questions in `profile.md` instead. Text first; open at most three screenshots a run, only to confirm a candidate.
    ```sh
    mkdir -p reviews/autopilot
    ```

    ## Every run
    1. **Catch up.** The days to do are those after the day in `reviews/autopilot/last-run` (every day if it's missing), up to and including yesterday. Nothing to do: stop.
    2. **Label.** If Consent in `profile.md` says labelling yes, run `.claude/sj label --apply` (`--titles-only` if that's what they agreed to); without the key it exits saying so, and the run goes on without labelling. Otherwise don't label, and use labels already in the journal. If Consent says nothing about labelling, add the question to Open questions once. If answers look wrong for a kind of window, add the `about` sentence or task kind that would fix it to Open questions (Labels in `CLAUDE.md`).
    3. **Look.** For each day, run the find-automations lenses: flagged moments, glances, ping-pong, rekeying, data entry, labels. Add or update `reviews/candidates.jsonl` (new ones `seen`; bump `lastSeen`, `days`, `minutesPerWeek`, evidence). Update the `measure` of every `built` candidate.
    4. **Learn.** Run the projects recipe; give unassigned windows of 15+ minutes a project in `projects.json` (`"confirmed": false`). Add what the day showed to `profile.md`, marked "(guess)": people and channels by name and kind from window titles (never message content), tools. Remove guesses the data no longer supports.
    5. **Log.** Append one line per day to `reviews/autopilot/log.md`: date, active time, top three projects, new candidates. Write the last day you did (yesterday, as YYYY-MM-DD) to `reviews/autopilot/last-run`.

    ## Mondays (or 7+ days since the last digest)
    Only once 7 or more days are captured; before that, the log is enough. Write `reviews/YYYY-MM-DD-week.md` for the owner, readable in a minute:
    - where the week went, from the projects recipe, in three lines;
    - the top three candidates (`seen` or `proposed`, ranked by score as in find-automations step 3) with days seen, minutes per week and how each would work, marked `proposed`;
    - what changed for each `built` helper, from its `measure`;
    - the open questions, at most five.

    ## Never on autopilot
    `forget`, `tidy --apply`, building or installing a helper, anything that contacts a person, a website or a service (`label` with recorded consent aside). These wait for the owner, through find-automations.

    ## The schedule
    Only after the owner says yes; record it under Consent. It runs every morning on this Mac (cloud routines can't read this folder, and the data stays here). Find the `claude` path with `command -v claude`, then write `~/Library/LaunchAgents/com.screenjournal.autopilot.plist`:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>Label</key><string>com.screenjournal.autopilot</string>
      <key>ProgramArguments</key><array>
        <string>/bin/zsh</string><string>-lc</string>
        <string>cd "$HOME/ScreenJournal" &amp;&amp; CLAUDE_PATH -p /autopilot --allowedTools "Read,Write,Edit,Bash(jq:*),Bash(ls:*),Bash(date:*),Bash(mkdir:*),Bash(sips:*),Bash(rm -rf /tmp/sj-view),Bash(sort:*),Bash(awk:*),Bash(grep:*),Bash(head:*),Bash(printf:*),Bash(.claude/sj label:*)"</string>
      </array>
      <key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
      <key>StandardOutPath</key><string>/tmp/screenjournal-autopilot.log</string>
      <key>StandardErrorPath</key><string>/tmp/screenjournal-autopilot.log</string>
    </dict></plist>
    ```
    Replace `CLAUDE_PATH`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.screenjournal.autopilot.plist`. A Mac asleep at 9:00 runs it on wake. To stop: `launchctl bootout gui/$(id -u)/com.screenjournal.autopilot` and delete the file. Labelling on the schedule needs the AI Gateway key saved in Settings → Connect AI categorization; without it, the runs skip labelling. Test once by hand with `launchctl kickstart gui/$(id -u)/com.screenjournal.autopilot` and read the log.
    """#

    static let tidyJournalSkill = #"""
    ---
    name: tidy-journal
    description: Show how much disk space the screen journal uses and slim down old days by deleting screenshots while keeping all text. Use when they say the folder is too big, their disk is full, or ask to clean up the journal.
    ---
    \#(marker)

    # Tidy journal

    The app's `tidy` command does the work (see Tools in `CLAUDE.md`).
    ## 1. Dry run
    ```sh
    .claude/sj tidy --keep-days 7
    ```
    It prints the journal's size, then what slimming would free, listing only days older than the cutoff. Use only these numbers. Tell them the total and the biggest days.

    Say plainly: slimming frees little, because the app already keeps one screenshot per unchanged screen. The real lever for size is **Settings → Keep the last N days**, which deletes whole days after that many days.

    If it says there is nothing old enough yet, tell them so and stop.

    ## 2. Pick what to keep in full
    Slimming a day keeps all its text, notes and summaries, and one screenshot per session, window visit and note; it deletes the rest, and every slimmed moment then shows its visit's kept screenshot. "Keep the last N days" means N full days before today, plus today; today is never slimmed. Suggest 7; if they pick another N, rerun the dry run with it.

    ## 3. Confirm, apply
    Tell them which days it slims and the space it would free, and wait for a yes. Then run the same command with `--apply` and tell them the space freed.
    """#
}
