-- A small stand-in for the WoW client API, enough to load Clean Quest Tracker's Lua files outside the game and run its
-- pure logic (tests/run.lua). It is not an emulator: frames accept any method and do nothing, and the quest log, zone
-- and map functions return whatever the test puts in the WOW table below.
--
-- WOW.now          the clock GetTime() reads; tests move it forward with WOW.Advance(seconds)
-- WOW.watches      the watch list, first to last: { questID, ... }
-- WOW.log          the quest log, top to bottom: { { title = "Westfall", isHeader = true }, { questID = 1 }, ... }
-- WOW.complete     [questID] = true for finished quests
-- WOW.zone         { real = GetRealZoneText(), text = GetZoneText(), map = map ID for the player, mapError = true }
-- WOW.maps         [mapID] = { mapType, name, parentMapID }
-- WOW.player       { name, realm }
-- WOW.secret       [value] = true makes issecretvalue(value) true, as a restricted client would
-- WOW.Fire(event, ...) sends an event to every stub frame that registered it.
-- WOW.RunTimers()  runs every C_Timer.After callback that is due (and any they add that are due), earliest first.
--                  C_Timer.NewTicker never fires.
-- WOW.Reset()      empties all of the above that a test sets up; tests/run.lua calls it before each suite.
--
-- Frames return a do-nothing function for ANY field that isn't one of the methods below (frame.Text, button.questID
-- too), and such a function counts as true. Fine for loading the add-on; don't test frame-reading code on top of it.

------------------------------------------------------------------------------------------------------------------------
-- State the tests control
------------------------------------------------------------------------------------------------------------------------
WOW = {
	now = 1000,
	watches = {},
	log = {},
	complete = {},
	zone = {},
	maps = {},
	player = { name = "Tester", realm = "Testrealm" },
	frames = {},
	timers = {},
	printed = {},
	secret = {}, -- [value] = true: issecretvalue(value) says it can't be read
}

function WOW.Reset()
	WOW.watches, WOW.log, WOW.complete, WOW.zone, WOW.maps = {}, {}, {}, {}, {}
	WOW.timers, WOW.secret, WOW.printed = {}, {}, {}
end

function WOW.Advance(seconds)
	WOW.now = WOW.now + seconds
end

------------------------------------------------------------------------------------------------------------------------
-- Frames: any method works and returns nothing, except the few that hand back another region
------------------------------------------------------------------------------------------------------------------------
local MAKES_REGION = {
	CreateTexture = true,
	CreateFontString = true,
	CreateMaskTexture = true,
	CreateLine = true,
	CreateAnimationGroup = true,
	CreateAnimation = true,
}

