# Testing Clean Quest Tracker

Three layers. Each catches what the one before it can't.

| Layer | What it covers | Where it runs | How long |
|---|---|---|---|
| 1. Offline tests (`tests/`) | The pure logic: tracked order (`Rank`), finished quests' place (`SortFinished`), zone grouping and order (`Group`), the watch list to zone groups (`Collect`), where you are (`T.ReadWhere`, `T.CurrentZone`, `T.OnZoneChanged`) | CI on every PR (`lua-tests`), and `python tools/prereview.py` when this machine has Lua 5.1 or `lupa` | Under a second |
| 2. In-game self-test (`/cqttest`) | What needs the real client and the real list: zones as drawn, the game briefly untracking and re-tracking a quest as it completes, focus mode folding and its fade | In the game, by hand | About 25 seconds |
| 3. Manual checklist (below) | What neither can fake: the server, real travel, combat, a party, how it looks | In the game, by hand | A few minutes |

## Which changes need which layer

- **Every change:** layer 1 must pass (CI enforces it).
- **Quest order, zone grouping, sorting, where-you-are, focus mode or zone folding** (`Tracker/Tracker.lua` sections
  "Watched quests" and `M:LayoutContents`, `Tracker/TrackerZones.lua`, the zone events in `Core/Core.lua`): add or
  update an offline test for the new behaviour, run `/cqttest` in game, and walk the matching lines of the checklist.
- **Layout, frames, animations, quest item buttons, party badges, settings window:** the checklist lines for what you
  touched. `/cqttest` is worth a run if the change touches the list's redraw.
- **Docs, tools or CI only:** layer 1 only.

Say in the PR which layers ran.

## 1. Offline tests

`tests/run.lua` loads every Lua file in `.toc` order on a stand-in WoW API (`tests/wow.lua`: quest log, watch list,
zone and map functions, a controllable clock and timers; frames accept any method and do nothing), sends
`ADDON_LOADED` so the settings load as in the game, then runs each `tests/test_*.lua` listed in its `SUITES`.

Run them:

```powershell
python tools/runtests.py
```

It uses `lua5.1`, `lua51`, `luajit` or a `lua` that is 5.1 if one is on the path, else the `lupa` Python package
(which carries its own Lua 5.1). On Windows the simplest setup is `pip install "lupa>=2"`: the Lua packages on `winget`
are usually 5.4, which the runner won't use because the game runs 5.1. With neither, `tools/runtests.py` exits 77
and `prereview.py` says the tests were skipped; CI still runs them. On Linux or in CI: `lua5.1 tests/run.lua`.

Adding a test: write `check("X1 what should hold", condition, detail_shown_on_failure)` in a `tests/test_*.lua` file
(add a new file to `SUITES` in `tests/run.lua`). Set up the game's side through the `WOW` table (`WOW.watches`,
`WOW.log`, `WOW.zone`, `WOW.maps`, `WOW.Advance(seconds)`); see the top of `tests/wow.lua`. Put back any setting you
change, since suites share one loaded add-on. The tests call the add-on's own functions, never a copy: file-local
ones are reached through `Q.Tracker._internal` (end of the "Watched quests" section of `Tracker/Tracker.lua`), and a
new one a test needs goes there too. Nothing in the add-on reads that table. Before
trusting a new test, break the code it covers on purpose and see it fail.

## 2. In-game self-test

`Dev/CleanQuestTracker_Tests/` is a separate add-on for developers (it is never packaged: `.github/pkgmeta.yml`
ignores `Dev`, and `tools/deploy.ps1` doesn't copy it). Copy that folder into `Interface\AddOns\` beside
`CleanQuestTracker` and restart the game (a new add-on needs a full restart, not `/reload`).

Then, out of combat, with at least two tracked quests in your current zone and a few in a second zone, type
`/cqttest`. It prints failures as it goes and a total at the end:

- L1 your zone is drawn first
- L2 the game dropping and re-adding a watch (as a quest completes) moves nothing; tracking it again by hand after
  three seconds puts it on top
- L3 a redraw for any other reason (a quest completing) doesn't re-read where you are, and keeps the zone order
- L4 in focus mode a zone that joins the list later is folded too, its quests hidden, your zone open
- L5 opening a zone by hand ends focus mode and it stays open
- L8 turning focus on fades first; a redraw mid-fade doesn't fold early
- L6 finished quests at the bottom don't move zones
- L7 everything is put back

It changes your watch list, folds, focus mode and the finished-quest setting while it runs, and always restores them,
with this character's saved quest order, afterwards: also if a step errors or combat starts, and at the next login if
a `/reload` or logout cuts the run short. Checks that need something you don't have (zones off, one zone only) are
skipped with a note rather than failed.

## 3. Manual checklist

Walk the lines that match the change. Note in the PR which ones you did.

- [ ] **Quest completion on a real server:** finish an objective of a quest in the middle of a zone. The quest stays
      where it is (or moves only within its zone, per the finished-quests setting), and no zone moves.
- [ ] **Turn-in:** hand a quest in. It leaves the list; the others keep their order; a zone left empty disappears.
- [ ] **Accepting and tracking:** a new quest appears on top of its zone; untracking and re-tracking by hand after a
      few seconds puts it on top again.
- [ ] **Real travel:** ride from one zone into the next. Your new zone moves to the top once, on arrival.
- [ ] **Caves and buildings:** walk into a mine or building in your zone. Nothing re-sorts.
- [ ] **Loading screens:** hearth or enter a dungeon and leave it. The list settles on the right zone after the
      loading screen.
- [ ] **Focus mode while travelling:** with the pin on, cross into another zone. The new zone opens, the old one folds.
- [ ] **/reload and relog:** quest order and folds are the same afterwards, per character.
- [ ] **Combat with a quest item button showing:** pull a mob while a quest with a usable item is listed. No errors;
      the list holds still and catches up when combat ends; the item button works in combat.
- [ ] **Party:** in a group, the party badges show the right counts and update as members progress.
- [ ] **Animations:** quests glide, zones fade and fold smoothly at each animation speed; nothing flickers.
- [ ] **Edit Mode taint:** open and close Edit Mode, then use a quest item and the world map. No "blocked action" or
      taint errors (turn on Lua errors with `/console scriptErrors 1`).
