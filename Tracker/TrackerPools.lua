-- Clean Quest Tracker: private frame pools for the quest list (see Tracker.lua).

local _, Q = ...
local T = Q.Tracker

------------------------------------------------------------------------------------------------------------------------
-- Private frame pools.
--
-- Blizzard's tracker keeps its frames in shared pools (ObjectiveTrackerManager's pool collection and template cache,
-- and a file-wide pool of POI buttons). Anything this add-on stores there counts as tainted, and the native tracker
-- reads it on its next update: Edit Mode refreshes the tracker on every layout change, and its scenario section then
-- fails to read auras ("tainted by" this add-on). So every frame this list uses comes from pools it owns, and the
-- few Blizzard methods that reach for the shared pools are replaced on Clean Quest Tracker's own blocks and module only.
------------------------------------------------------------------------------------------------------------------------
local Pools = { types = {} }
T.Pools = Pools

function Pools.Acquire(parent, template)
	if not Pools.collection then
		Pools.collection = CreateFramePoolCollection()
	end
	local frameType = Pools.types[template]
	if not frameType then
		local info = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(template)
		frameType = info and info.type or "Frame"
		Pools.types[template] = frameType
	end
	local frame, isNew = Pools.collection:GetOrCreatePool(frameType, parent, template):Acquire()
	if isNew then
		frame.template = template
	end
	return frame, isNew
end

function Pools.Release(frame)
	Pools.collection:Release(frame)
end

-- Same as ObjectiveTrackerBlockMixin:GetLine / FreeLine, with this add-on's pools.
local function BlockGetLine(self, objectiveKey, optTemplate)
	local template = optTemplate or self.parentModule.lineTemplate
	local line = self:GetExistingLine(objectiveKey)
	if line and line.template ~= template then
		self:FreeLine(line)
		line = nil
	end
	if not line then
		line = Pools.Acquire(self, template)
		line:SetParent(self)
		line:Show()
	end
	self.usedLines[objectiveKey] = line
	line.objectiveKey = objectiveKey
	line.parentBlock = self
	line.used = true
	return line
end

local function BlockFreeLine(self, line)
	self.usedLines[line.objectiveKey] = nil
	Pools.Release(line)
	line:Hide()
	if line.OnFree then
		line:OnFree(self)
	end
end

-- Same as ObjectiveTrackerQuestPOIBlockMixin:GetPOIButton / CheckAndReleasePOIButton, with a private button pool.
local poiPool
local POI_SCALE = 0.875
local function BlockGetPOIButton(self, style)
	local button = self.poiButton
	if not button then
		poiPool = poiPool or CreateFramePool("BUTTON", nil, "ObjectiveTrackerPOIButtonTemplate")
		button = poiPool:Acquire()
		button:SetParent(self)
		-- 28px instead of the template's 32px, so the icon sits snug beside the title. Scaling (rather than resizing)
		-- keeps every texture layer in the template in proportion.
		button:SetScale(POI_SCALE)
		button:SetQuestID(self.poiQuestID)
		self.poiButton = button
		self:SetExtraAddAnimation(button.AddAnim)
	end
	button:SetStyle(style)
	button:SetSelected(self.poiIsSuperTracked)
	button:UpdateButtonStyle()
	button:Show()
	return button
end

local function BlockReleasePOIButton(self)
	if self.poiButton then
		poiPool:Release(self.poiButton)
		self.poiButton = nil
		self:SetExtraAddAnimation(nil)
		self:SetPOIInfo()
	end
end

function T.PatchBlock(block)
	if block.qcPatched then
		return
	end
	block.qcPatched = true
	block.GetLine = BlockGetLine
	block.FreeLine = BlockFreeLine
	if block.GetPOIButton then
		block.GetPOIButton = BlockGetPOIButton
		block.CheckAndReleasePOIButton = BlockReleasePOIButton
	end
end
