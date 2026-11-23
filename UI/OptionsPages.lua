-- Clean Quest Tracker: what each page of the settings window holds. Options.lua draws the window and the controls;
-- this file only lists them. Each page is a name, a short note, and groups of rows: { label, side note, rows }.
-- A row's first entry picks the control (toggle, slider, choice, colour, card, presets, badges, themes, inset, notice;
-- `card` is a colour as a card, two to a line, on the Colours page); `k` is the setting it changes and `hl` the part
-- of the tracker shaded while it's hovered (the General page's rows shade nothing: they change the whole frame).
-- Other row options:
--   rebuild      redraw the whole list after a change (toggle, slider, choice)
--   min max step format   a slider's range, step and how its value is written
--   options      a choice's { value, label } pairs
--   get, set     a toggle that mirrors something that isn't a saved setting here (the game's questPOI)
--   onEnable     a toggle's extra work when it is switched on
--   icon         a toggle's texture, drawn before its label
--   kFn          a slider that edits one of two saved settings, chosen by a function (the quest indent)
--   parts        an inset's labels, bullets and text
--   lead, text   a notice's opening words (pale blue) and the rest
--   switch       a colour card's two-way choice bound to a saved switch: { k, on, off, noteOn, noteOff }, the labels
--                and the note for each side (`note` is not used). While it's on, the palette gives way to the
--                difficulty colours (Quest titles only)
-- A group can carry `button = { label, run }`, a small button at the right of its label line (Reset colours); such a
-- group has no side note, which would sit under the button.
-- A row that only matters while another setting is set carries `enabledBy` (a saved switch that must be on) or
-- `enabledWhen` (a function), plus `needs`, the line shown when it is hovered while greyed out. These apply to rows
-- that are controls; notes ignore them.
--
-- A page with `sectionLinks` lists its named groups under its button in the side column, as links that jump to them
-- (while the Show sections switch at the foot of that column is on; that switch is drawn in Options.lua, the one
-- setting not listed here).
--
-- How the pages are split:
--   General  the add-on itself and its window
--   Quests   what the tracker shows, and in what order
--   Layout   sizes and spacing; the preset sets the groups marked as such
--   Colours, Party, Search, Animations  as the names say
--   Extras   optional features that are off by default, kept apart from the settings every player has

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

-- Quest focus icons follow the game's own quest icon setting (questPOI), so whatever a player already has stays put.
local function IconsOn()
	return Q.Tracker.PoiShown()
end

local function SetIcons(on)
	pcall(SetCVar, "questPOI", on and "1" or "0")
end

