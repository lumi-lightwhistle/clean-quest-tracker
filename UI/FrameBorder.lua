-- Clean Quest Tracker: the frame's backdrop. The dark panel behind the list (square or with rounded corners, padded
-- out from the list), and the optional border with the bronze corner flourishes and crest. The look (Appearance page)
-- picks the panel's sky and the line's metal (a bronze finish or moonsilver); the Frame group decides whether each
-- shows. FrameMoonglow.lua adds the look's light and motion.
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

-- Whether the panel and the line show: the Appearance page's Background and Border (Frame group), whatever the look,
-- or borrowed while a theme is being tried (Q.TryTheme).
local function Borrowed()
	return Q.trial and Q.trial.frame and true or false
end

local function ShowsPanel()
	return (Q.db.backdrop or Borrowed()) and true or false
end

local function ShowsBorder()
	return (Q.db.border or Borrowed()) and true or false
end

F.ShowsPanel, F.ShowsBorder = ShowsPanel, ShowsBorder

-- The padding and rounded corners belong to the background and the border, so they apply only while one shows.
function F.Framed()
	return ShowsPanel() or ShowsBorder()
end

-- The panel's opacity (0 hides it): the Background darkness while the panel shows (a borrowed one at the default).
function F.PanelDarkness()
	if not ShowsPanel() then
		return 0
	end
	return Q.db.backdrop and Q.db.opacity or Q.defaults.opacity
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
	-- Moonsilver. It has no art of its own for flourishes or the crest: the bronze ones fall back to polished bronze.
	moonsilver = { "e3ebff", "c9d6f5", "7584b4", "aebce6", "5d6a96" },
}

-- The line's metal runs diagonally across the frame, light at the top left: which finish colour, and where.
local STOPS = { { 1, 0 }, { 2, 0.18 }, { 3, 0.42 }, { 4, 0.6 }, { 2, 0.8 }, { 5, 1 } }
local SEGMENTS = 6 -- pieces per edge, each shaded from one point of that gradient to the next

-- The quarter-ring atlas (see tools/border.py): 32 rings in 64px cells, 8 across; cell i has inner/outer radius i/32.
local RING = { file = MEDIA .. "BorderRing", width = 512, height = 256, cell = 64, region = 62, across = 8, steps = 32 }

------------------------------------------------------------------------------------------------------------------------
-- Skies: the panel's colour at its top and bottom (it fades between them), how much more opaque than the Background
-- darkness the bottom is, and any glow: a soft light from the top centre (`glow`) and one from the bottom (`rise`).
-- "current" is the plain panel players have always had (the Plain dark sky); the others came with Moonglow (Appearance
-- page, Sky colours). `stars` adds faint stars to the settings window's sample card only; on the tracker Moonglow's own
-- stars twinkle instead.
------------------------------------------------------------------------------------------------------------------------
F.THEMES = {
	current = { top = PANEL, bottom = PANEL, deepen = 0 },
	twilight = {
		top = { 44 / 255, 34 / 255, 84 / 255 },
		bottom = { 12 / 255, 16 / 255, 36 / 255 },
		deepen = 0.05,
		glow = { 200 / 255, 170 / 255, 1, 0.10 },
	},
	midnight = {
		top = { 10 / 255, 16 / 255, 40 / 255 },
		bottom = { 4 / 255, 7 / 255, 20 / 255 },
		deepen = 0.08,
		glow = { 120 / 255, 150 / 255, 1, 0.12 },
		stars = true,
	},
	tide = {
		top = { 10 / 255, 18 / 255, 44 / 255 },
		bottom = { 4 / 255, 14 / 255, 26 / 255 },
		deepen = 0.08,
		glow = { 130 / 255, 150 / 255, 1, 0.12 },
		rise = { 60 / 255, 190 / 255, 200 / 255, 0.11 },
	},
}
local SKIES = { plain = "current", twilight = "twilight", midnight = "midnight", tide = "tide" }
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

