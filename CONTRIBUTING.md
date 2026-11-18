# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Layout

The repository root is the add-on. `CleanQuestTracker.toc` lists the load order, the `.lua` files are the code and `Media/` holds the textures. `tools/` has dev scripts and `docs/` has the CurseForge page text; neither ships in the add-on zip.

## Trying a change in game

Nothing here can run the game, so test in WoW.

```powershell
.\tools\deploy.ps1 -AddOns "C:\path\to\World of Warcraft\_forever_\Interface\AddOns"
```

That copies the add-on into the AddOns folder you name. Edits need `/reload`; new files (Lua or `.tga`) need a full game restart. Point it at a test install if you want your live copy left alone.

## Before you open a pull request

- Run `python tools/luacheck.py <file>.lua` on every Lua file you changed. CI runs it on all of them.
- Never modify Blizzard's own objective tracker (its methods, pools or templates). It causes taint errors. The add-on draws its own list and hides Blizzard's with a secure state driver.
- Quest item buttons are secure: do not move layout while they are on screen in combat.
- Say in the pull request how you tested it in game.

## Pull request titles

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `perf: ...`, `refactor: ...`, `docs: ...`, `chore: ...`, `ci: ...`. A check enforces it. Pull requests are squash-merged, and the title becomes the line in the changelog, so write it for players: `fix: party count wrong after /reload`.

## How releases work

Merged `feat` and `fix` changes collect in a "Release PR" that sets the next version in the `.toc` and writes `CHANGELOG.md`. Merging that PR tags the release and starts the Package workflow, which builds `CleanQuestTracker-<version>.zip` and uploads it to GitHub and CurseForge. Only the maintainer merges it.
