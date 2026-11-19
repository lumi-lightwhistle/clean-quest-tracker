-- Clean Quest Tracker: the quest list's animations (glide, fade, fold, completion glow).

local _, Q = ...
local T = Q.Tracker

------------------------------------------------------------------------------------------------------------------------
-- Motion. The layout is always applied at once; these only change how blocks look on the way there. Rows glide from
-- where they were to where they now are, new rows fade in, and rows in a zone being folded fade out first.
------------------------------------------------------------------------------------------------------------------------
local Motion = Q.Motion
local folding = false -- a zone fold is fading out; zone toggles wait for it
local GLOW_COLOR = { r = 0.35, g = 1, b = 0.35 }

local function BlockKey(block)
	return tostring(block.template) .. ":" .. tostring(block.id)
end

-- Where each visible block's top edge is, before a layout.
function T.Snapshot()
	local tops = {}
	T.module:EnumerateActiveBlocks(function(block)
		if block:IsVisible() then
			tops[BlockKey(block)] = block:GetTop()
		end
	end)
	return tops
end

-- A zero-length jump back to the old position, then an eased glide to the new one.
local function Slide(block, offsetY, duration)
	local group = block.qcSlide
	if not group then
		group = block:CreateAnimationGroup()
		group.jump = group:CreateAnimation("Translation")
		group.jump:SetDuration(0)
		group.jump:SetOrder(1)
		group.glide = group:CreateAnimation("Translation")
		group.glide:SetOrder(2)
		group.glide:SetSmoothing("OUT")
		block.qcSlide = group
	end
	group:Stop()
	group.jump:SetOffset(0, offsetY)
	group.glide:SetOffset(0, -offsetY)
	group.glide:SetDuration(duration)
	group:Play()
end

local function FadeIn(block, duration)
	local group = block.qcAppear
	if not group then
		group = block:CreateAnimationGroup()
		group.alpha = group:CreateAnimation("Alpha")
		group.alpha:SetFromAlpha(0)
		group.alpha:SetToAlpha(1)
		group.alpha:SetSmoothing("OUT")
		block.qcAppear = group
	end
	group:Stop()
	group.alpha:SetDuration(duration)
	group:Play()
end

-- After a layout: blocks that moved glide from their old place, blocks that are new fade in. Blocks playing one of
-- Blizzard's own animations (new quest, turn-in) are left to it.
function T.Glide(before)
	local duration = Motion.Duration()
	if not before or duration <= 0 then
		return
	end
	T.module:EnumerateActiveBlocks(function(block)
		if not block:IsVisible() or block.activeAnim then
			return
		end
		local top = block:GetTop()
		if not top then
			return
		end
		local old = before[BlockKey(block)]
		if old then
			if math.abs(old - top) > 0.5 then
				Slide(block, old - top, duration)
			end
		else
			FadeIn(block, duration)
		end
	end)
end

-- Blocks faded out for a fold that are still on screen after the layout (the fold was undone) come back.
-- A layout during a fade leaves the fading blocks alone; the layout after the fold restores any still shown.
function T.RestoreFaded()
	if folding then
		return
	end
	T.module:EnumerateActiveBlocks(function(block)
		if block.qcFaded then
			block.qcFaded = nil
			block:SetAlpha(1)
		end
	end)
end

-- Fades out the quests under the given zones, then runs `apply` (which folds them). Without motion, applies at once.
function T.FadeOutThen(zones, apply)
	-- While searching, zones with matches stay open, so their quests would only fade and come straight back.
	if T.SearchActive() then
		apply()
		return
	end
	local duration = Motion.Duration() * 0.6
	local fading = {}
	if duration > 0 then
		T.module:EnumerateActiveBlocks(function(block)
			if block.qcGroup and zones[block.qcGroup] and block:IsVisible() and not block.activeAnim then
				fading[#fading + 1] = block
			end
		end)
	end
	if #fading == 0 then
		apply()
		return
	end
	folding = true
	for _, block in ipairs(fading) do
		block.qcFaded = true
	end
	Motion.Tween("qc-fold", 1, 0, duration, function(alpha)
		-- Only blocks still fading: one freed mid-fade by a layout goes back to the pool and must keep full alpha.
		for _, block in ipairs(fading) do
			if block.qcFaded then
				block:SetAlpha(alpha)
			end
		end
	end, function()
		folding = false
		apply()
	end)
end

-- A short green flare behind the title when a quest becomes complete, using the block's own header glow texture.
function T.Glow(block)
	local duration = Motion.Duration()
	local glow = block.HeaderGlow
	if duration <= 0 or not glow then
		return
	end
	local group = block.qcGlow
	if not group then
		group = block:CreateAnimationGroup()
		group.rise = group:CreateAnimation("Alpha")
		group.rise:SetTarget(glow)
		group.rise:SetFromAlpha(0)
		group.rise:SetToAlpha(0.85)
		group.rise:SetOrder(1)
		group.fall = group:CreateAnimation("Alpha")
		group.fall:SetTarget(glow)
		group.fall:SetFromAlpha(0.85)
		group.fall:SetToAlpha(0)
		group.fall:SetSmoothing("OUT")
		group.fall:SetOrder(2)
		group.text = group:CreateAnimation("Alpha")
		group.text:SetTarget(block.HeaderText)
		group.text:SetFromAlpha(0.35)
		group.text:SetToAlpha(1)
		group.text:SetOrder(1)
		local function Reset()
			glow:SetVertexColor(1, 1, 1)
		end
		group:SetScript("OnFinished", Reset)
		group:SetScript("OnStop", Reset)
		block.qcGlow = group
	end
	group:Stop()
	glow:SetVertexColor(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b)
	group.rise:SetDuration(duration * 0.8)
	group.fall:SetDuration(duration * 2.4)
	group.text:SetDuration(duration * 1.6)
	group:Play()
end

function T.IsFolding()
	return folding
end

function T.StopMotion(block)
	for _, key in ipairs({ "qcSlide", "qcAppear", "qcGlow" }) do
		if block[key] then
			block[key]:Stop()
		end
	end
	if block.qcFaded then
		block.qcFaded = nil
		block:SetAlpha(1)
	end
end
