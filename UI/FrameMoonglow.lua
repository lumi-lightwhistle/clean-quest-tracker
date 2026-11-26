-- Clean Quest Tracker: the look's light and motion, the parts that came with the Moonglow theme (Appearance page).
-- FrameBorder.lua draws the sky and the line like any other backdrop; this file adds what moves or glows on top of
-- them: the moonlit corner accents, the moon crest, the moonlit header, twinkling stars, shooting stars, aurora, mist,
-- the moonbeam, the light that runs on the border (Moonlit tide or Polished sweep), the Lunar bloom when an objective
-- finishes, and the clock for the light on progress bars. Each part follows its own look setting (Q.Look).
--
-- Everything is a plain texture on the tracker's own frame, from the add-on's own art (Media\Moon*, drawn offline),
-- under the quest list. Nothing here touches a secure frame, so it is safe in combat; moving effects still pause there,
-- and with Animations set to None, as the rest of the tracker's motion does (a bloom already playing finishes).
-- Effects that belong to the sky (stars, shooting stars, aurora, mist, moonbeam) need a sky and stay inside its panel.
--
-- Cost: pieces are laid out when the frame changes size (LayoutMoonglow), and the clock (Step) then only changes what
-- moves. Slow effects are drawn about 30 times a second and quick ones at most 60, whatever the frame rate. Each
-- texture remembers whether it shows (qcOn, through Q.ShowPart and Q.HidePart), so a resting effect costs nothing.

local _, Q = ...
local F = Q.Frame

local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"
local PALE = { 0.86, 0.9, 1 } -- moonlight, for tinted art
local SYNODIC = 29.530588853 * 86400 -- the moon's month, in seconds
local NEW_MOON = 947182440 -- a new moon: 6 January 2000, 18:14 UTC
local PHASE_NAMES = { "New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous",
	"Last quarter", "Waning crescent" }
local CORNER_FILES = { star = "Star", bracket = "Bracket", constellation = "Constellation", leaf = "Leaf", edge = "Edge" }
local CORNER_RADII = { 0, 4, 7, 10, 13 } -- the corner sizes the accents are drawn for (Media\MoonCorner<style><size>)
-- The art is the top-left corner; these texture coordinates turn it into each corner (top left, top right, bottom
-- left, bottom right).
local CORNER_FLIPS = { { 0, 1, 0, 1 }, { 1, 0, 0, 1 }, { 0, 1, 1, 0 }, { 1, 0, 1, 0 } }
-- The corner art covers 48 units with the panel's corner 12 in; the moon crest's box is 34 pixels, its disc's radius 11.6.
local CORNER_SPAN, CORNER_BEFORE = 48, 12
local CREST_BOX, CREST_DISC = 34, 11.6
-- The aurora: three layers of the same curtain art at different sizes, drifting at their own speeds, each shaded from
-- its base colour (bottom) to its crown colour (top) like the real thing: green low down, violet or rose above.
local AURORA = {
	{ scale = 1, alpha = 0.9, speed = 6, base = { 90 / 255, 235 / 255, 170 / 255 }, crown = { 170 / 255, 120 / 255, 1 } },
	{ scale = 0.75, alpha = 0.6, speed = -9, base = { 120 / 255, 220 / 255, 1 }, crown = { 170 / 255, 120 / 255, 1 } },
	{ scale = 1.35, alpha = 0.45, speed = 12, base = { 90 / 255, 235 / 255, 170 / 255 }, crown = { 1, 120 / 255, 200 / 255 } },
}
local AURORA_TILE = 512 * 0.55 -- one tile of the art across, in pixels, at scale 1
-- The rest of the sky. Stars: two layers of one tile (STARS_TILE pixels) twinkling at their own speeds. Mist: two
-- layers along the bottom, `height` tall at most, drifting `speed` tiles (MIST_TILE pixels) a second. Moonbeam: a shaft
-- at least `width` wide, crossing at `speed` pixels a second. Shooting star: `life` seconds, travelling `run` pixels
-- left and `fall` down.
local STARS_TILE = 128
local TWINKLE = { { speed = 1.1, phase = 0 }, { speed = 1.6, phase = 2 } }
local MIST_TILE = 256
local MIST = { { height = 44, speed = 0.012, alpha = 0.17 }, { height = 32, speed = -0.008, alpha = 0.12 } }
local BEAM = { width = 140, stretch = 1.12, speed = 22, alpha = 0.13 }
local STREAK = { life = 0.8, run = 140, fall = 60, width = 64, height = 32 }
local HEADER_TINT = { 232 / 255, 238 / 255, 1 } -- the Moonlit header's title, and Moonglow's zone names
-- Moonglow's moonlight on text: the zone names' silver and its hover shade, the faint halo behind a zone name (its
-- colour, strength, the room it adds round the words and its height; TrackerZones.lua), and the silver rules.
F.MOON = {
	zone = { r = HEADER_TINT[1], g = HEADER_TINT[2], b = HEADER_TINT[3], reverse = { r = 1, g = 1, b = 1 } },
	halo = { 150 / 255, 180 / 255, 1 },
	haloAlpha = 0.14,
	haloPad = 16,
	haloHeight = 20,
	rule = { 200 / 255, 215 / 255, 1 },
}
-- Tints, kept here so the clock doesn't make new tables every frame.
local TINT = {
	crestHalo = { 190 / 255, 210 / 255, 1 },
	stars = { 220 / 255, 230 / 255, 1 },
	mist = { 140 / 255, 200 / 255, 220 / 255 },
	beam = { 180 / 255, 200 / 255, 1 },
	gleam = { 0.91, 0.94, 1 }, -- the border light on silver
	gleamBronze = { 1, 0.86, 0.62 }, -- and on bronze
	gleamHalo = { 150 / 255, 180 / 255, 1 },
	ring = { 200 / 255, 220 / 255, 1 },
	ringGlow = { 190 / 255, 215 / 255, 1 },
	mote = { 225 / 255, 235 / 255, 1 },
}
-- The clock draws slow effects (stars, aurora, mist, moonbeam, Moontide and Crescent tip bars) every SLOW seconds and
-- quick ones (shooting stars, the border light, Polished glass bars, the bloom) every FAST seconds at most.
local SLOW, FAST = 1 / 30, 1 / 60
local VIEW_CHECK = 0.25 -- seconds between checks of which bars the quest list shows

