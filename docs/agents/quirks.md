# Quirks learned the hard way

Each entry says what, then why. The short "Never" list is in `AGENTS.md`; this is the detail.

## Quest list and Blizzard's tracker
- **Never touch Blizzard's tracker.** Replacing its methods or using ObjectiveTrackerManager's pools, template cache,
  `g_questPOIButtonPool`, `CanShowPOIs` or EventRegistry triggers taints it ("tainted by ..." errors through Edit
  Mode). We use our own pools and per-instance overrides and hide the native tracker with `RegisterStateDriver`.
- **Quest focus icons follow the game's `questPOI` setting.** The Quests-page switch reads and writes that CVar, so a
  player's existing choice is respected. `T.PoiShown()` is the one place that reads it, `T.PoiSize()` the one place
  that reads the icon size. Icons on: quest indent is `poiIndent` (list's left edge to the icon). Off: `indent`
  (from the zone name).
- **Quest item buttons are secure.** No layout moves while they are on screen in combat; catch up on
  `PLAYER_REGEN_ENABLED`. They must be registered for both `AnyUp` and `AnyDown`: the client fires a secure action
  on whichever half the `ActionButtonUseKeyDown` CVar picks (down by default), so `AnyUp` alone does nothing.
- **Scale animations stretch on a moving row.** Blizzard's check-mark flash on an objective line scales the check and
  a glow; if the row moves while it plays, the game draws them stretched and oversized. So a quest that moves as it
  completes (finished quests sorted to the top or bottom) folds to its title at once and only glides (`moves` in
  `M:QCObjectives` and `M:QCQuest`).
- **Redraws:** quest events alone are not enough. The watcher in `Tracker/TrackerWatch.lua` (including
  `QUEST_WATCH_UPDATE`) plus a once-a-second signature check keep the list current. Don't "optimise" either away
  without proving the list still updates.
- **New watches go to the front of the watch list** (checked in game 2026-11-20): `C_QuestLog.AddQuestWatch` puts the
  quest at index 1, so the newest tracked quest is first, and re-adding a list in its old order reverses it (re-add
  from last to first to restore it). The game can drop a quest and re-add it, so `Rank` in `Tracker/Tracker.lua` keeps
  each quest's place (saved per character in `db.questOrder`) instead of trusting the raw watch index.
- **The current zone is read on zone events only** (`T.ReadWhere`), not on every redraw, so a redraw for any other
  reason can't re-sort zones. Caves and buildings can report their own zone name; the zone-level map (climbing
  `C_Map` parents) still names the outer zone.

## Secrets and party data
- **Secret values exist on this client.** Guard reads with `Q.Readable` or `issecretvalue`; wrap risky API calls in
  `pcall`.
- **Party detection only sees nearby members.** Order: legacy `IsUnitOnQuest(logIndex, unit)`, then
  `C_QuestLog.IsUnitOnQuest`, then tooltip party data, then Questie's comms. Debug with `/cqt party`.

## Loading and saved settings
- **New files (Lua or `.tga`) need a full game restart.** Edits to existing files need only `/reload`.
- **`Q.SCHEMA`** must be bumped whenever a saved value changes meaning, with a migration that keeps the player's
  layout. A player who changes nothing must see the same tracker as before.
- **The `.toc` is the load order.** CI fails if a Lua file is missing from it or it lists one that doesn't exist.

## Textures and fonts
- TGAs: 32-bit, stored bottom-up (descriptor 8), white with alpha so the game can tint them. Exception: the border
  flourish and crest (`Media/BorderCorner*`, `BorderCrest*`) are coloured per finish by `tools/border.py`, since each
  holds several colours (keep them in step with `FINISHES` in `UI/FrameBorder.lua`), and so is `BackdropStars` (the
  Appearance page's theme cards only: two colours, so not tinted; tiled with REPEAT, so a power-of-two 128px). Moonglow's
  own art (`Media/Moon*`, drawn offline) is white with alpha and tinted in game, except the corner accents, the
  crescent and the moon phase sheet; its tiled pieces (`MoonStars`, `MoonMist`, `MoonAurora`) are powers of two.
  `BarWave` (Moontide's crest, tiled along a smooth progress bar) comes from `tools/border.py`.
- Round shapes use circle masks or nine-slice. Overlapping see-through pieces stack visibly, so use solid premixed
  colours.
- The game font (Friz) has no bold, and the OUTLINE flag adds a dark edge. Fake bold with a same-colour shadow
  offset by 1px.
- `tools/img.py` is a pure-Python TGA/PNG writer (no PIL); `tools/badges.py`, `tools/card_icons.py` and `tools/border.py`
  use it.

## Look
Modern WoW Forever: warm charcoal, bronze (accent #DCA77F), a little teal (the settings window's rim, and the lit
line under the search box while typing). Style reference: EllesmereUI's Forever theme (`STYLE` table in
`AddOns\EllesmereUI\EllesmereUI.lua`).

## Drawing cost
- **Moving effects cost every frame.** The look's clock (`UI/FrameMoonglow.lua`) lays pieces out when the frame
  changes size and per frame only changes what moves, draws slow effects about 30 times a second and quick ones at
  most 60, and remembers what shows (`qcOn`) so nothing is hidden twice. Keep new effects to that pattern; the
  budgets in `tests/test_drawing.lua` catch a slip. One gradient helper (`Q.Gradient`) reuses its colour objects, as
  SetGradient copies their values; don't call `CreateColor` in anything that runs per frame or per layout.

## Windows and shell
- Heredocs mangle backslashes in Lua paths (`\\`): write Python edit scripts to a file first.
- Windows refuses to rename or delete a folder this session (or the app) is using.
- No `luac` is installed; `tools/luacheck.py` is a structural check only. It cannot catch runtime errors.
- A folder named `undefined` can appear in the project root (a tool writing to an unset path). It is gitignored and
  safe to ignore; don't read it.
