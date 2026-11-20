-- Tracked order (Tracker.lua, Rank): a quest the game drops and re-adds keeps its place, new quests go next to their
-- watch-list neighbour, and the places are saved per character. R0-R16 from the zone-order fix.

local check, W, sortedIds = TEST.check, TEST.W, TEST.sortedIds
local Q, I = TEST.Q, TEST.I
local Rank, Ranks, goneAt, sessionRanks = I.Rank, I.Ranks, I.goneAt, I.sessionRanks

local rank = Ranks()
check("R0 places saved per character", rank ~= sessionRanks and Q.db.questOrder["Tester-Testrealm"] == rank)

-- A name the client won't let us read: places live for the session only, nothing is saved under a bad key.
WOW.secret["Tester"] = true
local hidden = Ranks()
WOW.secret["Tester"] = nil
WOW.secret["Testrealm"] = true
local hiddenRealm = Ranks()
WOW.secret["Testrealm"] = nil
check("R0b unreadable name or realm keeps places for the session only",
	hidden == sessionRanks and hiddenRealm == sessionRanks)

local function Clean()
	wipe(rank)
	wipe(goneAt)
end

Clean()
-- R1 seed keeps watch order
local l = W(101, 102, 103)
Rank(l)
check("R1 seed order", sortedIds(l) == "101,102,103", sortedIds(l))
-- R2 game drops 102 and re-adds it at the end within grace: keeps its place
Rank(W(101, 103))
l = W(101, 103, 102)
Rank(l)
check("R2 quick re-add keeps place", sortedIds(l) == "101,102,103", sortedIds(l))
-- R3 back after the grace: goes where the watch list puts it
Rank(W(101, 103))
goneAt[102] = GetTime() - 10
l = W(101, 103, 102)
Rank(l)
check("R3 late re-add goes to the end", sortedIds(l) == "101,103,102", sortedIds(l))
-- R4 new quest between two existing ones
l = W(101, 104, 103, 102)
Rank(l)
check("R4 new quest placed after its watch-list neighbour", sortedIds(l) == "101,104,103,102", sortedIds(l))
-- R5 new quest at the very start
l = W(105, 101, 104, 103, 102)
Rank(l)
check("R5 new quest at start", sortedIds(l) == "105,101,104,103,102", sortedIds(l))
-- R6 new quest at the end
l = W(105, 101, 104, 103, 102, 106)
Rank(l)
check("R6 new quest at end", sortedIds(l) == "105,101,104,103,102,106", sortedIds(l))
-- R7 game reorders the whole watch list: our order holds
l = W(106, 102, 103, 104, 101, 105)
Rank(l)
check("R7 game reshuffle ignored", sortedIds(l) == "105,101,104,103,102,106", sortedIds(l))
-- R8 two new adjacent quests between existing ones keep their relative order
l = W(105, 201, 202, 101, 104, 103, 102, 106)
Rank(l)
check("R8 two new adjacent", sortedIds(l) == "105,201,202,101,104,103,102,106", sortedIds(l))
-- R9 orders are whole numbers 1..n after every pass (no halving drift)
local okInts = true
for pass = 1, 80 do
	local base = W(105, 201, 202, 101, 104, 103, 102, 106)
	local fresh = 9000 + pass -- a fresh quest right after 105 every time
	table.insert(base, 2, { id = fresh, zone = "Z", complete = false, order = 2 })
	Rank(base)
	for _, quest in ipairs(base) do
		if quest.order ~= math.floor(quest.order) then
			okInts = false
		end
	end
	goneAt[fresh] = GetTime() - 10 -- forget it on the next pass
end
check("R9 orders stay whole numbers", okInts)
-- R10 forgotten quests are dropped from memory after the grace
Clean()
Rank(W(1, 2, 3))
Rank(W(1, 3))
goneAt[2] = GetTime() - 10
Rank(W(1, 3))
check("R10 long-gone quest forgotten", rank[2] == nil and goneAt[2] == nil)
-- R10b the same, with the clock moving rather than a back-dated entry
Clean()
Rank(W(1, 2, 3))
Rank(W(1, 3))
WOW.Advance(2)
Rank(W(1, 3))
local stillKept = rank[2] ~= nil
WOW.Advance(2)
Rank(W(1, 3))
check("R10b kept inside the grace, forgotten after it", stillKept and rank[2] == nil)
-- R11 order unaffected by completion flag
Clean()
Rank(W(1, 2, 3))
l = W(1, 2, 3)
l[2].complete = true
Rank(l)
check("R11 completing changes nothing", sortedIds(l) == "1,2,3", sortedIds(l))
-- R14 a quest the game moved to the front kept its place; a new quest at the front goes on top
Clean()
Rank(W(1, 2, 3))
Rank(W(1, 2))
Rank(W(3, 1, 2))
l = W(9, 3, 1, 2)
Rank(l)
check("R14 new first quest goes on top", sortedIds(l) == "9,1,2,3", sortedIds(l))
-- R15 a new quest after a moved one goes right after it
l = W(9, 3, 8, 1, 2)
Rank(l)
check("R15 new quest right after its neighbour", sortedIds(l) == "9,1,2,3,8", sortedIds(l))
-- R16 an empty list (log not loaded at login) forgets nothing
goneAt[1] = nil
Rank({})
WOW.Advance(10)
Rank({})
check("R16 empty list forgets nothing", rank[1] ~= nil and goneAt[1] == nil)
-- R12 empty list is fine
check("R12 empty list", (pcall(Rank, {})))
-- R13 the remove-then-re-add arrives in the same redraw as an objective tick (single pass)
Clean()
Rank(W(1, 2, 3, 4))
l = W(1, 3, 4, 2)
Rank(l)
check("R13 same-pass move to end keeps place", sortedIds(l) == "1,2,3,4", sortedIds(l))
Clean()
