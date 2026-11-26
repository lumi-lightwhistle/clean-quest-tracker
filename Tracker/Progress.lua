-- Thin rounded progress bars under counted objectives, with an eased fill animation when progress changes. In the
-- Segmented style (Quests page) a bar is cut into one segment per item the objective needs. The look (Appearance page)
-- picks the bar's colour and its effect: Flat, Crescent tip, Eclipse, Moontide or Polished glass.

local _, Q = ...
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\Bar"
local DURATION = 0.32
local TRACK = { r = 0.08, g = 0.12, b = 0.17, a = 0.8 }
local SEGMENTS_MAX = 30 -- objectives needing more items than this keep a smooth bar
local SEGMENT_MIN = 4 -- nor is a bar cut so fine that a segment and its gap are under this many pixels wide
local GAP_MAX = 3 -- the gap between segments: 3 pixels, or a fifth of each item's share of the bar if less (at least 1)
local LIT_TRACK = { r = 0.11, g = 0.15, b = 0.26, a = 0.85 } -- the track under every effect but Flat, a little lighter
-- so the empty part still reads on a dark sky
local GLEAM_HALF, GLEAM_SPEED = 20, 60 -- Polished glass's gleam: its half width and its speed, in pixels
local GLEAM_REST = 4 -- seconds between one gleam and the next
local TIDE_SPACING, TIDE_PERIOD = 46, 2.4 -- Moontide: pixels between wave crests, and seconds for a crest to move one
-- Each effect, and whether it moves (so it asks for a clock).
local EFFECTS = { flat = {}, crescent = { moving = true }, eclipse = {}, tide = { moving = true }, glass = { moving = true } }
local GLOW_FILE = "Interface\\AddOns\\CleanQuestTracker\\Media\\BackdropGlow"
-- Moontide's waves on a smooth fill: one crest per tile, brightest at its middle and fading to nothing a third of a
-- tile either side (tools/border.py); a tile is TIDE_SPACING pixels on screen.
local WAVE_FILE = "Interface\\AddOns\\CleanQuestTracker\\Media\\BarWave"

