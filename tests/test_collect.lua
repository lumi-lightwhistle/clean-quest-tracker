-- The whole path from the game's watch list and quest log to zone groups (Tracker.lua, Collect then Group), through the
-- stand-in API: a quest completing (the game drops it and re-adds it at the front) keeps its place and its zone's place.

local check, ids, names = TEST.check, TEST.ids, TEST.names
local Q, T, I = TEST.Q, TEST.T, TEST.I
local Collect, Group, OTHER_ZONE = I.Collect, I.Group, I.OTHER_ZONE
local db = Q.db

local saved = { grouping = db.grouping, currentFirst = db.currentFirst, completeOrder = db.completeOrder }
wipe(I.Ranks())
wipe(I.goneAt)
wipe(db.zoneOf)
db.grouping, db.currentFirst, db.completeOrder = true, true, "none"
WOW.log = {
	{ title = "Westfall", isHeader = true },
	{ questID = 1 },
	{ questID = 2 },
	{ questID = 3 },
	{ title = "Stormwind City", isHeader = true },
	{ questID = 4 },
	{ title = "Redridge Mountains", isHeader = true },
	{ questID = 5 },
}
WOW.watches = { 1, 2, 3, 4, 5 }
WOW.complete = {}
WOW.zone = { real = "Westfall", text = "Westfall", map = nil }
T.ReadWhere()

local function Drawn()
	local groups = Group(Collect())
	local out = {}
	for _, group in ipairs(groups) do
		out[#out + 1] = group.name .. ":" .. ids(group.quests)
	end
	return table.concat(out, " | ")
end

local START = "Westfall:1,2,3 | Redridge Mountains:5 | Stormwind City:4"
local drawn = Drawn()
check("F0 first look: your zone first, tracked order", drawn == START, drawn)

-- F1 a quest completes and the game drops and re-adds it in one go (it lands at the front of the watch list)
C_QuestLog.RemoveQuestWatch(2)
C_QuestLog.AddQuestWatch(2)
WOW.complete[2] = true
drawn = Drawn()
check("F1 completion in one redraw moves nothing", drawn == START, drawn)

-- F2 the same, with a redraw between the drop and the re-add
C_QuestLog.RemoveQuestWatch(3)
Drawn()
WOW.Advance(1)
C_QuestLog.AddQuestWatch(3)
WOW.complete[3] = true
drawn = Drawn()
check("F2 completion across two redraws moves nothing", drawn == START, drawn)

-- F3 completing a quest while the zone API already says Redridge, with no zone event yet: Westfall stays on top
WOW.zone = { real = "Redridge Mountains", text = "Redridge Mountains" }
C_QuestLog.RemoveQuestWatch(4)
C_QuestLog.AddQuestWatch(4)
WOW.complete[4] = true
drawn = Drawn()
check("F3 a redraw without a zone event keeps your zone on top", drawn == START, drawn)
WOW.zone = { real = "Westfall", text = "Westfall" }

-- F4 a newly tracked quest goes on top of its zone (this client puts it first in the watch list)
table.insert(WOW.log, 2, { questID = 6 })
C_QuestLog.AddQuestWatch(6)
drawn = Drawn()
check("F4 newly tracked quest goes on top", drawn == "Westfall:6,1,2,3 | Redridge Mountains:5 | Stormwind City:4", drawn)

-- F5 a quest the log no longer lists under a header keeps the zone it was last seen in
table.remove(WOW.log, 2)
table.insert(WOW.log, 1, { questID = 6 })
drawn = Drawn()
check("F5 last known zone is kept", drawn:find("^Westfall:6,") ~= nil, drawn)

-- F6 a quest never seen under a header goes to Other Quests, listed last
table.insert(WOW.log, 1, { questID = 7 })
C_QuestLog.AddQuestWatch(7)
local groups = Group(Collect())
check("F6 no zone: Other Quests, last", groups[#groups].name == OTHER_ZONE and ids(groups[#groups].quests) == "7",
	names(groups))

-- F7 quests that are not shown: world tasks, bounties, a quest listed twice in the watch list
table.insert(WOW.log, 1, { questID = 8, isTask = true })
table.insert(WOW.log, 1, { questID = 9, isBounty = true })
C_QuestLog.AddQuestWatch(8)
C_QuestLog.AddQuestWatch(9)
WOW.watches[#WOW.watches + 1] = 1
local list = Collect()
local count = {}
for _, quest in ipairs(list) do
	count[quest.id] = (count[quest.id] or 0) + 1
end
check("F7 tasks and bounties hidden, duplicates once", not count[8] and not count[9] and count[1] == 1)

-- F8 a quest that left the log is forgotten from the zone memory
WOW.watches = { 1, 2, 3, 4, 5 }
for index, entry in ipairs(WOW.log) do
	if entry.questID == 6 then
		table.remove(WOW.log, index)
		break
	end
end
Collect()
check("F8 zone memory dropped when the quest leaves the log", db.zoneOf[6] == nil and db.zoneOf[1] == "Westfall")

wipe(I.Ranks())
wipe(I.goneAt)
wipe(db.zoneOf)
WOW.watches, WOW.log, WOW.complete, WOW.zone = {}, {}, {}, {}
db.grouping, db.currentFirst, db.completeOrder = saved.grouping, saved.currentFirst, saved.completeOrder
