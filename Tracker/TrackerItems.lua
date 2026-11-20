-- Clean Quest Tracker: secure quest item buttons beside quests that have a usable item.

local _, Q = ...
local T = Q.Tracker

-- The client refuses UseQuestLogSpecialItem from add-on code, so item buttons are a fixed pool of secure buttons.
-- Their attributes can only change out of combat, which is why the list holds its layout in combat while one is shown.
local ITEM_POOL = 30
local HasAtlas = Q.HasAtlas
local items, itemsInUse = {}, 0
local holder -- parks unused buttons off screen

local function Holder()
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("TOPLEFT")
		holder:Hide()
	end
	return holder
end

function T.QuestShowsItem(logIndex, isComplete)
	if not logIndex then
		return false
	end
	if QuestUtil and QuestUtil.QuestShowsItemByIndex then
		return QuestUtil.QuestShowsItemByIndex(logIndex, isComplete) and true or false
	end
	local link, _, _, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
	return link ~= nil and (not isComplete or showWhenComplete == true)
end

------------------------------------------------------------------------------------------------------------------------
-- Secure quest item buttons
------------------------------------------------------------------------------------------------------------------------
local Item = {}

function Item:UpdateCooldown()
	if not self.questLogIndex or not GetQuestLogSpecialItemCooldown then
		return
	end
	local start, duration, enable = GetQuestLogSpecialItemCooldown(self.questLogIndex)
	if start and CooldownFrame_Set then
		CooldownFrame_Set(self.Cooldown, start, duration, enable)
	end
	if SetItemButtonTextureVertexColor then
		local cooling = duration and duration > 0 and enable == 0
		SetItemButtonTextureVertexColor(self, cooling and 0.4 or 1, cooling and 0.4 or 1, cooling and 0.4 or 1)
	end
end

-- Attribute writes are protected on a secure button, so this only runs out of combat.
function Item:SetUp(questLogIndex)
	local link, texture, charges = GetQuestLogSpecialItemInfo(questLogIndex)
	self.questLogIndex = questLogIndex
	self.charges = charges
	self.rangeTimer = -1
	self:SetAttribute("item", link)
	if SetItemButtonTexture then
		SetItemButtonTexture(self, texture)
	end
	if SetItemButtonCount then
		SetItemButtonCount(self, charges)
	end
	self:UpdateCooldown()
end

function Item:OnUpdate(elapsed)
	if not self.rangeTimer or not self.questLogIndex then
		return
	end
	self.rangeTimer = self.rangeTimer - elapsed
	if self.rangeTimer > 0 then
		return
	end
	self.rangeTimer = TOOLTIP_UPDATE_TIME or 0.2
	local link, _, charges = GetQuestLogSpecialItemInfo(self.questLogIndex)
	if not link then
		self.HotKey:Hide()
		return
	end
	if charges ~= self.charges and SetItemButtonCount then
		self.charges = charges
		SetItemButtonCount(self, charges)
	end
	local inRange = IsQuestLogSpecialItemInRange and IsQuestLogSpecialItemInRange(self.questLogIndex)
	if inRange == 0 then
		self.HotKey:SetVertexColor(1, 0.1, 0.1)
		self.HotKey:Show()
	elseif inRange == 1 then
		self.HotKey:SetVertexColor(0.6, 0.6, 0.6)
		self.HotKey:Show()
	else
		self.HotKey:Hide()
	end
end

function Item:OnEvent(event)
	if event == "PLAYER_TARGET_CHANGED" then
		self.rangeTimer = -1
	else
		self:UpdateCooldown()
	end
end

function Item:OnShow()
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN")
end

function Item:OnHide()
	self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	self:UnregisterEvent("BAG_UPDATE_COOLDOWN")
end

function Item:OnEnter()
	if self.questLogIndex then
		GameTooltip:SetOwner(self, Q.Frame.TooltipAnchor())
		GameTooltip:SetQuestLogSpecialItem(self.questLogIndex)
	end
