-- Clean Quest Tracker: shading on the quest list for the setting hovered in the settings window.

local _, Q = ...
local T = Q.Tracker

------------------------------------------------------------------------------------------------------------------------
-- Settings highlight: while a row in the settings window is hovered, the part of the list it changes is shaded gold.
-- Overlays only; nothing in the layout moves. Redrawn after each layout so it follows a slider being dragged.
------------------------------------------------------------------------------------------------------------------------
local ZONE_OFFSET_X = T.ZONE_OFFSET_X
local HL_COLOR = { r = 1, g = 0.82, b = 0, a = 0.3 }
local highlightKey
local overlay, overlayTextures = nil, {}

local function Shade(index)
	local texture = overlayTextures[index]
	if not texture then
		texture = overlay:CreateTexture(nil, "OVERLAY")
		texture:SetColorTexture(HL_COLOR.r, HL_COLOR.g, HL_COLOR.b, HL_COLOR.a)
		overlayTextures[index] = texture
	end
	texture:ClearAllPoints()
	texture:Show()
	return texture
end

-- What each highlight key shades, per block. Returns how many textures it used.
local SHADERS = {}
local function Band(index, region, top, bottom, left, right)
	local texture = Shade(index)
	texture:SetPoint("TOPLEFT", region, "TOPLEFT", left or 0, top)
	texture:SetPoint("BOTTOMRIGHT", region, "TOPRIGHT", right or 0, bottom)
	return 1
end
local function Around(index, region, pad)
	local texture = Shade(index)
	pad = pad or 2
	texture:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
	texture:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
	return 1
end
function SHADERS.qg(block, index)
	return not block.qcZone and Band(index, block, Q.db.questGap, 0) or 0
end
function SHADERS.zg(block, index)
	return block.qcZone and Band(index, block, Q.db.zoneGap, 0, -ZONE_OFFSET_X) or 0
end
function SHADERS.lg(block, index)
	if block.qcZone or not next(block.usedLines or {}) then
		return 0
	end
	local top = -(block.HeaderText:GetHeight() or 0)
	return Band(index, block, top, top - math.max(Q.db.spacing, 1))
end
function SHADERS.ind(block, index)
	if block.qcZone then
		return 0
	end
	-- From where zone names start (or the left edge, without zones) to where the quest starts.
	local width = math.max(4, (block.offsetX or 0) - (Q.db.grouping and ZONE_OFFSET_X or 0))
	local texture = Shade(index)
	texture:SetPoint("TOPLEFT", block, "TOPLEFT", -width, 0)
	texture:SetPoint("BOTTOMRIGHT", block, "BOTTOMLEFT", -2, 0)
	return 1
end
function SHADERS.fs(block, index)
	return not block.qcZone and Around(index, block, 1) or 0
end
function SHADERS.lvl(block, index)
	return not block.qcZone and Around(index, block.HeaderText) or 0
end
SHADERS.diff = SHADERS.lvl
function SHADERS.done(block, index)
	return (not block.qcZone and block.qcComplete) and Around(index, block.HeaderText) or 0
end
function SHADERS.zfs(block, index)
	return block.qcZone and Around(index, block.HeaderText) or 0
end
function SHADERS.group(block, index)
	return block.qcZone and Around(index, block, 1) or 0
end
function SHADERS.first(block, index)
	return (block.qcZone and T.zoneNames and block.qcZone == T.zoneNames[1]) and Around(index, block, 1) or 0
end
function SHADERS.party(block, index)
	return (block.qcBadge and block.qcBadge:IsShown()) and Around(index, block.qcBadge, 1) or 0
end
function SHADERS.bars(block, index)
	local used = 0
	for _, bar in pairs(block.qcBars or {}) do
		if bar:IsShown() then
			used = used + Around(index + used, bar, 2)
		end
	end
	return used
end

function T.HighlightActive()
	return highlightKey ~= nil
end

function T.ApplyHighlight()
	local container, module = T.container, T.module
	if not overlay then
		if not container then
			return
		end
		overlay = CreateFrame("Frame", nil, container)
		overlay:SetAllPoints()
		overlay:SetFrameLevel(container:GetFrameLevel() + 40)
	end
	for _, texture in ipairs(overlayTextures) do
		texture:Hide()
	end
	local shader = highlightKey and SHADERS[highlightKey]
	if not shader or not module then
		return
	end
	local used = 0
	module:EnumerateActiveBlocks(function(block)
		if block:IsVisible() then
			used = used + shader(block, used + 1)
		end
	end)
end

-- Shades the part of the list a setting changes, or clears it with nil. Keys the list doesn't own (the frame, its
-- heading) go to the frame.
function T.SetHighlight(key)
	highlightKey = key
	T.ApplyHighlight()
	local frameKey = nil
	if key and not SHADERS[key] then
		frameKey = key
	end
	Q.Frame.SetHighlight(frameKey)
end
