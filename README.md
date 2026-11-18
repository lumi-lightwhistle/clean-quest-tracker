<div align="center">

<img src="docs/icon-128.png" width="96" alt="Clean Quest Tracker icon">

# Clean Quest Tracker

**See what is left in your zone, and who in your party is on the same quest,<br>without opening the quest log.**

A quest tracker for World of Warcraft Forever.

[![Latest release](https://img.shields.io/github/v/release/lumi-lightwhistle/clean-quest-tracker?color=e8bd68&label=release)](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest)
[![CurseForge downloads](https://img.shields.io/curseforge/dt/1814563?color=e8bd68&label=CurseForge)](https://www.curseforge.com/wow/addons/clean-quest-tracker)
[![License: MIT](https://img.shields.io/badge/license-MIT-555555)](LICENSE)

**[Download](https://www.curseforge.com/wow/addons/clean-quest-tracker)** &nbsp;·&nbsp; [Features](#features) &nbsp;·&nbsp; [Install](#install) &nbsp;·&nbsp; [Commands](#commands) &nbsp;·&nbsp; [Changelog](CHANGELOG.md) &nbsp;·&nbsp; [Report a bug](https://github.com/lumi-lightwhistle/clean-quest-tracker/issues/new?template=bug_report.yml)

</div>

<br>

<table align="center">
<tr>
<td valign="top"><img src="https://media.forgecdn.net/attachments/2230/54/by-zonepng-png.png" width="300" alt="Tracked quests grouped under zone headings, with finished quests in green."></td>
<td valign="top"><img src="https://media.forgecdn.net/attachments/2230/50/party-number-png.png" width="420" alt="Party badge beside a quest, with a tooltip listing who has it."><br><img src="https://media.forgecdn.net/attachments/2230/51/config-2-png.png" width="420" alt="The settings window, open on the Layout page."></td>
</tr>
<tr>
<td align="center"><sub>Quests grouped by zone, current zone first</sub></td>
<td align="center"><sub>The party badge, and the settings window</sub></td>
</tr>
</table>

## Features

<table>
<tr>
<td valign="top" width="50%">

**Quests by zone**<br>
Your current zone stays on top and the list re-sorts as you travel. Fold zones one at a time, pin focus to keep only your current zone open, or expand and collapse everything in one click.

</td>
<td valign="top" width="50%">

**Search**<br>
Click the magnifying glass and type part of a quest title or objective. The list narrows as you type, the matching letters are highlighted, and zones with a match open by themselves.

</td>
</tr>
<tr>
<td valign="top">

**Party questing**<br>
A badge shows how many group members also have each quest. Hover it to see who and how far along they are; click it to share the quest with the people missing it.

</td>
<td valign="top">

**Objective progress**<br>
Bars fill as you collect items and defeat enemies. Finished quests turn green and fold to a single line.

</td>
</tr>
<tr>
<td valign="top">

**Yours to arrange**<br>
Compact or Comfortable spacing, your own colours, six party badge styles and an optional dark panel. Unlock the frame to move and resize it. Animation is Snappy, Smooth or off.

</td>
<td valign="top">

**Behaves like the original**<br>
Quest item buttons, map pins, the right-click menu and shift-click chat links work as they do in Blizzard's tracker. The add-on never modifies Blizzard's tracker code.

</td>
</tr>
</table>

## Install

- **CurseForge app:** search for *Clean Quest Tracker*, or open the [project page](https://www.curseforge.com/wow/addons/clean-quest-tracker).
- **By hand:** download the zip from the [latest release](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest) and extract the `CleanQuestTracker` folder into `Interface/AddOns`. Restart the game fully the first time.

## Getting started

<img src="https://media.forgecdn.net/attachments/2230/61/settings-cog-png.png" width="300" alt="The settings cog beside the Quests heading." align="right">

Hover the tracker's header and click the **cog**, or type `/cqt`, to open settings. Hover any setting to see the part of the tracker it changes, shaded in gold.

Shift-click a quest to link it in chat. Right-click it to stop tracking.

<br clear="right">

## Commands

| Command | What it does |
|---|---|
| `/cqt` | Open settings |
| `/cqt unlock`, `/cqt lock` | Show or hide the move strip and resize grip |
| `/cqt compact`, `/cqt comfortable` | Switch layout preset |
| `/cqt party` | List what each source reports about your party's quests, if a count looks wrong |
| `/cqt reset` | Restore every setting to its default |

## Works with

- **Questie** gives party quest counts at any distance through its party sync.
- **Spoken** adds its voiceover play buttons to your quests.
- If another add-on shows its own quest tracker, turn that one off so your quests don't appear twice. Clean Quest Tracker hides Blizzard's tracker for you; switch that off in settings if you want it back for scenarios or achievements.

## Contributing

Bug reports, ideas and pull requests are welcome. The [contributing guide](.github/CONTRIBUTING.md) covers setting up, testing in game and opening a pull request. Releases are automatic: merged changes collect in a release pull request, and merging it publishes to GitHub and CurseForge.

## License

[MIT](LICENSE). Formerly Simple Quest Tracker and, before that, Quest Companion.
