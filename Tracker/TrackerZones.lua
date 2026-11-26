-- Clean Quest Tracker: zone heading rows (arrow, name, quest count and the line under it), which zone you're in, and
-- the zone tools: folding a zone, focus on the current zone, and expand or collapse all. The list (Tracker.lua) lays
-- out a heading row for each zone with T.StyleZone and sorts your zone first with T.CurrentZone.

local _, Q = ...
local T = Q.Tracker

local Motion = Q.Motion
local HasAtlas = Q.HasAtlas
local ZONE_OFFSET_X = T.ZONE_OFFSET_X
local ZONE_TEMPLATE = T.ZONE_TEMPLATE
local ZONE_COUNT_WIDTH = 24
local RULE_ALPHA = 0.35 -- the line under a zone heading, in the zone colour
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"

------------------------------------------------------------------------------------------------------------------------
-- Zone heading rows
------------------------------------------------------------------------------------------------------------------------
local CHEVRON_OPEN, CHEVRON_FOLDED = -math.pi / 2, 0

-- Points the zone arrow right (folded) or down (open), turning it when `animate` is set and it already had a direction.
local function SetChevron(block, folded, animate)
	local target = folded and CHEVRON_FOLDED or CHEVRON_OPEN
	if block.qcChevronTarget == target then
		return
	end
	local from = block.qcChevronTarget
	block.qcChevronTarget = target
	local chevron = block.qcChevron
	local duration = (animate and from) and Motion.Duration() or 0
	Motion.Tween(chevron, from or target, target, duration, function(angle)
		chevron:SetRotation(angle)
	end)
end

local function ZoneParts(block)
	if block.qcRule then
		return
	end
	local chevron = block:CreateTexture(nil, "ARTWORK")
	if HasAtlas("common-dropdown-icon-next") then
		chevron:SetAtlas("common-dropdown-icon-next")
	else
		chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	end
	chevron:SetSize(10, 10)
	block.qcChevron = chevron

	local count = block:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	count:SetJustifyH("RIGHT")
	block.qcCount = count

	local rule = block:CreateTexture(nil, "BACKGROUND")
	rule:SetHeight(1)
	block.qcRule = rule

	-- Hovering a heading: Blizzard's own highlight would paint the name its header gold on top of ours, so on a zone row
	-- this block's highlight is the zone colour's lighter shade instead (an override on this pooled block only; it
	-- passes quest rows, which reuse blocks, to Blizzard's).
	local blizzardHighlight = block.UpdateHighlight
	block.UpdateHighlight = function(self, ...)
		if self.qcZone then
			local color = T.ZoneColor()
			T.PaintZone(self, self.isHighlighted and color.reverse or color)
		elseif blizzardHighlight then
			return blizzardHighlight(self, ...)
		end
	end

	-- The whole row toggles, not just the words.
	local button = block.HeaderButton
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", block, "TOPLEFT", -ZONE_OFFSET_X, 0)
	button:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT")
end

-- Colours a zone heading and its arrow. Bold zone headings use a shadow in the text's own colour, shifted one pixel
-- across, which thickens the letters; the game font has no bold, and its outline setting would add a dark edge
-- instead. Without bold, the heading keeps the font's usual dark drop shadow.
function T.PaintZone(block, color)
	local text = block.HeaderText
	if not block.qcShadow then
		local x, y = text:GetShadowOffset()
		local r, g, b, a = text:GetShadowColor()
		block.qcShadow = { x = x or 1, y = y or -1, r = r or 0, g = g or 0, b = b or 0, a = a or 1 }
	end
	text:SetTextColor(color.r, color.g, color.b)
	if Q.db.boldZones then
		text:SetShadowColor(color.r, color.g, color.b, 1)
		text:SetShadowOffset(1, 0)
	else
		local shadow = block.qcShadow
		text:SetShadowColor(shadow.r, shadow.g, shadow.b, shadow.a)
		text:SetShadowOffset(shadow.x, shadow.y)
	end
	block.qcChevron:SetVertexColor(color.r, color.g, color.b)
end

------------------------------------------------------------------------------------------------------------------------
-- Moonsilver zone names (Appearance page): the name in the moonlit header's silver over a faint moonlight, and a silver
-- line under the heading that fades out to the right. The quest count keeps its colour.
------------------------------------------------------------------------------------------------------------------------
local function MoonParts(block)
	if block.qcMoonHalo then
		return
	end
	block.qcMoonHalo = block:CreateTexture(nil, "BACKGROUND", nil, -1)
	block.qcMoonHalo:SetTexture(MEDIA .. "BackdropGlow")
	block.qcMoonRule = block:CreateTexture(nil, "BACKGROUND")
	block.qcMoonRule:SetHeight(1)
end

-- Styles the heading for Moonglow, or hides Moonglow's parts; returns true while Moonglow styles it (its own line under
-- the heading is then not wanted). With My colour picked for zone names (Appearance page) the heading stays plain.
local function StyleMoonZone(block, room)
	if Q.Look("lookZones") ~= "silver" then
		if block.qcMoonHalo then
			block.qcMoonHalo:Hide()
			block.qcMoonRule:Hide()
		end
		return false
	end
	MoonParts(block)
	local strength = Q.Frame.MoonStrength()
	local text = block.HeaderText
	-- Kept faint, so the name reads clearly over it.
	local moon = Q.Frame.MOON
	local halo = block.qcMoonHalo
	halo:SetVertexColor(moon.halo[1], moon.halo[2], moon.halo[3], moon.haloAlpha * strength)
	halo:ClearAllPoints()
	halo:SetPoint("LEFT", text, "LEFT", -8, 0)
	halo:SetSize(math.max(0, math.min(text:GetStringWidth() or 0, room)) + moon.haloPad, moon.haloHeight)
	halo:Show()
	local rule = block.qcMoonRule
	Q.Fade(rule, "HORIZONTAL", moon.rule, 0.3 + 0.25 * strength, 0)
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -ZONE_OFFSET_X + 4, -4)
	rule:SetPoint("RIGHT", block, "RIGHT")
	rule:Show()
	return true
