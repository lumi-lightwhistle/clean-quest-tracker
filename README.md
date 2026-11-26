<div align="center">

<img src="docs/icon-128.png" width="96" alt="Clean Quest Tracker icon">

# Clean Quest Tracker

**See what is left in your zone, and who in your party is on the same quest,<br>without opening the quest log.**

A quest tracker for World of Warcraft Forever.

[![Latest release](https://img.shields.io/github/v/release/lumi-lightwhistle/clean-quest-tracker?color=e8bd68&label=release)](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest)
[![CurseForge downloads](https://img.shields.io/curseforge/dt/1814563?color=e8bd68&label=CurseForge)](https://www.curseforge.com/wow/addons/cleanquesttracker)
[![License: MIT](https://img.shields.io/badge/license-MIT-555555)](LICENSE)

**[Download](https://www.curseforge.com/wow/addons/cleanquesttracker)** &nbsp;·&nbsp; [Features](#features) &nbsp;·&nbsp; [Install](#install) &nbsp;·&nbsp; [Commands](#commands) &nbsp;·&nbsp; [Changelog](CHANGELOG.md) &nbsp;·&nbsp; [Report a bug](https://github.com/lumi-lightwhistle/clean-quest-tracker/issues/new?template=bug_report.yml)

</div>

<br>

<table align="center">
<tr>
<td valign="top"><img src="docs/screenshots/25-tracker-overview-progress.png" width="260" alt="The tracker: quests grouped by zone, current zone open, progress bars filling."></td>
<td valign="top"><img src="docs/screenshots/23-party-badge-tooltip.png" width="380" alt="The party badge tooltip, listing each member's progress on a quest."><br><br><img src="docs/screenshots/03-search-typing.png" width="380" alt="Searching the tracker, with the matching letters marked."></td>
</tr>
<tr>
<td align="center"><sub>Quests by zone, current zone first</sub></td>
<td align="center"><sub>Party progress, and search</sub></td>
</tr>
</table>

## Features

<table>
<tr>
<td valign="middle" width="56%">

&nbsp;<br>
**Quests by zone**

Your current zone stays on top, even in caves and buildings, and the list re-sorts when you enter a new zone. Fold zones one at a time, pin focus to keep only your current zone open (zones that join the list later fold too), or expand everything in one click.<br>
&nbsp;

</td>
<td valign="middle" align="center"><img align="top" src="docs/screenshots/20-header-tooltip.png" width="320" alt="The zone tools on the Quests bar, with the Expand all zones tooltip."></td>
</tr>
<tr>
<td valign="middle">

&nbsp;<br>
**Search**

Hover the Quests bar, click the magnifying glass and type part of a quest title or objective. The list narrows as you type, the matching letters are marked, and folded zones with a match open by themselves. Enter keeps the filter; Esc while typing, or the X, clears it.<br>
&nbsp;

</td>
<td valign="middle" align="center"><img align="top" src="docs/screenshots/03-search-typing.png" width="320" alt="Searching for or, with five matches marked."></td>
</tr>
<tr>
<td valign="middle">

&nbsp;<br>
**Party questing**

A badge shows how many group members also have each quest. Hover it to see who and how far along they are, even across the map with Questie. Click it to share the quest with anyone missing it.<br>
&nbsp;

</td>
<td valign="middle" align="center"><img align="top" src="docs/screenshots/23-party-badge-tooltip.png" width="320" alt="The party badge tooltip with each member's progress."></td>
</tr>
<tr>
<td valign="middle">

&nbsp;<br>
**Objective progress**

Bars fill as you collect items and defeat enemies. Finished quests turn green and fold to a single line, in the order you tracked them, at the top of their zone, or at the bottom.<br>
&nbsp;

</td>
<td valign="middle" align="center"><img align="top" src="docs/screenshots/24-progress-bars.png" width="320" alt="Quests with progress bars part-way full."></td>
</tr>
<tr>
<td valign="middle">

&nbsp;<br>
**Yours to arrange**

Comfortable or Compact spacing, your own colours, six party badge styles, an optional dark panel with padding and rounded corners, and a border. Two themes, Classic (bronze, corner flourishes, a crest) and Moonglow (silver, night sky, moonlit effects), or mix your own from every part. Try a theme before you keep it. Unlock the frame to move and resize it. Animation is Snappy, Smooth or off.<br>
&nbsp;

</td>
<td valign="middle" align="center"><img align="top" src="docs/screenshots/08a-layout-comfortable.png" width="150" alt="The Comfortable preset."> <img align="top" src="docs/screenshots/08b-layout-compact.png" width="150" alt="The Compact preset."></td>
</tr>
<tr>
<td valign="middle" colspan="2">

&nbsp;<br>
**Behaves like the original**

Quest item buttons, map pins and the right-click menu work as they do in Blizzard's tracker, and shift-click links a quest in chat even with the chat box closed. The add-on never modifies Blizzard's tracker code.<br>
&nbsp;

</td>
</tr>
</table>

## Install

- **CurseForge app:** search for *Clean Quest Tracker*, or open the [project page](https://www.curseforge.com/wow/addons/cleanquesttracker).
- **By hand:** download the zip from the [latest release](https://github.com/lumi-lightwhistle/clean-quest-tracker/releases/latest) and extract the `CleanQuestTracker` folder into `Interface/AddOns`. Restart the game fully the first time.

## Getting started

<img src="docs/screenshots/19-header-icons.png" width="300" alt="The Quests bar with its zone tools, search, cog, lock and minimise buttons." align="right">

Hover the tracker's header and click the **cog**, or type `/cqt`, to open settings. Hover a setting to see the part of the list it changes, shaded in gold. Settings that don't apply right now are greyed out and say why.

Shift-click a quest to link it in chat. Right-click it for the quest menu, including Stop tracking.

<br clear="right">

<p align="center"><img src="docs/screenshots/05-settings-layout.png" width="560" alt="The settings window, open on the Layout page."></p>

## Commands

| Command | What it does |
|---|---|
| `/cqt` | Open settings |
| `/cqt unlock`, `/cqt lock` | Show or hide the move strip and resize grip |
| `/cqt compact`, `/cqt comfortable` | Switch layout preset |
| `/cqt party` | List what each source reports about your party's quests, if a count looks wrong |
| `/cqt reset` | Restore every setting to its default |
| `/cqt preview` | Show the progress bar effects side by side |

## Works with

- **Questie** gives party quest counts and progress at any distance through its party sync.
- **Spoken** adds its voiceover play buttons to your quests.
- If another add-on shows its own quest tracker, turn that one off so your quests don't appear twice. Clean Quest Tracker hides Blizzard's tracker for you; switch that off in settings if you want it back for scenarios or achievements.

## Contributing

Bug reports, ideas and pull requests are welcome. The [contributing guide](.github/CONTRIBUTING.md) covers setting up, testing in game and opening a pull request. Releases are automatic: merged changes collect in a release pull request, and merging it publishes to GitHub and CurseForge.

## License

[MIT](LICENSE). Formerly Simple Quest Tracker and, before that, Quest Companion.
