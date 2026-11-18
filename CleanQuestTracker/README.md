# Clean Quest Tracker

A quest tracker for World of Warcraft Forever (interface 16001). It groups your watched quests by zone, shows how many party members share each quest, adds animated progress bars, and sits in a frame you can move and resize.

Version 0.8.5 <!-- x-release-please-version -->. Formerly Simple Quest Tracker and, before that, Quest Companion.

## What it does

- **Zone groups.** Quests are grouped under their quest-log zone, with your current zone first; the list re-sorts whenever you change zone. Click a zone row to fold it.
- **Zone focus.** Hover the Quests bar and click the pin to collapse every zone except the one you're in. Focus follows you as you travel. Click the pin again to put your zones back how they were. The arrows icon next to it expands every zone, or collapses them all when they're all open.
- **Search.** Hover the Quests bar and click the magnifying glass, right of the zone arrows. Type part of a quest title or objective and the list narrows as you type, with the matching letters highlighted. Folded zones with matches open while you search. Click away or press Enter to keep the filter, and press Esc or click the X to clear it. On the Search settings page, pick Marker (a highlighter strip behind white letters) or Letters (coloured letters), the highlight colour, and whether zone names match too. The search starts empty each session.
- **Party badge.** In a group, each quest shows a person icon and the number of other party members who have it, in a small container so it isn't mistaken for the zone's quest count. Pick from six styles on the Party page (Pill, Dark chip, Solid, Forever rim, Split or Plain), each previewed as you choose. The badge brightens when the whole party has the quest. Hover the badge to see who has it and their progress, and who doesn't. Click it to share the quest with the people missing it.
- **Finished quests** turn the game's bright green with "(Complete)" after the title, and collapse to that one line once their objectives fade out.
- **Progress bars** appear under counted objectives once you've made progress, and animate when the count changes.
- **Animations.** Zones fold and unfold smoothly while the rows below glide into place, and the frame eases to its new height. Zone arrows turn, minimising rolls the list up under the header, and header icons fade in on hover. New quests fade in, finished quests flare green, and the party count pops when it changes. Pick None, Snappy (default) or Smooth on the Animations settings page. Nothing animates in combat.
- **Quest items, POI buttons, right-click menu and click behaviour** match Blizzard's tracker. Spoken's play buttons appear when Spoken is installed.

## Use

- `/cqt` (or `/sqt`, `/qc`) or the cog in the header (shown on hover) opens settings. They're also under Esc > Options > AddOns. Hover over any setting to see the part of the tracker it changes shaded in gold. Every slider has step buttons for one-notch changes.
- **Layout presets.** Comfortable is clear and easy to read; Compact fits more quests on screen with tighter spacing and slightly smaller text. Change any spacing or text size by hand and the preset becomes Custom. `/cqt compact` and `/cqt comfortable` switch from chat. Quest indent counts from the zone name, so 0 lines titles up under it.
- **Colours.** Zone headings, the number of quests per zone, quest titles, objectives, finished quests, progress bars and the party badge can each take a colour from a palette, and zone headings can be bold. The defaults are the game's own tracker colours, with a brighter quest count.
- **Background.** Off by default. Turn it on for a dark panel behind the list (50% to start), then set its darkness.
- `/cqt unlock` shows the move strip above the frame and a resize grip in the bottom corner. `/cqt lock` hides them.
- Click the "Quests" header or its button to minimise the list.
- Shift-click a quest to link it in chat. If the chat box is closed it opens with the link ready to send. To stop tracking a quest, right-click it and choose "Stop tracking".
- `/cqt reset` restores every setting. `/cqt preview` shows a test progress bar.
- `/cqt party` lists, for each tracked quest and party member, what each source reports: the game's two quest APIs, its party-progress data, and Questie's party sync. Use it if a party count looks wrong.
- With Questie installed, party members are also seen at any distance through Questie's own party sync, the same data Kerzo's quest log uses. Without it, the game only reports members who are close by.

## Layout

The frame remembers its position from the nearest top corner of the screen, so changing UI scale or resolution doesn't move it. With **Auto height** on, the frame grows to fit your quests up to the maximum height, and never past the bottom of the screen. While unlocked, the frame shows its full maximum-height box. Drag the grip to set the width and keep that box clear of your action bars.

## How it works

Clean Quest Tracker draws its own quest list from Blizzard's tracker templates. It never changes Blizzard's tracker code. Blizzard's tracker is hidden with the game's secure visibility driver. Turn off "Hide Blizzard's quest tracker" if you want to keep it for scenarios or tracked achievements.

Quest item buttons are secure buttons, as the game requires. When a quest item button is on screen, the list keeps its layout during combat and catches up when combat ends. Without item buttons, it updates in combat as normal.

## Other quest trackers

Clean Quest Tracker pauses itself on characters where EllesmereUI Quest Tracker, Kaliel's Tracker or Questie's tracker is enabled, and says so in chat. Enable only one quest tracker per character.

## Upgrading from 0.7

Settings carry over. If you were on a preset, it takes its refined values; a hand-tuned indent is converted so it looks the same. The heading is now always centred, and a background you had set becomes the Background switch, turned on.

## Upgrading from 0.5

Settings carry over. The party count is switched back on if the old cycling button had hidden it, and the old saved position is converted once. A copy of version 0.5.0 was saved to `Interface\QuestCompanion-backup-0.5.0`.

## Credits

The structure (own module from Blizzard templates, secure item pool, native tracker hidden by state driver) follows the approach used by ForeverCore's quest list. Blizzard's tracker logic is adapted from the game's own UI source.