end

-- The zone names' colour (Appearance page): moonsilver (a little lighter while hovered), or the Colours page's colour.
-- Hovering uses its `reverse`.
function T.ZoneColor()
	if Q.Look("lookZones") == "silver" then
		return Q.Frame.MOON.zone
	end
	return Q.Color("colorZone")
end

-- While searching, every zone in the list is open (it has matches) and its count reads matches/total.
function T.StyleZone(block, group)
	local db = Q.db
	local searching = T.SearchActive()
	local folded = (db.collapsed[group.name] and not searching) and true or false
	ZoneParts(block)
	block.qcZone = group.name
	-- "3/12" is wider than a plain count.
	block:AdjustRightEdgeOffset(-ZONE_COUNT_WIDTH - (searching and 16 or 0))
	Q.Font(block.HeaderText, math.max(db.zoneSize, db.fontSize + 1))
	block:SetHeader(db.searchZones and T.MarkSearch(group.name) or group.name)
	-- Moonsilver or the player's own colour (Zone names, Appearance page).
	local silver = Q.Look("lookZones") == "silver"
	local zoneColor = T.ZoneColor()
	-- The arrow's art is gold; greyed first, it takes Moonglow's silver.
	if block.qcChevron.SetDesaturated then
		block.qcChevron:SetDesaturated(silver)
	end
	local color = block.isHighlighted and zoneColor.reverse or zoneColor
	block.qcRule:SetColorTexture(zoneColor.r, zoneColor.g, zoneColor.b, RULE_ALPHA)
	block.height = block.height + 7

	block.qcChevron:ClearAllPoints()
	block.qcChevron:SetPoint("RIGHT", block.HeaderText, "LEFT", -4, 0)
	SetChevron(block, folded, block.qcChevronZone == group.name)
	block.qcChevronZone = group.name
	T.PaintZone(block, color)

	block.qcCount:ClearAllPoints()
	block.qcCount:SetPoint("RIGHT", block, "TOPRIGHT", -2, -(block.HeaderText:GetHeight() / 2))
	if searching and group.total then
		block.qcCount:SetFormattedText("%d/%d", #group.quests, group.total)
	else
		block.qcCount:SetText(#group.quests)
	end
	local countColor = Q.Color("colorCount")
	block.qcCount:SetTextColor(countColor.r, countColor.g, countColor.b)

	block.qcRule:ClearAllPoints()
	block.qcRule:SetPoint("TOPLEFT", block.HeaderText, "BOTTOMLEFT", -ZONE_OFFSET_X + 4, -4)
	block.qcRule:SetPoint("RIGHT", block, "RIGHT")
	-- The room between the name's start and the count, for Moonglow's moonlight behind the name.
	local width = block:GetWidth()
	if not width or width <= 0 then
		width = (Q.Frame.content and Q.Frame.content:GetWidth() or 0) - (block.offsetX or ZONE_OFFSET_X)
	end
	local room = width - ZONE_COUNT_WIDTH - (searching and 16 or 0) - 6
	block.qcRule:SetShown(not StyleMoonZone(block, room))
end

------------------------------------------------------------------------------------------------------------------------
-- Where you are
------------------------------------------------------------------------------------------------------------------------
-- The names your current place goes by, best first: the zone the game reports, the zone-level map you're on (a cave,
-- mine or building can report its own name while its map still sits in Westfall), and the zone text. They are read on
-- zone events only, so a redraw for any other reason (a quest completing, an objective ticking) never re-sorts zones.
local places = {}

local function Name(value)
	if Q.Readable(value) and type(value) == "string" and value ~= "" then
		return value
	end
end

-- The name of the zone-level map you're on, climbing out of dungeon, building and sub-area maps.
local function ZoneMapName()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then
		return nil
	end
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 8 do
		if not ok or not Q.Readable(mapID) or not mapID then
			return nil
		end
		local info
		ok, info = pcall(C_Map.GetMapInfo, mapID)
		if not ok or not info or not Q.Readable(info.mapType) or not info.mapType then
			return nil
		end
		if info.mapType == zoneType then
			return Name(info.name)
		elseif info.mapType < zoneType then
			return nil -- climbed past the zone to a continent
		end
		mapID = info.parentMapID
	end
	return nil
end

-- Reads where you are again. Returns true when any of the names changed. During a loading screen the game has no zone
-- yet; the last place is kept.
function T.ReadWhere()
	local real = Name(GetRealZoneText and GetRealZoneText())
	if not real then
		return false
	end
	local fresh = { real }
	for _, extra in ipairs({ ZoneMapName() or false, Name(GetZoneText and GetZoneText()) or false }) do
		if extra and extra ~= real then
			fresh[#fresh + 1] = extra
		end
	end
	local changed = #fresh ~= #places
	for index, name in ipairs(fresh) do
		changed = changed or places[index] ~= name
	end
	places = fresh
	return changed
end

-- The zone heading you're in: the first of your place's names that is a zone in `names` (default: the zones listed in
-- the last layout), or nil when none of your quests are in this zone.
function T.CurrentZone(names)
	if not places[1] then
		T.ReadWhere()
	end
	for _, place in ipairs(places) do
		for _, name in ipairs(names or T.zoneNames or {}) do
			if name == place then
				return name
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------------------------------------------------
-- Zone tools: fold one zone, focus the current zone, expand or collapse all
------------------------------------------------------------------------------------------------------------------------
local function TurnZoneArrow(name, folded)
	-- While searching every listed zone stays open, so the arrow would only swing and swing back.
	if T.SearchActive() then
		return
	end
	local block = T.module and T.module:GetExistingBlock("qczone:" .. name, ZONE_TEMPLATE)
	if block and block.qcChevron then
		SetChevron(block, folded, true)
	end
end

-- Folding a zone by hand ends focus mode, so the list doesn't undo the player's choice on the next zone change.
-- Folding fades the zone's quests out first; the rows below then glide up in the layout that follows.
function T.ToggleZone(name)
	if T.IsFolding() then
		return
	end
	local closing = not Q.db.collapsed[name]
	TurnZoneArrow(name, closing)
	local function Apply()
		Q.db.collapsed[name] = closing or nil
		Q.db.focusZone = false
		Q.db.collapsedBeforeFocus = nil
		T.MarkDirty()
		Q.Frame.UpdateHeader()
	end
	if closing then
		T.FadeOutThen({ [name] = true }, Apply)
	else
		Apply()
	end
end

-- Folds every zone group except the one you're in, and keeps doing so as you travel: the list does the folding on each
-- redraw while focus is on (Tracker.lua, M:LayoutContents). Returns whether your zone has a heading.
function T.FocusCurrentZone()
	Q.db.focusZone = true
	T.MarkDirty()
	return T.CurrentZone() ~= nil
end

-- The pin button: on, remember how the zones were folded and keep only the current zone open; off, put them back.
function T.ToggleFocus()
	local db = Q.db
	if T.IsFolding() then
		return db.focusZone
	end
	if db.focusZone then
		db.focusZone = false
		wipe(db.collapsed)
		for name, folded in pairs(db.collapsedBeforeFocus or {}) do
			db.collapsed[name] = folded
		end
		db.collapsedBeforeFocus = nil
		T.MarkDirty()
		return false
	end
	local saved = {}
	for name, folded in pairs(db.collapsed) do
		saved[name] = folded
	end
	db.collapsedBeforeFocus = saved
	-- The pin lights up straight away; the other zones fade, then fold.
	local here = T.CurrentZone()
	local closing = {}
	for _, name in ipairs(T.zoneNames or {}) do
		if name ~= here and not db.collapsed[name] then
			closing[name] = true
			TurnZoneArrow(name, true)
		end
	end
	db.focusZone = true
	T.FadeOutThen(closing, T.FocusCurrentZone)
	return true
end

-- True when every zone in the list is open.
function T.AllExpanded()
	for _, name in ipairs(T.zoneNames or {}) do
		if Q.db.collapsed[name] then
			return false
		end
	end
	return true
end

-- The arrows button: opens every zone, or folds them all when they're all open already. Either way it ends focus mode.
function T.ToggleAll()
	local db = Q.db
	if T.IsFolding() then
		return
	end
	db.focusZone = false
	db.collapsedBeforeFocus = nil
	if not T.AllExpanded() then
		wipe(db.collapsed)
		T.MarkDirty()
		return
	end
	local closing = {}
	for _, name in ipairs(T.zoneNames or {}) do
		closing[name] = true
		TurnZoneArrow(name, true)
	end
	T.FadeOutThen(closing, function()
		for name in pairs(closing) do
			db.collapsed[name] = true
		end
		T.MarkDirty()
		Q.Frame.UpdateHeader()
	end)
end

-- A new zone (or, with `minor`, a new sub-area) re-reads where you are. A sub-area that leaves every name the same
-- changes nothing, so walking around a zone doesn't redraw the list.
function T.OnZoneChanged(minor)
	local changed = T.ReadWhere()
	if minor and not changed then
		return
	end
	if Q.db.focusZone and Q.db.grouping then
		T.FocusCurrentZone()
	else
		T.MarkDirty()
	end
end
