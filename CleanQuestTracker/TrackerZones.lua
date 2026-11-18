-- Clean Quest Tracker: zone heading rows (arrow, name, quest count and the line under it) and the zone tools: folding
-- a zone, focus on the current zone, and expand or collapse all. The list (Tracker.lua) lays out a heading row for
-- each zone with T.StyleZone.

local _, Q = ...
local T = Q.Tracker

local Motion = Q.Motion
local HasAtlas = Q.HasAtlas
local ZONE_OFFSET_X = T.ZONE_OFFSET_X
local ZONE_TEMPLATE = T.ZONE_TEMPLATE
local ZONE_COUNT_WIDTH = 24
local RULE_ALPHA = 0.35 -- the line under a zone heading, in the zone colour

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
	local zoneColor = Q.Color("colorZone")
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
	block.qcRule:Show()
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

local function CurrentZone()
	return GetRealZoneText and GetRealZoneText() or ""
end

-- Folds every zone group except the one you're in, and keeps doing so as you travel.
function T.FocusCurrentZone()
	local db = Q.db
	local here = CurrentZone()
	db.focusZone = true
	for _, name in ipairs(T.zoneNames or {}) do
		db.collapsed[name] = (name ~= here) or nil
	end
	T.MarkDirty()
	return T.HasZone(here)
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
	local here = CurrentZone()
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

function T.HasZone(name)
	for _, zone in ipairs(T.zoneNames or {}) do
		if zone == name then
			return true
		end
	end
	return false
end

function T.OnZoneChanged()
	if Q.db.focusZone and Q.db.grouping then
		T.FocusCurrentZone()
	else
		T.MarkDirty()
	end
end
