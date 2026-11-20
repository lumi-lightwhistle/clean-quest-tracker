-- Settings: Clean Quest Tracker's own window (/cqt, the header cog, or Esc > Options > AddOns) and slash
-- commands.
--
-- The window is drawn by the add-on itself in WoW Forever's modern style, the same palette EllesmereUI Forever uses:
-- warm charcoal panels, thin bronze edges, a faint teal rim light and a bronze accent. Every page follows one pattern:
-- small section labels, then rows of settings in a bordered list, each with a short note. Hovering over a row shades
-- the part of the real tracker that setting changes (Tracker.SetHighlight).
-- The side column lists the pages; under the open one, links to its sections jump the page to them (the Show
-- sections switch at the column's foot turns them off).

local _, Q = ...
local O = {}
Q.Options = O

local WIDTH, HEIGHT = 790, 640
local SIDE_WIDTH, TOP_HEIGHT, FOOT_HEIGHT = 180, 56, 52
local NAV_STEP, LINK_HEIGHT, PIN_HEIGHT = 36, 22, 40 -- side column: page buttons, section links, the switch at the foot
local SCROLL_TWEEN = "qc-options-scroll"
local PAD = 20
local PAGE_WIDTH = WIDTH - SIDE_WIDTH - PAD * 2 - 10 -- 10 for the page scrollbar
local CONTROL_WIDTH = 250
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ARROW_ATLAS = "common-dropdown-icon-next"

-- Forever palette. Text and lines are white at an alpha, so they sit right on the warm background.
local C = {
	window = { 0.069, 0.058, 0.047 },
	side = { 0.055, 0.043, 0.035 },
	card = { 0.09, 0.075, 0.06 },
	accent = { 0.863, 0.655, 0.498 },
	teal = { 0.247, 0.663, 0.788 },
	white = { 1, 1, 1 },
	black = { 0, 0, 0 },
	toggleOff = { 0.267, 0.267, 0.267 },
}
-- The switch's track is drawn as two round ends and a middle that overlap, so it uses solid colours: see-through
-- pieces would stack where they overlap and show as darker patches. These are the Forever track colours (bronze at
-- 75%, grey at 65%) already blended over the window background.
local TRACK_ON = { 0.665, 0.506, 0.385 }
local TRACK_OFF = { 0.198, 0.194, 0.190 }
local TEXT, NOTE, LABEL = 0.9, 0.53, 0.41 -- white alphas: settings, notes, section labels

-- Colours offered on the Colours page. The setting's default is always offered too, marked with a dot.
local PALETTE = {
	{ "d9b04a", "Classic gold" }, { "ffd100", "Bright gold" }, { "f2dfa0", "Pale gold" }, { "dca77f", "Bronze" },
	{ "c27a4a", "Copper" }, { "e89b2e", "Amber" }, { "ede6d6", "Ivory" }, { "cccccc", "Silver grey" },
	{ "8ec9f0", "Ice blue" }, { "1f9eff", "Blue" }, { "4fd1b5", "Teal" }, { "1aff1a", "Bright green" },
	{ "e88fa0", "Rose" }, { "b79cf0", "Violet" },
}

local panel, scroll, child, thumb, pageTitle, pageNote
local navButtons, controls, pages = {}, {}, {}
local current = 1 -- opens on the first page (General)

------------------------------------------------------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------------------------------------------------------
local function Solid(parent, layer, color, alpha, sublevel)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
	texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	return texture
end

-- A colour that fades from one alpha to another across a texture. Falls back to the average on clients without
-- colour gradients.
local Fade = Q.Fade

-- A one-pixel outline inside a frame's edges; returns the four edges.
local function Outline(frame, color, alpha, layer)
	local edges = {}
	for index = 1, 4 do
		edges[index] = Solid(frame, layer or "BORDER", color, alpha)
	end
	edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)
	return edges
end

local function Recolor(edges, color, alpha)
	for _, edge in ipairs(edges) do
		edge:SetColorTexture(color[1], color[2], color[3], alpha)
	end
end

-- Clips a texture to a circle (toggle tracks, knobs, slider thumbs, colour dots).
local function Round(texture, owner)
	pcall(function()
		local mask = owner:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(texture)
		texture:AddMaskTexture(mask)
	end)
end

local function Text(parent, template, size, alpha, color)
	local fontString = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size then
		Q.Font(fontString, size)
	end
	color = color or C.white
	fontString:SetTextColor(color[1], color[2], color[3], alpha or 1)
	fontString:SetJustifyH("LEFT")
	return fontString
end

local function Hex(hex)
	local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

------------------------------------------------------------------------------------------------------------------------
-- Applying a change
------------------------------------------------------------------------------------------------------------------------
local PRESET_KEY = {}
for _, key in ipairs(Q.PRESET_KEYS) do
	PRESET_KEY[key] = true
end

local function Changed(key, rebuild)
	if PRESET_KEY[key] then
		Q.UpdatePresetName()
	end
	if rebuild then
		Q.Tracker.Rebuild()
	end
	Q.Apply(true)
	O.Refresh()
end

------------------------------------------------------------------------------------------------------------------------
-- Rows. A group is a bordered list of rows with alternating shades. Each row is a button: hovering it, or any control
-- in it, marks it with a bronze edge and shades the part of the tracker it changes.
------------------------------------------------------------------------------------------------------------------------
local function GroupLabel(page, title, side)
	if page.y < -4 then
		page.y = page.y - 18
	end
	if title and title ~= "" then
		-- Where the section starts, for its link in the side column.
		page.sections[#page.sections + 1] = { title = title, offset = -page.y }
		local label = Text(page, "GameFontNormal", 11, LABEL)
		label:SetPoint("TOPLEFT", 4, page.y)
		label:SetText(title:upper())
		if side then
			local note = Text(page, "GameFontHighlightSmall", 11, LABEL)
			note:SetPoint("TOPRIGHT", page, "TOPLEFT", PAGE_WIDTH - 4, page.y)
			note:SetJustifyH("RIGHT")
			note:SetText(side)
		end
		page.y = page.y - 20
	end
	page.list = nil
	page.rowIndex = 0
end

-- The bordered list rows go into; started by the first row after a group label.
local function List(page)
	if not page.list then
		local list = CreateFrame("Frame", nil, page)
		list:SetPoint("TOPLEFT", 0, page.y)
		list:SetWidth(PAGE_WIDTH)
		-- The border lives on its own frame above the rows; rows are child frames and would cover it otherwise.
		local border = CreateFrame("Frame", nil, page)
		border:SetAllPoints(list)
		border:SetFrameLevel(list:GetFrameLevel() + 10)
		Outline(border, C.white, 0.05, "OVERLAY")
		list.top = page.y
		page.list = list
	end
	return page.list
end

local function CloseList(page)
	local list = page.list
	if list then
		list:SetHeight(list.top - page.y)
	end
end

local function Row(page, height, highlightKey)
	local list = List(page)
	page.rowIndex = page.rowIndex + 1
	local row = CreateFrame("Button", nil, list)
	row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, page.y)
	row:SetSize(PAGE_WIDTH, height)
	Solid(row, "BACKGROUND", C.black, page.rowIndex % 2 == 1 and 0.1 or 0.2):SetAllPoints()
	row.tint = Solid(row, "BACKGROUND", C.accent, 0.05, 1)
	row.tint:SetAllPoints()
	row.edge = Solid(row, "ARTWORK", C.accent, 0.55)
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetWidth(2)
	row.tint:Hide()
	row.edge:Hide()
	function row.Enter()
		row.tint:Show()
		row.edge:Show()
		Q.Tracker.SetHighlight(highlightKey)
	end
	function row.Leave()
		if row:IsMouseOver() then
			return
		end
		row.tint:Hide()
		row.edge:Hide()
		Q.Tracker.SetHighlight(nil)
	end
	row:SetScript("OnEnter", row.Enter)
	row:SetScript("OnLeave", row.Leave)
	page.y = page.y - height
	CloseList(page)
	return row
