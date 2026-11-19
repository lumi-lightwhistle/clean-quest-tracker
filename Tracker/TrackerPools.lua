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
local POI_NATIVE_SIZE = 32 -- the template's own size
local POI_GAP = T.POI_GAP -- between the icon and the title (set in Tracker.lua, which also sizes the room for the icon)

-- The icon's size is a setting (Layout page). Scaling rather than resizing keeps every texture layer in the template in
-- proportion.
local function PoiScale()
	return T.PoiSize() / POI_NATIVE_SIZE
end

local function BlockGetPOIButton(self, style)
	local button = self.poiButton
	if not button then
		poiPool = poiPool or CreateFramePool("BUTTON", nil, "ObjectiveTrackerPOIButtonTemplate")
		button = poiPool:Acquire()
		button:SetParent(self)
		button:SetQuestID(self.poiQuestID)
		self.poiButton = button
		self:SetExtraAddAnimation(button.AddAnim)
	end
	-- Every time, so a change of size in settings reaches icons that already exist.
	button:SetScale(PoiScale())
	button:SetStyle(style)
	button:SetSelected(self.poiIsSuperTracked)
	button:UpdateButtonStyle()
	button:Show()
	return button
end

-- Height of the first line of the title (a long title wraps, and the icon belongs beside its first line).
local function FirstLineHeight(text)
	local height = text:GetStringHeight() or 0
	local lines = text.GetNumLines and text:GetNumLines() or 1
	if lines and lines > 1 then
		height = height / lines
	end
	-- An unmeasured title reads as 0 high; use the text size so the icon is not pinned to the top edge.
	return height > 0 and height or (Q.db.fontSize or Q.defaults.fontSize)
end

-- Same as ObjectiveTrackerQuestPOIBlockMixin:AddPOIButton, except the icon is centred on the title's first line.
-- Blizzard hangs it from the top of the title, which leaves a large icon sitting high.
local function BlockAddPOIButton(self)
	local style
	if self.poiIsWorldQuest then
		style = POIButtonUtil.Style.WorldQuest
	elseif self.poiIsComplete then
		style = POIButtonUtil.Style.QuestComplete
	else
		style = POIButtonUtil.Style.QuestInProgress
	end
	local button = self:GetPOIButton(style)
	local scale = button:GetScale()
	button:ClearAllPoints()
	-- Offsets count in the button's own (scaled) units.
	button:SetPoint("RIGHT", self.HeaderText, "TOPLEFT", -POI_GAP / scale, -(FirstLineHeight(self.HeaderText) / 2) / scale)
	button:SetPingWorldMap(nil)
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
		block.AddPOIButton = BlockAddPOIButton
		block.CheckAndReleasePOIButton = BlockReleasePOIButton
	end
end
