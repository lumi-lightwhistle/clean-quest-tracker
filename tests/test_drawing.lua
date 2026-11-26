-- Drawing cost (Appearance page): the look's moving parts and the frame's layout, drawn on a stand-in frame that counts
-- every call into the game. Guards against the per-frame waste that once made the tracker cost several percent of a
-- CPU core. Each budget sits well under what the old drawing cost (docs/agents/quirks.md) and above what it costs
-- now; each also has a floor, so a check can't pass because nothing was drawn at all.
--
-- This suite must stay last in SUITES (tests/run.lua): it gives the backdrop a stand-in frame of its own, which stays.
local Q, db, check = TEST.Q, TEST.Q.db, TEST.check
local F = Q.Frame

-- A widget that takes any method, counts it, and keeps only what the drawing reads back. Fields (lower case, like the
-- add-on's own qc ones) and scripts (OnUpdate) are nil until set.
local calls, colours = 0, 0
local Region = {}
local function Count()
	calls = calls + 1
end
Region.__index = function(_, key)
	if Region[key] then
		return Region[key]
	end
	if type(key) ~= "string" or key:match("^%l") or key:match("^On%u") then
		return nil
	end
	return Count
end
function Region.Show(self)
	calls = calls + 1
	self.shown = true
end
function Region.Hide(self)
	calls = calls + 1
	self.shown = false
end
function Region.SetShown(self, shown)
	calls = calls + 1
	self.shown = shown and true or false
end
function Region.IsShown(self)
	calls = calls + 1
	return self.shown ~= false
end
Region.IsVisible = Region.IsShown
function Region.GetWidth(self)
	calls = calls + 1
	return self.width or 200
end
function Region.GetHeight(self)
	calls = calls + 1
	return self.height or 3
end
function Region.SetHeight(self, height)
	calls = calls + 1
	self.height = height
end
function Region.SetSize(self, width, height)
	calls = calls + 1
	self.width, self.height = width, height
end
function Region.SetScript(self, name, fn)
	self[name] = fn
end
function Region.GetScript(self, name)
	return self[name]
end
function Region.RegisterEvent(self, event)
	self.events = self.events or {}
	self.events[event] = true
end
function Region.CreateTexture()
	calls = calls + 1
	return setmetatable({}, Region)
end
function Region.SetTexture()
	calls = calls + 1
	return true
end

local made = {}
local gameCreateFrame, gameCreateColor = CreateFrame, CreateColor
local SETTINGS = { "backdrop", "border", "rounded", "cornerSize", "padding", "opacity", "barStyle", "animSpeed" }
for _, key in ipairs(Q.LOOK_KEYS) do
	SETTINGS[#SETTINGS + 1] = key
end
local saved = {}
for _, key in ipairs(SETTINGS) do
	saved[key] = db[key]
end
local host, driver
local bars = {}

local function FreeBars()
	for _, bar in ipairs(bars) do
		bar:Hide()
		bar.OnHide(bar)
	end
	bars = {}
end

-- Draws the look `settings` (on top of a Moonglow frame with every moving part off), with `count` smooth bars showing
-- the bar effect `effect` (Flat when not given).
local function Look(settings, count, effect)
	FreeBars()
	db.backdrop, db.border, db.rounded, db.cornerSize, db.padding, db.opacity = true, true, true, 7, 6, 0.6
	db.barStyle = "smooth"
	for key, value in pairs(Q.THEMES.moonglow) do
		db[key] = value
	end
	db.moonGleam, db.moonBloom, db.moonStars, db.moonShooting, db.moonAurora, db.moonMist, db.moonBeam, db.moonBars =
		"off", false, false, false, false, false, false, effect or "flat"
	for key, value in pairs(settings) do
		db[key] = value
	end
	F.PaintBackdrop(0.6)
	for index = 1, count or 0 do
		local bar = Q.NewProgressBar(host)
		Q.SetBarProgress(bar, "bar" .. index, index % 9 + 1, 10, false)
		bars[index] = bar
	end
	F.StartMoonglow()
end

-- Runs the clock for `seconds` at `fps` frames a second (60 if not given): the calls into the game per frame, on
-- average, and how many frames the clock ran in.
local function Run(seconds, fps)
	fps = fps or 60
	calls = 0
	local frames, ran = math.floor(seconds * fps + 0.5), 0
	for _ = 1, frames do
		WOW.Advance(1 / fps)
		WOW.RunTimers()
		if driver.OnUpdate then
			ran = ran + 1
			driver.OnUpdate(driver, 1 / fps)
		end
	end
	return calls / frames, ran
end

local function Suite()
	host = setmetatable({ width = 300, height = 600 }, Region)
	F.CreateBackdrop(host)
	for _, frame in ipairs(made) do
		if frame.events and frame.events.PLAYER_REGEN_ENABLED then
			driver = frame
		end
	end
	check("DR1 the clock's driver was found", driver ~= nil)
	if not driver then
		return
	end
	db.animSpeed = Q.defaults.animSpeed

	-- A moving look starts the clock; Classic stops it.
	Look({ moonStars = true })
	Run(0.1)
	local started = driver.OnUpdate ~= nil
	Look(Q.THEMES.classic)
	Run(0.1)
	check("DR2 the clock runs for a moving look and stops for Classic", started and driver.OnUpdate == nil)

	-- Polished sweep alone: line up with its cycle (it sleeps through each rest), then measure a pass and a rest.
	Look({ moonGleam = "sweep" })
	for _ = 1, 400 do
		if driver.OnUpdate == nil then
			break
		end
		Run(1 / 60)
	end
	local asleep = driver.OnUpdate == nil
	for _ = 1, 400 do
		if driver.OnUpdate ~= nil then
			break
		end
		Run(1 / 60)
	end
	local pass = Run(2.4)
	check("DR3 a Polished sweep pass stays cheap", asleep and pass > 20 and pass < 150, pass)
	Run(0.4)
	local rest, ran = Run(3.6)
	check("DR4 the clock sleeps through the sweep's rest", driver.OnUpdate ~= nil and ran < 3.6 * 60 * 0.15 and rest < 5,
		ran)

	Look({ moonGleam = "tide" })
	local tide = Run(4)
	check("DR5 Moonlit tide stays cheap", tide > 20 and tide < 160, tide)

	Look({ moonStars = true })
	local stars = Run(2)
	check("DR6 after the border light, stars alone cost almost nothing", stars > 0 and stars < 5, stars)

	Look({}, 15, "tide")
	local waves = Run(3)
	check("DR7 Moontide on 15 bars stays cheap", waves > 5 and waves < 35, waves)
	-- Slow effects are drawn about 30 times a second whatever the frame rate.
	local fast = Run(3, 144)
	check("DR8 a faster frame rate doesn't draw slow effects more often", fast * 144 < waves * 60 * 1.15,
		fast * 144 / (waves * 60))

	Look({ moonStars = true, moonShooting = true, moonBeam = true, moonGleam = "sweep", moonBloom = true }, 15, "glass")
	local busy = Run(10)
	check("DR9 a busy look stays cheap", busy > 20 and busy < 170, busy)

	-- A step of a height ease lays the frame out again, but leaves the bars' light alone.
	local lit = 0
	for _, bar in ipairs(bars) do
		local light = bar.qcLight
		bar.qcLight = function(...)
			lit = lit + 1
			return light(...)
		end
	end
	calls, colours = 0, 0
	for step = 1, 50 do
		host.height = 600 - step
		F.LayoutBackdrop()
	end
	check("DR10 a step of a height ease stays cheap", calls / 50 > 50 and calls / 50 < 450, calls / 50)
	check("DR11 and makes no new colour objects", colours == 0, colours)
	check("DR12 and doesn't draw the bars' light", lit == 0, lit)

	-- With the tracker hidden its own effects stop; a bar on screen elsewhere (the /cqt preview) still moves.
	FreeBars()
	Look({ moonStars = true, moonGleam = "tide" })
	host.shown = false
	Run(0.1)
	local stopped = driver.OnUpdate == nil
	local bar = Q.NewProgressBar(UIParent)
	db.moonBars = "tide"
	Q.SetBarProgress(bar, "preview", 3, 10, false)
	Run(0.1)
	check("DR13 a hidden tracker stops its effects but not other bars' light", stopped and driver.OnUpdate ~= nil)
	bar:Hide()
	bar.OnHide(bar)
	host.shown = true

	-- Everything still, so the clock stops before the next suite.
	Look(Q.THEMES.classic)
	Run(0.1)
end

CreateFrame = function()
	local frame = setmetatable({}, Region)
	made[#made + 1] = frame
	return frame
end
CreateColor = function(...)
	colours = colours + 1
	return gameCreateColor(...)
end
local ok, err = pcall(Suite)
pcall(FreeBars)
for _, key in ipairs(SETTINGS) do
	db[key] = saved[key]
end
CreateFrame, CreateColor = gameCreateFrame, gameCreateColor
if not ok then
	error(err, 0)
end
