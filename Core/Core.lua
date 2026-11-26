-- Clean Quest Tracker: core namespace, saved settings, migration, compatibility and events.
--
-- Design rule for the whole add-on: Blizzard's objective tracker is never modified. Clean Quest Tracker draws its own
-- quest list from Blizzard's templates (Tracker.lua) inside its own frame (Frame.lua), and the native tracker is
-- hidden only through the game's secure visibility driver. Replacing Blizzard methods spreads taint into the
-- managed-frame layout, which is what produced Lua errors in earlier builds.

local ADDON, Q = ...
CleanQuestTracker = Q

Q.name = ADDON
Q.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
Q.SCHEMA = 7

Q.defaults = {
	enabled = true,
	-- quests
	grouping = true,
	currentFirst = true,
	focusZone = false, -- keep only the current zone open, following you as you travel
	levels = true,
	difficulty = true,
	foldComplete = true,
	completeOrder = "none", -- where finished quests sit within their zone: "none" (tracked order), "top" or "bottom"
	hideBlizzard = true,
	-- party
	party = true,
	partyStyle = "icon", -- "icon" or "text"
	partyShare = true,
	badgeStyle = "pill", -- "pill", "chip", "solid", "rim", "split" or "plain" (see Party.STYLES)
	-- layout preset and spacing ("comfortable", "compact" or "custom"; see Q.PRESETS)
	preset = "comfortable",
	fontSize = 13,
	zoneSize = 15,
	indent = 8, -- from the zone name to the quest title; 0 lines them up
	poiIndent = 0, -- the same, while quest focus icons are on: from the list's left edge to the icon
	spacing = 3, -- between a quest title and its objective lines
	questGap = 4, -- between one quest and the next
	zoneGap = 10, -- above each zone heading
	poiSize = 24, -- width of the round quest icon left of each title (shown only with the game's quest map icons on)
	-- bars
	bars = true,
	barHeight = 3,
	barGap = 4, -- space between an objective and its progress bar (part of the preset)
	barStyle = "smooth", -- "smooth" or "segmented" (one segment per item the objective needs; see Progress.lua)
	-- motion: "off", "snappy" or "smooth"
	animSpeed = "snappy",
	-- frame
	locked = true,
	autoHeight = true,
	minimized = false,
	scale = 1,
	width = 320,
	maxHeight = 520,
	showSections = true, -- settings window: list the open page's sections under it in the side column
	alwaysShowIcons = false, -- keep the Quests bar's icons on screen; off, they fade in when the mouse is over the bar
	backdrop = false, -- dark panel behind the list
	opacity = 0.6, -- its darkness, used while backdrop is on
	padding = 6, -- extra room between the list and the edge of the background or border (only while one shows)
	rounded = true, -- round the background's corners (the border follows them)
	cornerSize = 10, -- their radius (range in FrameBorder.lua, F.BACKDROP_LIMITS)
	-- the border around the frame (UI/FrameBorder.lua); the Appearance page's Frame group turns it on
	border = false,
	borderWeight = "fine", -- line weight: "fine", "standard" or "heavy"
	flourishSize = 1, -- the bronze flourishes' size, and the bronze crest's
	-- colours (hex, without #); the defaults are the game's own tracker colours
	colorZone = "d9b04a", -- zone names while lookZones is "mine"
	colorCount = "ede6d6", -- the number of quests at the right of a zone heading
	colorTitle = "ffd100", -- titles while difficulty colours are off
	colorObjective = "cccccc",
	colorDone = "1aff1a",
	colorBar = "1f9eff", -- progress bars while lookBarColour is "mine"
	colorBadge = "d9b86e",
	boldZones = false,
	-- search (the search text itself is never saved; it starts empty each session)
	searchStyle = "marker", -- "marker" (a strip behind the matched letters, which turn white) or "letters"
	colorSearch = "4fd1b5", -- the marker strip, or the letters in Letters style
	searchZones = false, -- a zone name that matches shows all of that zone's quests
	-- extras (optional; off until a player turns them on)
	superFocus = false, -- show the focus mode target button in the Quests bar
	focusQuest = false, -- the target button is lit (focus mode; only counts while superFocus is on)
	-- the look (Appearance page). A theme is a preset for the look's settings below (Q.THEMES); "custom" is the
	-- player's own mix, kept in lookCustom (not a default) with lookFrom, the theme it started from. A theme never
	-- changes the frame (background, border, their shape and darkness) or anything on another page. The defaults are
	-- the Classic theme, the look the tracker always had. Trying a theme (Q.TryTheme) is never saved.
	theme = "classic", -- "classic", "moonglow" or "custom"
	lookFrom = "classic", -- the theme a custom look started from
	lookBuilder = false, -- the Appearance page shows every part of the look (the builder); off, just a summary
	lookTitle = "gold", -- the Quests bar: "gold" (the game's own bar) or "moonlit" (a silver title over a starred rule)
	lookZones = "mine", -- zone names: "mine" (the Colours page's colour) or "silver"
	moonSky = "plain", -- the Background's colours: "plain", "twilight", "midnight" or "tide"
	moonStars = false, -- twinkling stars on the Background
	moonShooting = false,
	moonAurora = false,
	moonMist = false,
	moonBeam = false, -- a shaft of light that sweeps slowly across the Background
	borderFinish = "polished", -- the Border's metal: "polished", "aged" or "dark" bronze, or "moonsilver"
	borderOrnament = "none", -- at each corner: "none", "flourish" (bronze) or a moonlit accent: "star", "bracket",
	-- "constellation", "leaf" or "edge"
	lookCrest = "none", -- on the top edge: "none", "diamond" (bronze), "crescent" or "tonight" (the real moon's phase)
	moonGleam = "off", -- light on the border: "off", "tide" (a soft wash flowing round it) or "sweep" (a slanted shaft)
	lookBarColour = "mine", -- progress bars: "mine" (the Colours page's), or one of Q.BAR_COLOURS
	moonBars = "flat", -- the light on progress bars: "flat", "crescent", "eclipse", "tide" or "glass" (Progress.lua)
	moonBloom = false, -- a ring of light when an objective finishes
	moonGlow = 0.45, -- strength of every glow in the look
	point = "TOPRIGHT",
	x = -70,
	y = -220,
}

-- Layout presets. Each sets every spacing, text-size and quest icon size value together; changing one of them by hand makes the
-- preset "custom". Width, height, scale and background are never part of a preset, so picking one doesn't move or
-- resize the frame.
Q.PRESETS = {
	comfortable = { fontSize = 13, zoneSize = 15, spacing = 3, questGap = 4, zoneGap = 10, indent = 8, poiIndent = 0, barGap = 4, poiSize = 24 },
	compact = { fontSize = 12, zoneSize = 14, spacing = 1, questGap = 2, zoneGap = 6, indent = 2, poiIndent = 0, barGap = 2, poiSize = 20 },
}
-- The values a preset decides, in a fixed order.
Q.PRESET_KEYS = { "fontSize", "zoneSize", "spacing", "questGap", "zoneGap", "indent", "poiIndent", "barGap", "poiSize" }

-- The look's settings a theme sets, in a fixed order, and the values each choice may take (a saved value outside them
-- falls back to the default in LoadSettings). Adding a theme: add its options here and in OptionsPages.lua, its art
-- where each part is drawn, and a preset in Q.THEMES.
Q.LOOK_KEYS = { "lookTitle", "lookZones", "moonSky", "moonStars", "moonShooting", "moonAurora", "moonMist", "moonBeam",
	"borderFinish", "borderOrnament", "lookCrest", "moonGleam", "lookBarColour", "moonBars", "moonBloom", "moonGlow" }
Q.LOOK_CHOICES = {
	lookTitle = { gold = true, moonlit = true },
	lookZones = { mine = true, silver = true },
	moonSky = { plain = true, twilight = true, midnight = true, tide = true },
	borderFinish = { polished = true, aged = true, dark = true, moonsilver = true },
	borderOrnament = { none = true, flourish = true, star = true, bracket = true, constellation = true, leaf = true,
		edge = true },
	lookCrest = { none = true, diamond = true, crescent = true, tonight = true },
	moonGleam = { off = true, tide = true, sweep = true },
	lookBarColour = { mine = true, moonsilver = true, lilac = true, seafoam = true, amber = true, rose = true },
	moonBars = { flat = true, crescent = true, eclipse = true, tide = true, glass = true },
}
-- The theme colours a progress bar can take besides the player's own.
Q.BAR_COLOURS = { moonsilver = "c8d4ff", lilac = "a78bfa", seafoam = "2ee6b4", amber = "ffb347", rose = "ff4d6d" }
Q.THEMES = {
	classic = { lookTitle = "gold", lookZones = "mine", moonSky = "plain", moonStars = false, moonShooting = false,
		moonAurora = false, moonMist = false, moonBeam = false, borderFinish = "polished", borderOrnament = "none",
		lookCrest = "none", moonGleam = "off", lookBarColour = "mine", moonBars = "flat", moonBloom = false, moonGlow = 0.45 },
	moonglow = { lookTitle = "moonlit", lookZones = "silver", moonSky = "midnight", moonStars = true, moonShooting = true,
		moonAurora = false, moonMist = false, moonBeam = false, borderFinish = "moonsilver", borderOrnament = "edge",
		lookCrest = "crescent", moonGleam = "tide", lookBarColour = "moonsilver", moonBars = "tide", moonBloom = true,
		moonGlow = 0.7 },
}

local db

local function Print(message)
	print("|cffd9b24aClean Quest Tracker:|r " .. message)
end
Q.Print = Print

-- Coalesced timers: several calls with one key inside the delay run the callback once.
local timers = {}
function Q.Debounce(key, delay, callback)
	if timers[key] then
		return
	end
	timers[key] = true
	C_Timer.After(delay, function()
		timers[key] = nil
		callback()
	end)
end

-- Value is safe to read in addon code. Newer clients can hand out secret values in restricted contexts.
function Q.Readable(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value ~= nil
end

-- Shades a texture from one colour to another ("VERTICAL": bottom to top; "HORIZONTAL": left to right), each colour
-- with its opacity. Returns false, leaving the texture as it was, when the client refuses it; a client whose very first
-- gradient fails isn't asked again. Every gradient in the add-on goes through here. The two colour objects are
-- reused: SetGradient copies their values, so shading on every frame makes no new tables.
local gradientFrom, gradientTo
local gradientsRefused, gradientsWork = false, false
function Q.Gradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	if gradientsRefused or not CreateColor then
		return false
	end
	if not gradientFrom then
		gradientFrom, gradientTo = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 1)
	end
	gradientFrom:SetRGBA(r1, g1, b1, a1)
	gradientTo:SetRGBA(r2, g2, b2, a2)
	if pcall(texture.SetGradient, texture, orientation, gradientFrom, gradientTo) then
		gradientsWork = true
		return true
	end
	gradientsRefused = not gradientsWork
	return false
end

-- Show and hide a texture that remembers whether it shows (qcOn), so showing what shows or hiding what is hidden costs
-- nothing: for pieces drawn frame after frame (the look's moving parts, the light on bars). Such a texture must only be
-- shown and hidden through these.
function Q.ShowPart(texture)
	if not texture.qcOn then
		texture:Show()
		texture.qcOn = true
	end
end

function Q.HidePart(texture)
	if texture.qcOn then
		texture:Hide()
		texture.qcOn = nil
	end
end

-- Paints a texture with a gradient in one colour, from one opacity to another. Falls back to the average opacity if
-- the client refuses the gradient call.
function Q.Fade(texture, orientation, color, fromAlpha, toAlpha)
	texture:SetColorTexture(1, 1, 1, 1)
	if not Q.Gradient(texture, orientation, color[1], color[2], color[3], fromAlpha, color[1], color[2], color[3], toAlpha) then
		texture:SetColorTexture(color[1], color[2], color[3], (fromAlpha + toAlpha) / 2)
	end
end

-- True when the client has a texture atlas by this name (atlases differ between game versions).
function Q.HasAtlas(name)
	return type(name) == "string" and name ~= "" and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(name) ~= nil or false
end

-- Sets a FontString's size while keeping its font file. `flags` (such as "OUTLINE") replaces the flags it had first;
-- leave it out to keep them. Only touches the font when something changes.
function Q.Font(fontString, size, flags)
	if not fontString then
		return
	end
	if fontString.qcBaseFlags == nil then
		local _, _, baseFlags = fontString:GetFont()
		fontString.qcBaseFlags = baseFlags or ""
	end
	flags = flags or fontString.qcBaseFlags
	if fontString.qcSize == size and fontString.qcFlags == flags then
		return
	end
	local file = fontString:GetFont()
	if file then
		fontString:SetFont(file, size, flags)
		fontString.qcSize, fontString.qcFlags = size, flags
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Colours. Saved as hex strings; read as { r, g, b } tables, cached so a colour that hasn't changed is the same table
-- (Blizzard's line code only recolours text when it is handed a different table).
------------------------------------------------------------------------------------------------------------------------
local colorCache = {}

local function ParseHex(hex)
	hex = type(hex) == "string" and hex:gsub("^#", "") or ""
	local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
	if not r then
		return nil
	end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- A colour from its hex, as a table with r, g, b and a `reverse` (the lighter shade Blizzard's line code uses while the
-- mouse is over a quest); nil for a hex that can't be read.
function Q.ColorOf(hex)
	local r, g, b = ParseHex(hex)
	if not r then
		return nil
	end
	return { r = r, g = g, b = b, hex = hex, reverse = { r = r + (1 - r) * 0.35, g = g + (1 - g) * 0.35, b = b + (1 - b) * 0.35 } }
end

-- The colour for a colour setting (colorZone, colorBar...), as Q.ColorOf makes it.
function Q.Color(key)
	local hex = Q.db and Q.db[key] or Q.defaults[key]
	local cached = colorCache[key]
	if cached and cached.hex == hex then
		return cached
	end
	local color = Q.ColorOf(hex) or Q.ColorOf(Q.defaults[key])
	color.hex = hex
	colorCache[key] = color
	return color
end

------------------------------------------------------------------------------------------------------------------------
-- Motion: one speed setting for every transition, and a small tween driver.
--
-- Transitions only ever change how frames look on the way to their final state (alpha, rotation, a temporary
-- translation, the host frame's height); the layout itself is always applied at once. They are skipped in combat, so
-- nothing moves while secure quest item buttons are locked in place. Scrolling is the exception: mouse-wheel scrolls
-- always glide, at a fixed speed whatever the animation setting (the quest list itself still refuses to scroll in
-- combat while an item button is on screen).
------------------------------------------------------------------------------------------------------------------------
local Motion = {}
Q.Motion = Motion

Motion.SPEEDS = { off = 0, snappy = 0.15, smooth = 0.25 }
Motion.SCROLL = 0.2 -- seconds for a scroll to glide to where the wheel (or a section link) sends it

-- Seconds for one transition at the chosen speed; 0 means snap.
function Motion.Duration()
	if not Q.db or InCombatLockdown() then
		return 0
	end
	return Motion.SPEEDS[Q.db.animSpeed] or Motion.SPEEDS.smooth
end

function Motion.On()
	return Motion.Duration() > 0
end

local function EaseOut(t)
	return 1 - (1 - t) ^ 3
end

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
	local finished
	for key, tween in pairs(tweens) do
		tween.time = tween.time + elapsed
		local progress = math.min(1, tween.time / tween.duration)
		tween.apply(tween.from + (tween.to - tween.from) * EaseOut(progress))
		if progress >= 1 then
			tweens[key] = nil
			finished = finished or {}
			finished[#finished + 1] = tween
		end
	end
	for _, tween in ipairs(finished or {}) do
		if tween.done then
			tween.done()
		end
	end
	if not next(tweens) then
		self:Hide()
	end
end)

-- Eases a number from `from` to `to`, calling apply(value) every frame and done() at the end. One tween per key: a
-- new tween on the same key replaces the old one. With no duration it applies the end value at once.
function Motion.Tween(key, from, to, duration, apply, done)
	tweens[key] = nil
	if not duration or duration <= 0 or from == to then
		apply(to)
		if done then
			done()
		end
		return
	end
	tweens[key] = { from = from, to = to, duration = duration, time = 0, apply = apply, done = done }
	apply(from)
	driver:Show()
end

-- The value a running tween is heading to, or nil.
function Motion.Target(key)
	local tween = tweens[key]
	return tween and tween.to
end

-- Drops a tween where it is, without applying its end value.
function Motion.Stop(key)
	tweens[key] = nil
end

-- Ends a tween at once, at its end value.
function Motion.Finish(key)
	local tween = tweens[key]
	if tween then
		tweens[key] = nil
		tween.apply(tween.to)
		if tween.done then
			tween.done()
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Compatibility: another add-on that replaces the quest tracker owns it. Clean Quest Tracker steps aside rather than fight.
------------------------------------------------------------------------------------------------------------------------
local OWNERS = {
	{ addon = "EllesmereUIQuestTracker", label = "EllesmereUI Quest Tracker" },
	{ addon = "!KalielsTracker", label = "Kaliel's Tracker" },
}

local function FindOwner()
	for _, owner in ipairs(OWNERS) do
		if C_AddOns.IsAddOnLoaded(owner.addon) then
			return owner.label
		end
	end
	local questie = rawget(_G, "Questie")
	local profile = questie and questie.db and questie.db.profile
	if profile and profile.trackerEnabled then
		return "Questie's tracker"
	end
end

-- True when Clean Quest Tracker should draw the quest list on this character.
function Q.Active()
	return db ~= nil and db.enabled and not Q.pausedBy
end

------------------------------------------------------------------------------------------------------------------------
-- Saved settings
------------------------------------------------------------------------------------------------------------------------

-- Older versions stored a different shape. Each step carries over what still means the same thing.
local function MigrateFrom05(saved)
	if saved.transparent == true then
		saved.opacity = 0
	end
	if type(saved.height) == "number" then
		saved.maxHeight = math.floor(saved.height + 0.5)
	end
	-- The old settings button cycled icon > text > hidden, which left the party count off by accident.
	if saved.partyStyle == "hidden" then
		saved.party = true
		saved.partyStyle = "icon"
	end
	-- Old positions were TOPLEFT offsets from the screen's bottom-left. Frame.lua converts them once at login.
	if saved.relativePoint == "BOTTOMLEFT" and type(saved.x) == "number" and type(saved.y) == "number" then
		saved.legacyPosition = { x = saved.x, y = saved.y, width = saved.width, scale = saved.scale or 1 }
		saved.point, saved.x, saved.y = nil, nil, nil
	end
	for _, key in ipairs({ "transparent", "height", "centerHeaders", "hideAllHeader", "relativePoint" }) do
		saved[key] = nil
	end
end

local function MigrateFrom06(saved)
	-- The Quests heading is always centred now.
	saved.centerHeader = nil
	-- Background became a switch plus a darkness.
	if type(saved.opacity) == "number" and saved.opacity > 0 then
		saved.backdrop = true
	else
		saved.backdrop, saved.opacity = nil, nil
	end
	-- Indent is now measured from the zone name. Before, quests also sat behind a gutter kept for quest map icons (30,
	-- or 6 in Compact). A preset takes its refined values; a hand-tuned indent is converted so it looks the same.
	local preset = saved.preset and Q.PRESETS[saved.preset]
	if preset then
		for key, value in pairs(preset) do
			saved[key] = value
		end
	elseif type(saved.indent) == "number" then
		local gutter = type(saved.gutter) == "number" and saved.gutter or 30
		saved.indent = math.max(0, math.min(40, saved.indent + gutter - 18))
	end
	saved.gutter = nil
end

local function Migrate(saved)
	local schema = saved.schema or 1
	if schema < Q.SCHEMA and next(saved) ~= nil then
		if schema < 2 then
			MigrateFrom05(saved)
		end
		if schema < 3 then
			MigrateFrom06(saved)
		end
		if schema < 4 then
			-- 0.8.1 tightened both presets' indent (Comfortable 20 to 8, Compact 14 to 2). Anyone still on a preset
			-- moves with it; a hand-set indent stays.
			if saved.preset == "comfortable" and saved.indent == 20 then
				saved.indent = 8
			elseif saved.preset == "compact" and saved.indent == 14 then
				saved.indent = 2
			end
			-- Space above bars joined the presets (Comfortable 4, Compact 2).
			local preset = saved.preset and Q.PRESETS[saved.preset]
			if preset then
				saved.barGap = preset.barGap
			end
		end
		if schema < 5 then
			-- The quest icon's size joined the presets (Comfortable 24; Compact 20, so the icons no longer
			-- overlap). Only someone still on Compact is moved here; everyone else gets the default from the defaults above.
			if saved.preset == "compact" and saved.poiSize == nil then
				saved.poiSize = Q.PRESETS.compact.poiSize
			end
		end
		if schema < 6 then
			-- With quest focus icons on, the indent became its own setting, measured from the list's left edge to the
			-- icon. Titles used to sit at the larger of the zone indent and 32 (a 28px icon plus 4); now they sit at the
			-- icon's room plus this value. A long indent converts so its titles stay where they were; a shorter one
			-- converts to 0, and those titles move left with the smaller icon.
			if saved.poiIndent == nil and type(saved.indent) == "number" then
				local T = Q.Tracker
				local room = T.PoiRoom(tonumber(saved.poiSize) or Q.defaults.poiSize)
				local start = saved.grouping == false and T.UNGROUPED_OFFSET_X or T.ZONE_OFFSET_X
				saved.poiIndent = math.max(0, start + saved.indent - room)
			end
		end
		if schema < 7 then
			-- Test builds of the Themes page saved some settings in other shapes; bring them to this version's.
			if type(saved.moonBeam) == "string" then
				saved.moonBeam = saved.moonBeam ~= "off" -- was "off", "sweep" or "lantern"
			end
			if saved.moonGlint ~= nil and saved.moonGleam == nil then
				saved.moonGleam = saved.moonGlint == true and "tide" or "off" -- the travelling glint became the border light
			end
			if saved.moonBars == "sheen" then
				saved.moonBars = "glass"
			end
			-- Themes arrived. Corner flourishes and the crest were switches; they are choices now.
			if saved.borderFlourish == true then
				saved.borderOrnament = "flourish"
			end
			if saved.borderCrest == true then
				saved.lookCrest = "diamond"
			end
			saved.borderFlourish, saved.borderCrest = nil, nil
			-- Fills in Moonglow's look for every part not saved yet.
			local function Moonglow()
				for key, value in pairs(Q.THEMES.moonglow) do
					if saved[key] == nil then
						saved[key] = value
					end
				end
				saved.theme, saved.lookFrom = "moonglow", "moonglow"
			end
			-- The Extras page's background theme became Moonglow. It only showed with the Background on; those players
			-- get Moonglow, keeping their own bronze if they had a border (the old theme only coloured the background).
			-- Every save already holds a finish (older versions saved the defaults too), so it is decided here.
			if saved.theme == nil and saved.bgTheme == "moonglow" and saved.backdrop then
				if not saved.border then
					saved.borderFinish = "moonsilver"
				end
				Moonglow()
			end
			saved.bgTheme = nil
			-- Test builds of the Themes page saved Moonglow with its own settings; carry their picks over.
			if saved.theme == "moonglow" and saved.lookTitle == nil then
				saved.lookTitle = "moonlit"
				saved.lookZones = saved.themeZoneColour == false and "mine" or "silver"
				saved.lookBarColour = "moonsilver"
				if saved.moonBorder ~= "bronze" then
					saved.borderFinish = "moonsilver"
				end
				-- A choice turned off stays off (Moonglow() below would otherwise fill in its own).
				if type(saved.moonCorners) == "string" then
					saved.borderOrnament = saved.moonCorners ~= "off" and saved.moonCorners or saved.borderOrnament or "none"
				end
				if type(saved.moonCrest) == "string" then
					saved.lookCrest = ({ crescent = "crescent", live = "tonight" })[saved.moonCrest] or saved.lookCrest or "none"
				end
				Moonglow()
			end
			for _, key in ipairs({ "moonPreset", "moonCustom", "moonBorder", "moonCorners", "moonCrest", "themeZoneColour",
				"moonGlint", "moonHeader", "moonShape", "moonZones", "moonLine", "moonTake", "moonglow", "moonChips",
				"moonBullets", "moonHover" }) do
				saved[key] = nil
			end
		end
	end
	saved.schema = Q.SCHEMA
end

-- For the offline tests (tests/test_theme.lua).
Q._internal = { Migrate = Migrate }

local function LoadSettings()
	-- The add-on was called Quest Companion, then Simple Quest Tracker, and saved its settings under those names. If
	-- one of those tables is around (its settings file was carried over under the new name), it becomes this one.
	if type(CleanQuestTrackerDB) ~= "table" then
		for _, older in ipairs({ "SimpleQuestTrackerDB", "QuestCompanionDB" }) do
			if type(rawget(_G, older)) == "table" then
				CleanQuestTrackerDB = rawget(_G, older)
				break
			end
		end
	end
	CleanQuestTrackerDB = type(CleanQuestTrackerDB) == "table" and CleanQuestTrackerDB or {}
	db = CleanQuestTrackerDB
	Migrate(db)
	for key, value in pairs(Q.defaults) do
		if db[key] == nil then
			db[key] = value
		end
	end
	-- The first animation build saved Smooth as everyone's speed before Snappy became the default. Move those over
	-- once; a speed picked after this keeps.
	if not db.animDefaultSet then
		if db.animSpeed == "smooth" then
			db.animSpeed = "snappy"
		end
		db.animDefaultSet = true
	end
	-- Relaxed was removed; anyone who picked it gets the slowest speed left.
	if db.animSpeed == "relaxed" or not Q.Motion.SPEEDS[db.animSpeed] then
		db.animSpeed = "smooth"
	end
	-- A look value of the wrong kind, or a choice this version doesn't have, falls back to the default.
	for _, key in ipairs(Q.LOOK_KEYS) do
		if not Q.LookValueOK(key, db[key]) then
			db[key] = Q.defaults[key]
		end
	end
	db.moonGlow = math.max(0, math.min(1, db.moonGlow))
	db.lookCustom = type(db.lookCustom) == "table" and db.lookCustom or nil
	if not Q.THEMES[db.lookFrom] then
		db.lookFrom = "classic"
	end
	-- Name the theme the look matches (a hand-edited or unknown name included), or Custom.
	Q.UpdateThemeName()
	-- Settings from before presets existed: name the preset they match, or Custom if they were changed by hand.
	if db.preset ~= "compact" then
		Q.UpdatePresetName()
	end
	db.collapsed = type(db.collapsed) == "table" and db.collapsed or {}
	db.zoneOf = type(db.zoneOf) == "table" and db.zoneOf or {}
	-- Each character's quest order (Tracker.lua, Rank): name-realm -> { [questID] = place }.
	db.questOrder = type(db.questOrder) == "table" and db.questOrder or {}
	db.schema = Q.SCHEMA
	Q.db = db
end

-- Applies a layout preset's values and redraws.
function Q.ApplyPreset(name)
	local preset = Q.PRESETS[name]
	if not preset then
		return
	end
	for key, value in pairs(preset) do
		db[key] = value
	end
	db.preset = name
	Q.Apply(true)
end

-- After a spacing or text-size value changes by hand: the preset it still matches, or "custom".
function Q.UpdatePresetName()
	for name, preset in pairs(Q.PRESETS) do
		local same = true
		for _, key in ipairs(Q.PRESET_KEYS) do
			if db[key] ~= preset[key] then
				same = false
				break
			end
		end
		if same then
			db.preset = name
			return
		end
	end
	db.preset = "custom"
end

-- Whether `value` is one a look setting can take: the default's kind, and a choice this version has.
function Q.LookValueOK(key, value)
	local choices = Q.LOOK_CHOICES[key]
	return type(value) == type(Q.defaults[key]) and (not choices or choices[value]) and true or false
end

-- Puts a theme's look in place ("custom" brings back the player's own mix, if there is one), ending any try.
function Q.ApplyTheme(name)
	local look = Q.THEMES[name] or (name == "custom" and db.lookCustom)
	if not look then
		return
	end
	-- A kept mix only brings back values of the right kind (the saved file may have been edited by hand).
	for _, key in ipairs(Q.LOOK_KEYS) do
		if Q.LookValueOK(key, look[key]) then
			db[key] = look[key]
		end
	end
	-- Custom keeps the theme it started from (lookFrom); a theme becomes the one a new mix would start from.
	db.theme = name
	Q.trial = nil
	Q.UpdateThemeName()
	Q.Apply(true)
end

-- After a look setting changes by hand: the theme it still matches, or "custom", whose mix is kept (lookCustom) so the
-- Custom card can bring it back after trying or using a theme.
function Q.UpdateThemeName()
	for name, look in pairs(Q.THEMES) do
		local same = true
		for _, key in ipairs(Q.LOOK_KEYS) do
			if db[key] ~= look[key] then
				same = false
				break
			end
		end
		if same then
			db.theme = name
			return
		end
	end
	if db.theme ~= "custom" and Q.THEMES[db.theme] then
		db.lookFrom = db.theme
	end
	db.theme = "custom"
	db.lookCustom = {}
	for _, key in ipairs(Q.LOOK_KEYS) do
		db.lookCustom[key] = db[key]
	end
end

-- Trying a theme: Q.trial = { theme, frame } shows that theme's look (and, with `frame`, a background and border the
-- player hasn't turned on) until it is kept or ended. It is never saved: closing the settings window or /reload ends it.
Q.trial = nil

-- The theme on show: the one being tried, or the saved one ("custom" included).
function Q.Theme()
	return Q.trial and Q.trial.theme or (db and db.theme) or Q.defaults.theme
end

-- A look setting as it shows: the tried theme's while trying, otherwise the saved one. Everything that draws the look
-- reads it through here.
function Q.Look(key)
	local trial = Q.trial and Q.THEMES[Q.trial.theme]
	if trial and trial[key] ~= nil then
		return trial[key]
	end
	local value = db and db[key]
	if value == nil then
		return Q.defaults[key]
	end
	return value
end

function Q.TryTheme(theme)
	if not Q.THEMES[theme] or theme == db.theme then
		Q.trial = nil
	else
		Q.trial = { theme = theme, frame = not Q.trial or Q.trial.frame }
	end
	Q.Apply(true)
end

-- Ends a try. `keep` puts the tried theme's look in place; the background and border it borrowed are not kept.
function Q.EndTrial(keep)
	if not Q.trial then
		return
	end
	local theme = Q.trial.theme
	Q.trial = nil
	if keep then
		Q.ApplyTheme(theme)
	else
		Q.Apply(true)
	end
end

function Q.SetTrialFrame(on)
	if Q.trial then
		Q.trial.frame = on and true or false
		Q.Apply(true)
	end
end

-- Restores every setting, including frame size and position, and unfolds every zone.
function Q.ResetSettings()
	Q.trial = nil
	for key, value in pairs(Q.defaults) do
		db[key] = value
	end
	db.lookCustom = nil
	db.collapsed = {}
	db.collapsedBeforeFocus = nil
	Q.Apply()
end

-- Applies every setting: frame geometry and look, native tracker visibility and a fresh quest layout. The settings
-- panel passes `fromPanel` so a control being dragged is not reset under the cursor.
function Q.Apply(fromPanel)
	if not Q.ready then
		return
	end
	Q.Tracker.ApplyNativeVisibility()
	Q.Frame.Apply()
	-- Settings changes re-flow the list at once; gliding every row on each slider step would only get in the way.
	Q.Tracker.MarkDirty(true)
	if not fromPanel and Q.Options and Q.Options.Refresh then
		Q.Options.Refresh()
	end
end

function Q.Refresh()
	if Q.ready then
		Q.Tracker.MarkDirty()
	end
end

function Q.SetLocked(locked)
	db.locked = locked and true or false
	Q.Frame.Apply()
	if Q.Options and Q.Options.Refresh then
		Q.Options.Refresh()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------------------------------------------------
local function Start()
	if not ObjectiveTrackerFrame and C_AddOns.LoadAddOn then
		C_AddOns.LoadAddOn("Blizzard_ObjectiveTracker")
	end
	if not (ObjectiveTrackerFrame and QuestObjectiveTrackerMixin and ObjectiveTrackerManager) then
		Print("Blizzard's quest tracker code is not available on this client, so Clean Quest Tracker is off.")
		return
	end
	Q.pausedBy = FindOwner()
	Q.Frame.Create()
	Q.Tracker.Create(Q.Frame.content)
	Q.ready = true
	Q.Apply()
	if Q.pausedBy then
		Print(("Paused because %s is enabled on this character. Turn one of them off in the AddOns list."):format(Q.pausedBy))
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
-- A party member coming online can bring their quest log with them. Registered with pcall: not every client has it.
pcall(events.RegisterEvent, events, "UNIT_CONNECTION")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			LoadSettings()
		end
		return
	elseif event == "PLAYER_LOGIN" then
		Start()
		return
	end
	if not Q.ready then
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		Q.Tracker.OnCombatEnded()
		Q.Frame.OnCombatEnded()
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		-- Your own log changes already arrive as QUEST_LOG_UPDATE; only party members matter here.
		-- A party member's quest log can arrive in pieces, so check again a little later too.
		-- The unit can arrive restricted ("secret"); then it can't be read, so refresh anyway.
		local unit = Q.Readable(arg1) and arg1 or nil
		-- In a raid the same change can arrive as "raidN" rather than "partyN".
		if not unit or (type(unit) == "string" and (unit:find("^party") or unit:find("^raid"))) then
			Q.Debounce("party", 0.25, Q.Refresh)
			Q.Debounce("party-late", 1.5, Q.Refresh)
		end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION" then
		Q.Debounce("party", 0.25, Q.Refresh)
		Q.Debounce("party-late", 1.5, Q.Refresh)
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		Q.Frame.Apply()
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
		-- A new zone re-sorts the list (current zone first) and, in focus mode, opens the new zone instead.
		Q.Tracker.OnZoneChanged()
		if event == "PLAYER_ENTERING_WORLD" then
			-- Right after a loading screen the map can still be missing; look again once it has settled.
			C_Timer.After(1, function()
				Q.Tracker.OnZoneChanged(true)
			end)
		end
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		-- Walking into a cave or building can change the zone name the game reports without a new area.
		Q.Tracker.OnZoneChanged(true)
	else
		Q.Refresh()
	end
end)
