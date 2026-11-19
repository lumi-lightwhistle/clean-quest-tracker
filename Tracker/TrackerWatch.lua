-- Clean Quest Tracker: progress safety nets, so the list is always up to date.

local _, Q = ...
local T = Q.Tracker

-- A compact fingerprint of what the list shows: each watched quest, whether it's complete, and every objective's
-- count. The watchdog compares it with the last redraw to catch progress that arrived without a usable event.
local signatureParts = {}
function T.Signature()
	wipe(signatureParts)
	local ok = pcall(function()
		for index = 1, C_QuestLog.GetNumQuestWatches() do
			local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
			if questID then
				signatureParts[#signatureParts + 1] = questID
				signatureParts[#signatureParts + 1] = C_QuestLog.IsComplete(questID) and 1 or 0
				for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
					signatureParts[#signatureParts + 1] = objective.numFulfilled or 0
					signatureParts[#signatureParts + 1] = objective.finished and 1 or 0
				end
				-- Party members on the quest, so a share accepted far away still shows once their log syncs.
				signatureParts[#signatureParts + 1] = Q.Party.Count(questID)
			end
		end
		signatureParts[#signatureParts + 1] = C_QuestLog.GetNumQuestLogEntries()
	end)
	return ok and table.concat(signatureParts, ",") or nil
end
-- Progress safety nets, as ForeverCore and EllesmereUI's trackers use.
--
-- 1. A plain event frame of our own, so redraws never depend on the borrowed Blizzard module's event plumbing. It
--    includes QUEST_WATCH_UPDATE, the event for a watched quest's objective changing. That event fires before the
--    quest log holds the new count, so it and loot events also ask for a second redraw a moment later.
-- 2. A once-a-second watchdog that redraws whenever the quests' progress differs from what was last drawn. It does
--    nothing in combat or when nothing changed.
local WATCH_EVENTS = {
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"QUEST_ACCEPTED",
	"QUEST_REMOVED",
	"QUEST_TURNED_IN",
	"BAG_UPDATE_DELAYED",
	"CVAR_UPDATE", -- the quest map icon setting changes how much room titles get
}
local FOLLOW_UP = { QUEST_WATCH_UPDATE = true, BAG_UPDATE_DELAYED = true, UNIT_QUEST_LOG_CHANGED = true }

function T.StartWatching()
	local watcher = CreateFrame("Frame")
	for _, event in ipairs(WATCH_EVENTS) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	pcall(watcher.RegisterUnitEvent, watcher, "UNIT_QUEST_LOG_CHANGED", "player")
	watcher:SetScript("OnEvent", function(_, event, arg1)
		if event == "CVAR_UPDATE" then
			if Q.Readable(arg1) and arg1 == "questPOI" then
				if Q.Active() then
					T.MarkDirty(true)
				end
				-- The settings window shows this setting too (and the indent that depends on it), even while the
				-- add-on is switched off.
				if Q.Options and Q.Options.Refresh then
					Q.Options.Refresh()
				end
			end
			return
		end
		if not Q.Active() then
			return
		end
		if event ~= "BAG_UPDATE_DELAYED" then
			T.MarkDirty()
		end
		if FOLLOW_UP[event] then
			Q.Debounce("progress-follow-up", 0.4, T.MarkDirty)
		end
	end)

	if C_Timer.NewTicker then
		C_Timer.NewTicker(1, function()
			if T.IsDirty() or InCombatLockdown() or not Q.Active() then
				return
			end
			local signature = T.Signature()
			if signature and signature ~= T.drawnSignature then
				T.MarkDirty()
			end
		end)
	end
end