end

function Item.OnLeave()
	GameTooltip:Hide()
end

local function CreateItem()
	local button = CreateFrame("Button", nil, Holder(), "SecureActionButtonTemplate")
	button:SetSize(T.ITEM_SIZE, T.ITEM_SIZE)
	-- A secure button acts on the down or the up half of a click, whichever the ActionButtonUseKeyDown CVar picks
	-- (down by default). Registering only one half makes clicks do nothing for most players, so take both.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetAllPoints()
	button.icon = icon
	local count = button:CreateFontString(nil, "BORDER", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", -3, 2)
	count:Hide()
	button.Count = count
	local hotKey = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmallGray")
	hotKey:SetJustifyH("LEFT")
	hotKey:SetSize(29, 10)
	hotKey:SetPoint("TOPRIGHT", 16, -2)
	hotKey:SetText(RANGE_INDICATOR or "")
	hotKey:Hide()
	button.HotKey = hotKey
	button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.Cooldown:SetAllPoints()

	local art = HasAtlas("UI-QuestTrackerButton-QuestItem-Frame") and "UI-QuestTrackerButton-QuestItem-Frame"
	for _, setter in ipairs({ "SetNormalTexture", "SetPushedTexture" }) do
		local texture = button:CreateTexture(nil, "ARTWORK")
		if art then
			texture:SetAtlas(art, true)
			texture:SetPoint("CENTER")
		else
			texture:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			texture:SetPoint("TOPLEFT", -12, 12)
			texture:SetPoint("BOTTOMRIGHT", 12, -12)
		end
		button[setter](button, texture)
	end
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	Mixin(button, Item)
	button:SetScript("OnUpdate", Item.OnUpdate)
	button:SetScript("OnEvent", Item.OnEvent)
	button:SetScript("OnShow", Item.OnShow)
	button:SetScript("OnHide", Item.OnHide)
	button:SetScript("OnEnter", Item.OnEnter)
	button:SetScript("OnLeave", Item.OnLeave)
	button:Hide()
	items[#items + 1] = button
	return button
end

function T.ItemsInUse()
	return itemsInUse > 0
end

function T.ItemCount()
	return itemsInUse
end

-- In combat the buttons can't move, so a layout that would move them waits; they dim to show they're out of date.
function T.DimItems(dim)
	for _, button in ipairs(items) do
		button:SetAlpha(dim and 0.5 or 1)
	end
end

function T.ReleaseItems(fromIndex)
	for index = fromIndex or 1, #items do
		local button = items[index]
		button:Hide()
		button:SetAttribute("item", nil)
		button.questLogIndex = nil
		if button:GetParent() ~= Holder() then
			button:SetParent(Holder())
		end
	end
	if not fromIndex then
		itemsInUse = 0
	end
end

-- Gives each quest that has an item, and is fully inside the visible area, the next button. Anything scrolled out of
-- view is hidden, never just clipped, so it cannot take a click. Out of combat only.
function T.PlaceItems()
	local module = T.module
	if InCombatLockdown() or not module then
		return
	end
	local used = 0
	if Q.Active() and Q.Frame.IsExpanded() then
		local viewTop, viewBottom = Q.Frame.ViewBounds()
		local block = module.firstBlock
		while block and used < ITEM_POOL do
			if block.qcItemIndex and block:IsVisible() then
				local top = block:GetTop()
				local visible = top and (not viewTop or (top <= viewTop + 0.5 and top - T.ITEM_SIZE >= viewBottom - 0.5))
				if visible then
					used = used + 1
					local button = items[used] or CreateItem()
					button:SetParent(block)
					button:SetFrameLevel(block:GetFrameLevel() + 4)
					button:ClearAllPoints()
					button:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 1)
					button:SetUp(block.qcItemIndex)
					button:SetAlpha(1)
					button:Show()
				end
			end
			block = block.nextBlock
		end
	end
	T.ReleaseItems(used + 1)
	itemsInUse = used
end
