-- Clean Quest Tracker: the frame's backdrop. The dark panel behind the list (square or with rounded corners, padded
-- out from the list, plain or in a background theme), and the optional bronze border with its corner flourishes and
-- the crest on the header.
--
-- Everything here is drawn on the tracker's own frame from the add-on's own textures (Media\Border*, made by
-- tools/border.py), never on Blizzard's tracker. The padding grows the panel and border outward, so the list itself
-- never moves. Each piece is placed from the frame's current size, so it follows the height while it eases. These are
-- plain textures, not secure frames, so repainting them in combat is safe.

local _, Q = ...
local F = Q.Frame

local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"
local PANEL = { 0.03, 0.04, 0.06 }

-- The ranges of the sliders for these settings (OptionsPages.lua reads them from here).
F.BACKDROP_LIMITS = { padding = { 0, 16 }, cornerSize = { 2, 14 }, flourishSize = { 0.75, 1.5 } }

-- The padding and rounded corners belong to the background and the border, so they apply only while one shows.
function F.Framed()
	return (Q.db.backdrop or Q.db.border) and true or false
end

------------------------------------------------------------------------------------------------------------------------
-- The look: line weights, finishes and the layers of the line
------------------------------------------------------------------------------------------------------------------------
local WEIGHTS = { fine = 1.5, standard = 2.5, heavy = 3.5 }

-- Each finish's five colours, as the approved preview has them. tools/border.py colours the flourish and crest
-- textures with the same ones.
local FINISHES = {
	polished = { file = "Polished", "f6e0ac", "c99456", "7b4b23", "d9a86a", "6a4120" },
	aged = { file = "Aged", "dcc79b", "a7884f", "5d4a2f", "a18a5a", "463624" },
	dark = { file = "Dark", "c48e5c", "80552f", "3a2412", "704828", "24160a" },
}

-- The line's metal runs diagonally across the frame, light at the top left: which finish colour, and where.
local STOPS = { { 1, 0 }, { 2, 0.18 }, { 3, 0.42 }, { 4, 0.6 }, { 2, 0.8 }, { 5, 1 } }
local SEGMENTS = 6 -- pieces per edge, each shaded from one point of that gradient to the next

-- The quarter-ring atlas (see tools/border.py): 32 rings in 64px cells, 8 across; cell i has inner/outer radius i/32.
local RING = { file = MEDIA .. "BorderRing", width = 512, height = 256, cell = 64, region = 62, across = 8, steps = 32 }

------------------------------------------------------------------------------------------------------------------------
-- Background themes (Extras page, Experimental). Each is the panel's colour at its top and bottom (it fades between
-- them), how much more opaque than the Background darkness the bottom is, and any extras: a soft glow from the top
-- centre and faint stars. They only colour the background: quest text keeps its colours. "current" is the plain
-- panel players have always had.
------------------------------------------------------------------------------------------------------------------------
F.THEMES = {
	current = { top = PANEL, bottom = PANEL, deepen = 0 },
	moonglow = {
		top = { 10 / 255, 16 / 255, 32 / 255 },
		bottom = { 5 / 255, 8 / 255, 18 / 255 },
		deepen = 0.08,
		glow = { 170 / 255, 210 / 255, 1, 0.10 },
		stars = true,
	},
}
-- The glow (Media\BackdropGlow, an ellipse fading out to its edge): its radii as shares of the panel's width and
-- height, centred across and this share of the height above the top edge. Only the part inside the panel is drawn.
local GLOW = { file = MEDIA .. "BackdropGlow", across = 0.7, down = 0.55, above = 0.1 }
-- The stars (Media\BackdropStars): a 128px tile repeated over the panel.
local STARS = { file = MEDIA .. "BackdropStars", tile = 128 }

