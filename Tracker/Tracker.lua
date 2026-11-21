-- The quest list: Clean Quest Tracker's own objective tracker module, built from Blizzard's module and block templates.
--
-- The module is a private instance. Its methods are overridden on this instance only; Blizzard's QuestObjectiveTracker
-- and ObjectiveTrackerFrame are never written to. Layout runs in combat unless a secure item button is attached, in
-- which case the list holds its last layout and catches up when combat ends.
--
-- This file owns the list: what it shows, its layout, zone folding, clicks and the update cycle. The rest of the
-- tracker lives beside it, loaded after it, and shares state through the Q.Tracker table (T):
--   TrackerZones.lua      zone heading rows and the zone tools (fold, focus, expand all)
--   TrackerPools.lua      private frame and POI-button pools (keeps Blizzard's tracker untainted)
--   TrackerItems.lua      secure quest item buttons
--   TrackerSpoken.lua     Spoken's play button
--   TrackerMotion.lua     animations: glide, fade, fold, completion glow
--   TrackerHighlight.lua  gold shading for the setting hovered in the settings window
--   TrackerSearch.lua     quest search: matching, highlighted letters and marker strips
--   TrackerWatch.lua      progress safety nets: extra events and the once-a-second check

local _, Q = ...
local T = {}
Q.Tracker = T

-- ITEM_GAP clears the item's border art, which draws a few pixels outside the button.
local ITEM_SIZE, ITEM_GAP = 26, 7
local SPOKEN_SIZE, SPOKEN_GAP = 14, 4
local ZONE_OFFSET_X = 18 -- room for the zone chevron
local UNGROUPED_OFFSET_X = 6 -- where quest titles start (before the indent) when quests aren't grouped by zone
-- Shared with the files beside this one.
T.ITEM_SIZE, T.SPOKEN_SIZE, T.ZONE_OFFSET_X, T.UNGROUPED_OFFSET_X = ITEM_SIZE, SPOKEN_SIZE, ZONE_OFFSET_X, UNGROUPED_OFFSET_X
local ZONE_TEMPLATE = "ObjectiveTrackerBlockTemplate"
T.ZONE_TEMPLATE = ZONE_TEMPLATE
local OTHER_ZONE = OTHER and (OTHER .. " " .. (QUESTS_LABEL or "Quests")) or "Other Quests"
-- Quest focus icons. The icon is poiSize wide and its right edge sits POI_GAP left of the title. With an indent of 0 it
-- starts POI_OVERHANG left of the list's edge, about where it was before the size became a setting. "Room" is how far
-- in the title starts at that point. TrackerPools.lua anchors the icon with POI_GAP.
local POI_GAP = 7
local POI_OVERHANG = 3
T.POI_GAP = POI_GAP

-- Whether the game's quest map icons are on (its questPOI setting); the icons beside each title, and the room kept for
-- them, follow it. Shared with the files beside this one.
function T.PoiShown()
	return GetCVarBool("questPOI") and true or false
end

-- Focus mode is on when the Extras switch is on and the Quests bar's target button is lit.
function T.FocusModeOn()
	return Q.db and Q.db.superFocus and Q.db.focusQuest and true or false
end

-- The target button: lights focus mode on or off and redraws.
function T.ToggleFocusMode()
	Q.db.focusQuest = not Q.db.focusQuest
	T.MarkDirty()
end

-- The icon's width in pixels: the setting, whole and never tiny. The one place that reads it.
function T.PoiSize()
	local size = tonumber(Q.db and Q.db.poiSize) or Q.defaults.poiSize
	return math.floor(math.max(8, size) + 0.5)
end

-- `size` is only passed by the settings migration, which has a saved size that is not the current one yet.
function T.PoiRoom(size)
	return (size or T.PoiSize()) + POI_GAP - POI_OVERHANG
end

-- Two neighbouring icons may overlap by this many pixels before a row is stretched: the ring's art has a margin of
-- empty pixels, so a small overlap of the frames is not seen. It is wide enough that the preset sizes (Comfortable 24,
-- Compact 20) keep their row heights exactly; a custom icon size, quest gap or text size that brings two icons closer
-- than this stretches the rows.
local POI_OVERLAP = 8

-- The shortest a quest's row may be so icons do not run into each other: the distance between two icons' centres is a
-- row's height plus the gap below it.
function T.PoiMinRow()
	return T.PoiSize() - POI_OVERLAP - (Q.db.questGap or 0)
end

local module, container -- also T.module and T.container once created
local dirty = false
local instantNext = false -- the next redraw skips the glide
local completeSeen = {} -- questID -> complete at the last redraw, for the completion glow
local focusID -- while focus mode folds the other quests: the one quest that keeps its objectives
local Motion = Q.Motion

------------------------------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------------------------------
-- Shared with TrackerSearch.lua.
local function Hex(color)
	return ("|cff%02x%02x%02x"):format(
		math.floor(color.r * 255 + 0.5),
		math.floor(color.g * 255 + 0.5),
		math.floor(color.b * 255 + 0.5)
	)
end

T.Hex = Hex

local function Lighten(color, amount)
	return {
		r = color.r + (1 - color.r) * amount,
		g = color.g + (1 - color.g) * amount,
		b = color.b + (1 - color.b) * amount,
	}
end

-- Puts the quest's link in chat: into the chat box if it's open, otherwise opens it with the link ready to send.
function T.LinkQuest(questID)
	local link = GetQuestLink and GetQuestLink(questID)
	if not link then
		return false
	end
	local util = ChatFrameUtil
	local active = (util and util.GetActiveWindow and util.GetActiveWindow())
		or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
	if active then
		local insert = (util and util.InsertLink) or ChatEdit_InsertLink
		if insert and insert(link) then
			return true
		end
	end
	local open = (util and util.OpenChat) or ChatFrame_OpenChat
	if open then
		open(link)
		return true
	end
	return false
end

function T.ShareQuest(questID)
	if QuestUtil and QuestUtil.ShareQuest then
		QuestUtil.ShareQuest(questID)
	elseif C_QuestLog.SetSelectedQuest and QuestLogPushQuest then
		C_QuestLog.SetSelectedQuest(questID)
		QuestLogPushQuest()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Watched quests, grouped by quest-log zone
------------------------------------------------------------------------------------------------------------------------
local function ReadZones()
	local zones, header = {}, nil
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info then
			if info.isHeader then
				header = info.title
			elseif info.questID and header then
				zones[info.questID] = header
			end
		end
	end
	return zones
end

local function Displayable(questID, info)
	if not info or info.isHeader then
		return false
	end
	if C_QuestLog.IsQuestDisabledForSession and C_QuestLog.IsQuestDisabledForSession(questID) then
		return false
	end
	return not info.isTask and not info.isBounty
end

-- Tracked order. The game's watch list is the source (on this client a newly tracked quest goes to the front, so the
-- newest sits on top), but the game can drop a quest from it and add it straight back at the front (as a quest
-- completes), which would jump it to the top of its zone. So each quest keeps the place it had: a quest back within
-- RETURN_GRACE seconds keeps its old place. A quest new to the list goes right after the quest before it in the watch
-- list, or above everything when it is first. Places are saved per character, so a /reload doesn't undo them.
local RETURN_GRACE = 3
local goneAt = {}
local sessionRanks = {}