local host, driver, crestHit
local parts = {}
-- The panel: x0, y0, width, height and radius from the frame's top-left corner, y down; `per`, the length of its
-- border; `bounds`, the sky's inside ({ left, top, right, bottom }: the panel less a little at the edge, which keeps
-- effects inside rounded corners). `layouts` counts its changes.
local box
local layouts = 0
local look = {} -- the settings, read by F.PaintMoonglow
local repaint = true -- the settings changed since the last layout
local clock, nextStreak, streak = 0, 2, nil
local rings, motes = {}, {}
local litBars = setmetatable({}, { __mode = "k" })
local running = false -- the clock is running (the driver has its OnUpdate)
local slowWait, fastWait, viewWait, bloomTime = 0, 0, 0, 0
local wasMoving = false -- motion was on at the clock's last frame
-- A Polished sweep's rest slept through (Sleep): since when, for how long at most, and which sleep is the current one.
local sleepingSince, sleepFor, sleepToken = nil, 0, 0

------------------------------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------------------------------
-- How strongly glows and effects show (the Glow strength slider): 0.3 at its lowest, 1 at its highest.
function F.MoonStrength()
	local value = tonumber(Q.db and Q.Look("moonGlow")) or Q.defaults.moonGlow
	return 0.3 + 0.7 * math.max(0, math.min(1, value))
end

-- The moon tonight: how far through its month (0 new, 0.5 full), its name and how much of it is lit.
function F.MoonPhase()
	local now = (GetServerTime and GetServerTime()) or time()
	local share = ((now - NEW_MOON) % SYNODIC) / SYNODIC
	local lit = (1 - math.cos(share * 2 * math.pi)) / 2
	return share, PHASE_NAMES[math.floor(share * 8 + 0.5) % 8 + 1], lit
end

------------------------------------------------------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------------------------------------------------------
-- Every texture made by Texture() below shows and hides through these (the header's own textures don't).
local Show, Hide = Q.ShowPart, Q.HidePart

local function HideAll(list)
	for _, texture in ipairs(list) do
		Hide(texture)
	end
end

local function Texture(layer, sublevel, file, wrap)
	local texture = host:CreateTexture(nil, layer, nil, sublevel)
	if wrap then
		-- Repeated along the axes asked for; a client that refuses that stretches it instead.
		if not pcall(texture.SetTexture, texture, file, wrap[1], wrap[2]) then
			texture:SetTexture(file)
		end
	elseif file then
		texture:SetTexture(file)
	end
	texture:Hide()
	return texture
end

-- Sets a texture's art, only when it changes.
local function Art(texture, file)
	if texture.qcArt ~= file then
		texture:SetTexture(file)
		texture.qcArt = file
	end
end

local function Tint(texture, color, alpha)
	texture:SetVertexColor(color[1], color[2], color[3], math.max(0, math.min(1, alpha)))
end

-- Shades a texture from `bottom` to `top` at `alpha`; a client that refuses gradients gets the bottom colour.
local function Shade(texture, bottom, top, alpha)
	alpha = math.max(0, math.min(1, alpha))
	if not Q.Gradient(texture, "VERTICAL", bottom[1], bottom[2], bottom[3], alpha, top[1], top[2], top[3], alpha) then
		Tint(texture, bottom, alpha)
	end
end

-- Places a texture by its top-left corner, in pixels right of and below the frame's top-left corner, showing the part
-- of its art from u0..u1 across and v0..v1 down. With `bounds` ({ left, top, right, bottom }) only the part inside is
-- drawn, the art cropped to match. These textures are only ever anchored by their top-left corner, so setting it again
-- replaces the old one.
local function Place(texture, x, y, width, height, bounds, u0, u1, v0, v1)
	u0, u1, v0, v1 = u0 or 0, u1 or 1, v0 or 0, v1 or 1
	if bounds then
		local left, top = math.max(x, bounds[1]), math.max(y, bounds[2])
		local right, bottom = math.min(x + width, bounds[3]), math.min(y + height, bounds[4])
		if right - left <= 0.5 or bottom - top <= 0.5 then
			Hide(texture)
			return
		end
		local du, dv = (u1 - u0) / width, (v1 - v0) / height
		u0, u1 = u0 + (left - x) * du, u0 + (right - x) * du
		v0, v1 = v0 + (top - y) * dv, v0 + (bottom - y) * dv
		x, y, width, height = left, top, right - left, bottom - top
	end
	if width <= 0.5 or height <= 0.5 then
		Hide(texture)
		return
	end
	texture:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
	texture:SetSize(width, height)
	texture:SetTexCoord(u0, u1, v0, v1)
	Show(texture)
end

