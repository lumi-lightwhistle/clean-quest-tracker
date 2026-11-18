-- The tracker frame: header, scrolling quest area, auto height, and unlocked move/resize.
--
-- Position is stored in UIParent units from the nearest top corner, so it survives UI scale and resolution changes.
-- With auto height the frame grows to fit the quests up to the maximum height, and never past the bottom of the
-- screen. While unlocked it shows its full maximum-height box so the limit can be dragged clear of the action bars.

local _, Q = ...
local F = {}
Q.Frame = F

local HEADER_HEIGHT = 26
local SCROLLBAR_WIDTH = 8
local SCROLLBAR_GAP = 4 -- breathing room between the quest list and the scrollbar
local MIN_WIDTH, MAX_WIDTH = 220, 700
local MIN_HEIGHT, MAX_HEIGHT = 120, 1200
local GOLD = { r = 1, g = 0.82, b = 0 }
local EDGE = { r = 0.85, g = 0.69, b = 0.29 }
local BRIGHT = { r = 1, g = 0.93, b = 0.55 }
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"
local ICON_SIZE = 18 -- header icons share one size and centre line

local host, header, scroll, content, slider, strip, grip, background
local border = {}
local controls = {}
local contentHeight, questCount = 0, 0
local sizing, moving, syncing = false, false, false
local rolling = false -- minimising with motion: the list stays drawn while the frame rolls up

local HasAtlas = Q.HasAtlas

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- Layout calls that move or size the frame are refused in combat once a secure item button sits inside it.
local function Locked()
	return InCombatLockdown() and Q.Tracker.ItemsInUse()
end

function F.TooltipAnchor()
	local point = Q.db and Q.db.point or "TOPRIGHT"
	return point:find("RIGHT") and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

function F.IsExpanded()
	return not Q.db.minimized
end

function F.ViewBounds()
	if not scroll then
		return nil, nil
	end
	return scroll:GetTop(), scroll:GetBottom()
end

------------------------------------------------------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------------------------------------------------------

-- Saved offsets are UIParent units; SetPoint offsets are in the frame's own scale.
local function ApplyPosition()
	local db = Q.db
	local scale = db.scale > 0 and db.scale or 1
	host:ClearAllPoints()
	host:SetPoint(db.point, UIParent, db.point, db.x / scale, db.y / scale)
end

-- Version 0.5 saved TOPLEFT offsets from the screen's bottom-left. Converted once to the nearest top corner.
local function ConvertLegacyPosition()
	local db = Q.db
	local old = db.legacyPosition
	db.legacyPosition = nil
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local scale = old.scale or 1
	local left, top = old.x * scale, old.y * scale
	local right = left + (old.width or db.width) * scale
	if (left + right) / 2 > width / 2 then
		db.point, db.x = "TOPRIGHT", right - width
	else
		db.point, db.x = "TOPLEFT", left
	end
	db.y = top - height
end

function F.SavePosition()
	local db = Q.db
	local left, right, top = host:GetLeft(), host:GetRight(), host:GetTop()
	if not (left and right and top) then
		return
	end
	local ratio = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
	left, right, top = left * ratio, right * ratio, top * ratio
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if (left + right) / 2 > width / 2 then
		db.point, db.x = "TOPRIGHT", right - width
	else
		db.point, db.x = "TOPLEFT", left
	end
	db.y = top - height
	ApplyPosition()
	F.PlaceGrip()
end

------------------------------------------------------------------------------------------------------------------------
-- Scrolling
------------------------------------------------------------------------------------------------------------------------
local function ScrollRange()
	return math.max(0, contentHeight + 8 - (scroll:GetHeight() or 0))
end

local function ScrollTo(value)
	if Locked() then
		return
	end
	value = Clamp(value, 0, ScrollRange())
	scroll:SetVerticalScroll(value)
	if math.abs((slider:GetValue() or 0) - value) > 0.5 then
		syncing = true
		slider:SetValue(value)
		syncing = false
	end
	Q.Debounce("placeItems", 0.05, Q.Tracker.PlaceItems)
end

function F.Scroll(delta)
	if scroll then
		ScrollTo(scroll:GetVerticalScroll() - delta * 40)
	end
end

