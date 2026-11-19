# Clean Quest Tracker: notes for agents

A quest tracker add-on for **WoW Forever** (interface 16001; retail-style UI with Classic-era content). Lua, no build
step. Published on CurseForge as Clean Quest Tracker (slug `clean-quest-tracker`). It was formerly named Simple
Quest Tracker, and before that Quest Companion. Humans should start with `.github/CONTRIBUTING.md`; this file is the
same ground for coding agents, plus the rules learned the hard way.

## Do this on every change
1. **Before any commit, run the `pre-commit-review` skill** (`.claude/skills/pre-commit-review/SKILL.md`): `python tools/prereview.py`, then independent reviewer agents over the changed files. Fix what they find or say why not. Committing and pushing still happen only when the user asks.
   - In Claude Code a hook (`tools/commit_gate.py`, configured in `.claude/settings.json`) also blocks `git commit` (from the Bash and PowerShell tools) while `tools/prereview.py` is failing. It needs `python` on the path.
   - Other agents have no hook: run `python tools/prereview.py` yourself and follow the skill's steps by hand. The reviewer step needs the ability to start separate reviewer agents; if you cannot, say so and ask for a human review.
2. **When you prepare a pull request or release notes, use the `changelog` skill** (`.claude/skills/changelog/SKILL.md`). The pull request title becomes the changelog line (Conventional Commits, written for players). A short overview per section, detail only where players need it. `CHANGELOG.md` is written by release-please; don't hand-edit it.
3. **Fill in the pull request checklist** (`.github/pull_request_template.md`), including how you tested in game. Nothing here can run the game, so say what was and wasn't tested.

## Where things are
- The repository root is the add-on (`CleanQuestTracker.toc`; Lua in `Core/`, `Tracker/`, `UI/`; textures in `Media/`). New Lua files go in the `.toc` with their folder (`Tracker\X.lua`). Repo config lives in `.github/` (CONTRIBUTING, SECURITY, pkgmeta.yml, release-please files). Releases are automatic (release-please, then the Package workflow uploads to GitHub and CurseForge); see CONTRIBUTING.md.
- `tools/`: the only checks available (no `luac` is installed).
  - `luacheck.py <file.lua>`: a structural Lua syntax check. Run it on every file you touch.
  - `prereview.py`: mechanical pre-commit checks (syntax, `.toc`, unread settings, unhandled highlight keys, stale wording).
  - `commit_gate.py`: the Claude Code hook that runs `prereview.py` before a commit.
  - `img.py`: a pure-Python TGA/PNG writer (no PIL). `badges.py`: draws the badge images. `card_icons.py`: draws the CurseForge page's icon tiles (`docs/icons/tile-*.png`: rim, fill and icon in one picture).
- **Blizzard UI source for this client:** the `forever` branch of github.com/Gethe/wow-ui-source (raw files via curl).
- **Style reference:** EllesmereUI's Forever theme (`AddOns\EllesmereUI\EllesmereUI.lua`, its `STYLE` table, accent #DCA77F).
- **Look:** modern WoW Forever (warm charcoal, bronze, a little teal: the settings window's rim, and the lit line under the search box while typing). Defaults should match what players have today unless the change is meant to alter them.

## Files
- `Core/Core.lua`: settings, defaults, presets, migrations (`Q.SCHEMA`; bump it whenever a saved value changes meaning), the `Q.Color` and `Q.Motion` helpers, and events.
- `Tracker/Tracker.lua`: the quest list itself. Files beside it share state through `Q.Tracker` (T): Zones (zone headings and the fold/focus/expand tools), Pools (including the quest focus icons), Items, Spoken, Motion, Highlight (the gold shading when a setting is hovered), Search, Watch.
- `UI/Frame.lua`: the frame, header and icons. `UI/FrameSearch.lua` is the search box in the header; `Tracker/TrackerSearch.lua` does the matching, highlighted letters and marker strips (placed with `FontString:CalculateScreenAreaFromCharacterSpan`, which this client has).
- `Tracker/Party.lua`: party detection and badge styles.
- `UI/Options.lua`: the custom-drawn settings window and its controls. `UI/OptionsPages.lua` lists what each page holds (General, Quests, Layout, Colours, Party, Search, Animations); add or move settings there. A row can be greyed out while it doesn't apply (`enabledBy`, `disabledBy`, `enabledWhen`, with `needs` for the tooltip); the options are listed at the top of that file.
- `Tracker/Progress.lua`: the progress bars.

## Rules learned the hard way
- **Never touch Blizzard's tracker.** Don't replace its methods. Don't use ObjectiveTrackerManager's pools or template cache, `g_questPOIButtonPool`, `CanShowPOIs`, or EventRegistry triggers. Any of these taints it, which causes "tainted by …" errors through Edit Mode. Use the add-on's own pools and per-instance overrides, and hide the native tracker only with `RegisterStateDriver`.
- **Quest focus icons follow the game's `questPOI` setting.** The Quests-page switch reads and writes that CVar, so a player's existing choice is respected; `T.PoiShown()` is the one place that reads it, and `T.PoiSize()` the one place that reads the icon size. With icons on the quest indent is `poiIndent` (from the list's left edge to the icon); off, it is `indent` (from the zone name).
- **Quest item buttons are secure.** No layout moves while they're on screen in combat; catch up on `PLAYER_REGEN_ENABLED`.
- **Secret values exist on this client.** Guard reads with `Q.Readable` or `issecretvalue`, and wrap risky API calls in `pcall`.
- **Party detection:** the game's APIs only see nearby members. Check the legacy `IsUnitOnQuest(logIndex, unit)` first, then `C_QuestLog.IsUnitOnQuest`, then tooltip party data, then Questie's comms. Debug with `/cqt party`.
- **Redraws:** quest events aren't enough on their own. The watcher in TrackerWatch (including `QUEST_WATCH_UPDATE`) and a once-a-second signature check keep the list current.
- **New files (Lua or `.tga`) need a full game restart**; edits only need `/reload`.
- **Textures:**
  - TGAs must be 32-bit, stored bottom-up (descriptor 8), white with alpha so the game can tint them.
  - Round shapes use circle masks or nine-slice.
  - Overlapping see-through pieces stack visibly, so use solid premixed colours.
- **Fonts:** the game font (Friz) has no bold, and the OUTLINE flag adds a dark edge. Fake bold with a same-colour shadow offset by 1px.
- **Shell:**
  - Heredocs mangle backslashes in Lua paths (`\\`), so write Python edit scripts to a file first.
  - Windows refuses to rename or delete a folder this session (or the app) is using.