-- A point `distance` along the border's line, clockwise from the end of the top-left corner's curve: four straight
-- runs, each followed by a quarter turn round the next corner's centre.
local CORNER_TURNS = { -math.pi / 2, 0, math.pi / 2, math.pi } -- each corner's curve starts at this angle
local function AlongBorder(distance)
	local x0, y0, w, h, r = box.x0, box.y0, box.width, box.height, box.radius
	local bend = math.pi * r / 2
	for side = 1, 4 do
		local straight = (side % 2 == 1) and w - 2 * r or h - 2 * r
		if distance <= straight then
			if side == 1 then
				return x0 + r + distance, y0
			elseif side == 2 then
				return x0 + w, y0 + r + distance
			elseif side == 3 then
				return x0 + w - r - distance, y0 + h
			end
			return x0, y0 + h - r - distance
		end
		distance = distance - straight
		if distance <= bend then
			-- Corner centres in turn: top right, bottom right, bottom left, top left.
			local cx = (side == 1 or side == 2) and x0 + w - r or x0 + r
			local cy = (side == 1 or side == 4) and y0 + r or y0 + h - r
			local angle = CORNER_TURNS[side] + distance / math.max(r, 1e-6)
			return cx + r * math.cos(angle), cy + r * math.sin(angle)
		end
		distance = distance - bend
	end
	return x0 + r, y0
end