local function UpdateScroll()
	content:SetHeight(math.max(contentHeight, 1))
	local range = ScrollRange()
	slider:SetMinMaxValues(0, range)
	slider:SetShown(range > 1 and not Q.db.minimized)
	scroll:EnableMouseWheel(range > 1)
	ScrollTo(scroll:GetVerticalScroll())
end

------------------------------------------------------------------------------------------------------------------------
-- Height
------------------------------------------------------------------------------------------------------------------------
local HEIGHT_TWEEN = "qc-host-height"

-- Ends a minimise roll: the list is hidden for real and the tracker catches up.
local function FinishRoll()
	if not rolling then
		return
	end
	rolling = false
	scroll:SetAlpha(1)
	scroll:SetShown(not Q.db.minimized)
	Q.Tracker.MarkDirty()
end

-- Eases the frame to its new height when it was already on screen and locked; otherwise sets it at once.
local function SetHostHeight(height, animate)
	if Q.Motion.Target(HEIGHT_TWEEN) == height then
		return
	end
	local duration = animate and Q.Motion.Duration() or 0
	Q.Motion.Tween(HEIGHT_TWEEN, host:GetHeight(), height, duration, function(value)
		-- Combat can start mid-ease; with an item button inside, the frame can't be resized until it ends.
		if Locked() then
			F.pending = true
			return
		end
		host:SetHeight(value)
	end, function()
		UpdateScroll()
		-- Item buttons are only placed inside the visible area, which has just changed.
		Q.Tracker.PlaceItems()
		FinishRoll()
	end)
end

function F.Layout()
	if not host or sizing then
		return
	end
	if Locked() then
		F.pending = true
		return
	end
	local db = Q.db
	-- An open search keeps the frame up even when nothing matches, so the box stays reachable.
	local empty = not Q.Active() or (questCount == 0 and not F.SearchOpen())
	if empty and db.locked then
		Q.Motion.Finish(HEIGHT_TWEEN)
		host:Hide()
		return
	end
	local wasShown = host:IsShown()
	host:Show()
	local height
	if not db.locked then
		height = db.maxHeight
	elseif db.minimized then
		height = HEADER_HEIGHT
	elseif db.autoHeight then
		height = math.min(HEADER_HEIGHT + contentHeight + 8, db.maxHeight)
	else
		height = db.maxHeight
	end
	local top = host:GetTop()
	if top and top - 4 > HEADER_HEIGHT then
		height = math.min(height, top - 4)
	end
	SetHostHeight(math.max(HEADER_HEIGHT, height), wasShown and db.locked)
	scroll:SetShown(not db.minimized or rolling)
	UpdateScroll()
	F.UpdateReadout()
end

function F.SetContent(height, count)
	contentHeight, questCount = height or 0, count or 0
	F.Layout()
end

-- With motion, minimising fades the list while the frame rolls up under the header, and the tracker is told only
-- once the roll ends; restoring rolls the frame back down while the list fades in.
function F.SetMinimized(minimized)
	Q.db.minimized = minimized and true or false
	F.UpdateHeader()
	local duration = Q.Motion.Duration()
	if minimized and duration > 0 and host:IsShown() and Q.db.locked then
		rolling = true
		Q.Motion.Tween(scroll, scroll:GetAlpha(), 0, duration, function(alpha)
			scroll:SetAlpha(alpha)
		end)
		F.Layout()
		return
	end
	-- Restored before a roll finished: fade back from wherever the list had got to.
	local fromAlpha = rolling and scroll:GetAlpha() or 0
	rolling = false
	Q.Tracker.MarkDirty()
	F.Layout()
	if not minimized then
		Q.Motion.Tween(scroll, fromAlpha, 1, duration, function(alpha)
			scroll:SetAlpha(alpha)
		end)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Header
------------------------------------------------------------------------------------------------------------------------
-- Header icons appear on hover. One that shows an active state (unlocked, zone focus) stays visible while active.
local function ShowControls(show)
	for _, button in ipairs(controls) do
		local available = not button.available or button.available()
		local visible = available and (show or Q.db.alwaysShowIcons or (button.keepVisible and button.keepVisible()))
		button:SetShown(available)
		local alpha = visible and 1 or 0
		if Q.Motion.Target(button) ~= alpha then
			Q.Motion.Tween(button, button:GetAlpha(), alpha, available and Q.Motion.Duration() * 0.8 or 0, function(value)
				button:SetAlpha(value)
			end)
		end
		button:EnableMouse(visible and true or false)
	end
