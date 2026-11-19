# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Layout

The repository root is the add-on folder. `CleanQuestTracker.toc` lists the load order.

| Folder | What's in it |
|---|---|
| `Core/` | Settings, defaults, presets, migrations and events |
| `Tracker/` | The quest list and its parts: zones, pools, quest items, motion, search, progress bars and party detection |
| `UI/` | The tracker frame, the search box and the settings window |
| `Media/` | Textures |
| `tools/` | Dev scripts (not shipped) |
| `docs/` | The CurseForge page text and icons (not shipped) |

A new Lua file must be listed in the `.toc` with its folder, for example `Tracker\TrackerZones.lua`. CI fails if a file is missing from the `.toc` or the `.toc` lists one that doesn't exist.

## Trying a change in game

Nothing here can run the game, so test in WoW.

```powershell
.\tools\deploy.ps1 -AddOns "C:\path\to\World of Warcraft\_forever_\Interface\AddOns"
```

That copies the add-on into the AddOns folder you name. Edits need `/reload`; new files (Lua or `.tga`) need a full game restart. Point it at a test install if you want your live copy left alone.

## Before you open a pull request

- Run `python tools/luacheck.py <file>.lua` on every Lua file you changed. CI runs it on all of them.
- Run `python tools/prereview.py` for the wider mechanical checks (load order, settings nothing reads, unhandled highlight keys, stale wording in the Lua files). It checks the files you changed, or every Lua file if nothing is changed; `--all` checks every file.
- If you use Claude Code, the skills in `.claude/skills/` do the rest: `pre-commit-review` runs independent reviewer agents over your change before you commit, and `changelog` drafts the pull request title and release notes. A hook (`tools/commit_gate.py`, on the Bash and PowerShell tools) stops `git commit` while the mechanical checks fail.
- Never modify Blizzard's own objective tracker (its methods, pools or templates). It causes taint errors. The add-on draws its own list and hides Blizzard's with a secure state driver.
- Quest item buttons are secure: do not move layout while they are on screen in combat.
- Say in the pull request how you tested it in game.

## Pull request titles

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `perf: ...`, `refactor: ...`, `docs: ...`, `chore: ...`, `ci: ...`, `test: ...`. A check enforces it. Pull requests are squash-merged, and the title becomes the line in the changelog, so write it for players: `fix: party count wrong after /reload`.

## How releases work

Only player-facing changes make a release: merged `feat`, `fix` and `perf` changes collect in a "Release PR" that sets the next version in the `.toc` and writes `CHANGELOG.md`. Merging that PR tags the release and starts the Package workflow, which builds `CleanQuestTracker-<version>.zip` and uploads it to GitHub and CurseForge. Only the maintainer merges it.