------------------------------------------------------------------------------------------------------------------------
-- Building the pieces. Sublevels: the panel is BACKGROUND -8 to -7 (FrameBorder.lua), the sky's effects -5 to -1
-- above it (aurora, moonbeam, mist, stars, shooting star) and the bloom at 0; the line is BORDER; the bronze flourishes
-- and crest ARTWORK 1 and 2, Moonglow's accents and border light above them.
------------------------------------------------------------------------------------------------------------------------
function F.CreateMoonglow(frame)
	host = frame
	parts.aurora = {}
	for band = 1, #AURORA do
		parts.aurora[band] = Texture("BACKGROUND", -5, MEDIA .. "MoonAurora", { "REPEAT", "CLAMP" })
	end
	parts.beam = Texture("BACKGROUND", -4, MEDIA .. "MoonBeam")
	parts.mist = { Texture("BACKGROUND", -3, MEDIA .. "MoonMist", { "REPEAT", "CLAMP" }),
		Texture("BACKGROUND", -3, MEDIA .. "MoonMist", { "REPEAT", "CLAMP" }) }
	parts.stars = { Texture("BACKGROUND", -2, MEDIA .. "MoonStars", { "REPEAT", "REPEAT" }),
		Texture("BACKGROUND", -2, MEDIA .. "MoonStars", { "REPEAT", "REPEAT" }) }
	parts.streak = Texture("BACKGROUND", -1, MEDIA .. "MoonStreak")
	parts.corners = {}
	for corner = 1, 4 do
		parts.corners[corner] = Texture("ARTWORK", 3)
	end
	parts.crestHalo = Texture("ARTWORK", 5, MEDIA .. "BackdropGlow")
	parts.moon = Texture("ARTWORK", 6)
	-- Hovering the moon names tonight's phase. It only takes the mouse while it shows.
	crestHit = CreateFrame("Frame", nil, host)
	crestHit:SetSize(CREST_DISC * 2, CREST_DISC * 2)
	crestHit:EnableMouse(false)
	crestHit:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if look.crest == "live" then
			local _, name, lit = F.MoonPhase()
			GameTooltip:SetText(name)
			GameTooltip:AddLine(("%d%% lit tonight"):format(lit * 100 + 0.5), 1, 1, 1)
		else
			GameTooltip:SetText("Crescent moon")
		end
		GameTooltip:Show()
	end)
	crestHit:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	crestHit:Hide()
	-- The clock is the screen's, not the tracker's, so the /cqt preview's bars move while the tracker is hidden; the
	-- tracker's own effects only count while it shows (Busy), and pick up again when it shows.
	driver = CreateFrame("Frame", nil, UIParent)
	running, sleepingSince = false, nil
	host:HookScript("OnShow", function()
		F.StartMoonglow()
	end)
	-- Motion pauses in combat; it picks up again when combat ends.
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:SetScript("OnEvent", function()
		F.StartMoonglow()
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- The pieces that stay put: corner accents and the crest. `full`: the settings changed, not just the frame's size.
------------------------------------------------------------------------------------------------------------------------
local function PlaceCorners(full)
	local file = CORNER_FILES[look.corners]
	-- They sit on the frame's line, so look.corners is "off" without one (PaintMoonglow).
	if not file then
		HideAll(parts.corners)
		return
	end
	local x0, y0, w, h = box.x0, box.y0, box.width, box.height
	-- On a short frame (minimised, say) they shrink so opposite corners never meet.
	local scale = math.min(1, w / 90, h / 90)
	local size, before = CORNER_SPAN * scale, CORNER_BEFORE * scale
	local after = size - before
	-- The art drawn for the corner size nearest the frame's.
	local nearest = CORNER_RADII[1]
	for _, radius in ipairs(CORNER_RADII) do
		if math.abs(radius - box.radius) <= math.abs(nearest - box.radius) then -- a tie takes the rounder art
			nearest = radius
		end
	end
	local art = MEDIA .. "MoonCorner" .. file .. nearest
	for corner, texture in ipairs(parts.corners) do
		Art(texture, art)
		if full then
			texture:SetVertexColor(1, 1, 1, 0.55 + 0.45 * look.strength)
			local flip = CORNER_FLIPS[corner]
			texture:SetTexCoord(flip[1], flip[2], flip[3], flip[4])
		end
		local east, south = corner == 2 or corner == 4, corner >= 3
		texture:SetPoint("TOPLEFT", host, "TOPLEFT", east and x0 + w - after or x0 - before,
			-(south and y0 + h - after or y0 - before))
		texture:SetSize(size, size)
		Show(texture)
	end
end

local function PlaceCrest()
	if look.crest ~= "live" and look.crest ~= "crescent" then
		Hide(parts.moon)
		Hide(parts.crestHalo)
		crestHit:Hide()
		crestHit:EnableMouse(false)
		return
	end
	-- Centred on the top edge, lifted so its lowest point stays a pixel above the frame's own top, clear of the title.
	local cx = box.x0 + box.width / 2
	local cy = box.y0 - math.max(2, CREST_DISC + 1 - look.pad)
	if look.crest == "live" then
		local cell = math.floor(F.MoonPhase() * 16 + 0.5) % 16
		local u, v = (cell % 4) / 4, math.floor(cell / 4) / 4
		Art(parts.moon, MEDIA .. "MoonPhases")
		Place(parts.moon, cx - CREST_BOX / 2, cy - CREST_BOX / 2, CREST_BOX, CREST_BOX, nil, u, u + 0.25, v, v + 0.25)
	else
		-- A true crescent rather than a phase of the moon, which reads as a half moon this small.
		Art(parts.moon, MEDIA .. "MoonCrescent")
		Place(parts.moon, cx - CREST_BOX / 2, cy - CREST_BOX / 2, CREST_BOX, CREST_BOX)
	end
	local halo = CREST_BOX * 1.4
	Tint(parts.crestHalo, TINT.crestHalo, 0.55 * look.strength)
	Place(parts.crestHalo, cx - halo / 2, cy - halo / 2, halo, halo)
	crestHit:ClearAllPoints()
	crestHit:SetPoint("CENTER", host, "TOPLEFT", cx, -cy)
	crestHit:EnableMouse(true)
	crestHit:Show()
end

------------------------------------------------------------------------------------------------------------------------
-- The sky's effects. LayoutSky places them for the panel's size; DrawSky (slow) and DrawStreak (quick) then change
-- only what moves, for time `clock`. With motion paused they hold still and the shooting star hides.
------------------------------------------------------------------------------------------------------------------------
local function HideSky()
	HideAll(parts.stars)
	HideAll(parts.aurora)
	HideAll(parts.mist)
	Hide(parts.beam)
	Hide(parts.streak)
end

local function LayoutSky()
	local bounds = box.bounds
	local left, top = bounds[1], bounds[2]
	local width, height = bounds[3] - left, bounds[4] - top
	if look.stars and width > 0 and height > 0 then
		Place(parts.stars[1], left, top, width, height, nil, 0, width / STARS_TILE, 0, height / STARS_TILE)
		-- The second layer is the same tile turned round and shifted, so the two never line up.
		Place(parts.stars[2], left, top, width, height, nil, width / STARS_TILE + 0.37, 0.37, height / STARS_TILE + 0.21,
			0.21)
	else
		HideAll(parts.stars)
	end
	if look.aurora then
		-- Under the header's rule, not behind the title; DrawSky sets each layer's height.
		local from = math.max(top, F.HEADER_HEIGHT - 2)
		box.auroraTop = from
		for _, texture in ipairs(parts.aurora) do
			texture:SetPoint("TOPLEFT", host, "TOPLEFT", left, -from)
			texture:SetWidth(math.max(width, 0.01))
		end
	else
		HideAll(parts.aurora)
	end
	if look.mist then
		for layer, texture in ipairs(parts.mist) do
			local span = math.min(MIST[layer].height, height * 0.5)
			Tint(texture, TINT.mist, MIST[layer].alpha * look.strength)
			Place(texture, left, top + height - span, width, span) -- DrawSky sets its drift
		end
	else
		HideAll(parts.mist)
	end
	if not look.beam then
		Hide(parts.beam)
	end
	if not look.shooting then
		Hide(parts.streak)
	end
end

local function DrawSky()
	local strength = look.strength
	local bounds = box.bounds
	local left, top = bounds[1], bounds[2]
	local width, height = bounds[3] - left, bounds[4] - top
	if look.stars then
		local base = (0.35 + 0.65 * strength) * 0.8
		for layer, texture in ipairs(parts.stars) do
			local twinkle = TWINKLE[layer]
			Tint(texture, TINT.stars, base * (0.55 + 0.45 * math.sin(clock * twinkle.speed + twinkle.phase)))
		end
	end
	if look.aurora then
		local from = box.auroraTop or math.max(top, F.HEADER_HEIGHT - 2) -- LayoutSky's, unless it hasn't run yet
		for band, texture in ipairs(parts.aurora) do
			local layer = AURORA[band]
			local tile = AURORA_TILE * layer.scale
			local span = math.min((92 + band * 12) * (1 + 0.06 * math.sin(clock * 0.4 + band)), (top + height - from) * 0.7)
			if span <= 0.5 or width <= 0.5 then
				Hide(texture)
			else
				local drift = (clock * layer.speed / tile + band * 0.31) % 1
				local breath = 0.85 + 0.15 * math.sin(clock * 0.7 + band * 2)
				Shade(texture, layer.base, layer.crown, layer.alpha * 0.7 * strength * breath)
				texture:SetHeight(span)
				texture:SetTexCoord(drift, drift + width / tile, 0, 1)
				Show(texture)
			end
		end
	end
	if look.mist then
		for layer, texture in ipairs(parts.mist) do
			if texture.qcOn then
				local drift = (clock * MIST[layer].speed + layer * 0.5) % 1
				texture:SetTexCoord(drift, drift + width / MIST_TILE, 0, 1)
			end
		end
	end
	if look.beam then
		local beamWidth = math.max(BEAM.width, height * BEAM.stretch)
		local x = (clock * BEAM.speed + width * 0.35) % (width + beamWidth) - beamWidth / 2
		Tint(parts.beam, TINT.beam, BEAM.alpha * strength)
		Place(parts.beam, left + x - beamWidth / 2, top, beamWidth, height, bounds)
	end
end

-- Moves the shooting star on, or now and then starts one.
local function MoveStreak(elapsed)
	if not look.shooting then
		return
	end
	if streak then
		streak.t = streak.t + elapsed
		if streak.t >= STREAK.life then
			streak = nil
		end
		return
	end
	nextStreak = nextStreak - elapsed
	if nextStreak <= 0 and box then
		local bounds = box.bounds
		local width = bounds[3] - bounds[1]
		if width > 160 then
			streak = { x = bounds[1] + width * (0.3 + 0.7 * math.random()),
				y = bounds[2] + (bounds[4] - bounds[2]) * 0.4 * math.random(), t = 0 }
		end
		nextStreak = 3 + math.random() * 4
	end
end

local function DrawStreak()
	if not (look.shooting and streak) then
		Hide(parts.streak)
		return
	end
	local p = streak.t / STREAK.life
	Tint(parts.streak, PALE, (1 - p) * look.strength)
	local hx, hy = streak.x - p * STREAK.run, streak.y + p * STREAK.fall
	Place(parts.streak, hx - 4, hy - 28, STREAK.width, STREAK.height, box.bounds)
end

------------------------------------------------------------------------------------------------------------------------
-- The border light (moonGleam): soft dots of light along the border's own path, so it follows the corner shape: a
-- small bright core every few pixels over a wider, fainter halo. Moonlit tide: a long wash, brightest in its middle,
-- flowing round the whole border once every TIDE_LAP seconds. Polished sweep: every SWEEP_EVERY seconds a slanted
-- shaft crosses the frame from the top left, lighting the border only where it passes.
--
-- Every point along the border where a dot can be (a sample) has its own dot, placed once per layout of the panel; a
-- frame only changes the brightness of the dots in the light and hides the ones it has left.
------------------------------------------------------------------------------------------------------------------------
local TIDE_LAP, TIDE_SHARE, TIDE_MAX = 11, 0.32, 320 -- seconds a lap; the wash's share of the border, at most this long
local SWEEP_RUN, SWEEP_EVERY, SWEEP_SLANT, SWEEP_WIDTH = 2.6, 6.2, 0.55, 36
-- The two kinds of dot: their spacing along the border, size, sublevel, brightness and tint (from TINT, on silver), and
-- each one's state: the samples (n of them, `spacing` apart: x, y, and `slant`, x + y * SWEEP_SLANT from the panel's
-- corner, for the sweep), the dots made so far, the brightness each was last given (0: hidden), the layout it was
-- placed for and the frame it was last lit in, the list of dots lit (`count` of them) and the one being built for this
-- frame (`next`, `nextCount`).
local GLEAM = {
	{ step = 4, size = 6, sublevel = 4, bright = 0.9, tint = "gleam" },
	{ step = 10, size = 18, sublevel = 3, bright = 0.3, tint = "gleamHalo" },
}
for _, kind in ipairs(GLEAM) do
	kind.n, kind.spacing = 0, 1
	kind.x, kind.y, kind.slant = {}, {}, {}
	kind.dots, kind.alpha, kind.placed, kind.stamp = {}, {}, {}, {}
	kind.lit, kind.count, kind.next, kind.nextCount = {}, 0, {}, 0
