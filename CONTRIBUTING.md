# Contributing

- Work on a branch and open a pull request into `main`; `main` is protected.
- PR titles use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `perf: ...`, `docs: ...`, `chore: ...`. The squash-merged title becomes the changelog entry.
- Run `python tools/luacheck.py CleanQuestTracker/<file>.lua` on every Lua file you touch (CI does it for all).
- Never modify Blizzard's own objective tracker (its methods, pools or templates); that causes taint errors. See *How it works* in the add-on README.

## Releasing

Releases are automatic. Merged `feat`/`fix` commits accumulate in a "Release PR" that bumps the version in the `.toc` and README and updates `CHANGELOG.md`. Merging that PR tags the release and uploads the zip to GitHub and CurseForge.
