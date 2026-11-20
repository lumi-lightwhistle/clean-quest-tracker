# Clean Quest Tracker: agent rules

A quest tracker add-on for **WoW Forever** (interface 16001, retail-style UI, Classic-era content). Plain Lua, no build
step, no way to run the game from here. Published on CurseForge (project 1814563). Humans: `.github/CONTRIBUTING.md`.

Read this whole file; it is short on purpose. Detail lives in `docs/agents/`, open it when the task needs it.

## Workflow (every change, in order)
1. **Branch first.** `git fetch origin`, then `git switch -c <type>/<name> origin/main` (use `git worktree add -b ...`
   if the checkout has uncommitted work). One piece of work per branch and per PR, always from fresh `origin/main`,
   never from the branch you happen to be on. Wrong branch after editing: stop and say so.
2. **Orient cheaply.** Read `docs/REPOMAP.md` (every file, section and function with its line), then read only the
   slice you need (offset and limit, or grep). Never read a whole 30 KB file to change ten lines. Skip
   `docs/screenshots/` and `Releases/`. Use a subagent for wide searches.
3. **Make the change small.** Defaults must match what players have today unless the task is to change them.
   Match the file's style: header comment, `-----` section banners (the map is built from them).
4. **Check.** `python tools/luacheck.py <file>` on every Lua file you touch, then `python tools/prereview.py`
   (syntax, `.toc`, unread settings, highlight keys, stale wording, offline tests; it also refreshes
   `docs/REPOMAP.md`). The offline tests must pass; which change also needs `/cqttest`: `docs/testing.md`. To try a
   change in game, copy the changed files over the installed add-on and `/reload`; **make no backup copies, git is
   the backup** (`docs/agents/workflow.md`).
5. **Review, sized to the change** (`pre-commit-review` skill, step 0): small fix = script plus one light reviewer;
   new setting, migration, preset or release = full review.
6. **Ship.** PR title is the changelog line: Conventional Commits, written for players (`changelog` skill). Fill in
   the PR checklist and say what was and wasn't tested in game. CI needs `lua-syntax`, `lua-tests` and
   `conventional-title`; `main` needs one approval from the code owner and linear history, so PRs are squash-merged.
7. **Never commit, push or merge unless the user asks.** Ask before deleting anything.

## Never
- **Touch Blizzard's objective tracker:** no replaced methods, no ObjectiveTrackerManager pools or template cache,
  no `g_questPOIButtonPool`, `CanShowPOIs` or EventRegistry triggers (taint errors through Edit Mode). Use our own
  pools and per-instance overrides; hide the native tracker only with `RegisterStateDriver`.
- **Move layout in combat** while a quest item button is on screen (they are secure); catch up on
  `PLAYER_REGEN_ENABLED`.
- **Read a value that may be secret** without `Q.Readable` or `issecretvalue`; wrap risky API calls in `pcall`.
- **Hand-edit** `CHANGELOG.md` (release-please) or `docs/REPOMAP.md` (generated).
- **Add a Lua file without listing it in the `.toc`** with its folder (`Tracker\X.lua`). New files need a full game
  restart to load; edits need only `/reload`.
- **Change what a saved value means without bumping `Q.SCHEMA`** and adding a migration in `Core/Core.lua`.

## Shape of the add-on
- Root is the add-on: `CleanQuestTracker.toc`; Lua in `Core/` (settings, presets, migrations, events, helpers),
  `Tracker/` (the quest list and its parts, party badges, progress bars), `UI/` (frame, search box, settings
  window); textures in `Media/`. Files share state through namespaces on the add-on table: `Q`, `Q.Tracker` (T),
  `F`, `P`, `O`. Settings live in `Q.db`, defaults in `Q.defaults`.
- Settings window: `UI/Options.lua` draws it, `UI/OptionsPages.lua` lists what each page holds. Add or move a setting
  in the pages file (the side column's Show sections switch is the one exception, drawn in `Options.lua`); a setting
  with no control or no reader fails `prereview.py`.
- Everything else (files, functions, line numbers): `docs/REPOMAP.md`.

## Open when needed
- `docs/agents/quirks.md`: every known WoW, client, texture, font and Windows quirk, with the reason. Read before
  touching icons, fonts, textures, party detection, redraw timing or shell scripts.
- `docs/agents/workflow.md`: tools, CI, releases, forks, token-saving habits, local-machine oddities.
- `docs/testing.md`: the three test layers (offline, `/cqttest`, manual checklist) and which change needs which.