end
local sampled -- the layout the samples were taken for

-- Seconds left of the Polished sweep's rest between passes, or nil during a pass.
local function SweepResting()
	local t = clock % SWEEP_EVERY
	return t > SWEEP_RUN and SWEEP_EVERY - t or nil
end
local gleamFrame = 0 -- counts frames of border light

local function PlaceDot(kind, index)
	local half = kind.size / 2
	kind.dots[index]:SetPoint("TOPLEFT", host, "TOPLEFT", kind.x[index] - half, half - kind.y[index])
	kind.placed[index] = sampled
end

-- Takes the samples along the border for the panel as it is now. Dots already lit move to their new places at once
-- (or go, when the border got shorter), so none lags a frame behind the frame's edge.
local function SampleBorder()
	sampled = layouts
	for _, kind in ipairs(GLEAM) do
		local n = math.max(1, math.floor(box.per / kind.step + 0.5))
		local spacing = box.per / n
		local xs, ys, slant = kind.x, kind.y, kind.slant
		for index = 1, n do
			local x, y = AlongBorder((index - 1) * spacing)
			xs[index], ys[index] = x, y
			slant[index] = (x - box.x0) + (y - box.y0) * SWEEP_SLANT
		end
		kind.n, kind.spacing = n, spacing
		local count = 0
		for j = 1, kind.count do
			local index = kind.lit[j]
			if index <= n then
				PlaceDot(kind, index)
				count = count + 1
				kind.lit[count] = index
			else
				Hide(kind.dots[index])
				kind.alpha[index] = 0
			end
		end
		kind.count = count
	end
end

-- Lights sample `index` of `kind` at `alpha` in `tint` for this frame.
local function LightDot(kind, index, alpha, tint)
	local dot = kind.dots[index]
	if not dot then
		-- Additive, so overlapping dots read as one line of light.
		dot = Texture("ARTWORK", kind.sublevel, MEDIA .. "BackdropGlow")
		dot:SetBlendMode("ADD")
		dot:SetSize(kind.size, kind.size)
		kind.dots[index] = dot
	end
	if kind.placed[index] ~= sampled then
		PlaceDot(kind, index)
	end
	local old = kind.alpha[index] or 0
	if old == 0 or math.abs(old - alpha) > 0.01 then
		Tint(dot, tint, alpha)
		kind.alpha[index] = alpha
	end
	Show(dot)
	if kind.stamp[index] ~= gleamFrame then
		kind.stamp[index] = gleamFrame
		kind.nextCount = kind.nextCount + 1
		kind.next[kind.nextCount] = index
	end
end

local function BeginGleam()
	gleamFrame = gleamFrame + 1
	for _, kind in ipairs(GLEAM) do
		kind.nextCount = 0
	end
end

-- Ends a frame of border light: dots lit last frame and not this one go out.
local function EndGleam()
	for _, kind in ipairs(GLEAM) do
		local lit = kind.lit
		for j = 1, kind.count do
			local index = lit[j]
			if kind.stamp[index] ~= gleamFrame then
				Hide(kind.dots[index])
				kind.alpha[index] = 0
			end
		end
		kind.lit, kind.next = kind.next, lit
		kind.count = kind.nextCount
	end
