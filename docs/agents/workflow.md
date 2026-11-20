# Workflow, tools and cost

## Tools (`tools/`)
- `luacheck.py <file.lua>`: structural Lua syntax check. Run on every file you touch.
- `prereview.py`: syntax, `.toc` load order, settings nothing reads, unhandled highlight keys, stale wording, offline
  tests; also rewrites `docs/REPOMAP.md` if it is out of date (include that file in the commit). `--all` checks every
  file.
- `runtests.py`: runs the offline regression tests (`tests/run.lua`) with Lua 5.1 or the `lupa` package; exit 77 when
  neither is here. `prereview.py` runs it and reports a skip, not a failure, without Lua. See `docs/testing.md`.
- `repomap.py`: writes `docs/REPOMAP.md`; `--check` exits 1 if it is stale.
- `commit_gate.py`: Claude Code hook that blocks `git commit` while `prereview.py` fails. Needs `python` on the path.
- `img.py`, `badges.py`, `card_icons.py`, `make_icon.py`, `search_icon.py`: image drawing for `Media/` and `docs/`.
- `border.py`: the bronze border's corner ring atlas, flourishes and crest, and the background themes' glow and stars (`python tools/border.py Media`).

## Branches, CI and merging
- Every change: its own branch off fresh `origin/main` (`git fetch origin` first), its own PR.
- CI (`.github/workflows/ci.yml`) runs on PRs: `lua-syntax`, `lua-tests` (the offline tests, Lua 5.1) and
  `conventional-title` are required checks.
- `main` requires one approval from the code owner (`.github/CODEOWNERS`), linear history (squash merge), no
  force-push, no deletion. Contributors with write access can push branches; only the owner merges.
- Forks: open a PR from your fork. Same checks, same rules.
- Releases are automatic: release-please opens a release PR from the Conventional Commit titles, then the Package
  workflow uploads to GitHub and CurseForge. `.github/pkgmeta.yml` lists what is kept out of the player zip.
- The PR title becomes the changelog line. Use the `changelog` skill. `feat`, `fix`, `perf` and `refactor` reach
  players; `docs`, `chore`, `ci`, `test` do not.

## Tests
- Three layers, and which change needs which: `docs/testing.md`. Offline tests (`tests/`) run in CI and in
  `prereview.py`; `/cqttest` (the dev add-on in `Dev/CleanQuestTracker_Tests/`) runs in game; a manual checklist covers
  the rest.
- No Lua on this machine: `pip install lupa` and `python tools/runtests.py` runs them. Without it, say the tests were
  skipped locally and left to CI.
- `tests/` and `Dev/` are not part of the add-on: not in the `.toc`, not packaged, not copied by `deploy.ps1`. Copy
  `Dev/CleanQuestTracker_Tests` into `AddOns` only when the user asks; it needs a full game restart the first time.

## Testing in game
- Nothing runs from here, so a change is tried by copying the changed files into the installed add-on
  (`...\_forever_\Interface\AddOns\CleanQuestTracker`, same paths as the repo) and typing `/reload` in the open
  game. Only when the user asks, and never start a second game client.
- **Don't make backups when copying.** Git is the backup: the repo (and `origin/main`) holds every original. Compare
  the installed file with `origin/main` (ignore line endings), then copy over it and check with `cmp`. Save a copy
  elsewhere only if the installed file differs from every commit, and never inside `AddOns` (a folder with a `.toc`
  there loads as a second add-on). Saved settings are not in git; leave them alone.
- `/cqt fakeparty 1-4` pretends that many party members have every tracked quest (`/cqt fakeparty` turns it off), so
  party badges can be checked without a group.

## Reviews
- `pre-commit-review` skill, step 0 sizes the review: small = script plus one light diff-only reviewer; normal = full
  review in groups of about 400 changed lines; risky (migrations, `Q.SCHEMA`, presets, taint-sensitive code,
  releases) = full review at high or max effort.
- Reviewers are read-only, start from the diff, and report what they did not cover.

## Keeping token cost down
- Read `docs/REPOMAP.md` first, then slices. The four largest files (`Options`, `Tracker`, `Party`, `Frame`) are
  25 to 40 KB each.
- Don't open `docs/screenshots/`, `Releases/` zips or `.git`. Use a subagent for broad searches so the output stays
  out of the main conversation.
- One task per session; start fresh rather than dragging a long history along.
- Keep always-loaded files (`AGENTS.md`) short. Put detail in `docs/agents/` and link it.
- When you add a Lua file, give it a header comment and `-----` section banners so the map describes it.

## Local-machine notes
`CLAUDE.local.md` (not in git) holds paths and preferences that apply to one machine. Never put them in shared docs.