end

local function HeaderLeave()
	if not header:IsMouseOver() then
		ShowControls(false)
	end
end

local function HeaderButton(texture, fallback, size, tooltip, onClick)
	local button = CreateFrame("Button", nil, header)
	button:SetSize(size, size)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if HasAtlas(texture) then
		icon:SetAtlas(texture)
	else
		icon:SetTexture(fallback)
	end
	icon:SetVertexColor(EDGE.r, EDGE.g, EDGE.b)
	button.icon = icon
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		ShowControls(true)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip())
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
		HeaderLeave()
	end)
	button:SetScript("OnClick", onClick)
	controls[#controls + 1] = button
	return button
end

-- For header icons built in other files (the search icon, FrameSearch.lua): same size, tint and hover behaviour.
function F.HeaderButton(texture, tooltip, onClick)
	return HeaderButton("", texture, ICON_SIZE, tooltip, onClick)
end

function F.ShowControls(show)
	ShowControls(show)
end

local function CreateHeader()
	header = CreateFrame("Button", nil, host)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_HEIGHT)
	header:RegisterForClicks("LeftButtonUp")

	local art = header:CreateTexture(nil, "BACKGROUND")
	if HasAtlas("UI-QuestTracker-Secondary-Objective-Header") then
		art:SetAtlas("UI-QuestTracker-Secondary-Objective-Header")
		art:SetPoint("TOPLEFT", -10, 0)
		art:SetPoint("BOTTOMRIGHT", 10, 0)
	else
		art:SetPoint("BOTTOMLEFT", 4, 1)
		art:SetPoint("BOTTOMRIGHT", -4, 1)
		art:SetHeight(1)
		art:SetColorTexture(EDGE.r, EDGE.g, EDGE.b, 0.5)
	end

	local title = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
	title:SetText(TRACKER_HEADER_QUESTS or "Quests")
	title:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
	title:SetWordWrap(false)
	header.title = title

	local minimize = CreateFrame("Button", nil, header)
	minimize:SetSize(16, 16)
	minimize:SetPoint("RIGHT", -2, 0)
	minimize.normal = minimize:CreateTexture(nil, "ARTWORK")
	minimize.normal:SetAllPoints()
	minimize.pushed = minimize:CreateTexture(nil, "ARTWORK")
	minimize.pushed:SetAllPoints()
	minimize:SetNormalTexture(minimize.normal)
	minimize:SetPushedTexture(minimize.pushed)
	if HasAtlas("ui-questtrackerbutton-yellow-highlight") then
		minimize:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
	else
		minimize:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	minimize:SetScript("OnClick", function()
		F.SetMinimized(not Q.db.minimized)
	end)
	header.minimize = minimize

	local lock = HeaderButton("", MEDIA .. "Locked", ICON_SIZE, function()
		return Q.db.locked and "Unlock to move and resize" or "Lock position and size"
	end, function()
		Q.SetLocked(not Q.db.locked)
		GameTooltip:SetText(Q.db.locked and "Unlock to move and resize" or "Lock position and size")
	end)
	lock:SetPoint("RIGHT", minimize, "LEFT", -5, 0)
	lock.keepVisible = function()
		return Q.db and not Q.db.locked
	end
	header.lock = lock

	-- Left side: zone tools, only when quests are grouped by zone.
	local function Grouped()
		return Q.db and Q.db.grouping
	end
	local focus = HeaderButton("", MEDIA .. "FocusZone", ICON_SIZE, function()
		if Q.db.focusZone then
			return "Show all zones again"
		end
		return "Collapse every zone except the one you're in"
	end, function(self)
		local on = Q.Tracker.ToggleFocus()
		F.UpdateHeader()
		GameTooltip:SetText(on and "Show all zones again" or "Collapse every zone except the one you're in")
		if on and not Q.Tracker.HasZone(GetRealZoneText()) then
			GameTooltip:AddLine("None of your tracked quests are in this zone yet.", 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	focus:SetPoint("LEFT", 6, 0)
	focus.available = Grouped
	focus.keepVisible = function()
		return Q.db and Q.db.focusZone
	end
	header.focus = focus

	local function ExpandTip()
		return Q.Tracker.AllExpanded() and "Collapse all zones" or "Expand all zones"
	end
	local expand = HeaderButton("", MEDIA .. "ExpandAll", ICON_SIZE, ExpandTip, function()
		Q.Tracker.ToggleAll()
		F.UpdateHeader()
	end)
	header.expand = expand
	expand:SetPoint("LEFT", focus, "RIGHT", 5, 0)
	expand.available = Grouped

	-- The magnifying glass and its box, right of the arrows (FrameSearch.lua).
	F.CreateSearch(header)

	-- Drawn in the same flat style as the padlock and pin, so it takes the same gold tint and size.
	local cog = HeaderButton("", MEDIA .. "Settings", ICON_SIZE, function()
		return "Clean Quest Tracker settings"
	end, function()
		Q.Options.Toggle()
	end)
	cog:SetPoint("RIGHT", lock, "LEFT", -5, 0)

	header:SetScript("OnEnter", function()
		ShowControls(true)
	end)
	header:SetScript("OnLeave", HeaderLeave)
	header:SetScript("OnClick", function()
		F.SetMinimized(not Q.db.minimized)
	end)
	ShowControls(false)
end

-- Settings highlight for the parts of the frame itself: its heading, or the whole frame (size, lock, backdrop).
-- Keys with nothing to show here (Blizzard's tracker, animation speed) clear it.
local highlight
function F.SetHighlight(key)
	if not host then
		return
	end
	if not highlight then
		highlight = CreateFrame("Frame", nil, host)
		highlight:SetAllPoints()
		highlight:SetFrameLevel(host:GetFrameLevel() + 60)
		highlight.fill = highlight:CreateTexture(nil, "OVERLAY")
		highlight.fill:SetColorTexture(1, 0.82, 0, 0.1)
		highlight.edges = {}
		for index = 1, 4 do
			local edge = highlight:CreateTexture(nil, "OVERLAY")
			edge:SetColorTexture(1, 0.82, 0, 0.9)
			highlight.edges[index] = edge
		end
		local e = highlight.edges
		e[1]:SetPoint("TOPLEFT", -3, 3) e[1]:SetPoint("TOPRIGHT", 3, 3) e[1]:SetHeight(2)
		e[2]:SetPoint("BOTTOMLEFT", -3, -3) e[2]:SetPoint("BOTTOMRIGHT", 3, -3) e[2]:SetHeight(2)
		e[3]:SetPoint("TOPLEFT", -3, 3) e[3]:SetPoint("BOTTOMLEFT", -3, -3) e[3]:SetWidth(2)
		e[4]:SetPoint("TOPRIGHT", 3, 3) e[4]:SetPoint("BOTTOMRIGHT", 3, -3) e[4]:SetWidth(2)
	end
	local whole = key == "frame" or key == "w" or key == "op" or key == "lock"
	for _, edge in ipairs(highlight.edges) do
		edge:SetShown(whole)
	end
	highlight.fill:ClearAllPoints()
	highlight.fill:SetColorTexture(1, 0.82, 0, whole and 0.1 or 0.3)
	if whole then
		highlight.fill:SetAllPoints(host)
		highlight.fill:Show()
	elseif key == "head" then
		highlight.fill:SetPoint("TOPLEFT", header.title, "TOPLEFT", -4, 3)
		highlight.fill:SetPoint("BOTTOMRIGHT", header.title, "BOTTOMRIGHT", 4, -3)
		highlight.fill:Show()
	elseif key == "search" then
		local region = F.SearchRegion()
		highlight.fill:SetPoint("TOPLEFT", region, "TOPLEFT", -3, 3)
		highlight.fill:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 3, -3)
		highlight.fill:Show()
	else
		highlight.fill:Hide()
	end
end

-- The expand button shows arrows pointing out (expand all) or, when every zone is open, in (collapse all). Called after
-- each layout, since folding a single zone can change which one applies.
function F.UpdateZoneTools()
	if not header then
		return
	end
	local expand = header.expand
	expand.icon:SetTexture(MEDIA .. (Q.Tracker.AllExpanded() and "CollapseAll" or "ExpandAll"))
	if GameTooltip:IsOwned(expand) then
		GameTooltip:SetText(Q.Tracker.AllExpanded() and "Collapse all zones" or "Expand all zones")
	end
end

function F.UpdateHeader()
	local db = Q.db
	local title = header.title
	-- Always centred, clear of the icons on both sides.
	title:ClearAllPoints()
	title:SetPoint("LEFT", 50, 0)
	title:SetPoint("RIGHT", -50, 0)
	title:SetJustifyH("CENTER")
	local focusColor = db.focusZone and BRIGHT or EDGE
	header.focus.icon:SetVertexColor(focusColor.r, focusColor.g, focusColor.b)
	F.UpdateZoneTools()
	F.PlaceSearch()
	local minimize = header.minimize
	local atlas = db.minimized and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse"
	if HasAtlas(atlas) then
		minimize.normal:SetAtlas(atlas)
		minimize.pushed:SetAtlas(HasAtlas(atlas .. "-pressed") and atlas .. "-pressed" or atlas)
	else
		minimize.normal:SetTexture(db.minimized and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		minimize.pushed:SetTexture(db.minimized and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
	end
	-- Locked: closed padlock in the header gold. Unlocked: open padlock, brighter, and kept on screen.
	local lockIcon = header.lock.icon
	lockIcon:SetTexture(MEDIA .. (db.locked and "Locked" or "Unlocked"))
	local color = db.locked and EDGE or BRIGHT
	lockIcon:SetVertexColor(color.r, color.g, color.b)
	ShowControls(header:IsMouseOver())
end

------------------------------------------------------------------------------------------------------------------------
-- Unlocked mode: move strip, resize grip, outline
------------------------------------------------------------------------------------------------------------------------
local function StopGestures()
	if moving or sizing then
		host:StopMovingOrSizing()
		local wasSizing = sizing
		moving, sizing = false, false
		if wasSizing then
			Q.db.width = math.floor(host:GetWidth() + 0.5)
			Q.db.maxHeight = math.floor(host:GetHeight() + 0.5)
		end
		if host.SetUserPlaced then
			host:SetUserPlaced(false)
		end
		F.SavePosition()
		F.Layout()
		Q.Tracker.MarkDirty(true)
	end
end

function F.UpdateReadout()
	if strip and strip:IsShown() then
		strip.size:SetFormattedText("%d x %d", math.floor(host:GetWidth() + 0.5), math.floor(host:GetHeight() + 0.5))
	end
end

local function CreateUnlockControls()
	strip = CreateFrame("Button", nil, host)
	strip:SetPoint("BOTTOMLEFT", host, "TOPLEFT", -4, 6)
	strip:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 4, 6)
	strip:SetHeight(24)
	strip:SetFrameLevel(host:GetFrameLevel() + 20)
	local fill = strip:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.11, 0.08, 0.035, 0.92)
	local line = strip:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	line:SetColorTexture(EDGE.r, EDGE.g, EDGE.b, 0.8)
	local label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", 8, 0)
	label:SetText("Clean Quest Tracker: drag to move")
	local size = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	size:SetPoint("RIGHT", -8, 0)
	strip.size = size
	strip:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	strip:SetScript("OnMouseDown", function(_, mouseButton)
		if mouseButton == "LeftButton" and not InCombatLockdown() then
			moving = true
			host:StartMoving()
		end
	end)
	strip:SetScript("OnMouseUp", StopGestures)
	strip:SetScript("OnHide", StopGestures)

	grip = CreateFrame("Button", nil, host)
	grip:SetSize(16, 16)
	grip:SetFrameLevel(host:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Drag to set the width and maximum height")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	grip:SetScript("OnMouseDown", function(self, mouseButton)
		if mouseButton == "LeftButton" and not InCombatLockdown() then
			GameTooltip:Hide()
			sizing = true
			host:SetHeight(Q.db.maxHeight)
			host:StartSizing(self.corner)
		end
	end)
	grip:SetScript("OnMouseUp", StopGestures)

	for index = 1, 4 do
		local edge = host:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(EDGE.r, EDGE.g, EDGE.b, 0.7)
		border[index] = edge
	end
	border[1]:SetPoint("TOPLEFT", -2, 2)
	border[1]:SetPoint("TOPRIGHT", 2, 2)
	border[1]:SetHeight(1)
	border[2]:SetPoint("BOTTOMLEFT", -2, -2)
	border[2]:SetPoint("BOTTOMRIGHT", 2, -2)
	border[2]:SetHeight(1)
	border[3]:SetPoint("TOPLEFT", -2, 2)
	border[3]:SetPoint("BOTTOMLEFT", -2, -2)
	border[3]:SetWidth(1)
	border[4]:SetPoint("TOPRIGHT", 2, 2)
	border[4]:SetPoint("BOTTOMRIGHT", 2, -2)
	border[4]:SetWidth(1)
end

-- The grip sits on the corner away from the anchored side, so resizing grows the frame away from the screen edge.
function F.PlaceGrip()
	if not grip then
		return
	end
	local right = (Q.db.point or ""):find("RIGHT") ~= nil
	grip.corner = right and "BOTTOMLEFT" or "BOTTOMRIGHT"
	grip:ClearAllPoints()
	grip:SetPoint(grip.corner, host, grip.corner, right and -2 or 2, -2)
	local texture = grip:GetNormalTexture()
	local coords = right and { 1, 0, 0, 1 } or { 0, 1, 0, 1 }
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
		local tex = grip[getter](grip)
		if tex then
			tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		end
	end
	if texture then
		texture:SetAlpha(1)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Build and apply
------------------------------------------------------------------------------------------------------------------------
function F.Create()
	host = CreateFrame("Frame", "CleanQuestTrackerFrame", UIParent)
	host:SetFrameStrata("LOW")
	host:SetClampedToScreen(true)
	host:SetMovable(true)
	host:SetResizable(true)
	host:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	if host.SetDontSavePosition then
		host:SetDontSavePosition(true)
	end
	host:SetSize(Q.db.width, HEADER_HEIGHT)
	F.host = host

	background = host:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:SetAllPoints()

	CreateHeader()

	scroll = CreateFrame("ScrollFrame", nil, host)
	scroll:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
	scroll:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + SCROLLBAR_GAP), 0)
	scroll:SetClipsChildren(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		F.Scroll(delta)
	end)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(Q.db.width - SCROLLBAR_WIDTH - SCROLLBAR_GAP, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, width)
		if width and width > 0 then
			content:SetWidth(width)
			Q.Tracker.MarkDirty(true)
		end
	end)
	F.content = content

	slider = CreateFrame("Slider", nil, host)
	slider:SetOrientation("VERTICAL")
	slider:SetWidth(SCROLLBAR_WIDTH)
	slider:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT - 4)
	slider:SetPoint("BOTTOMRIGHT", 0, 4)
	slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(3, 34)
	thumb:SetVertexColor(0.85, 0.67, 0.3, 0.9)
	local rail = slider:CreateTexture(nil, "BACKGROUND")
	rail:SetWidth(1)
	rail:SetPoint("TOP")
	rail:SetPoint("BOTTOM")
	rail:SetColorTexture(0.65, 0.5, 0.2, 0.25)
	slider:SetMinMaxValues(0, 0)
	slider:SetValue(0)
	slider:SetScript("OnValueChanged", function(_, value)
		if not syncing then
			ScrollTo(value)
		end
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(_, delta)
		F.Scroll(delta)
	end)
	slider:Hide()

	CreateUnlockControls()
	host:SetScript("OnSizeChanged", F.UpdateReadout)

	local combat = CreateFrame("Frame")
	combat:RegisterEvent("PLAYER_REGEN_DISABLED")
	combat:SetScript("OnEvent", StopGestures)

	if Q.db.legacyPosition then
		ConvertLegacyPosition()
	end
	host:Hide()
end

function F.Apply()
	if not host then
		return
	end
	if Locked() then
		F.pending = true
		return
	end
	local db = Q.db
	db.width = Clamp(db.width, MIN_WIDTH, MAX_WIDTH)
	db.maxHeight = Clamp(db.maxHeight, MIN_HEIGHT, MAX_HEIGHT)
	host:SetScale(db.scale)
	host:SetWidth(db.width)
	ApplyPosition()
	local unlocked = not db.locked
	-- The Background switch shows the dark panel at its chosen darkness; while unlocked it always shows, so the frame's
	-- full size is visible while moving and resizing.
	local darkness = db.backdrop and db.opacity or 0
	background:SetColorTexture(0.03, 0.04, 0.06, unlocked and math.max(darkness, 0.35) or darkness)
	strip:SetShown(unlocked)
	grip:SetShown(unlocked)
	for _, edge in ipairs(border) do
		edge:SetShown(unlocked)
	end
	F.PlaceGrip()
	F.UpdateHeader()
	F.Layout()
end

function F.OnCombatEnded()
	if F.pending then
		F.pending = false
		F.Apply()
	end
end