end

local function HideGleam()
	for _, kind in ipairs(GLEAM) do
		for j = 1, kind.count do
			local index = kind.lit[j]
			Hide(kind.dots[index])
			kind.alpha[index] = 0
		end
		kind.count = 0
	end
end

local function DrawGleam(moving)
	if look.gleam == "off" or not (look.border and moving and box) then
		HideGleam()
		return
	end
	local strength, bronze = look.strength, not look.silver
	if look.gleam == "tide" then
		if sampled ~= layouts then
			SampleBorder()
		end
		local length = math.min(box.per * TIDE_SHARE, TIDE_MAX)
		local head = (clock / TIDE_LAP) * box.per
		local tail = head - length
		BeginGleam()
		for _, kind in ipairs(GLEAM) do
			local tint = bronze and TINT.gleamBronze or TINT[kind.tint]
			local scale, spacing, n = kind.bright * strength, kind.spacing, kind.n
			for j = math.ceil(tail / spacing), math.floor(head / spacing) do
				local glow = math.sin(math.pi * (j * spacing - tail) / length) ^ 2 -- soft at both ends
				if glow > 0.01 then
					LightDot(kind, j % n + 1, glow * scale, tint)
				end
			end
		end
		EndGleam()
		return
	end
	-- Polished sweep: rests between passes.
	local t = clock % SWEEP_EVERY
	if SweepResting() then
		HideGleam()
		return
	end
	if sampled ~= layouts then
		SampleBorder()
	end
	local p = t / SWEEP_RUN
	local travel = box.width + box.height * SWEEP_SLANT + 4 * SWEEP_WIDTH
	local at = -2 * SWEEP_WIDTH + p * travel
	local fade = p < 0.1 and p / 0.1 or p > 0.9 and (1 - p) / 0.1 or 1
	BeginGleam()
	for _, kind in ipairs(GLEAM) do
		local tint = bronze and TINT.gleamBronze or TINT[kind.tint]
		local scale, slant = kind.bright * strength * fade, kind.slant
		for index = 1, kind.n do
			local off = math.abs(slant[index] - at)
			if off < SWEEP_WIDTH then
				local glow = (1 - off / SWEEP_WIDTH) ^ 1.5
				if glow * fade > 0.01 then
					LightDot(kind, index, glow * scale, tint)
				end
			end
		end
	end
	EndGleam()
end

------------------------------------------------------------------------------------------------------------------------
-- The Lunar bloom: a ring of light and rising motes where an objective finishes
------------------------------------------------------------------------------------------------------------------------
-- Spare bloom textures: a finished ring or mote hands its texture back for the next one, so two never share one.
local spareRings, spareGlows, spareMotes = {}, {}, {}

local function Take(spare, file)
	return table.remove(spare) or Texture("BACKGROUND", 0, MEDIA .. file)
end

