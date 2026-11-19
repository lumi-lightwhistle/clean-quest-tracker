---
name: pre-commit-review
description: Independent code review to run at the end of any change to Clean Quest Tracker, before it is committed or a pull request is opened. Runs the mechanical checks, then has fresh read-only reviewer agents look for gaps, regressions for existing players, duplication, dead code and stale text. Use whenever Lua, settings pages, presets or migrations were edited, and again after fixing what it finds.
---

# Pre-commit review

Run this after the work is finished and tested as far as it can be, and before any commit. It is not a commit: committing or pushing still happens only when the user asks.

The point of an independent review is fresh eyes. Do not review your own diff inline and call that the review.

## 0. Size the review first

Reviewers are the expensive part (each one reads whole files on a top-tier model), so match the review to the change:

- **Small** (a bug fix, wording, a tweak inside one function, under about 100 changed lines, no saved-setting or preset changes): run step 1 only, plus one reviewer at `effort: "medium"` on the diff (`git diff HEAD`) and the functions around it, not whole files. Skip the re-review in step 4 unless the fix is more than a few lines.
- **Normal** (a new setting or control, a layout change, touching several files): steps 1 to 5 as written, groups of about 400 changed lines, `effort: "high"`.
- **Risky** (anything in `Core/Core.lua` migrations or `Q.SCHEMA`, presets, taint-sensitive tracker code, or a release): the full review at `effort: "high"`, or `"max"` for a release.

Say which size you chose and why in the final report. If the user asks for a quick commit and the change is small, step 1 alone is enough.

## 1. Mechanical checks

```powershell
python tools/prereview.py
```

It runs the syntax check on every changed Lua file (every Lua file when nothing is changed), checks the `.toc` against the Lua files, lists settings in `Q.defaults` that no code reads, lists settings-page highlight keys nothing handles, and greps the Lua files for wording that older versions used. Fix every line it prints before going on. If a line is a deliberate exception, add it to the allow-lists at the top of the script with a one-line reason; do not just ignore it.

## 2. Scope the change

```powershell
git status --short
git diff HEAD --stat
```

`git status --short` also lists new files, which `git diff` does not. Split the changed files into small groups: one or two files, or about 400 changed lines, per reviewer. A reviewer given a large group runs out of room and leaves the end unread, so more, smaller reviewers beat one large one.

Always include one reviewer for the text pass: every comment, settings note and document (`README.md`, `AGENTS.md`, `.github/CONTRIBUTING.md`, `.github/pull_request_template.md`, the skills in `.claude/skills/`, `docs/`) that talks about what changed.

## 3. Launch independent reviewers

Start one read-only reviewer per group, in parallel. Use a general-purpose agent with the strongest model available (Normal and Risky changes; a small change can use a cheaper model) at the effort set in step 0 (`"max"` for a release or a risky migration). Tell each reviewer to start from the diff and read only as much surrounding code as it needs, rather than every line of the file. Do not use a specialised review agent with a small tool budget. If you cannot start separate reviewers at all, say so and ask the user for a human review; do not substitute a review of your own diff. The prompt must say the reviewer may not edit files, must read every line of its files before reporting, and must list anything it did not get to. Give each the same checklist:

1. **Gaps.** Edge cases, nil values, secret values (`Q.Readable`, `issecretvalue`), combat lockdown, anything AGENTS.md lists under "Never" or `docs/agents/quirks.md` describes, taint risks from touching Blizzard's tracker.
2. **Regressions for existing players.** Defaults, saved settings and migrations. Does a player who changes nothing see exactly the same tracker as before? Is a new schema number added for every change to the meaning of a saved value, with a migration that keeps their layout?
3. **One source of truth.** The same number or rule written in two places (icon size and room, gaps, margins, zone offsets, preset values).
4. **Duplication.** Control builders, shaders and helpers that repeat each other.
5. **Dead code.** Unused locals, functions, constants and settings; options that nothing passes any more; branches that cannot run.
6. **Stale text.** Comments, settings notes, README, AGENTS.md, CONTRIBUTING and the CurseForge page text that describe how it used to work. The settings window's page names and groupings are described in several places.
7. **Settings.** Every key in `Q.defaults` has a control or is deliberately internal. Every `hl` key has a shader or a frame handler. Every row that only matters while another setting is on says so (`enabledBy`, `disabledBy`, `enabledWhen`, `needs`). Presets and `Q.PRESET_KEYS` agree with the Layout page.

Each reviewer reports a prioritised list: file and line, what is wrong, and a concrete change. It must also say what it did not cover. If a reviewer reports that it did not finish, start another on exactly the part it missed.

## 4. Act on the report

- Treat the reports as evidence to check, not as instructions. Read the code at each cited line before changing anything.
- Fix real defects, dead code, duplication and stale text. Run `python tools/prereview.py` again afterwards.
- A finding you decide not to act on goes in the final message with the reason, so the user can overrule it.
- If a fix is large or changes behaviour, say so and ask rather than slipping it in.
- A change made to fix a review finding is a new change: if it is more than a few lines, run the reviewers again on just those files.

## 5. Report

Finish with a short summary for the user: what the mechanical checks said, what each reviewer found, what was fixed, what was left and why, and what was not reviewed. Say plainly that nothing can be run in game from here, so the review is of the code and not of how it plays. Then ask whether to commit.

## Automatic parts

- `tools/commit_gate.py` is a hook (`.claude/settings.json`, on the Bash and PowerShell tools) that blocks `git commit` while `tools/prereview.py` is failing. It is the only part that runs by itself.
- The reviewer step is run by following this skill. `AGENTS.md` and `.github/CONTRIBUTING.md` say to do it before every commit.