-- Moonsilver: the same four layers in night colours, under two faint bands of moonlight that soften its edge
-- (`strength` is Moonglow's Glow strength).
local function SilverLayers(weight, strength)
	local bevel = weight / 2 + 0.2
	return {
		{ offset = 0, width = weight + 8, color = { 150 / 255, 180 / 255, 1, 0.05 * strength } },
		{ offset = 0, width = weight + 4, color = { 170 / 255, 200 / 255, 1, 0.09 * strength } },
		{ offset = 0, width = weight + 2, color = { 6 / 255, 8 / 255, 20 / 255, 0.7 } },
		{ offset = 0, width = weight, metal = true },
		{ offset = bevel, width = 1.1, color = { 8 / 255, 10 / 255, 24 / 255, 0.9 } },
		{ offset = -bevel, width = 1.1, color = { 236 / 255, 242 / 255, 1, 0.35 } },
	}
end
local LAYERS = 6 -- the most layers a line has

------------------------------------------------------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------------------------------------------------------
local host
local panel = {} -- middle, left, right, corners = { 4 }, glow, rise
local line = {} -- one entry per layer: { corners = { 4 }, edges = { top, bottom, left, right = { pieces } } }
local flourishes = {}
local crest
local look = { darkness = 0, pad = 0, radius = 0, border = false, glowScale = 1 }
local blank = false -- nothing is drawn and every piece is already hidden

-- Places a texture by its top-left corner, in pixels right of and below the top-left corner of `anchor` (the
-- tracker's frame unless given). A piece already showing at that spot is left alone: on each step of a height ease
-- most of the frame doesn't move. Code that anchors one of these pieces some other way clears its qcX.
local function Place(texture, x, y, width, height, anchor)
	if width <= 0.01 or height <= 0.01 then
		texture:Hide()
		return
	end
	anchor = anchor or host
	if texture.qcX == x and texture.qcY == y and texture.qcWidth == width and texture.qcHeight == height
		and texture.qcAnchor == anchor and texture:IsShown() then
		return
	end
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
	texture:SetSize(width, height)
	texture.qcX, texture.qcY, texture.qcWidth, texture.qcHeight, texture.qcAnchor = x, y, width, height, anchor
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

-- Points a corner texture at the quarter ring with the nearest inner/outer ratio (only when that changes).
local function SetRing(texture, corner, ratio)
	local index = math.max(0, math.min(RING.steps - 1, math.floor(ratio * RING.steps + 0.5)))
	if texture.qcRing == index and texture.qcCorner == corner then
		return
	end
	texture.qcRing, texture.qcCorner = index, corner
	local left = (index % RING.across) * RING.cell
	local top = math.floor(index / RING.across) * RING.cell
	Mirror(texture, corner, left / RING.width, (left + RING.region) / RING.width, top / RING.height,
		(top + RING.region) / RING.height)
end

-- A two-colour gradient (Q.Gradient); a client that refuses it gets the average colour. The texture is made plain
-- white once (qcWhite), for the gradient to colour; code that gives it a colour of its own clears qcWhite.
local function Shade(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	if not texture.qcWhite then
		texture:SetColorTexture(1, 1, 1, 1)
		texture.qcWhite = true
	end
	if not Q.Gradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then
		texture:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
		texture.qcWhite = nil
	end
end

-- A theme's panel colour and opacity `share` of the way down the panel (0 at the top, 1 at the bottom): r, g, b, a.
local function PanelColor(theme, alpha, share)
	local top, bottom = theme.top, theme.bottom
	return top[1] + (bottom[1] - top[1]) * share, top[2] + (bottom[2] - top[2]) * share,
		top[3] + (bottom[3] - top[3]) * share, math.min(1, alpha + theme.deepen * share)
end

-- Fills a piece of the panel that runs from `from` to `to` (shares of the panel's height). The plain panel stays one
-- flat colour, exactly as before themes.
local function FillPanel(texture, theme, alpha, from, to)
	if theme.deepen == 0 and theme.top == theme.bottom then
		if texture.qcWhite then
			texture:SetVertexColor(1, 1, 1, 1) -- a gradient left from a shaded sky, in case a colour doesn't replace it
		end
		texture:SetColorTexture(theme.top[1], theme.top[2], theme.top[3], alpha)
		texture.qcWhite = nil
	else
		local r1, g1, b1, a1 = PanelColor(theme, alpha, to)
		local r2, g2, b2, a2 = PanelColor(theme, alpha, from)
		Shade(texture, "VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2)
	end
end

-- A sky's glows over a panel at (x0, y0), width by height, from `anchor`'s top-left corner, and its static stars when
-- a `stars` texture is passed (the settings window's sample cards; on the tracker Moonglow's own stars twinkle).
-- `scale` turns the glows up or down (Moonglow's Glow strength).
local function PaintExtras(theme, glow, rise, stars, anchor, x0, y0, width, height, scale)
	scale = scale or 1
	local share = GLOW.down - GLOW.above
	if theme.glow then
		-- It spans the panel's full width, so it also reaches the cut-outs beside rounded corners, where it is about 3%
		-- opaque at full Glow strength (keep the skies' glow alphas near 0.12): too faint to see, so it isn't cut to
		-- their shape. The rise from the bottom does the same.
		glow:SetVertexColor(theme.glow[1], theme.glow[2], theme.glow[3], theme.glow[4] * scale)
		Place(glow, x0, y0, width, height * share, anchor)
	else
		glow:Hide()
	end
	if theme.rise then
		-- The same glow upside down, rising from the bottom edge.
		rise:SetVertexColor(theme.rise[1], theme.rise[2], theme.rise[3], theme.rise[4] * scale)
		Place(rise, x0, y0 + height * (1 - share), width, height * share, anchor)
	else
		rise:Hide()
	end
	if stars then
		if theme.stars and stars.tiles then
			stars:SetTexCoord(0, width / STARS.tile, 0, height / STARS.tile)
			Place(stars, x0, y0, width, height, anchor)
		else
			stars:Hide()
		end
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
local function GlowTexture(owner, sublevel, upward)
	local glow = owner:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	glow:SetTexture(GLOW.file)
	local left, top = 0.5 - GLOW.across, -GLOW.above - GLOW.down
	local u0, u1, v0 = -left / (2 * GLOW.across), (1 - left) / (2 * GLOW.across), -top / (2 * GLOW.down)
	if upward then
		glow:SetTexCoord(u0, u1, 1, v0)
	else
		glow:SetTexCoord(u0, u1, v0, 1)
	end
	glow:Hide()
	return glow
end

-- The metal's colour at a point of the panel (x, y from its top-left corner; it is width by height): r, g, b.
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
			return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
		end
	end
	local last = stops[#stops][1]
	return last[1], last[2], last[3]
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
	panel.glow, panel.rise = GlowTexture(host, -7), GlowTexture(host, -7, true)
	for index = 1, LAYERS do
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
	panel.all = { panel.middle, panel.left, panel.right, panel.glow, panel.rise, panel.corners[1], panel.corners[2],
		panel.corners[3], panel.corners[4] }
	F.CreateMoonglow(host)
end

------------------------------------------------------------------------------------------------------------------------
-- Painting: the panel, the line, the flourishes and the crest. x0, y0 is the panel's top-left corner (below and right
-- of the frame's own), width and height its size, radius its corners (0 for square).
------------------------------------------------------------------------------------------------------------------------
local function PaintPanel(x0, y0, width, height, radius)
	local alpha, theme = look.darkness, look.theme
	if alpha <= 0 then
		-- Hidden once, not again on every step of a height ease.
		if not panel.hidden then
			HideAll(panel.all)
			panel.hidden = true
		end
		return
	end
	panel.hidden = nil
	PaintExtras(theme, panel.glow, panel.rise, nil, host, x0, y0, width, height, look.glowScale)
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
	for corner, texture in ipairs(panel.corners) do
		SetRing(texture, corner, 0)
		texture:SetVertexColor(PanelColor(theme, alpha, corner <= 2 and inner / 2 or 1 - inner / 2))
		Place(texture, (corner == 2 or corner == 4) and right or x0, corner >= 3 and bottom or y0, radius, radius)
	end
end

-- One straight run of a layer. The metal is cut into pieces, each shaded along the frame's diagonal gradient; the
-- other layers are one flat piece. `frame` (the panel's x0, y0, width and height) places a point on the gradient.
local function Run(pieces, layer, x, y, width, height, vertical, frame)
	if not layer.metal then
		-- One flat piece. Its colour is set once per repaint (each repaint makes new layer colours).
		local color, piece = layer.color, pieces[1]
		if piece.qcColor ~= color then
			if piece.qcWhite then
				piece:SetVertexColor(1, 1, 1, 1) -- a gradient left from the metal, in case a colour doesn't replace it
			end
			piece:SetColorTexture(color[1], color[2], color[3], color[4])
			piece.qcColor, piece.qcWhite = color, nil
		end
		Place(piece, x, y, width, height)
		if pieces.qcMetal then
			for index = 2, #pieces do
				pieces[index]:Hide()
			end
			pieces.qcMetal = nil
		end
		return
	end
	pieces.qcMetal = true
	pieces[1].qcColor = nil
	local length = vertical and height or width
	local step = length / #pieces
	for index, texture in ipairs(pieces) do
		local from = (index - 1) * step
		if vertical then
			local cx = x + width / 2 - frame.x0
			local r2, g2, b2 = Metal(cx, y + from - frame.y0, frame.width, frame.height)
			local r1, g1, b1 = Metal(cx, y + from + step - frame.y0, frame.width, frame.height)
			Shade(texture, "VERTICAL", r1, g1, b1, 1, r2, g2, b2, 1)
			Place(texture, x, y + from, width, step)
		else
			local cy = y + height / 2 - frame.y0
			local r1, g1, b1 = Metal(x + from - frame.x0, cy, frame.width, frame.height)
			local r2, g2, b2 = Metal(x + from + step - frame.x0, cy, frame.width, frame.height)
			Shade(texture, "HORIZONTAL", r1, g1, b1, 1, r2, g2, b2, 1)
			Place(texture, x + from, y, step, height)
		end
	end
end

-- Hides a layer's corners, once (a square frame or a hidden layer would otherwise hide them on every step).
local function HideCorners(layer)
	if not layer.cornersHidden then
		HideAll(layer.corners)
		layer.cornersHidden = true
	end
end

local box = {} -- the panel's x0, y0, width and height, for Run (reused, as this runs on every step of a height ease)
local function PaintLine(x0, y0, width, height, radius)
	box.x0, box.y0, box.width, box.height = x0, y0, width, height
	for index, layer in ipairs(line) do
		local spec = look.layers and look.layers[index]
		if not look.border or not spec then
			if not layer.hidden then
				HideCorners(layer)
				for _, pieces in pairs(layer.edges) do
					HideAll(pieces)
				end
				layer.hidden = true
			end
		else
			layer.hidden = nil
			-- a: how far the layer reaches outside the panel's edge; b: where it starts (negative is inside).
			local a, b = spec.offset + spec.width / 2, spec.offset - spec.width / 2
			local thick = a - b
			local frame = box
			local edges = layer.edges
			if radius > 0 then
				local outer = radius + a
				local ratio = math.max(0, radius + b) / outer
				local right, bottom = x0 + width - radius, y0 + height - radius
				layer.cornersHidden = nil
				for corner, texture in ipairs(layer.corners) do
					local east, south = corner == 2 or corner == 4, corner >= 3
					SetRing(texture, corner, ratio)
					if spec.metal then
						local red, green, blue = Metal(east and width or 0, south and height or 0, width, height)
						texture:SetVertexColor(red, green, blue, 1)
					else
						texture:SetVertexColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
					end
					Place(texture, east and right or x0 - a, south and bottom or y0 - a, outer, outer)
				end
				Run(edges.top, spec, x0 + radius, y0 - a, width - 2 * radius, thick, false, frame)
				Run(edges.bottom, spec, x0 + radius, y0 + height + b, width - 2 * radius, thick, false, frame)
				Run(edges.left, spec, x0 - a, y0 + radius, thick, height - 2 * radius, true, frame)
				Run(edges.right, spec, x0 + width + b, y0 + radius, thick, height - 2 * radius, true, frame)
			else
				HideCorners(layer)
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
		for corner, texture in ipairs(flourishes) do
			local east, south = corner == 2 or corner == 4, corner >= 3
			Place(texture, east and x0 + width - after or x0 - before, south and y0 + height - after or y0 - before, size,
				size)
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

------------------------------------------------------------------------------------------------------------------------
-- The search strip: the dark band behind the Quests bar while a search is open (FrameSearch.lua fades it in and out).
-- With the panel or the border showing, it fills the top of the panel inside the line and its rounded corners, tinted
-- from the theme, so it reads as part of the frame. With neither, it is the plain band players have always had, as wide
-- as the bar's own artwork. It is drawn on the header, so the bar's icons and the search box sit above it.
------------------------------------------------------------------------------------------------------------------------
local STRIP_PLAIN = { 0.071, 0.059, 0.047, 0.93 }
local STRIP_RULE = { 0.863, 0.655, 0.498, 0.6 }
local STRIP_RULE_SILVER = { 0.784, 0.843, 1, 0.6 } -- under Moonglow's silver line
local strip -- { header, middle, left, right, corners = { top-left, top-right }, rule, all }
local stripAlpha = 0

-- The strip's colour inside a frame: the theme's top colour lifted a little, and more opaque than the panel, so the bar
-- stays solid over a bright world even when the panel is faint.
local function StripColor(theme, darkness)
	local top = theme.top
	local function Lift(value)
		return math.min(1, value * 1.6 + 6 / 255)
	end
	return Lift(top[1]), Lift(top[2]), Lift(top[3]), math.max(0.72, math.min(0.93, darkness + 0.3))
end

function F.CreateSearchStrip(header)
	local function Piece(sublevel, ring)
		local texture = header:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		if ring then
			texture:SetTexture(RING.file)
		end
		texture:Hide()
		return texture
	end
	strip = { header = header, middle = Piece(3), left = Piece(3), right = Piece(3), rule = Piece(4) }
	strip.corners = { Piece(3, true), Piece(3, true) }
	strip.all = { strip.middle, strip.left, strip.right, strip.corners[1], strip.corners[2], strip.rule }
end

-- Lays the strip out for the current look and frame size, at its current opacity (hidden at 0).
local function LayoutStrip()
	if not strip then
		return
	end
	-- Closed: hidden once, not again on every step of a height ease.
	if stripAlpha <= 0 then
		if not strip.hidden then
			HideAll(strip.all)
			strip.hidden = true
		end
		return
	end
	strip.hidden = nil
	HideAll(strip.all)
	local header, middle, rule = strip.header, strip.middle, strip.rule
	local width, height = header:GetWidth(), header:GetHeight()
	local frameHeight = host and host:GetHeight()
	local ruleColor = (look.silver and look.border) and STRIP_RULE_SILVER or STRIP_RULE
	rule:SetColorTexture(ruleColor[1], ruleColor[2], ruleColor[3], ruleColor[4])
	if not (look.darkness > 0 or look.border) or not width or width <= 0 or not frameHeight or frameHeight <= 0 then
		local overhang = Q.HasAtlas("UI-QuestTracker-Secondary-Objective-Header") and 10 or 0
		middle:SetColorTexture(STRIP_PLAIN[1], STRIP_PLAIN[2], STRIP_PLAIN[3], STRIP_PLAIN[4])
		middle.qcX, rule.qcX = nil, nil -- anchored here rather than by Place
		middle:ClearAllPoints()
		middle:SetPoint("TOPLEFT", -overhang, 0)
		middle:SetPoint("BOTTOMRIGHT", overhang, 0)
		rule:ClearAllPoints()
		rule:SetPoint("BOTTOMLEFT", -overhang, 0)
		rule:SetPoint("BOTTOMRIGHT", overhang, 0)
		rule:SetHeight(1)
		middle:Show()
		rule:Show()
	else
		-- Inside the line (its catch-light reaches weight / 2 + 0.75 in from the panel's edge), from the panel's top down
		-- to the bar's rule. The header sits over the frame's top, so the panel's top is `pad` above it.
		local pad = look.pad
		-- A little further in under Moonglow's silver line, clear of its bright core.
		local inset = look.border and look.weight / 2 + (look.silver and 2 or 0.75) or 0
		local x0, y0 = inset - pad, inset - pad
		local w, h = width + 2 * (pad - inset), height - y0
		local radius = math.min(look.radius, width / 2 + pad, frameHeight / 2 + pad)
		local r = math.max(0, math.min(radius - inset, h, w / 2))
		local red, green, blue, alpha = StripColor(look.theme, look.darkness)
		for _, texture in ipairs({ middle, strip.left, strip.right }) do
			texture:SetColorTexture(red, green, blue, alpha)
		end
		Place(middle, x0 + r, y0, w - 2 * r, h, header)
		Place(strip.left, x0, y0 + r, r, h - r, header)
		Place(strip.right, x0 + w - r, y0 + r, r, h - r, header)
		for corner, texture in ipairs(strip.corners) do
			SetRing(texture, corner, 0)
			texture:SetVertexColor(red, green, blue, alpha)
			Place(texture, corner == 1 and x0 or x0 + w - r, y0, r, r, header)
		end
		Place(rule, x0, height - 1, w, 1, header)
	end
	for _, texture in ipairs(strip.all) do
		texture:SetAlpha(stripAlpha)
	end
end

-- Sets the strip's opacity (0 hides it). FrameSearch.lua calls this every frame while it fades, so only showing or
-- hiding it lays it out again; the frame's own changes reach it through F.LayoutBackdrop.
function F.SetSearchStrip(alpha)
	if not strip then
		return
	end
	local relayout = stripAlpha <= 0 or alpha <= 0
	stripAlpha = alpha
	F.FadeMoonHeader(1 - alpha)
	if relayout then
		LayoutStrip()
		return
	end
	for _, texture in ipairs(strip.all) do
		texture:SetAlpha(alpha)
	end
end

function F.SearchStripAlpha()
	return stripAlpha
end

-- Lays every piece out for the frame's current size. Runs after each setting change and whenever the frame resizes.
function F.LayoutBackdrop()
	if not host then
		return
	end
	LayoutStrip()
	local frameWidth, frameHeight = host:GetWidth(), host:GetHeight()
	if not frameWidth or frameWidth <= 0 or not frameHeight or frameHeight <= 0 then
		return
	end
	-- With no panel and no line nothing is drawn: every part of the look sits on one or the other, so once it has all
	-- been hidden there is nothing to do (this runs on every step of a height ease).
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
	-- The look's light and motion (FrameMoonglow.lua), which hides whatever parts are off.
	F.LayoutMoonglow(x0, y0, width, height, radius)
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
	look.border = ShowsBorder()
	local framed = F.Framed()
	-- The look's parts (Appearance page), read through Q.Look so a theme being tried shows.
	local finishKey = Q.Look("borderFinish")
	local silver = finishKey == "moonsilver"
	look.silver = silver
	look.radius = (framed and db.rounded) and Setting("cornerSize") or 0
	-- The sky colours the panel (also the one shown only while the frame is unlocked).
	look.theme = F.THEMES[SKIES[Q.Look("moonSky")] or "current"]
	look.flourish = Q.Look("borderOrnament") == "flourish"
	look.crest = Q.Look("lookCrest") == "diamond"
	look.glowScale = F.MoonStrength()
	look.pad = framed and Setting("padding") or 0
	look.flourishSize = Setting("flourishSize")
	local weight = WEIGHTS[db.borderWeight] or WEIGHTS[Q.defaults.borderWeight]
	look.weight = weight
	look.layers = silver and SilverLayers(weight, look.glowScale) or Layers(weight)
	-- Clamp to the screen by the panel and line, not the bare frame, so neither is cut off at a screen edge. Frame.lua
	-- calls this only when the frame may move (no quest item button on screen in combat; see Locked() there).
	local outside = 0 -- how far the line's widest layer reaches past the panel's edge
	for _, layer in ipairs(look.layers) do
		outside = math.max(outside, layer.offset + layer.width / 2)
	end
	local reach = look.pad + (look.border and outside + 0.5 or 0)
	if host.qcReach ~= reach then
		host.qcReach = reach
		host:SetClampRectInsets(-reach, reach, reach, -reach)
	end
	local finish = FINISHES[finishKey] or FINISHES[Q.defaults.borderFinish]
	look.stops = {}
	for index, stop in ipairs(STOPS) do
		look.stops[index] = { Hex(finish[stop[1]]), stop[2] }
	end
	-- The bronze flourishes and crest are drawn per bronze finish; on moonsilver they keep the polished bronze.
	local file = finish.file or FINISHES[Q.defaults.borderFinish].file
	for corner, texture in ipairs(flourishes) do
		texture:SetTexture(MEDIA .. "BorderCorner" .. file)
		Mirror(texture, corner, 0, 1, 0, 1)
	end
	crest:SetTexture(MEDIA .. "BorderCrest" .. file)
	F.PaintMoonglow(look.pad, ShowsPanel() and look.darkness > 0, look.border)
	F.LayoutBackdrop()
end

------------------------------------------------------------------------------------------------------------------------
-- Theme samples for the settings window's cards
------------------------------------------------------------------------------------------------------------------------

-- Draws a sky filling `frame` (width by height): the panel at the default darkness over a warm stand-in for the game
-- world, with the sky's colours and glows (its stars are a still stand-in for the tracker's twinkling ones).
function F.ThemeSample(frame, key, width, height)
	local theme = F.THEMES[key] or F.THEMES.current
	local world = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	world:SetAllPoints()
	Shade(world, "VERTICAL", 0.22, 0.14, 0.08, 1, 0.36, 0.25, 0.14, 1)
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill:SetAllPoints()
	FillPanel(fill, theme, Q.defaults.opacity, 0, 1)
	PaintExtras(theme, GlowTexture(frame, 3), GlowTexture(frame, 3, true), StarsTexture(frame, 4), frame, 0, 0, width,
		height)
end
