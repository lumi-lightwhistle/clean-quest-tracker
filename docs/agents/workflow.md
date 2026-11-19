# Workflow, tools and cost

## Tools (`tools/`)
- `luacheck.py <file.lua>`: structural Lua syntax check. Run on every file you touch.
- `prereview.py`: syntax, `.toc` load order, settings nothing reads, unhandled highlight keys, stale wording; also
  rewrites `docs/REPOMAP.md` if it is out of date (include that file in the commit). `--all` checks every file.
- `repomap.py`: writes `docs/REPOMAP.md`; `--check` exits 1 if it is stale.
- `commit_gate.py`: Claude Code hook that blocks `git commit` while `prereview.py` fails. Needs `python` on the path.
- `img.py`, `badges.py`, `card_icons.py`, `make_icon.py`, `search_icon.py`: image drawing for `Media/` and `docs/`.

## Branches, CI and merging
- Every change: its own branch off fresh `origin/main` (`git fetch origin` first), its own PR.
- CI (`.github/workflows/ci.yml`) runs on PRs: `lua-syntax` and `conventional-title` are required checks.
- `main` requires one approval from the code owner (`.github/CODEOWNERS`), linear history (squash merge), no
  force-push, no deletion. Contributors with write access can push branches; only the owner merges.
- Forks: open a PR from your fork. Same checks, same rules.
- Releases are automatic: release-please opens a release PR from the Conventional Commit titles, then the Package
  workflow uploads to GitHub and CurseForge. `.github/pkgmeta.yml` lists what is kept out of the player zip.
- The PR title becomes the changelog line. Use the `changelog` skill. `feat`, `fix`, `perf` and `refactor` reach
  players; `docs`, `chore`, `ci`, `test` do not.

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
