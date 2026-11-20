-- Clean Quest Tracker's in-game self-test: /cqttest. For developers; never packaged (.github/pkgmeta.yml ignores Dev).
--
-- Checks what needs the real client and the real quest list: zones as drawn, the game briefly untracking and
-- re-tracking a quest (as it does when one completes), focus mode folding and its fade. The pure logic is covered
-- offline by tests/ in CI. It needs at least two tracked quests in one zone (and a second zone for the focus checks),
-- zones turned on, out of combat. It takes about 25 seconds.
--
-- It changes the watch list, folds, focus mode and the finished-quest setting while it runs, and always puts back the
-- watch list (in its order), folds, focus state, settings and this character's saved quest order afterwards: also
-- when a check errors or combat starts, and after a /reload or logout mid-run (what to put back is saved in
-- CleanQuestTrackerTestsDB until the run finishes). It only replaces functions on Clean Quest Tracker's own table,
-- never a game global, so it can't taint Blizzard's code.

local Q = CleanQuestTracker
local T = Q and Q.Tracker
local I = T and T._internal

------------------------------------------------------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------------------------------------------------------
local results = { pass = 0, fail = 0 }

local function Say(message)
	print("|cff80c0ffCQT self-test:|r " .. message)
end

local function Check(name, ok, detail)
	if ok then
		results.pass = results.pass + 1
	else
		results.fail = results.fail + 1
		Say("|cffff4040FAIL|r " .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or ""))
	end
end