local Frame = {}
local function NewFrame(kind, name)
	local frame = setmetatable({ _kind = kind, _scripts = {}, _events = {}, _shown = true }, Frame)
	if name then
		_G[name] = frame
	end
	WOW.frames[#WOW.frames + 1] = frame
	return frame
end

local methods = {}
function methods:SetScript(handler, fn)
	self._scripts[handler] = fn
end
function methods:GetScript(handler)
	return self._scripts[handler]
end
function methods:HookScript(handler, fn)
	local old = self._scripts[handler]
	self._scripts[handler] = function(...)
		if old then
			old(...)
		end
		return fn(...)
	end
end
function methods:RegisterEvent(event)
	self._events[event] = true
end
function methods:UnregisterEvent(event)
	self._events[event] = nil
end
function methods:UnregisterAllEvents()
	self._events = {}
end
function methods:IsEventRegistered(event)
	return self._events[event] or false
end
function methods:Show()
	self._shown = true
end
function methods:Hide()
	self._shown = false
end
function methods:IsShown()
	return self._shown
end
function methods:IsVisible()
	return self._shown
end
function methods:SetShown(shown)
	self._shown = shown and true or false
end
function methods:GetWidth()
	return 0
end
function methods:GetHeight()
	return 0
end
function methods:GetSize()
	return 0, 0
end
function methods:GetObjectType()
	return self._kind
end

Frame.__index = function(_, key)
	if methods[key] then
		return methods[key]
	end
	if MAKES_REGION[key] then
		return function()
			return NewFrame(key:sub(7))
		end
	end
	return function() end
end

function CreateFrame(kind, name)
	return NewFrame(kind, name)
end
UIParent = NewFrame("Frame", "UIParent")

function WOW.Fire(event, ...)
	for _, frame in ipairs(WOW.frames) do
		local handler = frame._scripts.OnEvent
		if frame._events[event] and handler then
			handler(frame, event, ...)
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Time and timers
------------------------------------------------------------------------------------------------------------------------
function GetTime()
	return WOW.now
end

C_Timer = {}
function C_Timer.After(delay, fn)
	WOW.timers[#WOW.timers + 1] = { at = WOW.now + (delay or 0), fn = fn }
end
function C_Timer.NewTicker(delay, fn)
	local ticker = { cancelled = false }
	function ticker:Cancel()
		self.cancelled = true
	end
	return ticker
end

function WOW.RunTimers()
	local budget = #WOW.timers + 100 -- what is due now, plus room for timers those add
	while true do
		local due
		for index, timer in ipairs(WOW.timers) do
			if timer.at <= WOW.now and (not due or timer.at < WOW.timers[due].at) then
				due = index
			end
		end
		if not due then
			return
		end
		budget = budget - 1
		if budget < 0 then
			error("timers keep adding timers that are already due")
		end
		table.remove(WOW.timers, due).fn()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Quest log and watch list
------------------------------------------------------------------------------------------------------------------------
C_QuestLog = {}
function C_QuestLog.GetNumQuestWatches()
	return #WOW.watches
end
function C_QuestLog.GetQuestIDForQuestWatchIndex(index)
	return WOW.watches[index]
end
function C_QuestLog.AddQuestWatch(questID)
	-- This client puts a newly tracked quest at the front.
	C_QuestLog.RemoveQuestWatch(questID)
	table.insert(WOW.watches, 1, questID)
end
function C_QuestLog.RemoveQuestWatch(questID)
	for index, id in ipairs(WOW.watches) do
		if id == questID then
			table.remove(WOW.watches, index)
			return
		end
	end
end
function C_QuestLog.GetNumQuestLogEntries()
	return #WOW.log
end
function C_QuestLog.GetInfo(index)
	local entry = WOW.log[index]
	if not entry then
		return nil
	end
	local info = {}
	for key, value in pairs(entry) do
		info[key] = value
	end
	info.title = info.title or ("Quest " .. tostring(info.questID))
	return info
end
function C_QuestLog.GetLogIndexForQuestID(questID)
	for index, entry in ipairs(WOW.log) do
		if entry.questID == questID then
			return index
		end
	end
end
function C_QuestLog.IsComplete(questID)
	return WOW.complete[questID] or false
end
function C_QuestLog.GetTitleForQuestID(questID)
	return "Quest " .. tostring(questID)
end

------------------------------------------------------------------------------------------------------------------------
-- Where you are
------------------------------------------------------------------------------------------------------------------------
function GetRealZoneText()
	return WOW.zone.real
end
function GetZoneText()
	return WOW.zone.text
end

C_Map = {}
function C_Map.GetBestMapForUnit()
	return WOW.zone.map
end
function C_Map.GetMapInfo(mapID)
	if WOW.zone.mapError then
		error("map info failed")
	end
	return WOW.maps[mapID]
end

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }

------------------------------------------------------------------------------------------------------------------------
-- Player, client and the rest
------------------------------------------------------------------------------------------------------------------------
function UnitName(unit)
	if unit == "player" then
		return WOW.player.name
	end
end
function GetRealmName()
	return WOW.player.realm
end
function UnitExists(unit)
	return unit == "player"
end
function IsInGroup()
	return false
end
function InCombatLockdown()
	return false
end
function issecretvalue(value)
	return value ~= nil and WOW.secret[value] or false
end
function GetCVarBool()
	return false
end
function hooksecurefunc() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function PlaySound() end

C_AddOns = {}
function C_AddOns.GetAddOnMetadata()
	return "test"
end
function C_AddOns.IsAddOnLoaded()
	return false
end
function C_AddOns.LoadAddOn()
	return false
end

function wipe(t)
	for key in pairs(t) do
		t[key] = nil
	end
	return t
end
table.wipe = wipe
function Mixin(object, ...)
	for index = 1, select("#", ...) do
		for key, value in pairs((select(index, ...))) do
			object[key] = value
		end
	end
	return object
end
function CreateColor(r, g, b, a)
	return { r = r, g = g, b = b, a = a }
end
strtrim = function(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
format = string.format
tinsert, tremove = table.insert, table.remove

SlashCmdList = {}
OTHER = "Other"
QUESTS_LABEL = "Quests"

DEFAULT_CHAT_FRAME = NewFrame("Frame", "DEFAULT_CHAT_FRAME")
function DEFAULT_CHAT_FRAME:AddMessage(text)
	WOW.printed[#WOW.printed + 1] = text
end
function print(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(index, ...)))
	end
	WOW.printed[#WOW.printed + 1] = table.concat(parts, " ")
end