-- This character's saved places: { [questID] = place }.
local function Ranks()
	local db = Q.db
	local name, realm = UnitName("player"), GetRealmName()
	if not (db and db.questOrder and Q.Readable(name) and name and Q.Readable(realm) and realm) then
		return sessionRanks
	end
	local key = name .. "-" .. realm
	db.questOrder[key] = db.questOrder[key] or {}
	return db.questOrder[key]
end

local function Rank(list)
	local rank = Ranks()
	local now = GetTime()
	local present = {}
	for _, quest in ipairs(list) do
		present[quest.id] = true
		if goneAt[quest.id] then
			if now - goneAt[quest.id] > RETURN_GRACE then
				rank[quest.id] = nil
			end
			goneAt[quest.id] = nil
		end
	end
	-- An empty list is often the quest log not loaded yet (at login), so nothing is forgotten then.
	if #list > 0 then
		for questID in pairs(rank) do
			if not present[questID] then
				goneAt[questID] = goneAt[questID] or now
				if now - goneAt[questID] > RETURN_GRACE then
					rank[questID], goneAt[questID] = nil, nil
				end
			end
		end
	end
	for index, quest in ipairs(list) do
		if not rank[quest.id] then
			local before = list[index - 1] and rank[list[index - 1].id]
			if before then
				-- Halfway to the next place up, so it lands right after `before`.
				local nextUp
				for _, value in pairs(rank) do
					if value > before and (not nextUp or value < nextUp) then
						nextUp = value
					end
				end
				rank[quest.id] = nextUp and (before + nextUp) / 2 or before + 1
			else
				local lowest
				for _, value in pairs(rank) do
					lowest = math.min(lowest or value, value)
				end
				rank[quest.id] = (lowest or 1) - 1
			end
		end
	end
	-- Renumber 1, 2, 3... so halving never runs out, keeping ties in watch-list order.
	local ids, watchPos = {}, {}
	for index, quest in ipairs(list) do
		watchPos[quest.id] = index
	end
	for questID in pairs(rank) do
		ids[#ids + 1] = questID
	end
	table.sort(ids, function(a, b)
		if rank[a] ~= rank[b] then
			return rank[a] < rank[b]
		end
		return (watchPos[a] or math.huge) < (watchPos[b] or math.huge)
	end)
	for position, questID in ipairs(ids) do
		rank[questID] = position
	end
	for _, quest in ipairs(list) do
		quest.order = rank[quest.id]
	end
end

-- One record per watched quest. The zone comes from the quest log; when a header is folded in the log the last zone
-- seen for that quest is used, so folding the log never moves quests into "Other Quests".
local function Collect()
	local db = Q.db
	local zones = ReadZones()
	local list, seen = {}, {}
	for watchIndex = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(watchIndex)
		if questID and not seen[questID] then
			seen[questID] = true
			local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
			local info = logIndex and C_QuestLog.GetInfo(logIndex)
			if Displayable(questID, info) then
				local zone = zones[questID]
				if zone then
					db.zoneOf[questID] = zone
				else
					zone = db.zoneOf[questID] or OTHER_ZONE
				end
				list[#list + 1] = {
					id = questID,
					logIndex = logIndex,
					info = info,
					zone = zone,
					complete = C_QuestLog.IsComplete(questID) and true or false,
				}
			end
		end
	end
	for questID in pairs(db.zoneOf) do
		if not C_QuestLog.GetLogIndexForQuestID(questID) then
			db.zoneOf[questID] = nil
		end
	end
	Rank(list)
	return list
end

-- Within a zone (or the whole list without zones), finished quests can sit above or below the rest. Each part keeps the
-- tracked order (see Rank).
local function SortFinished(quests)
	local where = Q.db.completeOrder
	local moves = where == "top" or where == "bottom"
	local top = where == "top"
	table.sort(quests, function(a, b)
		if moves and a.complete ~= b.complete then
			return a.complete == top
		end
		return a.order < b.order
	end)
end

local function Group(list)
	local db = Q.db
	if not db.grouping then
		SortFinished(list)
		return { { quests = list } }
	end
	local byZone, groups = {}, {}
	for _, quest in ipairs(list) do
		local group = byZone[quest.zone]
		if not group then
			group = { name = quest.zone, quests = {} }
			byZone[quest.zone] = group
			groups[#groups + 1] = group
		end
		group.quests[#group.quests + 1] = quest
	end
	for _, group in ipairs(groups) do
		SortFinished(group.quests)
	end
	local names = {}
	for _, group in ipairs(groups) do
		names[#names + 1] = group.name
	end
	local here = T.CurrentZone(names)
	table.sort(groups, function(a, b)
		if db.currentFirst then
			local aHere, bHere = a.name == here, b.name == here
			if aHere ~= bHere then
				return aHere
			end
		end
		local aOther, bOther = a.name == OTHER_ZONE, b.name == OTHER_ZONE
		if aOther ~= bOther then
			return bOther
		end
		return a.name < b.name
	end)
	return groups, here
end

-- For the regression tests only (tests/ offline, Dev/CleanQuestTracker_Tests in game): the file-local pieces they
-- check, so the tests run this code rather than a copy of it. Nothing in the add-on reads this table.
T._internal = {
	Rank = Rank,
	Ranks = Ranks,
	Collect = Collect,
	SortFinished = SortFinished,
	Group = Group,
	goneAt = goneAt,
	sessionRanks = sessionRanks,
	OTHER_ZONE = OTHER_ZONE,
}

-- Finished titles use the player's completion colour. For active quests, use the difficulty that Forever's quest
-- log assigns to this quest ID. The numeric quest level is only for the optional prefix.
-- Returns normal and hover text. Search matches are marked in the name, never in the level.
function T.Title(questID, info, isComplete)
	local db = Q.db
	local name = T.QuestName(questID, info, isComplete)
	local level = Q.Readable(info.difficultyLevel) and info.difficultyLevel or info.level
	local prefix = ""
	if db.levels and Q.Readable(level) and level > 0 then
		prefix = ("[%d] "):format(level)
	end
	local color, highlight
	if isComplete then
		color = Q.CompleteColor()
	elseif db.difficulty and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
		local ok, difficulty = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
		if ok and Q.Readable(difficulty) then
			color, highlight = GetDifficultyColor(difficulty)
		end
	end
	if not color then
		color = Q.Color("colorTitle")
		highlight = color.reverse
	end
	highlight = highlight or Lighten(color, 0.3)
	local normal, hover = Hex(color), Hex(highlight)
	return normal .. prefix .. T.MarkSearch(name, normal) .. "|r", hover .. prefix .. T.MarkSearch(name, hover) .. "|r"
end

------------------------------------------------------------------------------------------------------------------------
-- Lines and progress bars
------------------------------------------------------------------------------------------------------------------------

-- Acquires the line first so its font size is right before Blizzard measures the text. Lines without a colour of
-- their own use the Objectives colour from the Colours page.
local function AddLine(block, key, text, dashStyle, color)
	local line = block:GetLine(key)
	Q.Font(line.Text, Q.db.fontSize)
	Q.Font(line.Dash, Q.db.fontSize)
	return block:AddObjective(key, text, nil, true, dashStyle, color or Q.Color("colorObjective"))
end

local function MarkBarsUnused(block)
	for _, bar in pairs(block.qcBars or {}) do
		bar.qcUsed = false
	end
end

local function HideUnusedBars(block)
	for _, bar in pairs(block.qcBars or {}) do
		if not bar.qcUsed then
			bar:Hide()
		end
	end
end

-- A thin bar under a counted objective, lined up with the objective text. The bar object stays with its block and
-- key, so the fill animates from the old value whenever the count changes.
local function AddBar(block, line, key, done, total)
	block.qcBars = block.qcBars or {}
	local bar = block.qcBars[key]
	if not bar then
		bar = Q.NewProgressBar(block)
		block.qcBars[key] = bar
	end
	bar.qcUsed = true
	bar:SetHeight(Q.db.barHeight)
	local gap = Q.db.barGap or 2
	block:AddCustomRegion(bar, 0, -gap)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -gap)
	bar:SetPoint("RIGHT", line, "RIGHT", 0, 0)
	local inset = 0
	if line.Dash and line.Dash:IsShown() then
		inset = line.Dash:GetStringWidth() or 0
	end
	Q.SetBarInset(bar, inset + 1, 8)
	Q.SetBarProgress(bar, tostring(block.id) .. ":" .. tostring(key), done, total, false)
end

------------------------------------------------------------------------------------------------------------------------
-- Quest menu (right-click), matching Blizzard's entries
------------------------------------------------------------------------------------------------------------------------
local function OpenQuestMenu(block)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	local questID = block.id
	MenuUtil.CreateContextMenu(block, function(_, root)
		root:CreateTitle(C_QuestLog.GetTitleForQuestID(questID) or "")
		if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
			root:CreateButton(SUPER_TRACK_QUEST or "Focus", function()
				C_SuperTrack.SetSuperTrackedQuestID(questID)
			end)
		else
			root:CreateButton(STOP_SUPER_TRACK_QUEST or "Stop focusing", function()
				C_SuperTrack.SetSuperTrackedQuestID(0)
			end)
		end
		root:CreateButton(OBJECTIVES_VIEW_IN_QUESTLOG or "Open quest details", function()
			if QuestUtil and QuestUtil.OpenQuestDetails then
				QuestUtil.OpenQuestDetails(questID)
			else
				QuestMapFrame_OpenToQuestDetails(questID)
			end
		end)
		root:CreateButton(OBJECTIVES_SHOW_QUEST_MAP or "Show on map", function()
			QuestMapFrame_OpenToQuestDetails(questID)
		end)
		if IsInGroup() and C_QuestLog.IsPushableQuest(questID) then
			root:CreateButton(SHARE_QUEST or "Share quest", function()
				T.ShareQuest(questID)
			end)
		end
		if not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch() then
			root:CreateButton(OBJECTIVES_STOP_TRACKING or "Stop tracking", function()
				C_QuestLog.RemoveQuestWatch(questID)
			end)
		end
		if QuestMapQuestOptions_AbandonQuest then
			root:CreateButton(ABANDON_QUEST_ABBREV or "Abandon", function()
				QuestMapQuestOptions_AbandonQuest(questID)
			end)
		end
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- Module overrides (this instance only)
------------------------------------------------------------------------------------------------------------------------
local M = {}

function M:InitModule()
	self:WatchMoney(false)
end

-- A layout moves blocks; with a secure item button attached that is refused in combat.
function M:CanUpdate()
	return not InCombatLockdown() or T.ItemCount() == 0
end

function M:GetContextMenuParent()
	return Q.Frame.host
end

-- The module's frame lifecycle, routed to the private pools (TrackerPools.lua).
function M:AcquireFrame(template)
	local frame, isNew = T.Pools.Acquire(self, template)
	frame:SetParent(self.ContentsFrame)
	if frame.GetLine then
		T.PatchBlock(frame)
	end
	return frame, isNew
end

function M:FreeBlock(block)
	self:RemoveBlockFromCache(block, true)
	block:Free()
	self.usedBlocks[block.template][block.id] = nil
	T.Pools.Release(block)
	self:OnFreeBlock(block)
end

function M:FreeUnusedTimerBars()
	for key, timerBar in pairs(self.usedTimerBars or {}) do
		if not timerBar.used then
			self.usedTimerBars[key] = nil
			T.Pools.Release(timerBar)
		end
	end
end

function M:FreeUnusedProgressBars()
	for key, progressBar in pairs(self.usedProgressBars or {}) do
		if not progressBar.used then
			self.usedProgressBars[key] = nil
			if progressBar.OnFree then
				progressBar:OnFree()
			end
			T.Pools.Release(progressBar)
		end
	end
end

function M:FreeUnusedRightEdgeFrames()
	for key, frame in pairs(self.usedRightEdgeFrames or {}) do
		if not frame.used then
			self.usedRightEdgeFrames[key] = nil
			T.Pools.Release(frame)
		end
	end
end

-- A turned-in or removed quest is held on screen for its fade-out ("cached") and released when the animation reports
-- back. If that report never comes (the block was hidden, folded or re-used mid-animation), the quest would stay until
-- the next unrelated redraw. Each layout first releases any held block that no longer has an animation running.
function M:BeginLayout()
	local stale
	self:EnumerateActiveBlocks(function(block)
		if block.cached and not block.activeAnim and not block.pendingAnim then
			stale = stale or {}
			stale[#stale + 1] = block
		end
	end)
	for _, block in ipairs(stale or {}) do
		self:RemoveBlockFromCache(block, true)
		block:SetAlpha(1)
	end
	ObjectiveTrackerModuleMixin.BeginLayout(self)
end

-- Quest log changes that arrive in several steps (turn-in, abandon, accept) get one more redraw once the server and
-- the fade-out have both settled.
local SETTLE_EVENTS = {
	QUEST_TURNED_IN = true,
	QUEST_REMOVED = true,
	QUEST_ACCEPTED = true,
	QUEST_WATCH_LIST_CHANGED = true,
}

function M:OnEvent(event, ...)
	if SETTLE_EVENTS[event] then
		Q.Debounce("tracker-settle", 0.9, T.MarkDirty)
	end
	if event == "QUEST_WATCH_LIST_CHANGED" then
		local questID, added = ...
		if added and questID and not self:GetExistingBlock(questID) then
			self:SetNeedsFanfare(questID)
		end
	elseif event == "QUEST_TURNED_IN" then
		local questID = ...
		local block = questID and self:GetExistingBlock(questID)
		if block and block.PlayTurnInAnimation then
			block:PlayTurnInAnimation()
		end
	end
	self:MarkDirty()
end

function M:OnBlockHeaderClick(block, mouseButton)
	if block.qcZone then
		-- While searching, zones with matches stay open; folding one would change nothing on screen.
		if mouseButton == "LeftButton" and not T.SearchActive() then
			T.ToggleZone(block.qcZone)
		end
		return
	end
	local questID = block.id
	-- Shift-click links the quest in chat, opening the chat box if it isn't already. (Blizzard's tracker only links
	-- when the box is open and otherwise untracks the quest; "Stop tracking" stays in the right-click menu.)
	if mouseButton ~= "RightButton" and IsModifiedClick("CHATLINK") and T.LinkQuest(questID) then
		return
	end
	if mouseButton == "RightButton" then
		OpenQuestMenu(block)
	else
		local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
		local info = logIndex and C_QuestLog.GetInfo(logIndex)
		if info and info.isAutoComplete and C_QuestLog.IsComplete(questID) and ShowQuestComplete then
			ShowQuestComplete(questID)
		else
			QuestMapFrame_OpenToQuestDetails(questID)
		end
	end
end

function M:OnBlockHeaderEnter(block)
	if block.qcZone then
		T.PaintZone(block, Q.Color("colorZone").reverse)
		return
	end
	if block.qcTitleHi then
		block.HeaderText:SetText(block.qcTitleHi)
	end
	-- Blizzard also fires an EventRegistry event here. It is left out on purpose: firing it from add-on code would run
	-- other listeners tainted.
	if IsInGroup() and GameTooltip.SetQuestPartyProgress then
		GameTooltip:SetOwner(block, Q.Frame.TooltipAnchor())
		GameTooltip:SetQuestPartyProgress(block.id)
	end
end

function M:OnBlockHeaderLeave(block)
	if block.qcZone then
		T.PaintZone(block, Q.Color("colorZone"))
		return
	end
	if block.qcTitle then
		block.HeaderText:SetText(block.qcTitle)
	end
	GameTooltip:Hide()
end

function M:OnFreeBlock(block)
	for _, bar in pairs(block.qcBars or {}) do
		bar:Hide()
	end
	if block.qcSpoken then
		block.qcSpoken:Hide()
	end
	Q.Party.Detach(block)
	if block.qcRule then
		block.qcRule:Hide()
	end
	block.qcItemIndex = nil
	block.qcTitle, block.qcTitleHi, block.qcZone, block.qcGroup = nil, nil, nil, nil
	T.HideSearchMarks(block)
	T.StopMotion(block)
	if block.qcChevron then
		Motion.Finish(block.qcChevron)
		block.qcChevronZone, block.qcChevronTarget = nil, nil
	end
end

-- Adapted from Blizzard's QuestObjectiveTrackerMixin:DoQuestObjectives, with progress bars and the option to keep
-- finished objectives on screen.
function M:QCObjectives(block, questID, logIndex, isComplete, isSequenced, isExisting)
	local db = Q.db
	local S = ObjectiveTrackerAnimLineState
	-- Finished quests sorted to the top or bottom move as they complete. The move is their only animation: they fold to
	-- their title at once, since Blizzard's check-mark flash is drawn stretched and oversized on a row that is moving.
	local moves = db.completeOrder == "top" or db.completeOrder == "bottom"
	local done = Q.CompleteColor()
	local hideDash = OBJECTIVE_DASH_STYLE_HIDE
	local completing = false
	local objectives = C_QuestLog.GetQuestObjectives(questID)
	for index = 1, GetNumQuestLeaderBoards(logIndex) or 0 do
		local text, objectiveType, finished = GetQuestLogLeaderBoard(index, logIndex, true)
		if text then
			text = T.MarkSearch(text)
			local line = block:GetExistingLine(index)
			if isComplete then
				if not db.foldComplete then
					line = AddLine(block, index, text, hideDash, done)
				elseif moves then
					line = nil -- folded at once: the line is not added, so it is released at the end of this layout
				elseif line and line.state ~= S.Faded then
					line = AddLine(block, index, text, hideDash, done)
					if not line.state or line.state == S.Present then
						line:SetState(S.Completing)
					end
				end
			elseif finished then
				if line and line.state == S.Faded then
					line = nil
				elseif line then
					line = AddLine(block, index, text, hideDash, done)
					if not line.state or line.state == S.Present then
						line:SetState(S.Completing)
					end
				elseif not isSequenced then
					line = AddLine(block, index, text, hideDash, done)
					line:SetState(S.Completed)
				end
			elseif not (not line and isSequenced and completing) then
				if isSequenced and isExisting and not line then
					line = AddLine(block, index, text)
					line:SetState(S.Adding)
					if SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then
						PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
					end
				else
					line = AddLine(block, index, text)
					if line.state == S.Completed then
						line:SetState(S.Present)
					end
				end
				if objectiveType == "progressbar" then
					local bar = block:AddProgressBar(questID)
					if bar and GetQuestProgressBarPercent then
						bar:SetPercent(GetQuestProgressBarPercent(questID))
					end
				elseif db.bars then
					local objective = objectives and objectives[index]
					local required = objective and objective.numRequired or 0
					local fulfilled = objective and objective.numFulfilled or 0
					if objective and not objective.finished and required > 1 and fulfilled > 0 then
						AddBar(block, line, index, fulfilled, required)
					end
				end
			end
			if line and line.state == S.Completing then
				completing = true
			end
		end
	end
	if isComplete and db.foldComplete and not completing then
		block:ForEachUsedLine(function(line)
			if line.state == S.Completed then
				line:SetState(S.Fading)
			end
		end)
	end
	return completing
end

-- Adapted from Blizzard's QuestObjectiveTrackerMixin:UpdateSingle. The right-hand column (item button, Spoken's play
-- button and the party badge) is reserved before any text is set, so titles wrap clear of it.
function M:QCQuest(quest, grouped)
	local db = Q.db
	local questID, logIndex, info = quest.id, quest.logIndex, quest.info
	local isComplete = quest.complete
	local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID
	local showWaypoint = isSuperTracked
		or (QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID() == questID)
	local isSequenced = IsQuestSequenced and IsQuestSequenced(questID) or false
	local block, isExisting = self:GetBlock(questID)
	local folded = focusID and questID ~= focusID
	-- A block folded by focus mode has no lines, so opening it again is not a new objective arriving (which would
	-- play the sequenced-quest sound).
	isExisting = isExisting and not block.qcFolded
	block.qcFolded = folded
	block.offsetX = T.QuestOffset(grouped)
	block.qcGroup = grouped and quest.zone or nil
	self:AnchorBlock(block)
	MarkBarsUnused(block)

	local right = 0
	local hasItem = T.QuestShowsItem(logIndex, isComplete)
	block.qcItemIndex = hasItem and logIndex or nil
	if hasItem then
		right = right + ITEM_SIZE + ITEM_GAP
	end
	local spokenX
	if T.SpokenShows(questID) then
		spokenX = -right
		right = right + SPOKEN_SIZE + SPOKEN_GAP
	end
	local members, partySize = Q.Party.Members(questID)
	local badgeX
	if members then
		badgeX = -right
		right = right + Q.Party.BadgeWidth() + 2
	end
	if right > 0 then
		block:AdjustRightEdgeOffset(-right)
	end

	block.qcTitle, block.qcTitleHi = T.Title(questID, info, isComplete)
	Q.Font(block.HeaderText, db.fontSize)
	block:SetHeader(block.isHighlighted and block.qcTitleHi or block.qcTitle)
	-- Flare once when a quest seen in progress turns complete (not for quests already complete at login).
	local wasComplete = completeSeen[questID]
	completeSeen[questID] = isComplete
	block.qcComplete = isComplete
	-- A quest that moves as it completes (finished quests sorted to the top or bottom) only glides; see QCObjectives.
	local moves = db.completeOrder == "top" or db.completeOrder == "bottom"
	if isComplete and wasComplete == false and not moves then
		T.Glow(block)
	end

	local waypoint = showWaypoint and C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(questID)
	if folded then
		-- Focus mode: every quest but the focused one shows its title alone. Nothing is added, so the objective lines,
		-- bars and timers it had are released at the end of this layout.
	elseif isComplete then
		-- Finished: the objectives play Blizzard's check-and-fade, then the quest collapses to its title. Quests that
		-- complete from the tracker keep their "click to complete" line, since that is how they are turned in.
		local completing = self:QCObjectives(block, questID, logIndex, true, isSequenced, isExisting)
		if not completing and info.isAutoComplete then
			AddLine(block, "ClickComplete", QUEST_WATCH_CLICK_TO_COMPLETE, OBJECTIVE_DASH_STYLE_HIDE, Q.CompleteColor())
		end
	elseif C_QuestLog.IsFailed(questID) then
		AddLine(block, "Failed", FAILED, OBJECTIVE_DASH_STYLE_HIDE, OBJECTIVE_TRACKER_COLOR["Failed"])
	else
		if waypoint and WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL then
			AddLine(block, "Waypoint", WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL:format(waypoint))
		end
		self:QCObjectives(block, questID, logIndex, false, isSequenced, isExisting)
		local required = (C_QuestLog.GetRequiredMoney and C_QuestLog.GetRequiredMoney(questID))
			or (GetQuestLogRequiredMoney and GetQuestLogRequiredMoney(logIndex))
			or 0
		if required > 0 then
			self:WatchMoney(true)
			local money = GetMoney()
			if required > money then
				AddLine(block, "Money", GetMoneyString(money) .. " / " .. GetMoneyString(required))
			end
		end
		local timeTotal, timeElapsed = C_QuestLog.GetTimeAllowed(questID)
		if timeTotal and timeElapsed and timeElapsed < timeTotal then
			block:AddTimerBar(timeTotal, GetTime() - timeElapsed)
		end
	end
	HideUnusedBars(block)

	if hasItem then
		block.height = math.max(block.height, ITEM_SIZE)
	end
	-- A row with a party badge is at least as tall as the badge plus a gap, so badges never touch the one above or below.
	if members then
		block.height = math.max(block.height, Q.Party.MinRow())
	end
	-- The module skips Blizzard's shared POI check (showWorldQuests), so the quest-POI setting is honoured here. A short
	-- row (a finished quest folded to its title) is stretched to hold its icon, so icons never overlap.
	if T.PoiShown() then
		block.height = math.max(block.height, T.PoiMinRow())
		block:SetPOIInfo(questID, isComplete, isSuperTracked)
	else
		block:SetPOIInfo()
	end
	if not self:LayoutBlock(block) then
		return false
	end
	Q.Party.Attach(block, members, partySize, badgeX)
	if spokenX then
		T.DressSpoken(block, spokenX)
	elseif block.qcSpoken then
		block.qcSpoken:Hide()
	end
	return true
end

function M:LayoutContents()
	self:WatchMoney(false)
	local db = Q.db
	local list = Collect()
	self.qcCount, self.qcTotal = #list, #list
	-- Focus mode needs the focused quest to be in the list; otherwise nothing is folded.
	focusID = nil
	if T.FocusModeOn() then
		local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
		for _, quest in ipairs(list) do
			if quest.id == superTracked then
				focusID = superTracked
				break
			end
		end
	end
	local groups, here = Group(list)
	-- Zone names come from the whole list, so the zone tools (focus, expand all) see every zone while searching.
	local names = {}
	for _, group in ipairs(groups) do
		names[#names + 1] = group.name
	end
	T.zoneNames = names
	-- Collapse every zone but yours, also for zones that join the list later (a follow-up quest elsewhere). Turning it
	-- on fades the other zones first (T.ToggleFocus); folding mid-fade would cut that short, so it waits.
	if db.focusZone and db.grouping and not T.IsFolding() then
		for _, name in ipairs(names) do
			db.collapsed[name] = (name ~= here) or nil
		end
	end
	local searching = T.SearchActive()
	if searching then
		local kept, shown = {}, 0
		for _, group in ipairs(groups) do
			local zoneHit = group.name and db.searchZones and T.Matches(group.name)
			local quests = {}
			for _, quest in ipairs(group.quests) do
				if zoneHit or T.QuestMatches(quest) then
					quests[#quests + 1] = quest
				end
			end
			if #quests > 0 then
				kept[#kept + 1] = { name = group.name, quests = quests, total = #group.quests }
				shown = shown + #quests
			end
		end
		groups = kept
		self.qcCount = shown
	end
	-- Blizzard's module puts one fixed gap (fromBlockOffsetY) above every block. Setting it just before each block
	-- gives zone headings and quests their own gaps; GetBlock and LayoutBlock both read it at that moment.
	for _, group in ipairs(groups) do
		if group.name then
			self.fromBlockOffsetY = -db.zoneGap
			local block = self:GetBlock("qczone:" .. group.name, ZONE_TEMPLATE)
			block.offsetX = ZONE_OFFSET_X
			self:AnchorBlock(block)
			T.StyleZone(block, group)
			if not self:LayoutBlock(block) then
				return
			end
		end
		if not (group.name and db.collapsed[group.name] and not searching) then
			self.fromBlockOffsetY = -db.questGap
			for _, quest in ipairs(group.quests) do
				if not self:QCQuest(quest, group.name ~= nil) then
					return
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------------------------------------------
-- Where quest titles start. With quest focus icons off, the indent (indent) counts from the zone name, so 0 lines titles
-- up under it; without zones it counts from a small margin. With icons on, the icon comes first and the title follows
-- it: the indent (poiIndent, kept separately) is the space from the list's left edge to the icon.
function T.QuestOffset(grouped)
	if T.PoiShown() then
		return T.PoiRoom() + (tonumber(Q.db.poiIndent) or 0)
	end
	return (grouped and ZONE_OFFSET_X or UNGROUPED_OFFSET_X) + Q.db.indent
end

-- A redraw is already queued.
function T.IsDirty()
	return dirty
end

-- `instant` skips the glide for that redraw (settings changes, resizing).
function T.MarkDirty(instant)
	if instant == true then
		instantNext = true
	end
	if dirty then
		return
	end
	dirty = true
	C_Timer.After(0, T.Update)
end

function T.Update()
	dirty = false
	if not module then
		return
	end
	if not Q.Active() then
		if not (InCombatLockdown() and T.ItemsInUse()) then
			module:Hide()
			T.ReleaseItems()
		end
		Q.Frame.SetContent(0, 0)
		return
	end
	if not module:CanUpdate() then
		T.waitingForCombat = true
		T.DimItems(true)
		return
	end
	container.isCollapsed = Q.db.minimized and true or false
	module.lineSpacing = Q.db.spacing
	local instant = instantNext
	instantNext = false
	local before = not instant and not Q.db.minimized and Motion.On() and T.Snapshot() or nil
	module:Update(100000, false)
	T.ApplySearchMarks()
	local count = module.qcCount or 0
	-- A search with no matches shows a single "No quests match" line instead of an empty list.
	local height = Q.Frame.ShowNoMatch(T.SearchActive() and count == 0, module:GetContentsHeight())
	-- The frame hides only when no quests are tracked at all, never because a search matched nothing.
	local total = module.qcTotal or count
	Q.Frame.SetContent(height, total)
	Q.Frame.SetSearchCount(count, total)
	Q.Frame.UpdateZoneTools()
	T.RestoreFaded()
	T.Glide(before)
	T.PlaceItems()
	if T.HighlightActive() then
		T.ApplyHighlight()
	end
	T.drawnSignature = T.Signature()
end

-- Rebuilds every block from scratch, for settings that change what a block is made of.
function T.Rebuild()
	if not module or InCombatLockdown() then
		T.MarkDirty()
		return
	end
	local blocks = {}
	module:EnumerateActiveBlocks(function(block)
		blocks[#blocks + 1] = block
	end)
	for _, block in ipairs(blocks) do
		module:ForceRemoveBlock(block)
	end
	T.MarkDirty()
end

function T.OnCombatEnded()
	if T.waitingForCombat then
		T.waitingForCombat = false
		T.DimItems(false)
	end
	T.ApplyNativeVisibility()
	T.MarkDirty()
end

-- Blizzard's tracker is hidden only through the secure state driver, never with addon Show/Hide calls, which would
-- taint the managed-frame layout. In combat the driver cannot change, so a native Show is muted with alpha instead.
local nativeDriver = false
local nativeHooked = false
local function WantNativeHidden()
	return Q.Active() and Q.db.hideBlizzard
end

function T.ApplyNativeVisibility()
	local frame = ObjectiveTrackerFrame
	if not frame then
		return
	end
	if not nativeHooked then
		nativeHooked = true
		frame:HookScript("OnShow", function(self)
			if WantNativeHidden() then
				self:SetAlpha(0)
			end
		end)
	end
	if InCombatLockdown() then
		if WantNativeHidden() then
			frame:SetAlpha(0)
		end
		return
	end
	if WantNativeHidden() then
		frame:SetAlpha(0)
		if not nativeDriver then
			RegisterStateDriver(frame, "visibility", "hide")
			nativeDriver = true
		end
	elseif nativeDriver then
		RegisterStateDriver(frame, "visibility", "show")
		UnregisterStateDriver(frame, "visibility")
		nativeDriver = false
		frame:SetAlpha(1)
	end
end

function T.Create(parent)
	container = parent
	T.container = container
	container.isCollapsed = false
	function container:IsCollapsed()
		return self.isCollapsed
	end
	function container:ForceExpand()
		if Q.db.minimized then
			Q.Frame.SetMinimized(false)
		end
	end
	function container:MarkDirty()
		T.MarkDirty()
	end

	module = CreateFrame("Frame", "CleanQuestTrackerQuests", parent, "ObjectiveTrackerModuleTemplate")
	Mixin(module, QuestObjectiveTrackerMixin, M)
	module.events = {
		"QUEST_LOG_UPDATE",
		"QUEST_WATCH_LIST_CHANGED",
		"QUEST_AUTOCOMPLETE",
		"QUEST_TURNED_IN",
		"QUEST_POI_UPDATE",
		"SUPER_TRACKING_CHANGED",
		"PLAYER_LEVEL_UP",
		"PLAYER_MONEY",
	}
	module.headerHeight = 0
	module.fromHeaderOffsetY = -6
	module.blockOffsetX = ZONE_OFFSET_X -- only a fallback: every block sets its own offset
	-- Makes Blizzard's POI block show its button without asking ObjectiveTrackerManager:CanShowPOIs, which would
	-- write this module into the manager's shared state.
	module.showWorldQuests = true
	module.Header:Hide()
	module.ContentsFrame:ClearAllPoints()
	module.ContentsFrame:SetPoint("TOPLEFT")
	module.ContentsFrame:SetPoint("BOTTOMRIGHT")
	module:SetContainer(parent)
	-- Extra quest-log events beyond Blizzard's list, so accepting, abandoning, finishing and objective progress always
	-- redraw. Registered one by one with pcall, since not every client has every event.
	for _, event in ipairs({ "QUEST_REMOVED", "QUEST_ACCEPTED", "QUEST_LOG_CRITERIA_UPDATE", "SUPER_TRACKING_PATH_UPDATED" }) do
		pcall(module.RegisterEvent, module, event)
	end
	pcall(module.RegisterUnitEvent, module, "UNIT_QUEST_LOG_CHANGED", "player")
	module:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
	T.module = module
	T.StartWatching()
end