-- The flourish texture covers art units -16..52 from the corner; the crest -32..32 across and -16..16 down. One unit
-- is one pixel at 100% flourish size.
local FLOURISH_SPAN, FLOURISH_BEFORE = 68, 16
local FLOURISH_ROOM = 98 -- a side shorter than this many units shrinks the flourishes (each reaches 48.5 along it)
-- CREST_REACH: how far the crest's art reaches below its centre, edge softening included.
local CREST_WIDTH, CREST_HEIGHT, CREST_REACH = 64, 32, 9.5

local function Hex(value)
	local function Byte(from)
		return tonumber(value:sub(from, from + 1), 16) / 255
	end
	return { Byte(1), Byte(3), Byte(5) }
end

-- The line is four layers, centred on the panel's edge (offset: towards the outside, in pixels). A dark seat under
-- the metal, the metal, a dark bevel along its outside and a soft catch-light along its inside.
local function Layers(weight)
	local bevel = weight / 2 + 0.2
	return {
		{ offset = 0, width = weight + 3, color = { 10 / 255, 6 / 255, 2 / 255, 0.85 } },
		{ offset = 0, width = weight, metal = true },
		{ offset = bevel, width = 1.1, color = { 20 / 255, 12 / 255, 4 / 255, 0.9 } },
		{ offset = -bevel, width = 1.1, color = { 1, 232 / 255, 186 / 255, 0.3 } },
	}
end

------------------------------------------------------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------------------------------------------------------
local host
local panel = {} -- middle, left, right, corners = { 4 }, glow, stars
local line = {} -- one entry per layer: { corners = { 4 }, edges = { top, bottom, left, right = { pieces } } }
local flourishes = {}
local crest
local look = { darkness = 0, pad = 0, radius = 0, border = false }
local blank = false -- nothing is drawn and every piece is already hidden
local gradients -- nil until the first gradient call; false once the client refuses one

-- Places a texture by its top-left corner, in pixels right of and below the top-left corner of `anchor` (the
-- tracker's frame unless given).
local function Place(texture, x, y, width, height, anchor)
	if width <= 0.01 or height <= 0.01 then
		texture:Hide()
		return
	end
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchor or host, "TOPLEFT", x, -y)
	texture:SetSize(width, height)
	texture:Show()
end

local function HideAll(list)
	for _, texture in ipairs(list) do
		texture:Hide()
	end
end

-- Corners in the order top-left, top-right, bottom-left, bottom-right. Mirroring the texture coordinates turns the
-- top-left art into the others.
local FLIP = { { false, false }, { true, false }, { false, true }, { true, true } }

local function Mirror(texture, corner, left, right, top, bottom)
	local flip = FLIP[corner]
	if flip[1] then
		left, right = right, left
	end
	if flip[2] then
		top, bottom = bottom, top
	end
	texture:SetTexCoord(left, right, top, bottom)
end

-- Points a corner texture at the quarter ring with the nearest inner/outer ratio.
local function SetRing(texture, corner, ratio)
	local index = math.max(0, math.min(RING.steps - 1, math.floor(ratio * RING.steps + 0.5)))
	local left = (index % RING.across) * RING.cell
	local top = math.floor(index / RING.across) * RING.cell
	Mirror(texture, corner, left / RING.width, (left + RING.region) / RING.width, top / RING.height,
		(top + RING.region) / RING.height)
end

