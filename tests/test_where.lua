-- Where you are (TrackerZones.lua, T.ReadWhere, T.CurrentZone, T.OnZoneChanged): caves and sub-maps count as their
-- zone, dungeons with their own heading win, loading screens and map errors keep the last place, and the current zone
-- only changes on a zone event. C1-C22 from the zone-order fix.

local check = TEST.check
local Q, T = TEST.Q, TEST.T
local db = Q.db

WOW.maps = {
	[1] = { mapType = 1, name = "Azeroth", parentMapID = 0 },
	[2] = { mapType = 2, name = "Eastern Kingdoms", parentMapID = 1 },
	[52] = { mapType = 3, name = "Westfall", parentMapID = 2 },
	[900] = { mapType = 5, name = "Jangolode Mine", parentMapID = 52 },
	[901] = { mapType = 4, name = "The Deadmines", parentMapID = 52 },
	[902] = { mapType = 4, name = "Deep Cave", parentMapID = 900 },
	[903] = { mapType = 6, name = "Loop", parentMapID = 903 },
}
local ZN = { "Westfall", "Redridge Mountains", "Stormwind City" }

local function At(real, text, map)
	WOW.zone.real, WOW.zone.text, WOW.zone.map = real, text, map
end

At("Westfall", "Westfall", 52)
T.ReadWhere()
check("C1 plain zone", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
check("C2 same place again reports no change", T.ReadWhere() == false)
-- a cave that reports its own zone name
At("Jangolode Mine", "Jangolode Mine", 900)
check("C3 entering a cave reports a change", T.ReadWhere() == true)
check("C4 cave resolves to Westfall via the map", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
-- a nested sub-map
At("Deep Cave", "Deep Cave", 902)
T.ReadWhere()
check("C5 nested sub-map climbs to the zone", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
-- a dungeon with its own heading
At("The Deadmines", "The Deadmines", 901)
T.ReadWhere()
check("C6 dungeon with its own heading wins", T.CurrentZone({ "The Deadmines", "Westfall" }) == "The Deadmines")
check("C7 dungeon without heading falls back to its zone", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
-- a loading screen: empty text keeps the last place
At("Westfall", "Westfall", 52)
T.ReadWhere()
At("", "", nil)
check("C8 loading screen reports no change", T.ReadWhere() == false)
check("C9 loading screen keeps last zone", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
WOW.zone.real = nil
T.ReadWhere()
check("C10 nil zone keeps last zone", T.CurrentZone(ZN) == "Westfall")
-- stickiness: the API changes but no zone event came, so the current zone holds
At("Somewhere Else", "Somewhere Else", nil)
check("C11 no event, no change", T.CurrentZone(ZN) == "Westfall")
-- a zone with no heading
T.ReadWhere()
check("C12 zone without quests: nothing first", T.CurrentZone(ZN) == nil)
-- map API errors are survived
At("Westfall", "Westfall", 52)
WOW.zone.mapError = true
local okRead = pcall(T.ReadWhere)
check("C13 map error survived", okRead and T.CurrentZone(ZN) == "Westfall")
WOW.zone.mapError = nil
-- a map that is its own parent
At("Loop", "Loop", 903)
okRead = pcall(T.ReadWhere)
check("C14 map loop guard", okRead and T.CurrentZone(ZN) == nil)
-- a continent map only: the zone text still finds the heading (the real zone is a sub-area name here)
At("Sentinel Hill", "Westfall", 2)
T.ReadWhere()
check("C15 continent map uses the zone text", T.CurrentZone(ZN) == "Westfall", T.CurrentZone(ZN))
-- C_Map missing a function
local best = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = nil
At("Jangolode Mine", "Jangolode Mine", 900) -- with the map API this would resolve to Westfall
okRead = pcall(T.ReadWhere)
check("C16 no map API: no error, no match", okRead and T.CurrentZone(ZN) == nil)
C_Map.GetBestMapForUnit = best
-- zone text that differs from the real zone (an instance) is also tried
At("Instance Name", "Westfall", nil)
T.ReadWhere()
check("C17 zone text is a fallback", T.CurrentZone(ZN) == "Westfall")
-- with no names given, the zones of the last layout are used
local savedNames = T.zoneNames
T.zoneNames = { "Westfall" }
check("C18 defaults to the listed zones", T.CurrentZone() == "Westfall")
T.zoneNames = savedNames
-- a secret zone name is never read
WOW.secret["Secret Place"] = true
At("Secret Place", "Secret Place", nil)
check("C18b secret zone name reports no change", T.ReadWhere() == false and T.CurrentZone(ZN) == "Westfall")
WOW.secret["Secret Place"] = nil

------------------------------------------------------------------------------------------------------------------------
-- Zone events: a sub-area only redraws when a name changed; focus mode refolds around your zone
------------------------------------------------------------------------------------------------------------------------
At("Westfall", "Westfall", 52)
T.ReadWhere()
local savedFocus, savedGrouping = db.focusZone, db.grouping
db.focusZone, db.grouping = false, true
local redraws = 0
local focusCalls = 0
local realMark, realFocus = T.MarkDirty, T.FocusCurrentZone
T.MarkDirty = function()
	redraws = redraws + 1
end
T.FocusCurrentZone = function()
	focusCalls = focusCalls + 1
	return realFocus()
end
local ok, err = pcall(function()
	T.OnZoneChanged(true)
	check("C19 sub-area with same names: no redraw", redraws == 0, redraws)
	WOW.zone.real, WOW.zone.map = "Jangolode Mine", 900
	T.OnZoneChanged(true)
	check("C20 sub-area with new names: redraw", redraws == 1, redraws)
	T.OnZoneChanged()
	check("C21 new area always redraws", redraws == 2, redraws)
	T.zoneNames = ZN
	db.focusZone = true
	T.OnZoneChanged()
	check("C22 focus mode in a cave: Westfall is your zone, the zones refold",
		focusCalls == 1 and T.CurrentZone(ZN) == "Westfall" and redraws == 3, focusCalls .. " / " .. redraws)
	check("C22b outside focus mode the zones are not refolded", focusCalls == 1)
	db.focusZone = false
	-- the zone event the game sends is wired to the same code
	redraws = 0
	At("Redridge Mountains", "Redridge Mountains", nil)
	Q.ready = true
	WOW.Fire("ZONE_CHANGED_NEW_AREA")
	check("C23 ZONE_CHANGED_NEW_AREA re-reads where you are", T.CurrentZone(ZN) == "Redridge Mountains" and redraws == 1,
		tostring(T.CurrentZone(ZN)) .. " / " .. redraws)
	-- walking into a building: the minor events, which redraw only when a name changed
	WOW.Fire("ZONE_CHANGED")
	check("C24 ZONE_CHANGED with the same names: no redraw", redraws == 1, redraws)
	WOW.zone.real = "Stormwind City"
	WOW.Fire("ZONE_CHANGED_INDOORS")
	check("C25 ZONE_CHANGED_INDOORS with a new name: redraw", redraws == 2 and T.CurrentZone(ZN) == "Stormwind City",
		redraws)
	-- after a loading screen the map is read again a second later
	WOW.timers = {}
	At("", "", nil)
	WOW.Fire("PLAYER_ENTERING_WORLD")
	At("Westfall", "Westfall", 52)
	WOW.Advance(1)
	WOW.RunTimers()
	check("C26 a second after a loading screen the zone is read again", T.CurrentZone(ZN) == "Westfall",
		T.CurrentZone(ZN))
end)
Q.ready = nil
if not ok then
	check("zone event tests ran without error", false, err)
end
T.zoneNames = savedNames
T.MarkDirty, T.FocusCurrentZone = realMark, realFocus
WOW.zone = {}
db.focusZone, db.grouping = savedFocus, savedGrouping
WOW.timers = {}