------------------------------------------------------------------------------------------------------------------------
-- The watch list and what is drawn
------------------------------------------------------------------------------------------------------------------------
local function WatchList()
	local out = {}
	for index = 1, C_QuestLog.GetNumQuestWatches() do
		out[#out + 1] = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
	end
	return out
end

local watchTypes = {}
local function Watch(questID)
	if watchTypes[questID] ~= nil then
		C_QuestLog.AddQuestWatch(questID, watchTypes[questID])
	else
		C_QuestLog.AddQuestWatch(questID)
	end
end

local function Unwatch(questID)
	C_QuestLog.RemoveQuestWatch(questID)
end

-- Each call on its own, so one quest that can't be (un)tracked any more (handed in mid-run) doesn't stop the rest.
local function UnwatchAll()
	for _, questID in ipairs(WatchList()) do
		pcall(Unwatch, questID)
	end
end

-- This client puts a newly tracked quest first, so re-adding from last to first gives back the same order.
local function WatchInOrder(list)
	for index = #list, 1, -1 do
		pcall(Watch, list[index])
	end
end

-- Zone headings ("Z:Westfall") and quest IDs as drawn, top to bottom.
local function Drawn()
	local rows = {}
	T.module:EnumerateActiveBlocks(function(block)
		if block:IsVisible() and block:GetTop() and not block.cached then
			rows[#rows + 1] = { top = block:GetTop(), id = block.qcZone and ("Z:" .. block.qcZone) or tostring(block.id) }
		end
	end)
	table.sort(rows, function(a, b)
		return a.top > b.top
	end)
	local out = {}
	for _, row in ipairs(rows) do
		out[#out + 1] = row.id
	end
	return table.concat(out, ",")
end

local function ZonesDrawn()
	local out = {}
	for zone in Drawn():gmatch("Z:([^,]+)") do
		out[#out + 1] = zone
	end
	return table.concat(out, ",")
end

local function Copy(t)
	local copy = {}
	for key, value in pairs(t or {}) do
		copy[key] = value
	end
	return copy
end

local function Same(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------------------------------------------------------
-- What a run changes, saved before it starts and put back after it (or at the next login if the run was cut short)
------------------------------------------------------------------------------------------------------------------------
local function Character()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Snapshot()
	local db = Q.db
	local snapshot = {
		character = Character(),
		watches = WatchList(),
		watchTypes = {},
		rank = Copy(I.Ranks()),
		collapsed = Copy(db.collapsed),
		collapsedBeforeFocus = db.collapsedBeforeFocus and Copy(db.collapsedBeforeFocus) or nil,
		focusZone = db.focusZone,
		completeOrder = db.completeOrder,
	}
	for _, questID in ipairs(snapshot.watches) do
		snapshot.watchTypes[questID] = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID)
	end
	return snapshot
end

local function RestoreSettings(snapshot)
	local db = Q.db
	db.completeOrder = snapshot.completeOrder
	db.focusZone = snapshot.focusZone
	db.collapsedBeforeFocus = snapshot.collapsedBeforeFocus and Copy(snapshot.collapsedBeforeFocus) or nil
	wipe(db.collapsed)
	for name, folded in pairs(snapshot.collapsed) do
		db.collapsed[name] = folded
	end
end

-- Puts the saved places back. Run after the watch list is whole again: every quest then has its place, so the next
-- redraw changes nothing. Times of quests that left before the run are dropped, so they can't be forgotten by it.
local function RestoreRanks(snapshot)
	local rank = I.Ranks()
	wipe(rank)
	for questID, place in pairs(snapshot.rank) do
		rank[questID] = place
	end
	wipe(I.goneAt)
end

------------------------------------------------------------------------------------------------------------------------
-- Steps: each runs after a delay. An error or combat skips straight to the restore steps.
------------------------------------------------------------------------------------------------------------------------
local steps, restoreAt, stepIndex = {}, nil, 0
local running = false
local saved -- the snapshot this run puts back
local realReadWhere -- T.ReadWhere while L3 counts its calls

local function Next(delay)
	C_Timer.After(delay or 0.6, function()
		if InCombatLockdown() and stepIndex < restoreAt then
			Say("combat started: stopping the checks and putting everything back")
			stepIndex = restoreAt - 1
		end
		stepIndex = stepIndex + 1
		local step = steps[stepIndex]
		if not step then
			return
		end
		local ok, err = pcall(step)
		if not ok then
			Check("step " .. stepIndex .. " ran without error", false, err)
			if stepIndex < restoreAt then
				stepIndex = restoreAt - 1
			end
			Next(0.2)
		end
	end)
end

local function Add(fn)
	steps[#steps + 1] = fn
end

------------------------------------------------------------------------------------------------------------------------
-- The run
------------------------------------------------------------------------------------------------------------------------
local function Build()
	local db = Q.db
	local here = T.CurrentZone()
	local zonesOn = db.grouping and true or false
	local hereFirst = zonesOn and db.currentFirst and here
	local before, target, drop, readCalls, l6At
	wipe(steps)

	-- L1 your zone is drawn first
	Add(function()
		db.focusZone = false
		wipe(db.collapsed)
		T.MarkDirty(true)
		Next()
	end)
	Add(function()
		local zones = ZonesDrawn()
		Say("zones drawn: " .. zones .. " | you are in: " .. tostring(here))
		if hereFirst then
			Check("L1 current zone drawn first", (zones .. ","):sub(1, #here + 1) == here .. ",", zones)
		else
			Say("L1 skipped: needs zones on, your zone first on, and a tracked quest in this zone")
		end
		before = Drawn()
		for _, group in ipairs((I.Group(I.Collect()))) do
			if #group.quests >= 2 then
				target = group.quests[2].id
				break
			end
		end
		if not target then
			Say("L2 skipped: track at least two quests in one zone")
			Next(0.1)
			return
		end
		-- L2 the game's untrack and re-track (as a quest completes): nothing moves
		Unwatch(target)
		Next(0.3)
	end)
	Add(function()
		if not target then
			return Next(0.1)
		end
		Watch(target)
		Next(1.2)
	end)
	Add(function()
		if not target then
			return Next(0.1)
		end
		local list = WatchList()
		Check("L2a game puts the re-tracked quest first", list[1] == target, table.concat(list, ","))
		Check("L2b drawn order unchanged after quick drop and re-add", Drawn() == before, Drawn() .. " vs " .. before)
		-- L2c tracked again by hand after the grace: it goes where the game puts it (first)
		Unwatch(target)
		Next(4)
	end)
	Add(function()
		if not target then
			return Next(0.1)
		end
		Watch(target)
		Next(1.2)
	end)
	Add(function()
		if not target then
			return Next(0.1)
		end
		local first
		for item in Drawn():gmatch("[^,]+") do
			if not item:find("^Z:") then
				first = first or item
			end
		end
		Check("L2c late re-track moves to the top", first == tostring(target), Drawn())
		-- put the watch list and the places back for the rest of the run
		UnwatchAll()
		WatchInOrder(saved.watches)
		RestoreRanks(saved)
		T.MarkDirty(true)
		Next(1.2)
	end)
	-- L3 a redraw for any other reason (a quest completing) never re-reads where you are, so zones can't move
	Add(function()
		before = Drawn()
		readCalls = 0
		realReadWhere = T.ReadWhere
		T.ReadWhere = function(...)
			readCalls = readCalls + 1
			return realReadWhere(...)
		end
		T.MarkDirty(true)
		Next(0.3)
	end)
	Add(function()
		T.ReadWhere, realReadWhere = realReadWhere, nil
		Check("L3a a redraw doesn't re-read where you are", readCalls == 0, readCalls)
		Check("L3b a redraw without a zone event keeps zone order", Drawn() == before, Drawn())
		Next(0.1)
	end)
	-- L4 focus mode: a zone that joins the list later is folded too
	Add(function()
		if zonesOn then
			for _, group in ipairs((I.Group(I.Collect()))) do
				if group.name and group.name ~= here and group.name ~= I.OTHER_ZONE then
					drop = { name = group.name, ids = {} }
					for _, quest in ipairs(group.quests) do
						drop.ids[#drop.ids + 1] = quest.id
					end
				end
			end
		end
		if not drop then
			Say("L4-L8 skipped: needs zones on and tracked quests in a second zone")
			stepIndex = l6At - 1
		else
			T.FocusCurrentZone()
		end
		Next(0.4)
	end)
	Add(function()
		Check("L4a focus on: other zone folded", db.collapsed[drop.name] == true)
		for _, questID in ipairs(drop.ids) do
			Unwatch(questID)
		end
		Next(0.6)
	end)
	Add(function()
		Check("L4b zone gone from the list", not ZonesDrawn():find(drop.name, 1, true), ZonesDrawn())
		-- before the fix, a fold was forgotten while its zone was not listed
		db.collapsed[drop.name] = nil
		for _, questID in ipairs(drop.ids) do
			Watch(questID)
		end
		Next(1.0)
	end)
	Add(function()
		Check("L4c zone that joins later is folded", db.collapsed[drop.name] == true)
		local shown = false
		for _, questID in ipairs(drop.ids) do
			local block = T.module:GetExistingBlock(questID)
			if block and block:IsVisible() and not block.cached then
				shown = true
			end
		end
		Check("L4d its quests are hidden", not shown)
		if here then
			Check("L4e your zone stays open", not db.collapsed[here])
		end
		-- L5 opening a zone by hand in focus mode ends focus mode, and it stays open
		T.ToggleZone(drop.name)
		Next(0.6)
	end)
	Add(function()
		Check("L5a opening a zone by hand ends focus mode", db.focusZone == false)
		T.MarkDirty()
		Next(0.4)
	end)
	Add(function()
		Check("L5b hand-opened zone stays open after a redraw", not db.collapsed[drop.name])
		-- L8 turning focus on fades first; a redraw mid-fade must not fold early
		local on = T.ToggleFocus()
		local midFade = T.IsFolding()
		T.Update()
		if midFade then
			Check("L8a redraw mid-fade leaves the zone to the fade", not db.collapsed[drop.name])
		else
			Say("L8a skipped: no fade (animations are off)")
		end
		Check("L8b focus is on", on == true and db.focusZone == true)
		Next(1.0)
	end)
	Add(function()
		Check("L8c after the fade the zone is folded", db.collapsed[drop.name] == true)
		if here then
			Check("L8d your zone stays open", not db.collapsed[here])
		end
		Check("L8e focus off again", T.ToggleFocus() == false and not db.focusZone)
		Next(0.6)
	end)
	-- L6 finished quests at the bottom: zone order holds
	l6At = #steps + 1
	Add(function()
		db.completeOrder = "bottom"
		T.Rebuild()
		Next(0.6)
	end)
	Add(function()
		local zones = ZonesDrawn()
		if hereFirst then
			Check("L6 bottom mode: zone order holds", (zones .. ","):sub(1, #here + 1) == here .. ",", zones)
		else
			Say("L6 skipped: needs zones on, your zone first on, and a tracked quest in this zone")
		end
		Next(0.1)
	end)

	-- Restore: always runs, also after an error or combat.
	restoreAt = #steps + 1
	Add(function()
		if realReadWhere then
			T.ReadWhere, realReadWhere = realReadWhere, nil
		end
		-- A fold still fading would fold zones again after they are put back: finish it now.
		if T.IsFolding() then
			Q.Motion.Finish("qc-fold")
		end
		RestoreSettings(saved)
		UnwatchAll()
		Next(0.5)
	end)
	Add(function()
		WatchInOrder(saved.watches)
		Next(1.0)
	end)
	Add(function()
		local now = table.concat(WatchList(), ",")
		Check("L7a your tracked quests and their order are restored", now == table.concat(saved.watches, ","), now)
		RestoreRanks(saved)
		T.Rebuild()
		Next(1.0)
	end)
	Add(function()
		Check("L7b your saved quest order is restored", Same(I.Ranks(), saved.rank))
		Check("L7c folds and focus are restored", db.focusZone == saved.focusZone and Same(db.collapsed, saved.collapsed))
		CleanQuestTrackerTestsDB.pending = nil
		running = false
		local color = results.fail == 0 and "|cff80ff80" or "|cffff4040"
		Say(("%sdone: %d passed, %d failed|r"):format(color, results.pass, results.fail))
	end)
end

local function Ready()
	if not (I and T.module and Q.ready and Q.db) then
		Say("Clean Quest Tracker isn't running on this character (paused, or an older version without test hooks)")
		return false
	end
	return true
end

local function Run()
	if running then
		Say("already running")
		return
	end
	if not Ready() then
		return
	end
	if not Q.Active() then
		Say("Clean Quest Tracker is turned off or paused on this character")
		return
	end
	if T.SearchActive() then
		Say("clear the quest search first")
		return
	end
	CleanQuestTrackerTestsDB = type(CleanQuestTrackerTestsDB) == "table" and CleanQuestTrackerTestsDB or {}
	if InCombatLockdown() then
		Say("leave combat first")
		return
	end
	if CleanQuestTrackerTestsDB.pending then
		Say("a cut-short run still has to be put back on " .. tostring(CleanQuestTrackerTestsDB.pending.character))
		return
	end
	saved = Snapshot()
	if #saved.watches == 0 then
		Say("track some quests first")
		return
	end
	watchTypes = saved.watchTypes
	CleanQuestTrackerTestsDB.pending = saved
	results.pass, results.fail = 0, 0
	running = true
	stepIndex = 0
	Say("running (about 25 seconds; your tracked quests and settings are put back afterwards)...")
	Build()
	Next(0.2)
end

------------------------------------------------------------------------------------------------------------------------
-- A run cut short by /reload or logout is put back at the next login on the same character, once the quest log has
-- had time to load. The saved copy is only dropped once the watch list really matches it.
------------------------------------------------------------------------------------------------------------------------
local function Recover(tries)
	local pending = CleanQuestTrackerTestsDB.pending
	if not pending or pending.character ~= Character() or running or not Ready() then
		return
	end
	watchTypes = pending.watchTypes or {}
	RestoreSettings(pending)
	UnwatchAll()
	WatchInOrder(pending.watches)
	RestoreRanks(pending)
	T.MarkDirty(true)
	if table.concat(WatchList(), ",") == table.concat(pending.watches, ",") then
		CleanQuestTrackerTestsDB.pending = nil
		Say("put back your tracked quests, folds and settings from a run that was cut short")
	elseif tries < 5 then
		C_Timer.After(3, function()
			Recover(tries + 1)
		end)
	else
		Say("|cffff4040couldn't put back all of your tracked quests from a cut-short run|r; they were: "
			.. table.concat(pending.watches, ", ") .. ". The copy is kept and tried again at the next login.")
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	CleanQuestTrackerTestsDB = type(CleanQuestTrackerTestsDB) == "table" and CleanQuestTrackerTestsDB or {}
	if CleanQuestTrackerTestsDB.pending then
		C_Timer.After(2, function()
			Recover(1)
		end)
	end
end)

SLASH_CQTTEST1 = "/cqttest"
SlashCmdList.CQTTEST = Run