-- The indent is kept separately with icons on (from the list's left edge to the icon) and off (from the zone name).
local function IndentKey()
	return IconsOn() and "poiIndent" or "indent"
end

local Framed = Q.Frame.Framed -- the padding and rounded corners need the background or the border on
local LIMITS = Q.Frame.BACKDROP_LIMITS

local function Rounded()
	return Framed() and Q.db.rounded
end

local function Ornamented()
	return Q.db.border and (Q.db.borderFlourish or Q.db.borderCrest)
end

local TARGET_ICON = "Interface\\AddOns\\CleanQuestTracker\\Media\\FocusTarget" -- the Quests bar's focus mode button

local NEEDS_ZONES = "Turn on Group quests by zone (Quests page) to use this"
local NEEDS_BARS = "Turn on Show progress bars (Quests page) to use this"
local NEEDS_PARTY = "Turn on Show how many party members share each quest (Party page) to use this"
local NEEDS_ICONS = "Turn on Show quest focus icons (Quests page) to use this"
local NEEDS_FRAME = "Turn on Background or Border to use this"
local NEEDS_BORDER = "Turn on Border to use this"

local COLOUR_KEYS = { "colorZone", "colorCount", "colorTitle", "colorObjective", "colorDone", "colorBar", "colorBadge" }

O.PAGES = {
	{
		name = "General",
		note = "The add-on and its window",
		sectionLinks = true,
		groups = {
			{ "Quest list", nil, {
				{ "toggle", k = "enabled", label = "Enable Clean Quest Tracker", note = "Turn off to go back to Blizzard's tracker" },
				{ "toggle", k = "hideBlizzard", label = "Hide Blizzard's quest tracker", note = "Turn off to keep it too, for scenarios or tracked achievements" },
			} },
			{ "Window", "Size and position", {
				{ "toggle", k = "locked", label = "Lock position and size", note = "Unlock to drag the top strip to move, and the corner grip to resize" },
				{ "toggle", k = "alwaysShowIcons", label = "Always show header icons", note = "Off: the icons on the Quests bar fade in when you hover it" },
				{ "toggle", k = "autoHeight", label = "Auto height", note = "Grow to fit your quests, up to the maximum height" },
				{ "slider", k = "scale", label = "Scale", note = "Size of everything in the frame", min = 0.7, max = 1.6, step = 0.05, format = Decimal },
				{ "slider", k = "width", label = "Width", note = "Long titles wrap to fit", min = 220, max = 700, step = 10 },
				{ "slider", k = "maxHeight", label = "Maximum height", note = "The list scrolls past this", min = 120, max = 1200, step = 10 },
			} },
			{ "Background", nil, {
				{ "toggle", k = "backdrop", label = "Background", note = "A dark panel behind the list", onEnable = function()
					Q.db.opacity = Q.defaults.opacity
				end },
				{ "slider", k = "opacity", label = "Background darkness", note = "How dark the panel is", min = 0.05, max = 1, step = 0.05, format = Percent, enabledBy = "backdrop", needs = "Turn on Background to use this" },
				{ "slider", k = "padding", label = "Padding", note = "Room between the list and the edge of the background or border", min = LIMITS.padding[1], max = LIMITS.padding[2], format = Pixels, enabledWhen = Framed, needs = NEEDS_FRAME },
				{ "toggle", k = "rounded", label = "Rounded corners", note = "The border follows them", enabledWhen = Framed, needs = NEEDS_FRAME },
				{ "slider", k = "cornerSize", label = "Corner size", note = "How round the corners are", min = LIMITS.cornerSize[1], max = LIMITS.cornerSize[2], format = Pixels, enabledWhen = Rounded, needs = "Turn on Rounded corners, and Background or Border, to use this" },
			} },
			{ "Border", "A bronze frame around the list", {
				{ "toggle", k = "border", label = "Border", note = "Works with the background on or off" },
				{ "choice", k = "borderWeight", label = "Line weight", note = "How thick the bronze line is", options = { { "fine", "Fine" }, { "standard", "Standard" }, { "heavy", "Heavy" } }, enabledBy = "border", needs = NEEDS_BORDER },
				{ "choice", k = "borderFinish", label = "Finish", note = "Polished, aged or dark bronze", options = { { "polished", "Polished" }, { "aged", "Aged" }, { "dark", "Dark" } }, enabledBy = "border", needs = NEEDS_BORDER },
				{ "toggle", k = "borderFlourish", label = "Corner flourishes", note = "Curls and leaves at each corner, reaching outward", enabledBy = "border", needs = NEEDS_BORDER },
				{ "toggle", k = "borderCrest", label = "Crest on the header", note = "A small bronze diamond centred on the top edge", enabledBy = "border", needs = NEEDS_BORDER },
				{ "slider", k = "flourishSize", label = "Flourish size", note = "Also sizes the crest", min = LIMITS.flourishSize[1], max = LIMITS.flourishSize[2], step = 0.05, format = Percent, enabledWhen = Ornamented, needs = "Turn on Border, and Corner flourishes or Crest on the header, to use this" },
			} },
		},
	},
	{
		name = "Quests",
		note = "What the tracker shows, and in what order",
		sectionLinks = true,
		groups = {
			{ "Zones", nil, {
				{ "toggle", k = "grouping", hl = "group", label = "Group quests by zone", note = "Click a zone heading to fold it" },
				{ "toggle", k = "currentFirst", hl = "first", label = "Show my current zone first", note = "Re-sorts as you travel", enabledBy = "grouping", needs = NEEDS_ZONES },
			} },
			{ "Finished quests", "Position is within each zone, or the whole list without zones", {
				{ "choice", k = "completeOrder", hl = "done", rebuild = true, label = "Position", note = "None keeps the order you tracked them in; Top or Bottom moves quests you can hand in", options = { { "none", "None" }, { "top", "Top" }, { "bottom", "Bottom" } } },
				{ "toggle", k = "foldComplete", hl = "done", rebuild = true, label = "Collapse finished quests to their title", note = "They turn green with (Complete) after the name" },
			} },
			{ "Titles", nil, {
				{ "toggle", k = "levels", hl = "lvl", label = "Show quest level", note = "The [37] in front of each title" },
				{ "toggle", k = "difficulty", hl = "diff", label = "Colour titles by difficulty", note = "Unfinished quests use the quest log's colours. Off: one colour you pick on the Colours page." },
			} },
			{ "Quest focus icons", "The round icon beside each quest; click it to focus that quest", {
				{ "toggle", get = IconsOn, set = SetIcons, hl = "poi", rebuild = true, label = "Show quest focus icons", note = "The game's own quest icon setting, so the world map follows it too" },
			} },
			{ "Progress bars", nil, {
				{ "toggle", k = "bars", hl = "bars", label = "Show progress bars", note = "A bar appears under an objective once it has some progress" },
				{ "choice", k = "barStyle", hl = "bars", label = "Bar style", note = "Segmented: one segment per item needed, so 4/18 shows 18. Bars needing more than 30, or too narrow, stay smooth", options = { { "smooth", "Smooth" }, { "segmented", "Segmented" } }, enabledBy = "bars", needs = NEEDS_BARS },
			} },
		},
	},
	{
		name = "Layout",
		note = "Sizes and spacing",
		sectionLinks = true,
		groups = {
			{ "Preset", "Sets the groups marked Preset below", {
				{ "presets" },
			} },
			{ "Sizes", "Preset", {
				{ "slider", k = "fontSize", hl = "fs", label = "Quest text", note = "Titles and objectives", min = 10, max = 20 },
				{ "slider", k = "zoneSize", hl = "zfs", label = "Zone headings", note = "Zone names", min = 12, max = 24, enabledBy = "grouping", needs = NEEDS_ZONES },
				{ "slider", k = "poiSize", hl = "poi", rebuild = true, label = "Quest focus icon size", note = "Each layout preset sets its own size", min = 16, max = 40, format = Pixels, enabledWhen = IconsOn, needs = NEEDS_ICONS },
			} },
			{ "Spacing", "Preset", {
				{ "slider", k = "questGap", hl = "qg", label = "Quest spacing", note = "Gap between one quest and the next", min = 0, max = 20 },
				{ "slider", k = "zoneGap", hl = "zg", label = "Zone spacing", note = "Gap above each zone heading", min = 0, max = 20, enabledBy = "grouping", needs = NEEDS_ZONES },
				{ "slider", k = "spacing", hl = "lg", label = "Line spacing", note = "Gap between a title and its objectives", min = 0, max = 10 },
				{ "slider", k = "barGap", hl = "bars", label = "Space above progress bar", note = "Gap between an objective and its bar", min = 0, max = 10, format = Pixels, enabledBy = "bars", needs = NEEDS_BARS },
				{ "slider", k = "indent", hl = "ind", label = "Quest indent", note = "Icons off: from the zone name (or the left edge without zones); 0 lines titles up under it. Icons on: from the left edge to the icon", min = 0, max = 40, kFn = IndentKey },
			} },
			{ "Style", "Not part of the preset", {
				{ "toggle", k = "boldZones", hl = "zfs", label = "Bold zone headings", note = "Thicker letters on zone names", enabledBy = "grouping", needs = NEEDS_ZONES },
				{ "slider", k = "barHeight", hl = "bars", label = "Progress bar thickness", note = "How tall the bar is", min = 1, max = 6, format = Pixels, enabledBy = "bars", needs = NEEDS_BARS },
			} },
		},
	},
	{
		name = "Colours",
		note = "The tick marks the colour in use, the bronze dot the default",
		sectionLinks = true,
		groups = {
			{ "Text", nil, {
				{ "card", k = "colorZone", hl = "zfs", label = "Zone headings", note = "Zone names, their arrows and the line under them", enabledBy = "grouping", needs = NEEDS_ZONES },
				{ "card", k = "colorCount", hl = "zcount", label = "Number of quests", note = "The count at the right of each zone heading", enabledBy = "grouping", needs = NEEDS_ZONES },
				{ "card", k = "colorTitle", hl = "diff", label = "Quest titles", switch = { k = "difficulty", on = "By difficulty", off = "My colour", noteOn = "Each unfinished quest in its quest log colour", noteOff = "One colour for every unfinished quest" } },
				{ "card", k = "colorObjective", hl = "obj", label = "Objectives", note = "The lines under each quest" },
				{ "card", k = "colorDone", hl = "done", label = "Finished quests", note = "Title, (Complete) and full bars" },
			}, button = { label = "Reset colours", run = function()
				for _, key in ipairs(COLOUR_KEYS) do
					Q.db[key] = Q.defaults[key]
				end
				-- The Quest titles card's By difficulty / My colour choice lives on this page too.
				Q.db.difficulty = Q.defaults.difficulty
			end } },
			{ "Bars and badges", nil, {
				{ "card", k = "colorBar", hl = "bars", label = "Progress bars", note = "The fill under counted objectives", enabledBy = "bars", needs = NEEDS_BARS },
				{ "card", k = "colorBadge", hl = "party", label = "Party badge", note = "The person icon; lighter once the whole party has the quest", enabledBy = "party", needs = NEEDS_PARTY },
			} },
		},
	},
	{
		name = "Party",
		note = "Who else is on each quest",
		groups = {
			{ "Party badge", nil, {
				{ "toggle", k = "party", hl = "party", label = "Show how many party members share each quest", note = "Counts the other members of your group of five" },
				{ "choice", k = "partyStyle", hl = "party", rebuild = true, label = "Show as", note = "Person icon and number, or [1 party]", options = { { "icon", "Icon" }, { "text", "Text" } }, enabledBy = "party", needs = NEEDS_PARTY },
				{ "toggle", k = "partyShare", hl = "party", label = "Click the badge to share the quest", note = "Shares with members who don't have it yet", enabledBy = "party", needs = NEEDS_PARTY },
			} },
			{ "Badge style", "Sets it apart from the zone's quest count", {
				{ "badges", enabledBy = "party", needs = NEEDS_PARTY },
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
		name = "Search",
		note = "Finding quests in the list",
		groups = {
			{ "Matches", nil, {
				{ "choice", k = "searchStyle", hl = "search", label = "Highlight style", note = "Marker: a strip behind the letters, which turn white. Letters: the letters change colour.", options = { { "marker", "Marker" }, { "letters", "Letters" } } },
				{ "colour", k = "colorSearch", hl = "search", label = "Highlight colour", note = "The marker strip, or the letters themselves" },
				{ "toggle", k = "searchZones", hl = "search", label = "Also match zone names", note = "Typing a zone's name shows every quest in it", enabledBy = "grouping", needs = NEEDS_ZONES },
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
					{ "bullet", "New quests fade in, and finished quests flare green (or, when sorted to the top or bottom, fold and glide there)" },
					{ "label", "Always" },
					{ "text", "Nothing animates during combat; the list snaps to its new layout instead. Progress bars always ease to their new value, and scrolling always glides, even on None (in combat the list can't scroll while a quest item button shows)." },
				} },
			} },
		},
	},
	{
		name = "Extras",
		note = "Optional extras, off until you want them",
		groups = {
			{ "Quest focus", nil, {
				{ "toggle", k = "superFocus", hl = "target", icon = TARGET_ICON, onEnable = function()
					Q.db.focusQuest = false -- starts unlit each time, so the list never folds before the button is clicked
				end, label = "Super focus mode", note = "Adds a target button to the Quests bar. Click it to turn focus mode on or off. While on, every quest except the one you focus (its round icon, or Focus in its right-click menu) folds down to its title" },
			} },
			{ "Experimental", "Try-outs", {
				{ "notice", lead = "A playground for features that may come later.", text = "They may change, or go away, between versions." },
				{ "themes", k = "bgTheme", label = "Themes", note = "Changes the tracker's background only", enabledBy = "backdrop", needs = "Turn on Background (General page) to use this" },
			} },
		},
	},
}
