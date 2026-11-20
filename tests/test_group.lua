-- Finished quests' place in a zone (Tracker.lua, SortFinished) and zone grouping and order (Group). S1-S3 and G1-G8
-- from the zone-order fix: a quest completing never moves zones.

local check, ids, names = TEST.check, TEST.ids, TEST.names
local Q, T, I = TEST.Q, TEST.T, TEST.I
local SortFinished, Group, OTHER_ZONE = I.SortFinished, I.Group, I.OTHER_ZONE
local db = Q.db
local saved = { grouping = db.grouping, currentFirst = db.currentFirst, completeOrder = db.completeOrder }

------------------------------------------------------------------------------------------------------------------------
-- S: finished quests at the top, the bottom or in place
------------------------------------------------------------------------------------------------------------------------
local function shuffled()
	local l = {
		{ id = 1, complete = false, order = 1 },
		{ id = 2, complete = true, order = 2 },
		{ id = 3, complete = false, order = 3 },
		{ id = 4, complete = true, order = 4 },
	}
	return { l[4], l[1], l[3], l[2] }
end

db.completeOrder = "none"
local l = shuffled()
SortFinished(l)
check("S1 none sorts by tracked order", ids(l) == "1,2,3,4", ids(l))
db.completeOrder = "bottom"
l = shuffled()
SortFinished(l)
check("S2 bottom", ids(l) == "1,3,2,4", ids(l))
db.completeOrder = "top"
l = shuffled()
SortFinished(l)
check("S3 top", ids(l) == "2,4,1,3", ids(l))

------------------------------------------------------------------------------------------------------------------------
-- G: zone groups, your zone first, then A-Z, Other Quests last
------------------------------------------------------------------------------------------------------------------------
local realCurrent = T.CurrentZone
local fakeHere
T.CurrentZone = function(list)
	for _, name in ipairs(list or {}) do
		if name == fakeHere then
			return name
		end
	end
end

local function list()
	return {
		{ id = 1, zone = "Westfall", complete = false, order = 1 },
		{ id = 2, zone = "Stormwind City", complete = false, order = 2 },
		{ id = 3, zone = "Westfall", complete = false, order = 3 },
		{ id = 4, zone = OTHER_ZONE, complete = false, order = 4 },
		{ id = 5, zone = "Redridge Mountains", complete = false, order = 5 },
		{ id = 6, zone = "Westfall", complete = false, order = 6 },
	}
end
local HERE_FIRST = "Westfall,Redridge Mountains,Stormwind City," .. OTHER_ZONE
local A_TO_Z = "Redridge Mountains,Stormwind City,Westfall," .. OTHER_ZONE

local ok, err = pcall(function()
	db.grouping, db.currentFirst, db.completeOrder = true, true, "none"
	fakeHere = "Westfall"
	local g, here = Group(list())
	check("G1 current zone first", names(g) == HERE_FIRST, names(g))
	check("G1b Group reports the current zone", here == "Westfall", here)
	fakeHere = nil
	g = Group(list())
	check("G2 no current zone: A-Z, Other last", names(g) == A_TO_Z, names(g))
	fakeHere = "Westfall"
	db.currentFirst = false
	g = Group(list())
	check("G3 current-first off: A-Z", names(g) == A_TO_Z, names(g))
	db.currentFirst = true
	-- G4 completing a quest in every position never moves zones
	local stable = true
	for index = 1, 6 do
		local quests = list()
		quests[index].complete = true
		for _, mode in ipairs({ "none", "top", "bottom" }) do
			db.completeOrder = mode
			if names(Group(quests)) ~= HERE_FIRST then
				stable = false
			end
		end
	end
	check("G4 completion never moves zones", stable)
	db.completeOrder = "none"
	-- G5 within a zone, tracked order holds when a quest completes
	local quests = list()
	quests[3].complete = true
	g = Group(quests)
	check("G5 quest stays in place on completion (none)", ids(g[1].quests) == "1,3,6", ids(g[1].quests))
	-- G6 bottom: the finished quest goes to the bottom of its own zone only
	db.completeOrder = "bottom"
	quests = list()
	quests[1].complete = true
	g = Group(quests)
	check("G6 bottom: finished quest to the bottom of its zone only",
		ids(g[1].quests) == "3,6,1" and names(g) == HERE_FIRST, ids(g[1].quests) .. " / " .. names(g))
	-- G7 being "in" Other Quests is harmless
	fakeHere = OTHER_ZONE
	db.completeOrder = "none"
	g = Group(list())
	check("G7 sorting with an odd here still valid", #g == 4, #g)
	-- G8 grouping off: one group in tracked order
	db.grouping = false
	quests = list()
	g = Group({ quests[6], quests[2], quests[1], quests[5], quests[4], quests[3] })
	check("G8 no zones: tracked order", #g == 1 and ids(g[1].quests) == "1,2,3,4,5,6", g[1] and ids(g[1].quests))
end)
if not ok then
	check("group tests ran without error", false, err)
end
T.CurrentZone = realCurrent
db.grouping, db.currentFirst, db.completeOrder = saved.grouping, saved.currentFirst, saved.completeOrder