-- Finished quests and full bars: the Finished quests colour from the Colours page (the game's green by default).
function Q.CompleteColor()
	return Q.Color("colorDone")
end

local function Pieces(parent, layer)
	local pieces = {}
	for index, name in ipairs({ "Left", "Middle", "Right" }) do
		pieces[index] = parent:CreateTexture(nil, layer)
		pieces[index]:SetTexture(MEDIA .. name)
	end
	return pieces
end

-- Paints a three-piece rounded bar `width` wide. Caps shrink for very short fills so the ends stay round.
local function Paint(pieces, width, height, r, g, b, a)
	if width < 0.05 or height <= 0 then
		for _, texture in ipairs(pieces) do
			texture:Hide()
		end
		return
	end
	local cap = math.min(height / 2, width / 2)
	for _, texture in ipairs(pieces) do
		texture:ClearAllPoints()
		texture:SetVertexColor(r, g, b, a or 1)
		texture:Show()
	end
	pieces[1]:SetPoint("TOPLEFT")
	pieces[1]:SetSize(cap, height)
	pieces[2]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT")
	pieces[2]:SetSize(math.max(0.01, width - 2 * cap), height)
	pieces[3]:SetPoint("TOPLEFT", pieces[2], "TOPRIGHT")
	pieces[3]:SetSize(cap, height)
	if width <= 2 * cap then
		pieces[2]:Hide()
		pieces[3]:ClearAllPoints()
		pieces[3]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT")
	end
end

-- How many segments the bar is cut into, or nil to draw it smooth. A preview bar (/cqt preview) sets its own style in
-- bar.qcPreview = { segmented, style }; every other bar follows the settings.
local function SegmentCount(bar, width)
	local total = bar.total
	local segmented = Q.db.barStyle == "segmented"
	if bar.qcPreview then
		segmented = bar.qcPreview.segmented
	end
	if not segmented or not total or total < 2 or total > SEGMENTS_MAX then
		return nil
	end
	if width / total < SEGMENT_MIN then -- leaves each segment at least 3 pixels after its gap
		return nil
	end
	return total
end

-- The bar effect (Appearance page; a preview bar sets its own): "flat", "crescent", "eclipse", "tide" or "glass".
local function BarEffect(bar)
	local effect = bar.qcPreview and bar.qcPreview.style or Q.Look("moonBars")
	return EFFECTS[effect] and effect or "flat"
end

-- The bar's colour: the Finished quests colour once full, else the look's bar colour (the Colours page's, or a theme
-- colour from Q.BAR_COLOURS).
local themeColours = {}
local function BarColor(bar)
	if bar.complete then
		return Q.CompleteColor()
	end
	local key = Q.Look("lookBarColour")
	local hex = Q.BAR_COLOURS[key]
	if not hex then
		return Q.Color("colorBar")
	end
	themeColours[key] = themeColours[key] or Q.ColorOf(hex)
	return themeColours[key]
end

local function Lighten(value, k)
	return value + (1 - value) * k
end

-- Colours one fill texture: flat, or for Polished glass lighter on top and a touch darker below; `k` (0 to 1) lifts it
-- towards white, for the light passing over it.
local function Shade(texture, r, g, b, glass, k)
	k = k or 0
	r, g, b = Lighten(r, k), Lighten(g, k), Lighten(b, k)
	if glass and Q.Gradient(texture, "VERTICAL", r * 0.8, g * 0.8, b * 0.8, 1, Lighten(r, 0.45), Lighten(g, 0.45),
		Lighten(b, 0.45), 1) then
		texture.qcGradient = true
		return
	end
	-- A gradient left from Polished glass is flattened first, in case a plain colour doesn't replace it on this client.
	if texture.qcGradient then
		Q.Gradient(texture, "VERTICAL", r, g, b, 1, r, g, b, 1)
		texture.qcGradient = nil
	end
	texture:SetVertexColor(r, g, b, 1)
end

-- The pieces of a bar's light show and hide through these (they remember whether they show), so resting light costs
-- nothing frame after frame.
local On, Off = Q.ShowPart, Q.HidePart

-- Paints `count` segments across `width`, `filled` (0 to 1) of the way; the one the fill ends in is drawn part way.
-- Segments are made as needed and kept with the bar. Fill segments keep their colour and centre (qcColor, qcCenter)
-- for the light that passes over them, and `glass` shades them as glass. qcShown says whether a segment shows.
local function PaintSegments(bar, list, layer, count, width, height, filled, r, g, b, a, glass)
	for index = #list + 1, count do
		list[index] = bar.inner:CreateTexture(nil, layer)
		list[index]:SetTexture(MEDIA .. "Middle")
	end
	-- Whole-unit gaps and edges, so every gap comes out the same width.
	local gap = count > 0 and math.max(1, math.floor(math.min(GAP_MAX, width / count * 0.2))) or 0
	local step = count > 0 and (width + gap) / count or 0
	for index, texture in ipairs(list) do
		local left = math.floor((index - 1) * step + 0.5)
		local right = math.min(math.floor(index * step - gap + 0.5), width)
		local part = math.max(0, math.min(1, filled * count - (index - 1)))
		local shown = index <= count and (right - left) * part or 0
		if shown > 0.05 then
			texture:ClearAllPoints()
			texture:SetPoint("TOPLEFT", left, 0)
			texture:SetSize(shown, height)
			if list == bar.fillSegments then
				Shade(texture, r, g, b, glass)
				texture.qcK = 0
				local base = texture.qcColor or {}
				base[1], base[2], base[3] = r, g, b
				texture.qcColor = base
				texture.qcCenter = left + shown / 2
				texture.qcLeft, texture.qcWidth = left, shown
			else
				texture:SetVertexColor(r, g, b, a or 1)
			end
			texture:Show()
			texture.qcShown = true
		else
			texture:Hide()
			texture.qcShown = false
		end
	end
end

-- A plain texture of the bar's, made on first use.
local function Part(bar, key, layer, sublevel, file)
	if not bar[key] then
		bar[key] = bar.inner:CreateTexture(nil, layer, nil, sublevel)
		if file then
			bar[key]:SetTexture(file)
		else
			bar[key]:SetColorTexture(1, 1, 1, 1)
		end
	end
	return bar[key]
end

-- The soft glow under a smooth fill, for Crescent tip, Eclipse and Moontide (under a segmented fill it would light the
-- gaps).
local function PaintGlow(bar, effect, fillWidth, height, color, segmented, strength)
	if effect == "flat" or effect == "glass" or fillWidth < 1 or segmented then
		if bar.glow then
			bar.glow:Hide()
		end
		return
	end
	local glow = Part(bar, "glow", "BACKGROUND", -2, GLOW_FILE)
	glow:SetVertexColor(Lighten(color.r, 0.2), Lighten(color.g, 0.2), Lighten(color.b, 0.2),
		(effect == "tide" and 0.55 or 0.4) * strength)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", -5, 5)
	glow:SetSize(fillWidth + 10, height + 10)
	glow:Show()
end

-- The thin light along the top of a smooth fill: Crescent tip's silver edge, Polished glass's gloss.
local function PaintEdge(bar, effect, fillWidth, height, strength)
	local on = (effect == "crescent" or effect == "glass") and height >= 3 and fillWidth > height
	if not on then
		if bar.qcEdge then
			bar.qcEdge:Hide()
		end
		return
	end
	local edge = Part(bar, "qcEdge", "ARTWORK", 3)
	local cap = height / 2
	if effect == "glass" then
		edge:SetColorTexture(1, 1, 1, 0.55 * strength)
	else
		edge:SetColorTexture(0.92, 0.95, 1, 0.5 * strength)
	end
	edge:ClearAllPoints()
	edge:SetPoint("TOPLEFT", cap, effect == "glass" and -1 or 0)
	edge:SetSize(math.max(0.01, fillWidth - 2 * cap), 1)
	edge:Show()
end

-- Eclipse's dark core, one pixel inside the fill (or each segment), so the bar colour shows as a rim round it.
local function PaintCores(bar, effect, fillWidth, height, color, segmented)
	local cores = bar.qcCores or {}
	bar.qcCores = cores
	local used = 0
	if effect == "eclipse" and height >= 3 then
		local function Core(left, width)
			if width <= 2 then
				return
			end
			used = used + 1
			local core = cores[used]
			if not core then
				core = bar.inner:CreateTexture(nil, "ARTWORK", nil, 2)
				core:SetColorTexture(1, 1, 1, 1)
				cores[used] = core
			end
			core:SetVertexColor(color.r * 0.14, color.g * 0.14, color.b * 0.18 + 0.02, 1)
			core:ClearAllPoints()
			core:SetPoint("TOPLEFT", left + 1, -1)
			core:SetSize(width - 2, height - 2)
			core:Show()
		end
		if segmented then
			for _, texture in ipairs(bar.fillSegments) do
				if texture.qcShown then
					Core(texture.qcLeft, texture.qcWidth)
				end
			end
		else
			Core(height / 2 - 1, fillWidth - height + 2)
		end
	end
	for index = used + 1, #cores do
		cores[index]:Hide()
	end
end

-- Hides a bar's bands of light from band `keep` + 1 on (bar.qcBandsUsed: how many may show).
local function HideBands(bar, keep)
	for index = keep + 1, bar.qcBandsUsed or 0 do
		Off(bar.qcBands[index][1])
		Off(bar.qcBands[index][2])
	end
	bar.qcBandsUsed = keep
end

-- Hides the light that moves over a bar: its bands, Moontide's waves and Crescent tip's point.
local function HideLight(bar)
	HideBands(bar, 0)
	if bar.qcWave then
		Off(bar.qcWave)
	end
	if bar.qcTip then
		Off(bar.qcTip)
	end
end

local function Draw(bar)
	local inner = bar.inner
	local width, height = inner:GetWidth(), inner:GetHeight()
	if not width or width <= 0 then
		return
	end
	local color = BarColor(bar)
	local display = bar.display or 0
	local count = SegmentCount(bar, width) or 0
	local effect = BarEffect(bar)
	local glass = effect == "glass"
	local track = effect == "flat" and TRACK or LIT_TRACK
	PaintSegments(bar, bar.trackSegments, "BACKGROUND", count, width, height, 1, track.r, track.g, track.b, track.a)
	PaintSegments(bar, bar.fillSegments, "ARTWORK", count, width, height, display, color.r, color.g, color.b, nil, glass)
	bar.qcSegmented = count > 0
	bar.qcFillWidth = width * display
	bar.qcEffect = effect
	local strength = effect ~= "flat" and Q.Frame.MoonStrength() or 1
	PaintGlow(bar, effect, width * display, height, color, count > 0, strength)
	-- Crescent tip, Moontide and Polished glass move on Moonglow's clock (FrameMoonglow.lua).
	local moving = EFFECTS[effect].moving and display > 0
	if bar.qcMoving ~= moving then
		bar.qcMoving = moving
		Q.Frame.WatchBarLight(bar, moving)
	end
	if not moving then
		HideLight(bar)
	else
		Q.Frame.BarLightNow(bar) -- the tip follows the fill at once, also while motion rests (combat, Animations off)
	end
	if count > 0 then
		Paint(bar.track, 0, height)
		Paint(bar.fill, 0, height)
		PaintEdge(bar, effect, 0, height, strength)
		PaintCores(bar, effect, 0, height, color, true)
		return
	end
	Paint(bar.track, width, height, track.r, track.g, track.b, track.a)
	Paint(bar.fill, width * display, height, color.r, color.g, color.b)
	for _, texture in ipairs(bar.fill) do
		Shade(texture, color.r, color.g, color.b, glass)
	end
	PaintEdge(bar, effect, width * display, height, strength)
	PaintCores(bar, effect, width * display, height, color, false)
end

-- One band of light at `x` over a smooth fill `fill` wide, `half` wide each side, at most `peak` bright: two textures,
-- each fading from nothing at its outer edge to `peak` in the middle, kept off the fill's round ends. Each half is
-- only anchored by its top-left corner, and shaded again only when its fade changes (at the fill's ends).
local function Band(bar, index, x, half, peak, fill, height)
	bar.qcBands = bar.qcBands or {}
	local band = bar.qcBands[index]
	if not band then
		band = { bar.inner:CreateTexture(nil, "OVERLAY"), bar.inner:CreateTexture(nil, "OVERLAY") }
		for _, texture in ipairs(band) do
			texture:SetColorTexture(1, 1, 1, 1)
			texture:Hide()
		end
		bar.qcBands[index] = band
	end
	local cap = math.min(height / 2, fill / 2)
	for side, texture in ipairs(band) do
		local from = side == 1 and x - half or x
		local to = from + half
		local left, right = math.max(cap, from), math.min(fill - cap, to)
		if right - left < 0.5 then
			Off(texture)
		else
			-- Brightest where the two halves meet, fading to nothing at the band's outer edges.
			local shareLeft, shareRight = (left - from) / half, (right - from) / half
			local a1 = peak * (side == 1 and shareLeft or 1 - shareLeft)
			local a2 = peak * (side == 1 and shareRight or 1 - shareRight)
			texture:SetPoint("TOPLEFT", left, 0)
			texture:SetSize(right - left, height)
			if texture.qcFrom ~= a1 or texture.qcTo ~= a2 then
				texture.qcFrom, texture.qcTo = a1, a2
				if not Q.Gradient(texture, "HORIZONTAL", 0.92, 0.96, 1, a1, 0.92, 0.96, 1, a2) then
					texture:SetVertexColor(0.92, 0.96, 1, (a1 + a2) / 2)
				end
			end
			On(texture)
		end
	end
end

-- Moontide on a smooth fill: the wave art repeated along the fill (kept off its round ends) and slid along it, one
-- texture whatever the fill's length. Returns false on a client that won't repeat a texture; the waves are then drawn
-- as bands.
local waveRepeats -- nil until tried
local function Wave(bar, t, fill, height, strength)
	if waveRepeats == false then
		return false
	end
	local wave = bar.qcWave
	if not wave then
		wave = bar.inner:CreateTexture(nil, "OVERLAY")
		wave:Hide()
		waveRepeats = pcall(wave.SetTexture, wave, WAVE_FILE, "REPEAT", "CLAMP") and true or false
		if not waveRepeats then
			return false
		end
		bar.qcWave = wave
	end
	local cap = math.min(height / 2, fill / 2)
	local left, right = cap, fill - cap
	if right - left < 0.5 then
		Off(wave)
		return true
	end
	if wave.qcLeft ~= left or wave.qcRight ~= right or wave.qcHeight ~= height then
		wave:SetPoint("TOPLEFT", left, 0)
		wave:SetSize(right - left, height)
		wave.qcLeft, wave.qcRight, wave.qcHeight = left, right, height
	end
	-- A crest every TIDE_SPACING pixels, a quarter spacing past each multiple of it, moving one spacing to the right
	-- every TIDE_PERIOD seconds; the crest is the middle of a tile.
	local u0 = (left - TIDE_SPACING / 4) / TIDE_SPACING - (t / TIDE_PERIOD % 1) + 0.5
	wave:SetTexCoord(u0, u0 + (right - left) / TIDE_SPACING, 0, 1)
	local alpha = 0.38 * strength
	if wave.qcAlpha ~= alpha then
		wave:SetVertexColor(0.92, 0.96, 1, alpha)
		wave.qcAlpha = alpha
	end
	On(wave)
	return true
end

-- The light that moves over a bar, for time `clock` (nil: motion is off, so it rests). Polished glass: one gleam along
-- the fill, then a rest. Moontide: waves rolling along the fill. Crescent tip: the point at the fill's end breathes.
-- On a segmented bar the segments the light passes brighten, so the gaps stay dark.
local function Light(bar, clock, strength)
	bar.qcPhase = bar.qcPhase or math.random() * 8 -- seconds, so bars don't all move together
	local fill = bar.qcFillWidth or 0
	local effect = bar.qcEffect
	if not (bar.qcMoving and fill > 1 and bar:IsVisible()) then
		HideLight(bar)
		return
	end
	local height = bar.inner:GetHeight()
	local t = clock and clock + bar.qcPhase
	-- Polished glass: where the gleam is (nil between gleams, or at rest).
	local gleam
	if effect == "glass" and t then
		local travel = fill + 3 * GLEAM_HALF
		local at = (t % (travel / GLEAM_SPEED + GLEAM_REST)) * GLEAM_SPEED
		gleam = at < travel and at - 1.5 * GLEAM_HALF or nil
	end
	-- Crescent tip: the point at the fill's end, breathing; not on a finished bar. Moved only when the fill moves.
	if effect == "crescent" and not bar.complete then
		local tip = bar.qcTip
		if not tip then
			tip = Part(bar, "qcTip", "OVERLAY", 1, GLOW_FILE)
			tip:SetBlendMode("ADD")
			tip:Hide()
		end
		local size = height * 3 + 8
		if tip.qcAt ~= fill or tip.qcSize ~= size then
			tip:SetPoint("CENTER", bar.inner, "LEFT", fill, 0)
			tip:SetSize(size, size)
			tip.qcAt, tip.qcSize = fill, size
		end
		local pulse = t and (0.7 + 0.3 * math.sin(t * 2 * math.pi / 2.6)) or 0.85
		tip:SetVertexColor(0.95, 0.97, 1, pulse * strength)
		On(tip)
	elseif bar.qcTip then
		Off(bar.qcTip)
	end
	if bar.qcSegmented then
		HideBands(bar, 0)
		if bar.qcWave then
			Off(bar.qcWave)
		end
		local peak = (effect == "tide" and 0.35 or 0.45) * strength
		local glass = effect == "glass"
		for _, texture in ipairs(bar.fillSegments) do
			local base = texture.qcColor
			if base and texture.qcShown then
				local k = 0
				if gleam then
					k = math.max(0, 1 - math.abs(texture.qcCenter - gleam) / GLEAM_HALF) * peak
				elseif effect == "tide" and t then
					local wave = math.sin((texture.qcCenter / TIDE_SPACING - t / TIDE_PERIOD) * 2 * math.pi) * 0.5 + 0.5
					k = wave * wave * peak
				end
				-- Only segments whose light changed are shaded again (most of a glass bar sits unlit between gleams).
				if not texture.qcK or math.abs(texture.qcK - k) > 0.01 then
					texture.qcK = k
					Shade(texture, base[1], base[2], base[3], glass, k)
				end
			end
		end
		return
	end
	local used, waving = 0, false
	if gleam then
		used = 1
		Band(bar, 1, gleam, GLEAM_HALF, 0.55 * strength, fill, height)
	elseif effect == "tide" and t then
		waving = Wave(bar, t, fill, height, strength)
		if not waving then
			-- Moontide without the repeating art: a band for each crest, every TIDE_SPACING pixels, rolling right.
			local offset = (t / TIDE_PERIOD % 1) * TIDE_SPACING
			for x = offset - TIDE_SPACING, fill + TIDE_SPACING, TIDE_SPACING do
				used = used + 1
				Band(bar, used, x + TIDE_SPACING / 4, TIDE_SPACING / 3, 0.38 * strength, fill, height)
			end
		end
	end
	HideBands(bar, used)
	if not waving and bar.qcWave then
		Off(bar.qcWave)
	end
end

local function Animate(bar, elapsed)
	bar.elapsed = math.min(DURATION, (bar.elapsed or 0) + elapsed)
	local t = bar.elapsed / DURATION
	local ease = 1 - (1 - t) ^ 3
	bar.display = bar.start + (bar.target - bar.start) * ease
	Draw(bar)
	if t >= 1 then
		bar.display = bar.target
		bar:SetScript("OnUpdate", nil)
	end
end

-- A bar frame spans its objective line; the visible track sits inside it, inset to line up with the text.
function Q.NewProgressBar(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar.inner = CreateFrame("Frame", nil, bar)
	bar.inner:SetAllPoints()
	bar.track = Pieces(bar.inner, "BACKGROUND")
	bar.fill = Pieces(bar.inner, "ARTWORK")
	bar.trackSegments, bar.fillSegments = {}, {}
	bar.qcLight = Light
	bar.inner:SetScript("OnSizeChanged", function()
		Draw(bar)
	end)
	bar:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		-- A hidden bar (freed with its quest, in a folded zone, or the tracker hidden) stops asking for Moonglow's clock,
		-- and asks again when it shows.
		if self.qcMoving then
			Q.Frame.WatchBarLight(self, false)
			HideLight(self)
		end
		if self.target then
			self.display = self.target
		end
	end)
	bar:SetScript("OnShow", function(self)
		if self.qcMoving then
			Q.Frame.WatchBarLight(self, true)
			Q.Frame.BarLightNow(self) -- its light was hidden with it; while motion rests the clock won't redraw it
		end
	end)
	return bar
end

function Q.SetBarInset(bar, left, right)
	bar.inner:ClearAllPoints()
	bar.inner:SetPoint("TOPLEFT", left or 0, 0)
	bar.inner:SetPoint("BOTTOMRIGHT", -(right or 0), 0)
end

-- `key` identifies what the bar shows. A new key snaps to the value; the same key animates from where it was.
function Q.SetBarProgress(bar, key, count, total, complete)
	local target = math.max(0, math.min(1, (count or 0) / math.max(total or 1, 1)))
	if bar.key ~= key or bar.display == nil then
		bar.display, bar.target, bar.key, bar.elapsed = target, target, key, DURATION
	elseif target ~= bar.target then
		bar.start, bar.target, bar.elapsed = bar.display, target, 0
	end
	bar.complete = complete
	bar.total = total
	Draw(bar)
	if bar.display ~= bar.target then
		bar:SetScript("OnUpdate", Animate)
	else
		bar:SetScript("OnUpdate", nil)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- /cqt preview: every bar effect side by side (Flat, Crescent tip, Eclipse, Moontide and Polished glass, each smooth and
-- segmented), on the plain panel or Moonglow's night sky, to compare them and check the animation without doing a
-- quest. The bars use your look's bar colour, your thickness and Glow strength; their light moves on Moonglow's clock
-- like the tracker's, whatever the look (and rests in combat and with Animations set to None).
------------------------------------------------------------------------------------------------------------------------
local PREVIEW_STYLES = { { "flat", "Flat" }, { "crescent", "Crescent tip" }, { "eclipse", "Eclipse" },
	{ "tide", "Moontide" }, { "glass", "Polished glass" } }
local PREVIEW_TOTAL = 10 -- items each preview bar needs, so the segmented ones show ten segments

function Q.PreviewProgress()
	if Q.preview then
		Q.preview:Refresh()
		Q.preview:Show()
		return
	end
	local labelWidth, barWidth, gap, rowHeight = 80, 190, 24, 34
	local width = 20 + labelWidth + barWidth * 2 + gap + 20
	local frame = CreateFrame("Frame", "CleanQuestTrackerBarPreview", UIParent, "BasicFrameTemplateWithInset")
	Q.preview = frame
	frame:SetSize(width, 72 + 24 + #PREVIEW_STYLES * rowHeight + 20 + 56)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText("Progress bar preview")

	-- The two backgrounds behind the bars: the plain panel, and Moonglow's Midnight sky.
	local skies = {}
	for index, key in ipairs({ "current", "midnight" }) do
		local stage = CreateFrame("Frame", nil, frame)
		stage:SetPoint("TOPLEFT", 12, -64)
		stage:SetPoint("TOPRIGHT", -12, -64)
		stage:SetHeight(24 + #PREVIEW_STYLES * rowHeight + 16)
		Q.Frame.ThemeSample(stage, key, width - 24, stage:GetHeight())
		stage:SetShown(index == 1)
		skies[index] = stage
	end
	local skyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	skyButton:SetPoint("TOPRIGHT", -14, -32)
	skyButton:SetSize(150, 22)
	local function ShowSky(night)
		skies[1]:SetShown(not night)
		skies[2]:SetShown(night)
		skyButton:SetText(night and "Plain background" or "Moonglow sky")
	end
	skyButton:SetScript("OnClick", function()
		ShowSky(not skies[2]:IsShown())
	end)
	ShowSky(false)

	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(skies[1])
	holder:SetFrameLevel(skies[2]:GetFrameLevel() + 5)
	local function Label(text, template, point, x, y)
		local label = holder:CreateFontString(nil, "OVERLAY", template)
		label:SetPoint(point, holder, "TOPLEFT", x, y)
		label:SetText(text)
		return label
	end
	Label("Smooth", "GameFontNormalSmall", "TOPLEFT", 8 + labelWidth, -8)
	Label("Segmented", "GameFontNormalSmall", "TOPLEFT", 8 + labelWidth + barWidth + gap, -8)
	local bars = {}
	local height = Q.db.barHeight or 3
	for row, entry in ipairs(PREVIEW_STYLES) do
		local y = -24 - (row - 1) * rowHeight - 12
		Label(entry[2], "GameFontHighlightSmall", "LEFT", 8, y)
		for column = 1, 2 do
			local bar = Q.NewProgressBar(holder)
			bar.qcPreview = { style = entry[1], segmented = column == 2 }
			bar:SetSize(barWidth, height)
			bar:SetPoint("LEFT", holder, "TOPLEFT", 8 + labelWidth + (column - 1) * (barWidth + gap), y)
			bars[#bars + 1] = bar
		end
	end

	local count = 3
	local function Set()
		for _, bar in ipairs(bars) do
			Q.SetBarProgress(bar, "preview", count, PREVIEW_TOTAL, count == PREVIEW_TOTAL)
		end
	end
	-- Opening it again picks up a changed bar thickness or colour.
	function frame:Refresh()
		for _, bar in ipairs(bars) do
			bar:SetHeight(Q.db.barHeight or 3)
		end
		Set()
	end
	Set()
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetPoint("BOTTOM", 0, 18)
	button:SetSize(150, 25)
	button:SetText("Add progress")
	button:SetScript("OnClick", function()
		count = count >= PREVIEW_TOTAL and 0 or count + 1
		Set()
	end)

	tinsert(UISpecialFrames, "CleanQuestTrackerBarPreview")
end
