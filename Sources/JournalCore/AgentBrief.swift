/// The prompt Settings copies for any coding agent: where the journal lives, how to read it,
/// and the gates to pass (understand, interview, approval) before it builds agents, skills or routines for her.
public enum AgentBrief {
    public static func prompt(root: String, language: Language) -> String {
        let skills = JournalGuide.skills.map { "`\($0.name)`" }.joined(separator: ", ")
        return #"""
        # Build my agents from my Screen Journal

        Help me turn my Screen Journal into agents, skills and routines that take repetitive computer work off my plate. Work through four gates, in order, without skipping one: understand, interview, propose, build. Nothing gets created, installed, scheduled or connected until I've approved it by name.

        ## Where everything is
        Screen Journal is a Mac menu-bar app that records my screen: a snapshot every few seconds when something changed, with on-device OCR of the text, the app and window in front, and (when allowed) the folder or site it shows. All of it lives on this Mac, in one folder. Work from there: `cd "\#(root)"`.

        - `\#(root)/CLAUDE.md`: the manual. Read it in full first: privacy rules, file layout, what each field means, and tested `jq` recipes for every search below. If you are Claude Code, start the session in that folder so the manual and the skills load by themselves.
        - `\#(root)/profile.md`: what earlier sessions learned about me and what I consented to. May not exist yet.
        - `\#(root)/index.md` and `week.md`: one line per day, and the last 7 days. Start the data here.
        - `\#(root)/days/YYYY-MM-DD/`: one folder per day.
          - `summary.md`: the day in prose.
          - `.digest.json`: time per app and window, and the switches between them.
          - `sessions.jsonl`: focused stretches in one window.
          - `frames.jsonl`: every distinct screen state with its text. The source of truth.
          - `events.jsonl`: notes I flagged, pauses, gaps.
          - `labels.jsonl`: AI labels per session (work, automatable, task).
          - `frames/*.heic`: screenshots.
        - `\#(root)/reviews/`: results of earlier sessions. `reviews/candidates.jsonl` tracks every automation candidate and its status.
        - `\#(root)/projects.json` and `labels.json`: my projects, and how I describe my work.
        - `\#(root)/.claude/skills/`: skills that already exist: \#(skills). Reuse them; don't rebuild what they do.
        - `\#(root)/.claude/journal.jq`: helpers the recipes load with `jq -L .claude 'include "journal"; …'`.
        - `\#(root)/.claude/sj`: the app's command line (`forget`, `tidy`, `rebuild`, `label`). A dry run unless given `--apply`; see Tools in `CLAUDE.md`.

        ## How to read it
        - Text first, screenshots last. A week is tens of thousands of rows: query with `jq`, never read `frames.jsonl` whole. Open a screenshot only to confirm a specific finding (convert a temporary copy with `sips`, as in `CLAUDE.md`, then delete it).
        - Count the days first (`ls days | wc -l`). Under a week, tell me the picture is early.
        - Read in this order: `profile.md`, `reviews/`, `index.md`, `week.md`, my notes (`"kind": "note"` in `events.jsonl`: moments I flagged on purpose, the strongest signal), then `.claude/sj label` (a dry run: time by task and where to look first), then the sessions and frames of the windows that matter.
        - Look through every lens in `.claude/skills/find-automations/SKILL.md`, each with its recipe: ping-pong between two windows, glances at a chat while waiting on something, the same values retyped across windows, data entry, windows that recur on several days, the people and channels I spend time with, the folders and sites the work happens in.
        - Timestamps are local ISO-8601, so plain string comparison orders them. A missing field means no value: use `// default` in `jq`.

        ## Privacy
        Follow the Privacy section of `CLAUDE.md` exactly. In short: screen text and screenshots stay on this Mac, inside anything you build too. Never quote other people's messages, personal banking or exact amounts; describe chats at window level (who, when, how often). Never look for, print or ask me to paste an API key.

        ## Gate 1: Understand
        Read the manual and the data before saying anything about my work. Then give me your model in a few lines: what I do, my projects and tools, the people and channels, where my hours go each week, and the 5 to 10 most repetitive things you saw, each with days seen, minutes per week and two timestamps as evidence.

        ## Gate 2: Interview me
        Grill me until we share one picture. Ask one question at a time, each with your best guess so I can just confirm or correct it. Cover:
        - my job, my goals, and what I'd hate to lose control of;
        - the tools that must stay as they are;
        - for each candidate: how it works today, its edge cases, how often it goes wrong, and what done looks like;
        - the accounts and services an agent would need, and whether I may connect them.

        Mirror back what you heard ("here's what I understand: a, b, c"). When my answer and the data disagree, say so and show the evidence. Write what's confirmed into `profile.md` (format in `CLAUDE.md`) as we go. Move on only when I say the picture is right.

        ## Gate 3: Propose, then wait for my approval
        Propose the smallest set that removes the most repetitive minutes. For each item:
        - **What**: a skill, an agent (a skill with its tools and permissions), a script, a routine (a scheduled run), or a connection (an MCP server, an API, a Shortcut, browser automation).
        - **Why**: the evidence, and the minutes per week it saves.
        - **How**: trigger, inputs, steps, output, and what it never does on its own.
        - **Where**: the exact paths it will live at.
        - **From me**: the logins, keys and permissions it needs, and how I'd give them.
        - **Measure**: the number in the journal it should move, and its value today.
        - **Risk**: what could go wrong, and how to undo it.

        Rank them, mark the hard ones, save the proposal to `reviews/YYYY-MM-DD-agents.md` and update `reviews/candidates.jsonl`. Then ask which to build, and stop until I answer.

        ## Gate 4: Build what I approved, one at a time
        - The simplest thing that works: a deterministic script beats an agent, a skill beats a long prompt, one job per skill.
        - **Skills**: `~/.claude/skills/<name>/SKILL.md` to work from any folder, or `\#(root)/.claude/skills/<name>/SKILL.md` when it's about the journal. Frontmatter with `name` (the folder's name) and a `description` of what it does and when to use it, in the words I'd actually say. Body: goal, numbered steps, done-when, rules. Scripts sit beside it and it calls them.
        - **Agents**: the fewest tools and permissions they need, read-only by default. Anything that sends, posts, pays or deletes either asks me first or drafts it for me to send.
        - **Routines**: run on this Mac with launchd, since cloud runs can't read this folder; the `autopilot` skill shows the pattern, with a narrow `--allowedTools`. Ask before scheduling anything.
        - **Connections**: tell me exactly what to click or run to connect each service (sign-in, OAuth, a key), then pause until I say it's done. Keys go in the Keychain or the tool's own settings, never in this chat, in this folder, or in a prompt.
        - Test each one on a real case from the journal before installing it, then walk me through its first real run until it works. Put a short README beside it: what it does, how to start it, how to turn it off.
        - Record it: under Built in `profile.md`, and as `built`, with its `measure`, in `reviews/candidates.jsonl`.

        Talk to me in \#(language.name), plainly, unless `profile.md` says I write code. Start with Gate 1 now.
        """#
    }
}
