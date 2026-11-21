-- Clean Quest Tracker's offline regression tests. Loads the add-on's Lua files in .toc order on top of a stand-in WoW
-- API (tests/wow.lua), then runs every tests/test_*.lua file listed in SUITES below.
--
-- Every tests/test_*.lua file must be listed in SUITES (tools/prereview.py and CI check it), and every suite must run
-- at least one check. Before each suite the stand-in game is emptied (WOW.Reset) and the add-on's rank memory and zone
-- memory wiped, so suites don't depend on each other's leftovers; settings a suite changes it puts back itself. Not
-- reset: where you are (TrackerZones keeps the last place read) and T.zoneNames; a suite that needs them sets them.
--
-- Run from the repository root with Lua 5.1:   lua5.1 tests/run.lua
-- or, without Lua installed:                   python tools/runtests.py   (uses Lua if found, else the lupa package)
-- Exit code 0 when every check passes, 1 otherwise.

local SUITES = { "test_rank.lua", "test_group.lua", "test_where.lua", "test_collect.lua", "test_title.lua" }

local ROOT = rawget(_G, "CQT_ROOT") or "."
local write = io.write

------------------------------------------------------------------------------------------------------------------------
-- Checks: the same shape as the in-game self-test, so a check can move between the two unchanged
------------------------------------------------------------------------------------------------------------------------
local results = { pass = 0, fail = 0, suite = "?" }

local TEST = {}
_G.TEST = TEST

function TEST.check(name, ok, detail)
	if ok then
		results.pass = results.pass + 1
	else
		results.fail = results.fail + 1
		write(("FAIL [%s] %s%s\n"):format(results.suite, name, detail ~= nil and (" :: " .. tostring(detail)) or ""))
	end
end

-- "1,2,3" from a list of quest records.
function TEST.ids(list)
	local out = {}
	for _, quest in ipairs(list) do
		out[#out + 1] = tostring(quest.id)
	end
	return table.concat(out, ",")
end

-- Quest records in watch-list order, all in zone "Z", the way Rank sees them.
function TEST.W(...)
	local list = {}
	for index, id in ipairs({ ... }) do
		list[index] = { id = id, zone = "Z", complete = false, order = index }
	end
	return list
end

-- The ids sorted by the order Rank gave them.
function TEST.sortedIds(list)
	local copy = {}
	for index, quest in ipairs(list) do
		copy[index] = quest
	end
	table.sort(copy, function(a, b)
		return a.order < b.order
	end)
	return TEST.ids(copy)
end

-- "Westfall,Stormwind City" from a list of zone groups.
function TEST.names(groups)
	local out = {}
	for _, group in ipairs(groups) do
		out[#out + 1] = tostring(group.name)
	end
	return table.concat(out, ",")
end

------------------------------------------------------------------------------------------------------------------------
-- Load the add-on
------------------------------------------------------------------------------------------------------------------------
local function Load(path, ...)
	local chunk, err = loadfile(ROOT .. "/" .. path)
	if not chunk then
		error("could not compile " .. path .. ": " .. tostring(err), 0)
	end
	local ok, run = pcall(chunk, ...)
	if not ok then
		error("loading " .. path .. " failed: " .. tostring(run), 0)
	end
end

local function TocFiles()
	local files = {}
	for line in io.lines(ROOT .. "/CleanQuestTracker.toc") do
		line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
		if line:match("%.lua$") and not line:match("^#") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

local function Main()
	Load("tests/wow.lua")
	local Q = {}
	for _, file in ipairs(TocFiles()) do
		Load(file, "CleanQuestTracker", Q)
	end
	-- Saved settings load on ADDON_LOADED, as in the game. PLAYER_LOGIN (which builds the frames from Blizzard's
	-- tracker templates) is not sent: the tests use the logic only.
	WOW.Fire("ADDON_LOADED", "CleanQuestTracker")
	assert(Q.db and Q.Tracker and Q.Tracker._internal, "the add-on did not load its settings or its test hooks")
	TEST.Q, TEST.T, TEST.I = Q, Q.Tracker, Q.Tracker._internal
	for _, suite in ipairs(SUITES) do
		results.suite = suite
		WOW.Reset()
		wipe(TEST.I.Ranks())
		wipe(TEST.I.goneAt)
		wipe(Q.db.zoneOf)
		local before = results.pass + results.fail
		local ok, err = pcall(Load, "tests/" .. suite)
		if not ok then
			TEST.check("suite ran without error", false, err)
		elseif results.pass + results.fail == before then
			TEST.check("suite ran at least one check", false)
		end
	end
end

local ok, err = pcall(Main)
if not ok then
	write("ERROR " .. tostring(err) .. "\n")
	results.fail = results.fail + 1
end
if results.fail > 0 and WOW and #WOW.printed > 0 then
	write("The add-on printed (last suite):\n  " .. table.concat(WOW.printed, "\n  ") .. "\n")
end
write(("%d passed, %d failed\n"):format(results.pass, results.fail))
if rawget(_G, "CQT_ROOT") then
	-- Run from Python (tools/runtests.py), which reads the result instead of an exit code.
	CQT_RESULT = results
elseif results.fail > 0 then
	os.exit(1)
end