local function Give(spare, texture)
	Hide(texture)
	spare[#spare + 1] = texture
end

local function DrawBloom(elapsed)
	local bounds = look.sky and box and box.bounds or nil
	for index = #rings, 1, -1 do
		local ring = rings[index]
		ring.t = ring.t + elapsed
		if ring.t >= 0.9 then
			Give(spareRings, ring.line)
			Give(spareGlows, ring.glow)
			table.remove(rings, index)
		else
			local p = ring.t / 0.9
			local rx, ry = 10 + p * 110, 4 + p * 26
			Tint(ring.line, TINT.ring, (1 - p) * 0.9)
			Place(ring.line, ring.x - rx, ring.y - ry, rx * 2, ry * 2, bounds)
			Tint(ring.glow, TINT.ringGlow, (1 - p) * 0.35 * look.strength)
			Place(ring.glow, ring.x - 60, ring.y - 60, 120, 120, bounds)
		end
	end
	for index = #motes, 1, -1 do
		local mote = motes[index]
		mote.t = mote.t + elapsed
		if mote.t >= mote.life then
			Give(spareMotes, mote.texture)
			table.remove(motes, index)
		else
			mote.x, mote.y = mote.x + mote.vx * elapsed, mote.y + mote.vy * elapsed
			Tint(mote.texture, TINT.mote, 1 - mote.t / mote.life)
			Place(mote.texture, mote.x - 4, mote.y - 4, 8, 8, bounds)
		end
	end
end

-- A ring of light where an objective just finished (`region`, its line). Called by Tracker.lua.
function F.MoonBloom(region)
	if not (host and look.bloom and Q.Motion.On() and region and region.GetLeft) then
		return
	end
	-- The line is placed in the same layout pass that finished it, so it is read a frame later.
	C_Timer.After(0, function()
		-- The setting may have changed in between.
		if not look.bloom then
			return
		end
		local left, top, height = region:GetLeft(), region:GetTop(), region:GetHeight()
		local hostLeft, hostTop = host:GetLeft(), host:GetTop()
		if not (left and top and height and hostLeft and hostTop and region:IsVisible()) or #rings >= 4 then
			return
		end
		local x, y = left - hostLeft + 40, hostTop - (top - height / 2)
		rings[#rings + 1] = { x = x, y = y, t = 0, line = Take(spareRings, "MoonRing"), glow = Take(spareGlows, "BackdropGlow") }
		for _ = 1, 10 do
			if #motes >= 30 then
				break
			end
			motes[#motes + 1] = { x = x + (math.random() - 0.5) * 60, y = y, vx = (math.random() - 0.5) * 18,
				vy = -14 - math.random() * 30, t = 0, life = 1.2 + math.random(), texture = Take(spareMotes, "MoonSpark") }
		end
		F.StartMoonglow()
	end)
end

------------------------------------------------------------------------------------------------------------------------
-- The light on progress bars. Progress.lua registers each bar on screen whose effect moves (the tracker's and the
-- /cqt preview window's); bar.qcLight draws it.
------------------------------------------------------------------------------------------------------------------------
-- The quest list scrolled: bars that came into view start moving straight away (Frame.lua).
function F.MoonViewChanged()
	viewWait = 0
end

function F.WatchBarLight(bar, on)
	on = on and bar:IsVisible() or nil
	litBars[bar] = on
	bar.qcInView = nil
	if on then
		F.StartMoonglow()
	end
end

-- The quest list clips the bars it has scrolled past rather than hiding them, so they still count as visible; their
-- light is left alone (bar.qcInView false) until they come back into view. Checked every VIEW_CHECK seconds.
local function CheckView()
	local viewTop, viewBottom = F.ViewBounds()
	for bar in pairs(litBars) do
		local inView = true
		if viewTop and viewBottom and not bar.qcPreview then
			local top, bottom = bar:GetTop(), bar:GetBottom()
			inView = not (top and bottom) or (bottom <= viewTop and top >= viewBottom)
		end
		bar.qcInView = inView
	end
end

-- Draws the light on the bars due this frame: Polished glass's gleam on quick frames, the others on slow ones.
local function DrawBarLight(moving, slow, fast)
	local strength = look.strength or F.MoonStrength()
	local now = moving and clock or nil
	for bar in pairs(litBars) do
		local due = slow
		if bar.qcEffect == "glass" then
			due = fast
		end
		if due and bar.qcInView ~= false and bar.qcLight then
			bar:qcLight(now, strength)
		end
	end
end

-- Draws one bar's light now (Progress.lua, after the bar is drawn), so it follows the fill even while motion rests.
function F.BarLightNow(bar)
	if bar.qcLight then
		bar:qcLight(Q.Motion.On() and clock or nil, look.strength or F.MoonStrength())
	end
end

------------------------------------------------------------------------------------------------------------------------
-- The clock
------------------------------------------------------------------------------------------------------------------------
local function SkyMoves()
	return look.stars or look.shooting or look.aurora or look.mist or look.beam
end

-- Whether anything needs drawing frame after frame: a bloom playing, or (with motion on) the light on a bar, and while
-- the tracker shows the sky's effects or the border light.
local function Busy(moving)
	if #rings > 0 or #motes > 0 then
		return true
	end
	if not moving then
		return false
	end
	return next(litBars) ~= nil or (host:IsVisible() and (SkyMoves() or (look.gleam ~= "off" and look.border))) or false
end

-- Whether the Polished sweep is all that moves (so the clock may sleep through its rests).
local function OnlySweepMoves()
	return look.gleam == "sweep" and not SkyMoves() and #rings == 0 and #motes == 0 and next(litBars) == nil
end

local Step

local function Stop()
	driver:SetScript("OnUpdate", nil)
	running = false
end

-- With the Polished sweep the only thing moving, the clock sleeps through its rest between passes instead of waking
-- every frame for nothing; the time slept is added when it wakes.
local function Sleep(seconds)
	Stop()
	sleepingSince, sleepFor = GetTime(), seconds
	sleepToken = sleepToken + 1
	local token = sleepToken
	C_Timer.After(seconds, function()
		if sleepToken == token then
			F.StartMoonglow()
		end
	end)
end

function F.StartMoonglow()
	if not driver then
		return
	end
	if sleepingSince then
		-- The clock moves on by the rest slept (no more: combat or a change of setting may have cut the sleep short).
		clock = clock + math.min(GetTime() - sleepingSince, sleepFor)
		sleepingSince = nil
		sleepToken = sleepToken + 1 -- the sleep's own wake-up no longer applies
	end
	if not Busy(Q.Motion.On()) then
		return
	end
	if not running then
		driver:SetScript("OnUpdate", Step)
		running = true
	end
end

Step = function(_, elapsed)
	elapsed = math.min(elapsed or 0, 0.1)
	local moving = Q.Motion.On()
	if moving then
		clock = clock + elapsed
		MoveStreak(elapsed)
	end
	bloomTime = bloomTime + elapsed
	viewWait = viewWait - elapsed
	slowWait, fastWait = slowWait - elapsed, fastWait - elapsed
	local slow, fast = slowWait <= 0, fastWait <= 0
	if wasMoving and not moving then
		slow, fast = true, true -- motion just stopped: everything is drawn at rest, at once
	end
	wasMoving = moving
	if not (slow or fast) then
		return
	end
	if slow then
		slowWait = math.max(0, slowWait + SLOW)
	end
	if fast then
		fastWait = math.max(0, fastWait + FAST)
	end
	local shown = host:IsVisible()
	if box and look.sky and shown then
		if not moving then
			Hide(parts.streak)
		else
			if slow then
				DrawSky()
			end
			if fast then
				DrawStreak()
			end
		end
	elseif not shown then
		Hide(parts.streak) -- not left hanging mid-flight for when the tracker shows again
	end
	if fast then
		DrawGleam(moving and shown)
	end
	if next(litBars) then
		if viewWait <= 0 then
			viewWait = VIEW_CHECK
			CheckView()
		end
		DrawBarLight(moving, slow, fast)
	end
	if fast then
		DrawBloom(bloomTime)
		bloomTime = 0
	end
	if not Busy(moving) then
		Stop()
	elseif fast and OnlySweepMoves() then
		local rest = SweepResting()
		if rest and rest > 0.2 then
			HideGleam()
			Sleep(rest)
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- The header. Moonlit silver (lookTitle): a silver title, and the bar's line becomes a silver rule fading at both ends
-- with a small star at its middle. Gold bar: the game's own bar.
------------------------------------------------------------------------------------------------------------------------
local header -- the Quests bar (Frame.lua), styled once it exists

local function HeaderParts()
	if header.qcMoon then
		return header.qcMoon
	end
	local moon = {}
	moon.left = header:CreateTexture(nil, "BORDER")
	moon.right = header:CreateTexture(nil, "BORDER")
	moon.star = header:CreateTexture(nil, "ARTWORK", nil, 1)
	moon.star:SetTexture(MEDIA .. "MoonStar")
	moon.star:SetSize(13, 13)
	moon.star:SetPoint("CENTER", header, "BOTTOM", 0, 0)
	moon.left:SetHeight(1)
	moon.right:SetHeight(1)
	moon.left:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0)
	moon.left:SetPoint("BOTTOMRIGHT", header, "BOTTOM", -5, 0)
	moon.right:SetPoint("BOTTOMLEFT", header, "BOTTOM", 5, 0)
	moon.right:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0)
	moon.all = { moon.left, moon.right, moon.star }
	header.qcMoon = moon
	return moon
end

-- While a search is open its bar has its own line, so the moonlit rule and its star fade out as the
-- search bar fades in (`shown` is 1 with no search, 0 with the bar fully in). FrameBorder.lua calls this as it fades.
function F.FadeMoonHeader(shown)
	local moon = header and header.qcMoon
	if not moon then
		return
	end
	for _, texture in ipairs(moon.all) do
		texture:SetAlpha(shown)
	end
end

local function StyleHeader()
	header = header or F.header
	if not header then
		return
	end
	local moonlit = look.title == "moonlit"
	if header.art then
		header.art:SetShown(not moonlit)
	end
	local title = header.title
	if moonlit then
		title:SetTextColor(HEADER_TINT[1], HEADER_TINT[2], HEADER_TINT[3])
	else
		title:SetTextColor(F.TITLE_GOLD.r, F.TITLE_GOLD.g, F.TITLE_GOLD.b)
	end
	if not moonlit then
		if header.qcMoon then
			for _, texture in ipairs(header.qcMoon.all) do
				texture:Hide()
			end
		end
		return
	end
	local moon = HeaderParts()
	local edge = 0.5 + 0.4 * look.strength
	-- The two halves fade out towards the ends.
	Q.Fade(moon.left, "HORIZONTAL", F.MOON.rule, 0, edge)
	Q.Fade(moon.right, "HORIZONTAL", F.MOON.rule, edge, 0)
	moon.star:SetVertexColor(1, 1, 1, 0.6 + 0.4 * look.strength)
	for _, texture in ipairs(moon.all) do
		texture:Show()
	end
	F.FadeMoonHeader(1 - F.SearchStripAlpha())
end

------------------------------------------------------------------------------------------------------------------------
-- Reading the settings, and laying the pieces out for the panel's size
------------------------------------------------------------------------------------------------------------------------
-- Called by FrameBorder.lua after each repaint. `pad` is the padding, `sky` whether the panel shows and `border`
-- whether the line does. Each part reads its own look setting (Q.Look), so parts from any theme mix.
function F.PaintMoonglow(pad, sky, border)
	if not host then
		return
	end
	local Look = Q.Look
	look.pad = pad or 0
	look.sky = sky and true or false
	look.border = border and true or false
	look.strength = F.MoonStrength()
	look.title = Look("lookTitle")
	look.silver = Look("borderFinish") == "moonsilver"
	-- Moonlit corner accents and the moon crest sit on the frame's edge, so they need the line.
	local ornament = Look("borderOrnament")
	look.corners = (look.border and CORNER_FILES[ornament]) and ornament or "off"
	local crest = Look("lookCrest")
	look.crest = not look.border and "off" or crest == "crescent" and "crescent" or crest == "tonight" and "live" or "off"
	look.gleam = Look("moonGleam")
	look.bloom = Look("moonBloom") and true or false
	look.stars = look.sky and Look("moonStars") and true or false
	look.shooting = look.sky and Look("moonShooting") and true or false
	look.aurora = look.sky and Look("moonAurora") and true or false
	look.mist = look.sky and Look("moonMist") and true or false
	look.beam = look.sky and Look("moonBeam") and true or false
	if not look.shooting then
		streak = nil
	end
	-- Lit dots take the new tint and strength when next lit, and everything is laid out again.
	HideGleam()
	repaint = true
	StyleHeader()
end

-- Called by FrameBorder.lua with the panel's place and size whenever it is laid out (on every step of a height ease).
function F.LayoutMoonglow(x0, y0, width, height, radius)
	if not host then
		return
	end
	local full = repaint
	local moved = not box or box.x0 ~= x0 or box.y0 ~= y0 or box.width ~= width or box.height ~= height
		or box.radius ~= radius
	if not (full or moved) then
		return
	end
	repaint = false
	local top = full or not box or box.x0 ~= x0 or box.y0 ~= y0 or box.width ~= width
	if moved then
		box = box or { bounds = {} }
		box.x0, box.y0, box.width, box.height, box.radius = x0, y0, width, height, radius
		box.per = 2 * (width + height - 4 * radius) + 2 * math.pi * radius
		local inset = math.ceil(radius * 0.3)
		local bounds = box.bounds
		bounds[1], bounds[2], bounds[3], bounds[4] = x0 + inset, y0 + inset, x0 + width - inset, y0 + height - inset
		layouts = layouts + 1
	end
	PlaceCorners(full)
	if top then
		PlaceCrest()
	end
	if look.sky then
		LayoutSky()
		DrawSky() -- the moving parts follow the new size at once, not at the clock's next slow tick
	else
		HideSky()
	end
	if full then
		DrawGleam(Q.Motion.On() and host:IsVisible()) -- lit again in its new tint straight away
	elseif moved and (GLEAM[1].count > 0 or GLEAM[2].count > 0) then
		SampleBorder()
	end
	F.StartMoonglow()
end