end

local function PassHover(row, widget)
	widget:HookScript("OnEnter", row.Enter)
	widget:HookScript("OnLeave", row.Leave)
end

-- Label and note on the left of a row. If they wrap onto more lines than the row was sized for, the row grows (and
-- the rows after it move down), so text never spills into the next row.
-- `icon` is a texture drawn before the label, in the accent colour, so a row can show the part of the tracker it
-- belongs to (the Extras page uses the Quests bar's own icon).
local ICON_SIZE = 18
local ICON_ROOM = ICON_SIZE + 8 -- an icon's width plus the gap after it
local function Labels(page, row, label, note, width, icon)
	width = width or (PAGE_WIDTH - CONTROL_WIDTH - 30)
	local left = icon and 14 + ICON_ROOM or 14
	if icon then
		width = width - ICON_ROOM
		local picture = row:CreateTexture(nil, "ARTWORK")
		picture:SetTexture(icon)
		picture:SetSize(ICON_SIZE, ICON_SIZE)
		picture:SetPoint("LEFT", 14, 0)
		picture:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
	end
	local title = Text(row, "GameFontHighlight", 14, TEXT)
	title:SetPoint("TOPLEFT", left, note and -9 or -15)
	title:SetWidth(width)
	title:SetText(label)
	local needed = 9 + math.ceil(title:GetStringHeight()) + 9
	if note then
		local hint = Text(row, "GameFontHighlightSmall", 11, NOTE)
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
		hint:SetWidth(width)
		hint:SetText(note)
		needed = needed + 3 + math.ceil(hint:GetStringHeight())
	end
	local extra = needed - row:GetHeight()
	if extra > 0 and not row.fixedHeight then
		row:SetHeight(row:GetHeight() + extra)
		page.y = page.y - extra
		CloseList(page)
	end
	return title
end

local function RowHeight(note)
	return note and 52 or 44
end

------------------------------------------------------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------------------------------------------------------

-- A pill switch `width` by `height` with its knob `inset` from the ends. The track is two round ends and a middle in
-- solid colours (see TRACK_ON). Returns the button; switch:SetOn(on) paints it.
local function Pill(parent, width, height, inset)
	local switch = CreateFrame("Button", nil, parent)
	switch:SetSize(width, height)
	local parts = {}
	for index, point in ipairs({ "LEFT", "RIGHT" }) do
		parts[index] = Solid(switch, "ARTWORK", C.toggleOff)
		parts[index]:SetSize(height, height)
		parts[index]:SetPoint(point)
		Round(parts[index], switch)
	end
	parts[3] = Solid(switch, "ARTWORK", C.toggleOff)
	parts[3]:SetPoint("TOPLEFT", height / 2, 0)
	parts[3]:SetPoint("BOTTOMRIGHT", -height / 2, 0)
	local knob = Solid(switch, "OVERLAY", C.white)
	knob:SetSize(height - 2 * inset, height - 2 * inset)
	Round(knob, switch)
	function switch:SetOn(on)
		local color = on and TRACK_ON or TRACK_OFF
		for _, part in ipairs(parts) do
			part:SetColorTexture(color[1], color[2], color[3], 1)
		end
		knob:ClearAllPoints()
		knob:SetPoint(on and "RIGHT" or "LEFT", on and -inset or inset, 0)
		-- Off: a dimmed knob, also solid so it can't show the track through it.
		if on then
			knob:SetColorTexture(1, 1, 1, 1)
		else
			knob:SetColorTexture(0.6, 0.59, 0.585, 1)
		end
	end
	return switch
end

-- Pill switch.
local function Toggle(page, spec)
	local row = Row(page, RowHeight(spec.note), spec.hl)
	Labels(page, row, spec.label, spec.note, PAGE_WIDTH - 90, spec.icon)
	local switch = Pill(row, 38, 20, 3)
	switch:SetPoint("RIGHT", -14, 0)
	PassHover(row, switch)
	-- A switch normally flips a saved setting (spec.k). One that mirrors something the add-on doesn't own, such as a game
	-- setting, passes spec.get and spec.set instead.
	local function Current()
		if spec.get then
			return spec.get() and true or false
		end
		return Q.db[spec.k] and true or false
	end
	local function Flip()
		if spec.set then
			spec.set(not Current())
			Changed(nil, spec.rebuild) -- no saved key is involved
			return
		end
		local value = not Q.db[spec.k]
		if spec.k == "locked" then
			Q.SetLocked(value)
			return
		end
		Q.db[spec.k] = value
		if value and spec.onEnable then
			spec.onEnable()
		end
		Changed(spec.k, spec.rebuild)
	end
	switch:SetScript("OnClick", Flip)
	row:SetScript("OnClick", Flip)
	function row:Refresh()
		switch:SetOn(Current())
	end
	controls[#controls + 1] = row
end

local function StepButton(row, direction, onClick)
	local button = CreateFrame("Button", nil, row)
	button:SetSize(20, 22)
	Solid(button, "BACKGROUND", C.black, 0.2):SetAllPoints()
	local edges = Outline(button, C.white, 0.08)
	local arrow = button:CreateTexture(nil, "ARTWORK")
	arrow:SetSize(10, 10)
	arrow:SetPoint("CENTER")
	if Q.HasAtlas(ARROW_ATLAS) then
		arrow:SetAtlas(ARROW_ATLAS)
		if direction < 0 then
			arrow:SetTexCoord(1, 0, 0, 1)
		end
	else
		arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
		if direction < 0 then
			arrow:SetTexCoord(1, 0, 0, 1)
		end
	end
	arrow:SetVertexColor(1, 1, 1, NOTE)
	button:SetScript("OnEnter", function()
		arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		Recolor(edges, C.accent, 0.4)
	end)
	button:SetScript("OnLeave", function()
		arrow:SetVertexColor(1, 1, 1, NOTE)
		Recolor(edges, C.white, 0.08)
	end)
	button:SetScript("OnClick", onClick)
	PassHover(row, button)
	return button
end

-- Slider with step buttons either side and a value box.
local function Slider(page, spec)
	local row = Row(page, RowHeight(spec.note), spec.hl)
	Labels(page, row, spec.label, spec.note)
	local step = spec.step or 1
	local format = spec.format or function(value)
		return tostring(value)
	end
	local trackWidth = CONTROL_WIDTH - 20 - 20 - 46 - 24

	local box = CreateFrame("Frame", nil, row)
	box:SetSize(46, 24)
	box:SetPoint("RIGHT", -14, 0)
	Solid(box, "BACKGROUND", { 0.03, 0.023, 0.018 }, 0.5):SetAllPoints()
	Outline(box, C.white, 0.12)
	local value = Text(box, "GameFontHighlight", 12, TEXT)
	value:SetPoint("CENTER")
	value:SetJustifyH("CENTER")

	-- Which saved setting the slider edits can depend on another setting too (spec.kFn): the indent is kept separately
	-- for quests with and without icons.
	local function Key()
		return spec.kFn and spec.kFn() or spec.k
	end

	-- The saved value, held inside the slider's range (a setting edited by hand in the saved file can lie outside it).
	local function Shown()
		return math.max(spec.min, math.min(spec.max, Q.db[Key()] or spec.min))
	end

	local function Set(raw)
		local snapped = math.floor(math.max(spec.min, math.min(spec.max, raw)) / step + 0.5) * step
		snapped = tonumber(("%.2f"):format(snapped))
		-- Against the saved value, not the one shown: a value outside the range (edited by hand in the saved file) still
		-- has to be replaceable by the end of the range.
		local saved = Q.db[Key()]
		if type(saved) == "number" and math.abs(saved - snapped) < step / 4 then
			return
		end
		Q.db[Key()] = snapped
		Changed(Key(), spec.rebuild)
	end

	local more = StepButton(row, 1, function()
		Set(Shown() + step)
	end)
	more:SetPoint("RIGHT", box, "LEFT", -8, 0)

	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(trackWidth, 16)
	slider:SetPoint("RIGHT", more, "LEFT", -8, 0)
	slider:SetMinMaxValues(spec.min, spec.max)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	local track = Solid(slider, "BACKGROUND", C.white, 0.16)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	local filled = Solid(slider, "BORDER", C.accent, 0.75)
	filled:SetPoint("LEFT")
	filled:SetHeight(4)
	local knob = slider:CreateTexture(nil, "OVERLAY", nil, 2)
	knob:SetColorTexture(1, 1, 1, 1)
	knob:SetSize(12, 12)
	Round(knob, slider)
	slider:SetThumbTexture(knob)
	local ring = slider:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
	ring:SetSize(16, 16)
	ring:SetPoint("CENTER", knob)
	Round(ring, slider)
	PassHover(row, slider)

	local less = StepButton(row, -1, function()
		Set(Shown() - step)
	end)
	less:SetPoint("RIGHT", slider, "LEFT", -8, 0)

	local loading = false
	slider:SetScript("OnValueChanged", function(_, raw)
		if not loading then
			Set(raw)
		end
	end)
	function row:Refresh()
		local shown = Shown()
		loading = true
		slider:SetValue(shown)
		loading = false
		value:SetText(format(shown))
		filled:SetWidth(math.max(1, trackWidth * (shown - spec.min) / (spec.max - spec.min)))
	end
	controls[#controls + 1] = row
end

-- Segmented buttons.
local function Choice(page, spec)
	local row = Row(page, RowHeight(spec.note), spec.hl)
	Labels(page, row, spec.label, spec.note)
	local holder = CreateFrame("Frame", nil, row)
	local segmentWidth = 76
	holder:SetSize(segmentWidth * #spec.options, 26)
	holder:SetPoint("RIGHT", -14, 0)
	Outline(holder, C.white, 0.18)
	local segments = {}
	for index, option in ipairs(spec.options) do
		local segment = CreateFrame("Button", nil, holder)
		segment:SetSize(segmentWidth, 26)
		segment:SetPoint("LEFT", (index - 1) * segmentWidth, 0)
		segment.fill = Solid(segment, "BACKGROUND", C.accent, 0.18)
		segment.fill:SetAllPoints()
		segment.label = Text(segment, "GameFontHighlight", 13, NOTE)
		segment.label:SetPoint("CENTER")
		segment.label:SetJustifyH("CENTER")
		segment.label:SetText(option[2])
		if index > 1 then
			local divider = Solid(segment, "BORDER", C.white, 0.12)
			divider:SetPoint("TOPLEFT")
			divider:SetPoint("BOTTOMLEFT")
			divider:SetWidth(1)
		end
		segment:SetScript("OnClick", function()
			Q.db[spec.k] = option[1]
			Changed(spec.k, spec.rebuild)
		end)
		PassHover(row, segment)
		segment.value = option[1]
		segments[index] = segment
	end
	function row:Refresh()
		for _, segment in ipairs(segments) do
			local selected = Q.db[spec.k] == segment.value
			segment.fill:SetShown(selected)
			if selected then
				segment.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
			else
				segment.label:SetTextColor(1, 1, 1, NOTE)
			end
		end
	end
	controls[#controls + 1] = row
end

-- Colour row: label and current colour, then the palette. The setting's default carries a small dot.
local function Colour(page, spec)
	local row = Row(page, 86, spec.hl)
	-- The palette sits at a fixed place below the label, so this row keeps its height.
	row.fixedHeight = true
	Labels(page, row, spec.label, spec.note, PAGE_WIDTH - 200)
	local currentSwatch = Solid(row, "ARTWORK", C.white)
	currentSwatch:SetSize(16, 16)
	currentSwatch:SetPoint("TOPRIGHT", -14, -12)
	local currentName = Text(row, "GameFontHighlightSmall", 11, NOTE)
	currentName:SetPoint("RIGHT", currentSwatch, "LEFT", -8, 0)
	currentName:SetJustifyH("RIGHT")

	local default = Q.defaults[spec.k]
	local options = {}
	local hasDefault = false
	for _, entry in ipairs(PALETTE) do
		options[#options + 1] = entry
		hasDefault = hasDefault or entry[1] == default
	end
	if not hasDefault then
		table.insert(options, 1, { default, "Default" })
	end
	local swatches = {}
	for index, entry in ipairs(options) do
		local swatch = CreateFrame("Button", nil, row)
		swatch:SetSize(22, 22)
		swatch:SetPoint("TOPLEFT", 14 + (index - 1) * 28, -50)
		local rgb = Hex(entry[1])
		Solid(swatch, "ARTWORK", rgb):SetAllPoints()
		swatch.ring = Outline(swatch, C.black, 0.6, "OVERLAY")
		if entry[1] == default then
			local dot = Solid(swatch, "OVERLAY", C.white, 1, 2)
			dot:SetSize(7, 7)
			dot:SetPoint("CENTER", swatch, "TOPRIGHT", -1, -1)
			Round(dot, swatch)
		end
		swatch:SetScript("OnClick", function()
			Q.db[spec.k] = entry[1]
			Changed(spec.k)
		end)
		swatch:SetScript("OnEnter", function(self)
			row.Enter()
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(entry[2] .. (entry[1] == default and " (default)" or ""))
			GameTooltip:Show()
		end)
		swatch:SetScript("OnLeave", function()
			GameTooltip:Hide()
			row.Leave()
		end)
		swatch.hex, swatch.name = entry[1], entry[2]
		swatches[index] = swatch
	end
	function row:Refresh()
		local hex = Q.db[spec.k] or default
		local rgb = Hex(hex)
		currentSwatch:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
		local name = ""
		for _, swatch in ipairs(swatches) do
			local selected = swatch.hex == hex
			Recolor(swatch.ring, selected and C.white or C.black, selected and 1 or 0.6)
			if selected then
				name = swatch.name
			end
		end
		currentName:SetText(name .. (hex == default and " (default)" or ""))
	end
	controls[#controls + 1] = row
end

local PRESET_CARDS = {
	{ value = "comfortable", name = "Comfortable", note = "Clear and easy to read", gaps = { 5, 8, 5 } },
	{ value = "compact", name = "Compact", note = "More quests on screen", gaps = { 2, 4, 2 } },
	{ value = "custom", name = "Custom", note = "Your own mix", gaps = { 3, 6, 3 } },
}

local function Presets(page)
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", 0, page.y)
	holder:SetSize(PAGE_WIDTH, 84)
	local width = (PAGE_WIDTH - 20) / 3
	local cards = {}
	local function Enter()
		Q.Tracker.SetHighlight("qg")
	end
	local function Leave()
		Q.Tracker.SetHighlight(nil)
	end
	for index, info in ipairs(PRESET_CARDS) do
		local card = CreateFrame("Button", nil, holder)
		card:SetSize(width, 84)
		card:SetPoint("TOPLEFT", (index - 1) * (width + 10), 0)
		Solid(card, "BACKGROUND", C.card):SetAllPoints()
		card.edges = Outline(card, C.white, 0.08)
		-- Preview lines with clear space below them, then the name and note.
		local y = -14
		for line = 1, 4 do
			local bar = Solid(card, "ARTWORK", line % 2 == 1 and C.accent or C.white, line % 2 == 1 and 0.85 or 0.22)
			bar:SetSize(line % 2 == 1 and width * 0.55 or width * 0.38, 2)
			bar:SetPoint("TOPLEFT", line % 2 == 1 and 14 or 22, y)
			y = y - 2 - (info.gaps[line] or 0)
		end
		card.name = Text(card, "GameFontHighlight", 14, TEXT)
		card.name:SetPoint("TOPLEFT", 14, -44)
		card.name:SetText(info.name)
		card.note = Text(card, "GameFontHighlightSmall", 11, NOTE)
		card.note:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
		card.note:SetText(info.note)
		card:SetScript("OnClick", function()
			if Q.PRESETS[info.value] then
				Q.ApplyPreset(info.value)
				O.Refresh()
			end
		end)
		card:SetScript("OnEnter", Enter)
		card:SetScript("OnLeave", Leave)
		card.value = info.value
		cards[index] = card
	end
	page.y = page.y - 84
	local row = { hover = holder }
	function row:Refresh()
		for _, card in ipairs(cards) do
			local selected = Q.db.preset == card.value
			Recolor(card.edges, selected and C.accent or C.white, selected and 0.75 or 0.08)
			if selected then
				card.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
			else
				card.name:SetTextColor(1, 1, 1, TEXT)
			end
			card:SetAlpha((card.value == "custom" and not selected) and 0.4 or 1)
			card:SetEnabled(card.value ~= "custom")
		end
	end
	controls[#controls + 1] = row
end

-- Badge style picker: one card per style, each with a real badge drawn by Party.lua on a dark strip, so the choice
-- shows exactly what the tracker will draw (including Text mode and the Party badge colour).
local function BadgeStyles(page)
	local columns, gap, height = 3, 10, 92
	local width = (PAGE_WIDTH - gap * (columns - 1)) / columns
	local rows = math.ceil(#Q.Party.STYLES / columns)
	local holder = CreateFrame("Frame", nil, page)
	holder:SetPoint("TOPLEFT", 0, page.y)
	holder:SetSize(PAGE_WIDTH, rows * height + (rows - 1) * gap)
	local cards = {}
	for index, style in ipairs(Q.Party.STYLES) do
		local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
		local card = CreateFrame("Button", nil, holder)
		card:SetSize(width, height)
		card:SetPoint("TOPLEFT", column * (width + gap), -line * (height + gap))
		Solid(card, "BACKGROUND", C.card):SetAllPoints()
		card.edges = Outline(card, C.white, 0.08)
		local stage = Solid(card, "BORDER", C.black, 0.35)
		stage:SetPoint("TOPLEFT", 1, -1)
		stage:SetPoint("TOPRIGHT", -1, -1)
		stage:SetHeight(38)
		card.preview = Q.Party.CreatePreview(card)
		card.preview:SetPoint("CENTER", stage, "CENTER")
		card.name = Text(card, "GameFontHighlight", 13, TEXT)
		card.name:SetPoint("TOPLEFT", 12, -48)
		card.name:SetText(style.name)
		card.note = Text(card, "GameFontHighlightSmall", 10, NOTE)
		card.note:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
		card.note:SetWidth(width - 20)
		card.note:SetText(style.note)
		card:SetScript("OnClick", function()
			Q.db.badgeStyle = style.key
			Changed("badgeStyle")
		end)
		card:SetScript("OnEnter", function()
			Q.Tracker.SetHighlight("party")
			if Q.db.badgeStyle ~= style.key then
				Recolor(card.edges, C.accent, 0.35)
			end
		end)
		card:SetScript("OnLeave", function()
			Q.Tracker.SetHighlight(nil)
			O.Refresh()
		end)
		card.key = style.key
		cards[index] = card
	end
	page.y = page.y - holder:GetHeight()
	local row = { hover = holder }
	-- Hovering the picker while it is greyed out (no party badge) still shades where the badges would go.
	function row.Enter()
		Q.Tracker.SetHighlight("party")
	end
	function row.Leave()
		Q.Tracker.SetHighlight(nil)
	end
	function row:Refresh()
		for _, card in ipairs(cards) do
			local selected = (Q.db.badgeStyle or "pill") == card.key
			Recolor(card.edges, selected and C.accent or C.white, selected and 0.75 or 0.08)
			if selected then
				card.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
			else
				card.name:SetTextColor(1, 1, 1, TEXT)
			end
			card.preview:ShowStyle(card.key, false)
		end
	end
	controls[#controls + 1] = row
end

local function Button(parent, label, primary, onClick)
	local button = CreateFrame("Button", nil, parent)
	local text = Text(button, "GameFontHighlight", 13, primary and 1 or 0.55, primary and C.accent or C.white)
	text:SetPoint("CENTER")
	text:SetText(label)
	button:SetSize(math.max(100, math.ceil(text:GetStringWidth()) + 36), 30)
	local fill = Solid(button, "BACKGROUND", { 0.089, 0.08, 0.072 }, 0.6)
	fill:SetAllPoints()
	local edges = Outline(button, primary and C.accent or C.white, primary and 0.6 or 0.3)
	button:SetScript("OnEnter", function()
		fill:SetColorTexture(0.089, 0.08, 0.072, 0.65)
		Recolor(edges, primary and C.accent or C.white, primary and 0.8 or 0.45)
	end)
	button:SetScript("OnLeave", function()
		fill:SetColorTexture(0.089, 0.08, 0.072, 0.6)
		Recolor(edges, primary and C.accent or C.white, primary and 0.6 or 0.3)
	end)
	button:SetScript("OnClick", onClick)
	return button
end

local function ActionButton(page, spec)
	local button = Button(page, spec.label, false, function()
		spec.run()
		Q.Apply(true)
		O.Refresh()
	end)
	button:SetPoint("TOPRIGHT", page, "TOPLEFT", PAGE_WIDTH, page.y - 4)
	page.y = page.y - 38
end

-- A short tinted notice with a small moonlit diamond (the Experimental section's opening line): spec.lead in pale blue,
-- then spec.text.
local MOON = { 0.725, 0.812, 0.941 }

local function Notice(page, spec)
	local box = CreateFrame("Frame", nil, page)
	box:SetPoint("TOPLEFT", 0, page.y)
	box:SetWidth(PAGE_WIDTH)
	local fill = box:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	Fade(fill, "HORIZONTAL", MOON, 0.07, 0.02)
	Outline(box, MOON, 0.16)
	local mark = Solid(box, "ARTWORK", MOON, 0.85)
	mark:SetSize(7, 7)
	mark:SetRotation(math.rad(45))
	local line = Text(box, "GameFontHighlight", 12, NOTE)
	line:SetWidth(PAGE_WIDTH - 60)
	line:SetSpacing(2)
	local hex = ("%02x%02x%02x"):format(math.floor(MOON[1] * 255 + 0.5), math.floor(MOON[2] * 255 + 0.5),
		math.floor(MOON[3] * 255 + 0.5))
	line:SetText(("|cff%s%s|r %s"):format(hex, spec.lead, spec.text))
	line:SetPoint("TOPLEFT", 38, -11)
	local height = math.ceil(line:GetStringHeight()) + 22
	mark:SetPoint("CENTER", box, "TOPLEFT", 20, -height / 2)
	box:SetHeight(height)
	page.y = page.y - height - 10
end

-- Background themes: a card per theme, each showing that background behind a small sample of the tracker, drawn by
-- FrameBorder.lua's F.ThemeSample at the default darkness.
local THEME_CARDS = {
	{ key = "current", name = "Current", note = "Today's dark panel" },
	{ key = "moonglow", name = "Moonglow", note = "Night blue, moonlight and stars" },
}

local function Themes(page, spec)
	local gap, art, caption = 12, 118, 44
	local box = CreateFrame("Frame", nil, page)
	box:SetPoint("TOPLEFT", 0, page.y)
	box:SetSize(PAGE_WIDTH, 14 + 20 + 10 + art + caption + 14)
	Solid(box, "BACKGROUND", C.black, 0.1):SetAllPoints()
	Outline(box, C.white, 0.05)
	local title = Text(box, "GameFontHighlight", 14, TEXT)
	title:SetPoint("TOPLEFT", 24, -14)
	title:SetText(spec.label)
	local note = Text(box, "GameFontHighlightSmall", 11, NOTE)
	note:SetPoint("TOPRIGHT", box, "TOPRIGHT", -14, -16)
	note:SetJustifyH("RIGHT")
	note:SetText(spec.note)
	local width = (PAGE_WIDTH - 24 - 14 - gap) / 2
	local cards = {}
	for index, info in ipairs(THEME_CARDS) do
		local card = CreateFrame("Button", nil, box)
		card:SetSize(width, art + caption)
		card:SetPoint("TOPLEFT", 24 + (index - 1) * (width + gap), -44)
		Solid(card, "BACKGROUND", C.card):SetAllPoints()
		card.edges = Outline(card, C.white, 0.12)
		local stage = CreateFrame("Frame", nil, card)
		stage:SetPoint("TOPLEFT", 6, -6)
		stage:SetSize(width - 12, art - 6)
		Q.Frame.ThemeSample(stage, info.key, width - 12, art - 6)
		-- A few lines of the tracker in its own colours, which a theme never changes.
		local lines = {
			{ "Quests", 10, { 1, 0.82, 0 }, "CENTER" },
			{ "Stranglethorn Vale", 10, { 0.851, 0.69, 0.29 } },
			{ "[41] Venture Company Mining", 9, { 1, 0.82, 0 }, nil, 8 },
			{ "- 7/10 Singing Blue Crystal", 9, { 0.8, 0.8, 0.8 }, nil, 14 },
			{ "[37] Favor for Krazek", 9, { 1, 0.82, 0 }, nil, 8 },
		}
		local y = -10
		for _, entry in ipairs(lines) do
			local text = Text(stage, "GameFontHighlight", entry[2], 1, entry[3])
			if entry[4] == "CENTER" then
				text:SetPoint("TOP", stage, "TOP", 0, y)
				local rule = Solid(stage, "ARTWORK", C.accent, 0.45)
				rule:SetPoint("TOPLEFT", 12, y - 14)
				rule:SetPoint("TOPRIGHT", -12, y - 14)
				rule:SetHeight(1)
				y = y - 20
			else
				text:SetPoint("TOPLEFT", 12 + (entry[5] or 0), y)
				y = y - 15
			end
		end
		card.name = Text(card, "GameFontHighlight", 14, TEXT)
		card.name:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 4, -8)
		card.name:SetText(info.name)
		card.note = Text(card, "GameFontHighlightSmall", 11, NOTE)
		card.note:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
		card.note:SetText(info.note)
		-- The chosen card's dot fills in.
		card.ring = Solid(card, "ARTWORK", C.white, 0.3)
		card.ring:SetSize(12, 12)
		card.ring:SetPoint("BOTTOMRIGHT", -12, 16)
		Round(card.ring, card)
		card.hole = Solid(card, "ARTWORK", C.card, 1, 1)
		card.hole:SetSize(10, 10)
		card.hole:SetPoint("CENTER", card.ring)
		Round(card.hole, card)
		card.dot = Solid(card, "ARTWORK", C.accent, 1, 2)
		card.dot:SetSize(6, 6)
		card.dot:SetPoint("CENTER", card.ring)
		Round(card.dot, card)
		card:SetScript("OnClick", function()
			Q.db[spec.k] = info.key
			Changed(spec.k)
		end)
		card:SetScript("OnEnter", function()
			if Q.db[spec.k] ~= info.key then
				Recolor(card.edges, C.white, 0.28)
			end
		end)
		card:SetScript("OnLeave", function()
			O.Refresh()
		end)
		card.key = info.key
		cards[index] = card
	end
	page.y = page.y - box:GetHeight()
	local row = { hover = box }
	function row:Refresh()
		local chosen = Q.db[spec.k]
		if not Q.Frame.THEMES[chosen] then
			chosen = Q.defaults[spec.k]
		end
		for _, card in ipairs(cards) do
			local selected = chosen == card.key
			Recolor(card.edges, selected and C.accent or C.white, selected and 0.75 or 0.12)
			if selected then
				card.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
				card.ring:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
			else
				card.name:SetTextColor(1, 1, 1, TEXT)
				card.ring:SetColorTexture(1, 1, 1, 0.3)
			end
			card.dot:SetShown(selected)
		end
	end
	controls[#controls + 1] = row
end

-- A boxed explanation: small labels, bullet points and paragraphs.
local function Inset(page, spec)
	local box = CreateFrame("Frame", nil, page)
	box:SetPoint("TOPLEFT", 0, page.y)
	box:SetWidth(PAGE_WIDTH)
	Solid(box, "BACKGROUND", C.black, 0.18):SetAllPoints()
	Outline(box, C.white, 0.05)
	local y = -14
	local width = PAGE_WIDTH - 36
	for _, part in ipairs(spec.parts) do
		local kind, content = part[1], part[2]
		if kind == "label" then
			if y < -14 then
				y = y - 8
			end
			local label = Text(box, "GameFontNormal", 11, LABEL)
			label:SetPoint("TOPLEFT", 18, y)
			label:SetText(content:upper())
			y = y - 20
		elseif kind == "bullet" or kind == "text" then
			local line = Text(box, "GameFontHighlight", 12, 0.7)
			line:SetWidth(kind == "bullet" and width - 14 or width)
			line:SetSpacing(2)
			line:SetText(content)
			if kind == "bullet" then
				local dot = Solid(box, "ARTWORK", C.accent, 0.8)
				dot:SetSize(4, 4)
				dot:SetPoint("TOPLEFT", 20, y - 6)
				line:SetPoint("TOPLEFT", 32, y)
			else
				line:SetPoint("TOPLEFT", 18, y)
			end
			y = y - math.ceil(line:GetStringHeight()) - 8
		end
	end
	box:SetHeight(-y + 6)
	page.y = page.y + y - 6
end

-- A setting that only matters while another is set (spec.enabledBy = a saved switch that must be on, spec.disabledBy =
-- one that must be off, spec.enabledWhen = a function) is dimmed, ignores the mouse, and names what it needs in a
-- tooltip (spec.needs). Hovering it still shades the part of the tracker it would change.
local function SpecEnabled(spec)
	if spec.enabledBy and not Q.db[spec.enabledBy] then
		return false
	end
	if spec.disabledBy and Q.db[spec.disabledBy] then
		return false
	end
	if spec.enabledWhen and not spec.enabledWhen() then
		return false
	end
	return true
end

local function Gate(row, spec)
	local frame = row.hover or row
	local blocker = CreateFrame("Frame", nil, frame)
	blocker:SetAllPoints()
	blocker:SetFrameLevel(frame:GetFrameLevel() + 30)
	blocker:EnableMouse(true)
	blocker:Hide()
	blocker:SetScript("OnEnter", function(self)
		if row.Enter then
			row.Enter()
		end
		if spec.needs then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(spec.needs)
			GameTooltip:Show()
		end
	end)
	blocker:SetScript("OnLeave", function()
		GameTooltip:Hide()
		if row.Leave then
			row.Leave()
		end
	end)
	local refresh = row.Refresh
	function row:Refresh()
		if refresh then
			refresh(self)
		end
		local enabled = SpecEnabled(spec)
		frame:SetAlpha(enabled and 1 or 0.4)
		blocker:SetShown(not enabled)
	end
end

local BUILD = {
	toggle = Toggle,
	slider = Slider,
	choice = Choice,
	colour = Colour,
	presets = Presets,
	badges = BadgeStyles,
	button = ActionButton,
	inset = Inset,
	notice = Notice,
	themes = Themes,
}

------------------------------------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------------------------------------
-- The section links under the open page: the lit one is the last section whose heading is at or above the top of the
-- view (the last section once the page is scrolled to its end).
-- A section near the end of a page can't reach the top of the view, so the link last clicked stays lit until the page
-- is scrolled by hand.
local jumpedTo
local function UpdateSections()
	local button = navButtons[current]
	local links = button and button.links
	if not links or not Q.db.showSections then
		return
	end
	local top, range = scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()
	local lit = 1
	for index, link in ipairs(links) do
		if link.offset <= top + 8 then
			lit = index
		end
	end
	if range > 1 and top >= range - 2 then
		lit = #links
	end
	lit = jumpedTo or lit
	for index, link in ipairs(links) do
		local on = index == lit
		link.tick:SetShown(on)
		if on then
			link.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
		else
			link.label:SetTextColor(1, 1, 1, NOTE)
		end
	end
end

local function UpdateThumb()
	UpdateSections()
	local range = scroll:GetVerticalScrollRange()
	thumb:SetShown(range > 1)
	if range <= 1 then
		return
	end
	local view = scroll:GetHeight()
	local size = math.max(24, view * view / (view + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -(view - size) * (scroll:GetVerticalScroll() / range))
end

-- Scrolls the page so a section's heading sits at the top, gliding there like a wheel scroll.
local function JumpTo(offset)
	local target = math.min(scroll:GetVerticalScrollRange(), offset)
	Q.Motion.Tween(SCROLL_TWEEN, scroll:GetVerticalScroll(), target, Q.Motion.SCROLL, function(value)
		scroll:SetVerticalScroll(value)
		UpdateThumb()
	end)
end

-- Stacks the page buttons down the side column, with the open page's section links (while Show sections is on)
-- between its button and the next.
local function LayoutNav()
	local y = -TOP_HEIGHT - 12
	for index, button in ipairs(navButtons) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, y)
		y = y - NAV_STEP
		local links = button.links
		if links then
			local open = Q.db.showSections and index == current
			links.guide:SetShown(open)
			for _, link in ipairs(links) do
				link:SetShown(open)
				if open then
					link:ClearAllPoints()
					link:SetPoint("TOPLEFT", 0, y)
					y = y - LINK_HEIGHT
				end
			end
			if open then
				y = y - 8
			end
		end
	end
end

local function ShowPage(index)
	current = index
	Q.Motion.Stop(SCROLL_TWEEN) -- a jump still easing on the page before
	jumpedTo = nil
	LayoutNav()
	for pageIndex, page in ipairs(pages) do
		page:SetShown(pageIndex == index)
	end
	child:SetHeight(pages[index].height)
	scroll:SetVerticalScroll(0)
	UpdateSections()
	pageTitle:SetText(O.PAGES[index].name)
	pageNote:SetText(O.PAGES[index].note or "")
	for buttonIndex, button in ipairs(navButtons) do
		local selected = buttonIndex == index
		button.fill:SetShown(selected)
		button.accent:SetShown(selected)
		if selected then
			button.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
		else
			button.label:SetTextColor(1, 1, 1, 0.7)
		end
	end
	Q.Tracker.SetHighlight(nil)
	C_Timer.After(0, UpdateThumb)
end

function O.Refresh()
	if not panel then
		return
	end
	for _, control in ipairs(controls) do
		control:Refresh()
	end
end

local function BuildPage(index, info)
	local page = CreateFrame("Frame", nil, child)
	page:SetPoint("TOPLEFT")
	page:SetSize(PAGE_WIDTH, 10)
	page.y = 0
	page.sections = {}
	for _, group in ipairs(info.groups) do
		GroupLabel(page, group[1], group[2])
		for _, spec in ipairs(group[3]) do
			local before = #controls
			BUILD[spec[1]](page, spec)
			-- Only a control that added itself to the list can be greyed out (buttons and notes don't).
			if #controls > before and (spec.enabledBy or spec.disabledBy or spec.enabledWhen) then
				Gate(controls[#controls], spec)
			end
		end
	end
	page.height = -page.y + 12
	page:SetHeight(page.height)
	pages[index] = page
end

-- Indented links to a page's sections, on a faint bronze guide line; the lit one gets a tick on the line.
local function SectionLinks(side, sections)
	local links = {}
	for index, section in ipairs(sections) do
		local link = CreateFrame("Button", nil, side)
		link:SetSize(SIDE_WIDTH - 1, LINK_HEIGHT)
		Solid(link, "HIGHLIGHT", C.white, 0.04):SetAllPoints()
		link.label = Text(link, "GameFontHighlight", 12, NOTE)
		link.label:SetPoint("LEFT", 34, 0)
		link.label:SetWidth(SIDE_WIDTH - 1 - 34 - 8)
		link.label:SetWordWrap(false)
		link.label:SetText(section.title)
		link.tick = Solid(link, "ARTWORK", C.accent)
		link.tick:SetSize(3, LINK_HEIGHT - 10)
		link.tick:SetPoint("LEFT", 23, 0)
		link.offset = section.offset
		link:SetScript("OnClick", function()
			jumpedTo = index
			JumpTo(section.offset)
		end)
		link:Hide()
		links[index] = link
	end
	links.guide = Solid(side, "BORDER", C.accent, 0.18)
	links.guide:SetWidth(1)
	links.guide:SetPoint("TOPLEFT", links[1], "TOPLEFT", 24, -2)
	links.guide:SetPoint("BOTTOMLEFT", links[#links], "BOTTOMLEFT", 24, 2)
	links.guide:Hide()
	return links
end

-- Show sections: a small switch pinned to the foot of the side column (the saved setting showSections).
local function ShowSectionsSwitch(side)
	local row = CreateFrame("Button", nil, side)
	row:SetPoint("BOTTOMLEFT")
	row:SetPoint("BOTTOMRIGHT", -1, 0)
	row:SetHeight(PIN_HEIGHT)
	local rule = Solid(row, "BORDER", C.accent, 0.14)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetHeight(1)
	Solid(row, "HIGHLIGHT", C.white, 0.04):SetAllPoints()
	local label = Text(row, "GameFontHighlight", 12, NOTE)
	label:SetPoint("LEFT", 18, 0)
	label:SetText("Show sections")
	-- The same switch as the settings rows, smaller.
	local switch = Pill(row, 30, 16, 2)
	switch:SetPoint("RIGHT", -12, 0)
	local function Flip()
		Q.db.showSections = not Q.db.showSections
		row:Refresh()
	end
	row:SetScript("OnClick", Flip)
	switch:SetScript("OnClick", Flip)
	function row:Refresh()
		switch:SetOn(Q.db.showSections and true or false)
		LayoutNav()
		UpdateSections()
	end
	-- Refreshed with the settings rows, so Reset to defaults puts it back too.
	controls[#controls + 1] = row
end

local function Create()
	panel = CreateFrame("Frame", "CleanQuestTrackerOptions", UIParent)
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	Solid(panel, "BACKGROUND", C.window, 0.98):SetAllPoints()
	Outline(panel, C.accent, 0.32, "OVERLAY")
	tinsert(UISpecialFrames, "CleanQuestTrackerOptions")

	-- Teal rim light in the lower corners, as on the Forever window art.
	for _, corner in ipairs({ "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		local glow = panel:CreateTexture(nil, "BORDER")
		glow:SetSize(180, 70)
		glow:SetPoint(corner, 1, 1)
		Fade(glow, "VERTICAL", C.teal, 0.12, 0)
	end

	-- Side column: name and version on top, page list below.
	local side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 1, -1)
	side:SetPoint("BOTTOMLEFT", 1, FOOT_HEIGHT)
	side:SetWidth(SIDE_WIDTH)
	Solid(side, "BACKGROUND", C.side, 1, 1):SetAllPoints()
	local sideEdge = Solid(side, "BORDER", C.accent, 0.18)
	sideEdge:SetPoint("TOPRIGHT")
	sideEdge:SetPoint("BOTTOMRIGHT")
	sideEdge:SetWidth(1)
	local brandRule = Solid(side, "BORDER", C.accent, 0.28)
	brandRule:SetPoint("TOPLEFT", 0, -TOP_HEIGHT)
	brandRule:SetPoint("TOPRIGHT", 0, -TOP_HEIGHT)
	brandRule:SetHeight(1)
	local name = Text(side, "GameFontNormal", 15, 1, C.accent)
	name:SetText("Clean Quest Tracker")
	-- Equal room either side of the name, between the window edge and the column's divider (the version sits under it).
	name:SetPoint("TOPLEFT", math.max(10, math.floor((SIDE_WIDTH - 1 - name:GetStringWidth()) / 2)), -14)
	local version = Text(side, "GameFontHighlightSmall", 11, LABEL)
	version:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	version:SetText(Q.version)

	-- Top bar over the page: drag to move. Its bottom edge is bronze with a teal rim light toward the right.
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(TOP_HEIGHT)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
	end)
	local barRule = Solid(bar, "BORDER", C.accent, 0.28)
	barRule:SetPoint("BOTTOMLEFT")
	barRule:SetPoint("BOTTOMRIGHT")
	barRule:SetHeight(1)
	local rim = bar:CreateTexture(nil, "ARTWORK")
	rim:SetPoint("BOTTOMRIGHT")
	rim:SetPoint("BOTTOMLEFT", bar, "BOTTOM", -80, 0)
	rim:SetHeight(1)
	Fade(rim, "HORIZONTAL", C.teal, 0, 0.75)
	pageTitle = Text(bar, "GameFontHighlight", 19, TEXT)
	pageTitle:SetPoint("LEFT", PAD, 0)
	pageNote = Text(bar, "GameFontHighlightSmall", 11, LABEL)
	pageNote:SetPoint("BOTTOMLEFT", pageTitle, "BOTTOMRIGHT", 12, 2)

	local close = CreateFrame("Button", nil, bar)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", -12, 0)
	local closeFill = Solid(close, "BACKGROUND", C.black, 0.25)
	closeFill:SetAllPoints()
	local closeEdges = Outline(close, C.white, 0.18)
	local strokes = {}
	for _, angle in ipairs({ 45, -45 }) do
		local stroke = Solid(close, "ARTWORK", C.white, 0.7)
		stroke:SetSize(13, 1.5)
		stroke:SetPoint("CENTER")
		stroke:SetRotation(math.rad(angle))
		strokes[#strokes + 1] = stroke
	end
	close:SetScript("OnEnter", function()
		Recolor(closeEdges, C.accent, 0.6)
		for _, stroke in ipairs(strokes) do
			stroke:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
		end
	end)
	close:SetScript("OnLeave", function()
		Recolor(closeEdges, C.white, 0.18)
		for _, stroke in ipairs(strokes) do
			stroke:SetColorTexture(1, 1, 1, 0.7)
		end
	end)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)

	-- Page area: one scroll frame; each page is a child shown on its own.
	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -TOP_HEIGHT - 18)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 10, FOOT_HEIGHT + 8)
	scroll:SetClipsChildren(true)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(PAGE_WIDTH, 10)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	-- Each notch glides 44px; notches that come quickly add up. The wheel takes over from a section jump still gliding.
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local from, range = self:GetVerticalScroll(), self:GetVerticalScrollRange()
		local base = math.max(0, math.min(range, Q.Motion.Target(SCROLL_TWEEN) or from))
		local target = math.max(0, math.min(range, base - delta * 44))
		jumpedTo = nil
		Q.Motion.Tween(SCROLL_TWEEN, from, target, Q.Motion.SCROLL, function(value)
			self:SetVerticalScroll(value)
			UpdateThumb()
		end)
	end)
	thumb = Solid(panel, "ARTWORK", C.accent, 0.7)
	thumb:SetWidth(3)
	thumb:Hide()

	for index, info in ipairs(O.PAGES) do
		local button = CreateFrame("Button", nil, side)
		button:SetSize(SIDE_WIDTH - 1, 34)
		button.fill = button:CreateTexture(nil, "BACKGROUND", nil, 2)
		button.fill:SetAllPoints()
		Fade(button.fill, "HORIZONTAL", C.accent, 0.16, 0)
		button.accent = Solid(button, "ARTWORK", C.accent)
		button.accent:SetPoint("TOPLEFT", 0, -6)
		button.accent:SetPoint("BOTTOMLEFT", 0, 6)
		button.accent:SetWidth(2)
		Solid(button, "HIGHLIGHT", C.white, 0.05):SetAllPoints()
		button.label = Text(button, "GameFontHighlight", 14, 0.7)
		button.label:SetPoint("LEFT", 18, 0)
		button.label:SetText(info.name)
		button:SetScript("OnClick", function()
			ShowPage(index)
		end)
		navButtons[index] = button
		BuildPage(index, info)
		if info.sectionLinks and #pages[index].sections > 1 then
			button.links = SectionLinks(side, pages[index].sections)
		end
	end
	ShowSectionsSwitch(side)

	-- Footer.
	local foot = CreateFrame("Frame", nil, panel)
	foot:SetPoint("BOTTOMLEFT", 1, 1)
	foot:SetPoint("BOTTOMRIGHT", -1, 1)
	foot:SetHeight(FOOT_HEIGHT - 1)
	Solid(foot, "BACKGROUND", C.side, 0.9):SetAllPoints()
	local footRule = Solid(foot, "BORDER", C.accent, 0.22)
	footRule:SetPoint("TOPLEFT")
	footRule:SetPoint("TOPRIGHT")
	footRule:SetHeight(1)
	local reset = Button(foot, "Reset to defaults", false, function()
		Q.ResetSettings()
		Q.Tracker.Rebuild()
		O.Refresh()
	end)
	reset:SetPoint("LEFT", 16, 0)
	local done = Button(foot, DONE or "Done", true, function()
		panel:Hide()
	end)
	done:SetPoint("RIGHT", -16, 0)

	panel:SetScript("OnShow", O.Refresh)
	panel:SetScript("OnHide", function()
		Q.Motion.Stop(SCROLL_TWEEN)
		-- A row under the mouse gets no OnLeave when the window closes; clear its shading and the tracker's.
		for _, control in ipairs(controls) do
			if control.tint then
				control.tint:Hide()
				control.edge:Hide()
			end
		end
		Q.Tracker.SetHighlight(nil)
	end)
	ShowPage(current)
	O.Refresh()
end

function O.Toggle()
	if not Q.db then
		return
	end
	if not panel then
		Create()
		panel:Show()
		return
	end
	panel:SetShown(not panel:IsShown())
end

------------------------------------------------------------------------------------------------------------------------
-- Esc > Options > AddOns entry
------------------------------------------------------------------------------------------------------------------------
local function RegisterWithSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local frame = CreateFrame("Frame")
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Clean Quest Tracker")
	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	text:SetWidth(520)
	text:SetJustifyH("LEFT")
	text:SetText("Zone grouping, party counts and progress bars for your quest tracker. Settings open in their own window.")
	local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	open:SetText("Open settings")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel)
		end
		if not (panel and panel:IsShown()) then
			O.Toggle()
		end
	end)
	local category = Settings.RegisterCanvasLayoutCategory(frame, "Clean Quest Tracker")
	Settings.RegisterAddOnCategory(category)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	pcall(RegisterWithSettings)
end)

------------------------------------------------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------------------------------------------------
-- /cqt is the command; /sqt and /qc, from the add-on's earlier names, keep working.
SLASH_CLEANQUESTTRACKER1 = "/cqt"
SLASH_CLEANQUESTTRACKER2 = "/sqt"
SLASH_CLEANQUESTTRACKER3 = "/qc"
SLASH_CLEANQUESTTRACKER4 = "/cleanquesttracker"
SlashCmdList.CLEANQUESTTRACKER = function(message)
	local command = strtrim(message or ""):lower()
	if not Q.ready then
		Q.Print("Not ready yet.")
	elseif command == "lock" or command == "unlock" then
		Q.SetLocked(command == "lock")
		Q.Print(command == "lock" and "Locked." or "Unlocked. Drag the top strip to move, and the corner grip to resize.")
	elseif command == "preview" then
		Q.PreviewProgress()
	elseif command == "party" then
		Q.Party.Report()
	elseif command:match("^fakeparty") then
		-- Pretends that many party members (1 to 4) have every tracked quest, to see the badges without a group.
		-- Not saved: /cqt fakeparty alone, or /reload, turns it off.
		local count = tonumber(command:match("%d+"))
		Q.Party.fake = count and count >= 1 and math.min(count, 4) or nil
		Q.Tracker.MarkDirty()
		Q.Print(Q.Party.fake and ("Pretending %d party member(s) have every quest."):format(Q.Party.fake) or "Fake party off.")
	elseif command == "compact" or command == "comfortable" then
		Q.ApplyPreset(command)
		O.Refresh()
		Q.Print(("%s layout."):format(command == "compact" and "Compact" or "Comfortable"))
	elseif command == "reset" then
		Q.ResetSettings()
		Q.Tracker.Rebuild()
		Q.Print("All settings reset.")
	elseif command == "help" then
		Q.Print("/cqt opens settings (/sqt and /qc work too). /cqt lock, unlock, compact, comfortable, reset, preview, party, fakeparty 1-4.")
	else
		O.Toggle()
	end
end
