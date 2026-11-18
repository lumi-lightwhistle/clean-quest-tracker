<div align="center">

# Clean Quest Tracker

**See what is left in your zone, and who in your party is on the same quest, without opening the quest log.**

A quest tracker for **World of Warcraft Forever**.

[![Latest release](https://img.shields.io/github/v/release/lumi-lightwhistle/clean-quest-tracker?color=e8bd68&label=release)](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest)
[![CurseForge downloads](https://img.shields.io/curseforge/dt/1814563?color=e8bd68&label=CurseForge)](https://www.curseforge.com/wow/addons/clean-quest-tracker)
[![License: MIT](https://img.shields.io/badge/license-MIT-555555)](LICENSE)

[Download](https://www.curseforge.com/wow/addons/clean-quest-tracker) · [Changelog](CHANGELOG.md) · [Report a bug](https://github.com/lumi-lightwhistle/clean-quest-tracker/issues/new?template=bug_report.yml) · [Contribute](CONTRIBUTING.md)

</div>

<br>

<table>
<tr>
<td align="center" width="33%"><a href="https://media.forgecdn.net/attachments/2230/54/by-zonepng-png.png"><img src="https://media.forgecdn.net/attachments/2230/54/by-zonepng-png.png" alt="Tracked quests grouped under zone headings." width="100%"></a><br><sub>Quests grouped by zone, current zone first</sub></td>
<td align="center" width="33%"><a href="https://media.forgecdn.net/attachments/2230/50/party-number-png.png"><img src="https://media.forgecdn.net/attachments/2230/50/party-number-png.png" alt="Party badge beside a quest that another group member has." width="100%"></a><br><sub>The party badge on a shared quest</sub></td>
<td align="center" width="33%"><a href="https://media.forgecdn.net/attachments/2230/51/config-2-png.png"><img src="https://media.forgecdn.net/attachments/2230/51/config-2-png.png" alt="Clean Quest Tracker configuration panel." width="100%"></a><br><sub>The settings window</sub></td>
</tr>
</table>

## What it does

| | |
|---|---|
| **Quests by zone** | Your current zone stays on top and the list re-sorts when you travel. Fold zones one at a time, pin focus to keep only your current zone open, or expand and collapse everything in one click. |
| **Search** | Click the magnifying glass and type part of a quest title or objective. The list narrows as you type and the matching letters are highlighted. Zones with a match open by themselves. |
| **Party questing** | A badge shows how many group members also have each quest. Hover it to see who and how far along they are, click it to share the quest with the people missing it. |
| **Objective progress** | Bars fill as you collect items and defeat enemies. Finished quests turn green and fold to a single line. |
| **Yours to arrange** | Compact or Comfortable spacing, your own colours, six party badge styles and an optional dark panel. Unlock the frame to move and resize it. Animation is Snappy, Smooth or off. |
| **Behaves like the original** | Quest item buttons, map pins, the right-click menu and shift-click chat links work as in Blizzard's tracker. The add-on never modifies Blizzard's tracker code. |

## Install

**CurseForge app or website:** search for *Clean Quest Tracker*, or use the [project page](https://www.curseforge.com/wow/addons/clean-quest-tracker).

**By hand:** download the zip from the [latest release](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest) and extract the `CleanQuestTracker` folder into your `Interface/AddOns` folder. Restart the game; a full restart is needed the first time.

## Using it

Hover the tracker's header and click the **cog**, or type `/cqt`, to open settings. Hover any setting to see the part of the tracker it changes.

| Command | What it does |
|---|---|
| `/cqt` | Open settings |
| `/cqt unlock` · `/cqt lock` | Show the move strip and resize grip, or hide them |
| `/cqt compact` · `/cqt comfortable` | Switch layout preset |
| `/cqt party` | List what each source reports about your party's quests, if a count looks wrong |
| `/cqt reset` | Restore every setting to its default |

Shift-click a quest to link it in chat. Right-click it to stop tracking.

## Works with

- **Questie** gives party quest counts at any distance through its party sync.
- **Spoken** adds its voiceover play buttons to quests.
- If another add-on shows its own quest tracker, turn that one off so your quests do not appear twice. This add-on hides Blizzard's tracker for you; switch that off in settings if you want it back for scenarios or achievements.

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers how to set up, test and submit a change.

Releases are automatic: merged changes build a release pull request with the next version and changelog, and merging it publishes to GitHub and CurseForge.

## License

[MIT](LICENSE). Formerly Simple Quest Tracker and, before that, Quest Companion.