-- A two-colour gradient (each colour's fourth value is its opacity, 1 if left out); a client that refuses it gets the
-- average colour (and isn't asked again).
local function Shade(texture, orientation, from, to)
	local fromAlpha, toAlpha = from[4] or 1, to[4] or 1
	texture:SetColorTexture(1, 1, 1, 1)
	local ok = gradients ~= false and CreateColor and pcall(texture.SetGradient, texture, orientation,
		CreateColor(from[1], from[2], from[3], fromAlpha), CreateColor(to[1], to[2], to[3], toAlpha))
	gradients = ok and true or false
	if not ok then
		texture:SetColorTexture((from[1] + to[1]) / 2, (from[2] + to[2]) / 2, (from[3] + to[3]) / 2,
			(fromAlpha + toAlpha) / 2)
	end
end

-- A theme's panel colour and opacity `share` of the way down the panel (0 at the top, 1 at the bottom).
local function PanelColor(theme, alpha, share)
	local top, bottom = theme.top, theme.bottom
	return { top[1] + (bottom[1] - top[1]) * share, top[2] + (bottom[2] - top[2]) * share,
		top[3] + (bottom[3] - top[3]) * share, math.min(1, alpha + theme.deepen * share) }
end

-- Fills a piece of the panel that runs from `from` to `to` (shares of the panel's height). The plain panel stays one
-- flat colour, exactly as before themes.
local function FillPanel(texture, theme, alpha, from, to)
	if theme.deepen == 0 and theme.top == theme.bottom then
		texture:SetColorTexture(theme.top[1], theme.top[2], theme.top[3], alpha)
	else
		Shade(texture, "VERTICAL", PanelColor(theme, alpha, to), PanelColor(theme, alpha, from))
	end
end

-- A theme's glow and stars over a panel at (x0, y0), width by height, from `anchor`'s top-left corner. The stars keep
-- `inset` pixels in from the edge, which keeps them inside rounded corners.
local function PaintExtras(theme, glow, stars, anchor, x0, y0, width, height, inset)
	if theme.glow then
		-- It spans the panel's full width, so it also reaches the cut-outs beside rounded top corners, where it is under
		-- 3% opaque: too faint to see, so it isn't cut to their shape.
		glow:SetVertexColor(theme.glow[1], theme.glow[2], theme.glow[3], theme.glow[4])
		Place(glow, x0, y0, width, height * (GLOW.down - GLOW.above), anchor)
	else
		glow:Hide()
	end
	if theme.stars and stars.tiles then
		local w, h = width - 2 * inset, height - 2 * inset
		stars:SetTexCoord(0, w / STARS.tile, 0, h / STARS.tile)
		Place(stars, x0 + inset, y0 + inset, w, h, anchor)
	else
		stars:Hide()
	end
end

-- The stars texture, repeated (its texture coordinates run past 1) rather than stretched. If the client refuses the
-- repeat setting, the theme goes without stars rather than showing one stretched tile.
local function StarsTexture(owner, sublevel)
	local stars = owner:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	stars.tiles = pcall(stars.SetTexture, stars, STARS.file, "REPEAT", "REPEAT") and true or false
	stars:Hide()
	return stars
end

-- The glow texture, cropped to the part of its ellipse inside the panel: the ellipse's box in shares of the panel's
-- width and height, as texture coordinates.
local function GlowTexture(owner, sublevel)
	local glow = owner:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	glow:SetTexture(GLOW.file)
	local left, top = 0.5 - GLOW.across, -GLOW.above - GLOW.down
	glow:SetTexCoord(-left / (2 * GLOW.across), (1 - left) / (2 * GLOW.across), -top / (2 * GLOW.down), 1)
	glow:Hide()
	return glow
end

-- The metal's colour at a point of the panel (x, y from its top-left corner; it is width by height).
local function Metal(x, y, width, height)
	local t = (x * width + y * height) / (width * width + height * height)
	t = math.max(0, math.min(1, t))
	local stops = look.stops
	for index = 2, #stops do
		local stop = stops[index]
		if t <= stop[2] then
			local before = stops[index - 1]
			local k = (t - before[2]) / math.max(stop[2] - before[2], 1e-6)
			local a, b = before[1], stop[1]
			return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
		end
	end
	return stops[#stops][1]
end

------------------------------------------------------------------------------------------------------------------------
-- Building the pieces
------------------------------------------------------------------------------------------------------------------------
local function RingTexture(layer, sublevel)
	local texture = host:CreateTexture(nil, layer, nil, sublevel)
	texture:SetTexture(RING.file)
	texture:Hide()
	return texture
end

local function Plain(layer, sublevel)
	local texture = host:CreateTexture(nil, layer, nil, sublevel)
	texture:Hide()
	return texture
end

function F.CreateBackdrop(frame)
	host = frame
	panel.corners = {}
	for corner = 1, 4 do
		panel.corners[corner] = RingTexture("BACKGROUND", -8)
	end
	panel.middle, panel.left, panel.right = Plain("BACKGROUND", -8), Plain("BACKGROUND", -8), Plain("BACKGROUND", -8)
	panel.glow, panel.stars = GlowTexture(host, -7), StarsTexture(host, -6)
	for index = 1, 4 do
		local layer = { corners = {}, edges = {} }
		for corner = 1, 4 do
			layer.corners[corner] = RingTexture("BORDER", index)
		end
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			local pieces = {}
			for piece = 1, SEGMENTS do
				pieces[piece] = Plain("BORDER", index)
			end
			layer.edges[side] = pieces
		end
		line[index] = layer
	end
	for corner = 1, 4 do
		flourishes[corner] = Plain("ARTWORK", 1)
	end
	crest = Plain("ARTWORK", 2)
end

------------------------------------------------------------------------------------------------------------------------
-- Painting: the panel, the line, the flourishes and the crest. x0, y0 is the panel's top-left corner (below and right
-- of the frame's own), width and height its size, radius its corners (0 for square).
------------------------------------------------------------------------------------------------------------------------
local function PaintPanel(x0, y0, width, height, radius)
	local alpha, theme = look.darkness, look.theme
	local parts = { panel.middle, panel.left, panel.right, panel.glow, panel.stars }
	if alpha <= 0 then
		HideAll(parts)
		HideAll(panel.corners)
		return
	end
	PaintExtras(theme, panel.glow, panel.stars, host, x0, y0, width, height, math.ceil(radius * 0.3))
	if radius <= 0 then
		FillPanel(panel.middle, theme, alpha, 0, 1)
		Place(panel.middle, x0, y0, width, height)
		panel.left:Hide()
		panel.right:Hide()
		HideAll(panel.corners)
		return
	end
	local inner = radius / height -- where the side strips start and end, as shares of the height
	FillPanel(panel.middle, theme, alpha, 0, 1)
	FillPanel(panel.left, theme, alpha, inner, 1 - inner)
	FillPanel(panel.right, theme, alpha, inner, 1 - inner)
	Place(panel.middle, x0 + radius, y0, width - 2 * radius, height)
	Place(panel.left, x0, y0 + radius, radius, height - 2 * radius)
	Place(panel.right, x0 + width - radius, y0 + radius, radius, height - 2 * radius)
	local right, bottom = x0 + width - radius, y0 + height - radius
	local spots = { { x0, y0 }, { right, y0 }, { x0, bottom }, { right, bottom } }
	for corner, texture in ipairs(panel.corners) do
		SetRing(texture, corner, 0)
		local color = PanelColor(theme, alpha, corner <= 2 and inner / 2 or 1 - inner / 2)
		texture:SetVertexColor(color[1], color[2], color[3], color[4])
		Place(texture, spots[corner][1], spots[corner][2], radius, radius)
	end
end

-- One straight run of a layer. The metal is cut into pieces, each shaded along the frame's diagonal gradient; the
-- other layers are one flat piece. `frame` (the panel's x0, y0, width and height) places a point on the gradient.
local function Run(pieces, layer, x, y, width, height, vertical, frame)
	if not layer.metal then
		local color = layer.color
		pieces[1]:SetColorTexture(color[1], color[2], color[3], color[4])
		Place(pieces[1], x, y, width, height)
		for index = 2, #pieces do
			pieces[index]:Hide()
		end
		return
	end
	local length = vertical and height or width
	local step = length / #pieces
	for index, texture in ipairs(pieces) do
		local from = (index - 1) * step
		if vertical then
			local cx = x + width / 2 - frame.x0
			local top = Metal(cx, y + from - frame.y0, frame.width, frame.height)
			local bottom = Metal(cx, y + from + step - frame.y0, frame.width, frame.height)
			Shade(texture, "VERTICAL", bottom, top)
			Place(texture, x, y + from, width, step)
		else
			local cy = y + height / 2 - frame.y0
			local left = Metal(x + from - frame.x0, cy, frame.width, frame.height)
			local right = Metal(x + from + step - frame.x0, cy, frame.width, frame.height)
			Shade(texture, "HORIZONTAL", left, right)
			Place(texture, x + from, y, step, height)
		end
	end
end

local function PaintLine(x0, y0, width, height, radius)
	for index, layer in ipairs(line) do
		local spec = look.layers and look.layers[index]
		if not look.border or not spec then
			HideAll(layer.corners)
			for _, pieces in pairs(layer.edges) do
				HideAll(pieces)
			end
		else
			-- a: how far the layer reaches outside the panel's edge; b: where it starts (negative is inside).
			local a, b = spec.offset + spec.width / 2, spec.offset - spec.width / 2
			local thick = a - b
			local frame = { x0 = x0, y0 = y0, width = width, height = height }
			local edges = layer.edges
			if radius > 0 then
				local outer = radius + a
				local ratio = math.max(0, radius + b) / outer
				local right, bottom = x0 + width - radius, y0 + height - radius
				local spots = { { x0 - a, y0 - a, 0, 0 }, { right, y0 - a, width, 0 }, { x0 - a, bottom, 0, height },
					{ right, bottom, width, height } }
				for corner, texture in ipairs(layer.corners) do
					local spot = spots[corner]
					SetRing(texture, corner, ratio)
					if spec.metal then
						local color = Metal(spot[3], spot[4], width, height)
						texture:SetVertexColor(color[1], color[2], color[3], 1)
					else
						texture:SetVertexColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
					end
					Place(texture, spot[1], spot[2], outer, outer)
				end
				Run(edges.top, spec, x0 + radius, y0 - a, width - 2 * radius, thick, false, frame)
				Run(edges.bottom, spec, x0 + radius, y0 + height + b, width - 2 * radius, thick, false, frame)
				Run(edges.left, spec, x0 - a, y0 + radius, thick, height - 2 * radius, true, frame)
				Run(edges.right, spec, x0 + width + b, y0 + radius, thick, height - 2 * radius, true, frame)
			else
				HideAll(layer.corners)
				Run(edges.top, spec, x0 - a, y0 - a, width + 2 * a, thick, false, frame)
				Run(edges.bottom, spec, x0 - a, y0 + height + b, width + 2 * a, thick, false, frame)
				Run(edges.left, spec, x0 - a, y0 - b, thick, height + 2 * b, true, frame)
				Run(edges.right, spec, x0 + width + b, y0 - b, thick, height + 2 * b, true, frame)
			end
		end
	end
end

local function PaintOrnaments(x0, y0, width, height)
	if not (look.border and look.flourish) then
		HideAll(flourishes)
	else
		-- On a short frame (minimised, say) the flourishes shrink so the curls of opposite corners never meet.
		local scale = math.min(look.flourishSize, width / FLOURISH_ROOM, height / FLOURISH_ROOM)
		local size, before = FLOURISH_SPAN * scale, FLOURISH_BEFORE * scale
		local after = size - before
		local spots = { { x0 - before, y0 - before }, { x0 + width - after, y0 - before },
			{ x0 - before, y0 + height - after }, { x0 + width - after, y0 + height - after } }
		for corner, texture in ipairs(flourishes) do
			Place(texture, spots[corner][1], spots[corner][2], size, size)
		end
	end
	if not (look.border and look.crest) then
		crest:Hide()
		return
	end
	-- Centred on the top edge and lifted at least 3 units, more when the padding is small, so its lowest point stays
	-- a pixel above the frame's own top and clear of the Quests title.
	local scale = look.flourishSize
	local lift = math.max(3 * scale, CREST_REACH * scale + 1 - look.pad)
	Place(crest, x0 + width / 2 - CREST_WIDTH * scale / 2, y0 - lift - CREST_HEIGHT * scale / 2, CREST_WIDTH * scale,
		CREST_HEIGHT * scale)
end

-- Lays every piece out for the frame's current size. Runs after each setting change and whenever the frame resizes.
function F.LayoutBackdrop()
	if not host then
		return
	end
	local frameWidth, frameHeight = host:GetWidth(), host:GetHeight()
	if not frameWidth or frameWidth <= 0 or not frameHeight or frameHeight <= 0 then
		return
	end
	local visible = look.darkness > 0 or look.border
	if not visible and blank then
		return
	end
	blank = not visible
	local pad = look.pad
	local x0, y0 = -pad, -pad
	local width, height = frameWidth + 2 * pad, frameHeight + 2 * pad
	local radius = math.min(look.radius, width / 2, height / 2)
	PaintPanel(x0, y0, width, height, radius)
	PaintLine(x0, y0, width, height, radius)
	PaintOrnaments(x0, y0, width, height)
end

-- A slider setting, held inside its range; a missing or hand-edited value falls back to the default.
local function Setting(key)
	local limits = F.BACKDROP_LIMITS[key]
	return math.max(limits[1], math.min(limits[2], tonumber(Q.db[key]) or Q.defaults[key]))
end

-- Reads the settings and repaints. `darkness` is the panel's opacity (0 hides it); Frame.lua decides it, since the
-- panel also shows while the frame is unlocked.
function F.PaintBackdrop(darkness)
	if not host then
		return
	end
	local db = Q.db
	look.darkness = darkness or 0
	look.border = db.border and true or false
	local framed = F.Framed()
	-- A theme colours the Background; the panel shown only while unlocked stays plain.
	look.theme = db.backdrop and F.THEMES[db.bgTheme] or F.THEMES.current
	look.pad = framed and Setting("padding") or 0
	look.radius = (framed and db.rounded) and Setting("cornerSize") or 0
	look.flourish = db.borderFlourish and true or false
	look.crest = db.borderCrest and true or false
	look.flourishSize = Setting("flourishSize")
	local weight = WEIGHTS[db.borderWeight] or WEIGHTS[Q.defaults.borderWeight]
	look.layers = Layers(weight)
	-- Clamp to the screen by the panel and line, not the bare frame, so neither is cut off at a screen edge. Frame.lua
	-- calls this only when the frame may move (no quest item button on screen in combat; see Locked() there).
	local reach = look.pad + (look.border and weight / 2 + 2 or 0)
	if host.qcReach ~= reach then
		host.qcReach = reach
		host:SetClampRectInsets(-reach, reach, reach, -reach)
	end
	local finish = FINISHES[db.borderFinish] or FINISHES[Q.defaults.borderFinish]
	look.stops = {}
	for index, stop in ipairs(STOPS) do
		look.stops[index] = { Hex(finish[stop[1]]), stop[2] }
	end
	for corner, texture in ipairs(flourishes) do
		texture:SetTexture(MEDIA .. "BorderCorner" .. finish.file)
		Mirror(texture, corner, 0, 1, 0, 1)
	end
	crest:SetTexture(MEDIA .. "BorderCrest" .. finish.file)
	F.LayoutBackdrop()
end

------------------------------------------------------------------------------------------------------------------------
-- Theme samples for the settings window's cards
------------------------------------------------------------------------------------------------------------------------

-- Draws a background theme filling `frame` (width by height): the panel at the default darkness over a warm stand-in
-- for the game world, with the theme's glow and stars, as the tracker would show it.
function F.ThemeSample(frame, key, width, height)
	local theme = F.THEMES[key] or F.THEMES.current
	local world = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	world:SetAllPoints()
	Shade(world, "VERTICAL", { 0.22, 0.14, 0.08 }, { 0.36, 0.25, 0.14 })
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill:SetAllPoints()
	FillPanel(fill, theme, Q.defaults.opacity, 0, 1)
	PaintExtras(theme, GlowTexture(frame, 3), StarsTexture(frame, 4), frame, 0, 0, width, height, 0)
end
