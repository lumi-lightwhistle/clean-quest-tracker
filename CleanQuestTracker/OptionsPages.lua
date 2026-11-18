-- Clean Quest Tracker: what each page of the settings window holds. Options.lua draws the window and the controls;
-- this file only lists them. Each page is a name, a short note, and groups of rows: { label, side note, rows }.
-- A row's first entry picks the control (toggle, slider, choice, colour, presets, badges, button, inset); `k` is the
-- setting it changes and `hl` the part of the tracker shaded while it's hovered.

local _, Q = ...
local O = Q.Options

local function Decimal(value)
	return ("%.2f"):format(value)
end

local function Percent(value)
	return ("%d%%"):format(value * 100 + 0.5)
end

local function Pixels(value)
	return ("%dpx"):format(value)
end

local COLOUR_KEYS = { "colorZone", "colorCount", "colorTitle", "colorObjective", "colorDone", "colorBar", "colorBadge" }

O.PAGES = {
	{
		name = "Layout",
		note = "Spacing, size and position",
		groups = {
			{ "Preset", "Sets spacing, text size and bar spacing together", {
				{ "presets" },
			} },
			{ "Spacing", "Gaps in the quest list", {
				{ "slider", k = "questGap", hl = "qg", label = "Quest spacing", note = "Gap between one quest and the next", min = 0, max = 20 },
				{ "slider", k = "zoneGap", hl = "zg", label = "Zone spacing", note = "Gap above each zone heading", min = 0, max = 20 },
				{ "slider", k = "spacing", hl = "lg", label = "Line spacing", note = "Gap between a title and its objectives", min = 0, max = 10 },
				{ "slider", k = "indent", hl = "ind", label = "Quest indent", note = "From the zone name; 0 lines titles up under it", min = 0, max = 40 },
			} },
			{ "Frame", "Size, position and backdrop", {
				{ "toggle", k = "locked", hl = "lock", label = "Lock position and size", note = "Unlock to drag the top strip to move, and the corner grip to resize" },
				{ "toggle", k = "alwaysShowIcons", hl = "head", label = "Always show header icons", note = "Off: the icons on the Quests bar fade in when you hover it" },
				{ "toggle", k = "autoHeight", hl = "frame", label = "Auto height", note = "Grow to fit your quests, up to the maximum height" },
				{ "slider", k = "scale", hl = "frame", label = "Scale", note = "Size of everything in the frame", min = 0.7, max = 1.6, step = 0.05, format = Decimal },
				{ "slider", k = "width", hl = "w", label = "Width", note = "Long titles wrap to fit", min = 220, max = 700, step = 10 },
				{ "slider", k = "maxHeight", hl = "frame", label = "Maximum height", note = "The list scrolls past this", min = 120, max = 1200, step = 10 },
				{ "toggle", k = "backdrop", hl = "op", label = "Background", note = "A dark panel behind the list", onEnable = function()
					Q.db.opacity = 0.5
				end },
				{ "slider", k = "opacity", hl = "op", label = "Background darkness", note = "Available while Background is on", min = 0.05, max = 1, step = 0.05, format = Percent, enabledBy = "backdrop" },
			} },
		},
	},
	{
		name = "Quests",
		note = "What the tracker shows",
		groups = {
			{ "Quest list", nil, {
				{ "toggle", k = "enabled", hl = "frame", label = "Enable Clean Quest Tracker", note = "Turn off to go back to Blizzard's tracker" },
				{ "toggle", k = "hideBlizzard", hl = "hide", label = "Hide Blizzard's quest tracker", note = "Turn off to keep it too, for scenarios or tracked achievements" },
			} },
			{ "Zones", nil, {
				{ "toggle", k = "grouping", hl = "group", label = "Group quests by zone", note = "Click a zone heading to fold it" },
				{ "toggle", k = "currentFirst", hl = "first", label = "Show my current zone first", note = "Re-sorts as you travel" },
			} },
			{ "Titles", nil, {
				{ "toggle", k = "levels", hl = "lvl", label = "Show quest level", note = "The [37] in front of each title" },
				{ "toggle", k = "difficulty", hl = "diff", label = "Colour titles by difficulty", note = "Off: every title uses the Quest titles colour" },
				{ "toggle", k = "foldComplete", hl = "done", rebuild = true, label = "Collapse finished quests to their title", note = "They turn green with (Complete) after the name" },
			} },
		},
	},
	{
		name = "Search",
		note = "Finding quests in the list",
		groups = {
			{ "Matches", nil, {
				{ "choice", k = "searchStyle", hl = "search", label = "Highlight style", note = "Marker: a strip behind the letters, which turn white. Letters: the letters change colour.", options = { { "marker", "Marker" }, { "letters", "Letters" } } },
				{ "colour", k = "colorSearch", hl = "search", label = "Highlight colour", note = "The marker strip, or the letters themselves" },
				{ "toggle", k = "searchZones", hl = "search", label = "Also match zone names", note = "Typing a zone's name shows every quest in it" },
			} },
			{ "", nil, {
				{ "inset", parts = {
					{ "label", "Using search" },
					{ "bullet", "Hover the Quests bar and click the magnifying glass" },
					{ "bullet", "Type part of a quest title or objective; capitals don't matter" },
					{ "bullet", "Click away or press Enter to keep the filter; click the box to change it" },
					{ "bullet", "Click the X, or press Esc while typing, to clear it; your zones fold back how they were" },
					{ "label", "Not saved" },
					{ "text", "The search starts empty after /reload or logging in, so no quests stay hidden by mistake." },
				} },
			} },
		},
	},
	{
		name = "Party",
		note = "Who else is on each quest",
		groups = {
			{ "Badge style", "Sets it apart from the zone's quest count", {
				{ "badges" },
			} },
			{ "Party badge", nil, {
				{ "toggle", k = "party", hl = "party", label = "Show how many party members share each quest", note = "Counts the other members of your group of five" },
				{ "choice", k = "partyStyle", hl = "party", rebuild = true, label = "Show as", note = "Person icon and number, or [1 party]", options = { { "icon", "Icon" }, { "text", "Text" } } },
				{ "toggle", k = "partyShare", hl = "party", label = "Click the badge to share the quest", note = "Shares with members who don't have it yet" },
			} },
			{ "", nil, {
				{ "inset", parts = {
					{ "label", "Far away" },
					{ "text", "Party members far away are seen through Questie when you both run it. Otherwise the game only reports members close by. /cqt party shows what each source reports." },
				} },
			} },
		},
	},
	{
		name = "Colours",
		note = "Pick from a palette; the dot marks the default",
		groups = {
			{ "Text", nil, {
				{ "colour", k = "colorZone", hl = "zfs", label = "Zone headings", note = "Zone names, their arrows and the line under them" },
				{ "toggle", k = "boldZones", hl = "zfs", label = "Bold zone headings", note = "Thicker letters on zone names" },
				{ "colour", k = "colorCount", hl = "group", label = "Number of quests", note = "The count at the right of each zone heading" },
				{ "colour", k = "colorTitle", hl = "diff", label = "Quest titles", note = "Used while difficulty colours are off (Quests page)" },
				{ "colour", k = "colorObjective", hl = "fs", label = "Objectives", note = "The lines under each quest" },
				{ "colour", k = "colorDone", hl = "done", label = "Finished quests", note = "Title, (Complete) and full bars" },
			} },
			{ "Bars and badges", nil, {
				{ "colour", k = "colorBar", hl = "bars", label = "Progress bars", note = "The fill under counted objectives" },
				{ "colour", k = "colorBadge", hl = "party", label = "Party badge", note = "The person icon; lighter once the whole party has the quest" },
			} },
			{ "", nil, {
				{ "button", label = "Reset colours", run = function()
					for _, key in ipairs(COLOUR_KEYS) do
						Q.db[key] = Q.defaults[key]
					end
					Q.db.boldZones = false
				end },
			} },
		},
	},
	{
		name = "Text & bars",
		note = "Text sizes and bar spacing are part of the preset",
		groups = {
			{ "Text", nil, {
				{ "slider", k = "fontSize", hl = "fs", label = "Quest text", note = "Titles and objectives", min = 10, max = 20 },
				{ "slider", k = "zoneSize", hl = "zfs", label = "Zone headings", note = "Zone names", min = 12, max = 24 },
			} },
			{ "Progress bars", "Space above bar follows the preset", {
				{ "toggle", k = "bars", hl = "bars", label = "Show bars under counted objectives", note = "A bar appears once an objective has some progress" },
				{ "slider", k = "barHeight", hl = "bars", label = "Bar thickness", note = "How tall the bar is", min = 1, max = 6, format = Pixels },
				{ "slider", k = "barGap", hl = "bars", label = "Space above bar", note = "Gap between an objective and its bar", min = 0, max = 10, format = Pixels },
			} },
		},
	},
	{
		name = "Animations",
		note = "Motion in the tracker",
		groups = {
			{ "Motion", nil, {
				{ "choice", k = "animSpeed", hl = "anim", label = "Speed", note = "How quickly things move", options = { { "off", "None" }, { "snappy", "Snappy" }, { "smooth", "Smooth" } } },
			} },
			{ "", nil, {
				{ "inset", parts = {
					{ "label", "What animates" },
					{ "bullet", "Zones fold and unfold, with the rows below gliding into place" },
					{ "bullet", "The frame eases to its new height, and minimising rolls it up" },
					{ "bullet", "Zone arrows turn, and header icons fade in on hover" },
					{ "bullet", "New quests fade in, finished quests flare green, and the party count pops" },
					{ "label", "Always" },
					{ "text", "Nothing animates during combat; the list snaps to its new layout instead. Progress bars always ease to their new value, even on None." },
				} },
			} },
		},
	},
}
