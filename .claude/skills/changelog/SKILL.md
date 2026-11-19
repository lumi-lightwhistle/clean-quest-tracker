---
name: changelog
description: Write the changelog entry, pull request title and Discord-ready release notes for Clean Quest Tracker. Gives each section a short overview of what was added or changed for players, and goes into detail only where players need it. Use when preparing a pull request, a release, or when the user asks for a changelog or release notes.
---

# Changelog and release notes

Players read this, not developers. They want to know what is different when they open the game.

## How the project's changelog works

`CHANGELOG.md` is written by release-please from the titles of merged pull requests (Conventional Commits). Do not edit `CHANGELOG.md` by hand; the next release would overwrite or conflict with it. What can be controlled is the pull request title, optional override lines in the pull request body, and the release notes text given to the user.

Sections come from `.github/release-please-config.json`:

| Prefix | Section | Shown |
|---|---|---|
| `feat:` | ✨ New | yes |
| `fix:` | 🐛 Fixed | yes |
| `perf:` | ⚡ Faster | yes |
| `refactor:` `docs:` `chore:` `ci:` `test:` | Under the hood, Docs, Chores, CI, Tests | hidden from players |

Only `feat`, `fix` and `perf` make a release.

## The style

1. **One headline per change, written as an overview.** Say what a player gets, in plain words. "Search box redesigned to sit on the bar with a single glowing line", not "added LINE_STOPS and PaintLine".
2. **Group related work under one headline.** Five commits that all touch the quest icons are one bullet about quest icons, not five.
3. **Detail only where it earns its place.** Add indented sub-bullets under a headline only when a player must know something: a setting that moved, a default that changed, something that behaves differently for people on a certain preset. Two or three sub-bullets at most. If the headline says it all, stop.
4. **Say what changed for existing players.** Anything that alters how their current setup looks or behaves gets named, even if small.
5. **Name settings the way the settings window does** (page, then setting), so players can find them.
6. **Leave out** internal refactors, tool changes, file moves and test notes. They belong in the hidden sections.
7. No marketing words, no version history, no apologies. Short sentences, active voice.

## Steps

1. Read what changed: `git log --oneline <last tag>..HEAD` and `git diff --stat <last tag>..HEAD` (the last tag is `git describe --tags --abbrev=0`), or the working tree if nothing is committed yet. Read the actual diff for anything that touches settings, defaults, presets or migrations, since those are the changes players notice.
2. Sort every change into New, Fixed, Faster or hidden, and merge related changes into one headline each.
3. Decide, for each headline, whether it needs sub-bullets, using rule 3.
4. Produce, in this order:
   - the **pull request title** for the change (`feat: ...`, one line, written for players, because it becomes the changelog line);
   - the **changelog preview**, as it would read in `CHANGELOG.md`;
   - the **Discord release notes** in a fenced code block so the user can copy them (see the template).
5. If a single pull request carries several unrelated headlines, suggest putting override lines in the pull request body so each becomes its own changelog entry:

   ```
   BEGIN_COMMIT_OVERRIDE
   feat: first headline
   feat: second headline
   fix: a fix
   END_COMMIT_OVERRIDE
   ```

6. Ask the user to confirm the wording. Do not commit, push or tag.

## Discord release notes template

```
**Clean Quest Tracker <version>**

**New**
- Headline.
  - Detail only if needed.

**Fixed**
- Headline.

**Faster**
- Only if there is a `perf` change.

**Worth knowing**
- Only if something changes for people who change nothing, such as a new default.
```

Use the version from the release-please Release PR (or write "next release" if there isn't one yet). Leave out any section that has nothing in it, and keep "Worth knowing" to real changes to existing setups.
