-- Thin rounded progress bars under counted objectives, with an eased fill animation when progress changes. In the
-- Segmented style (Quests page) a bar is cut into one segment per item the objective needs.

local _, Q = ...
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\Bar"
local DURATION = 0.32
local TRACK = { r = 0.08, g = 0.12, b = 0.17, a = 0.8 }
local SEGMENTS_MAX = 30 -- objectives needing more items than this keep a smooth bar
local SEGMENT_MIN = 4 -- nor is a bar cut so fine that a segment and its gap are under this many pixels wide
local GAP_MAX = 3 -- the gap between segments: 3 pixels, or a fifth of each item's share of the bar if less (at least 1)

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

-- How many segments the bar is cut into, or nil to draw it smooth.
local function SegmentCount(bar, width)
	local total = bar.total
	if Q.db.barStyle ~= "segmented" or not total or total < 2 or total > SEGMENTS_MAX then
		return nil
	end
	if width / total < SEGMENT_MIN then -- leaves each segment at least 3 pixels after its gap
		return nil
	end
	return total
end

-- Paints `count` segments across `width`, `filled` (0 to 1) of the way; the one the fill ends in is drawn part way.
-- Segments are made as needed and kept with the bar.
local function PaintSegments(bar, list, layer, count, width, height, filled, r, g, b, a)
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
			texture:SetVertexColor(r, g, b, a or 1)
			texture:Show()
		else
			texture:Hide()
		end
	end
end

local function Draw(bar)
	local inner = bar.inner
	local width, height = inner:GetWidth(), inner:GetHeight()
	if not width or width <= 0 then
		return
	end
	local color = bar.complete and Q.CompleteColor() or Q.Color("colorBar")
	local display = bar.display or 0
	local count = SegmentCount(bar, width) or 0
	PaintSegments(bar, bar.trackSegments, "BACKGROUND", count, width, height, 1, TRACK.r, TRACK.g, TRACK.b, TRACK.a)
	PaintSegments(bar, bar.fillSegments, "ARTWORK", count, width, height, display, color.r, color.g, color.b)
	if count > 0 then
		Paint(bar.track, 0, height)
		Paint(bar.fill, 0, height)
		return
	end
	Paint(bar.track, width, height, TRACK.r, TRACK.g, TRACK.b, TRACK.a)
	Paint(bar.fill, width * display, height, color.r, color.g, color.b)
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
	bar.inner:SetScript("OnSizeChanged", function()
		Draw(bar)
	end)
	bar:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		if self.target then
			self.display = self.target
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

-- /cqt preview: a test bar to check the animation without doing a quest.
function Q.PreviewProgress()
	if Q.preview then
		Q.preview:Show()
		return
	end
	local frame = CreateFrame("Frame", "CleanQuestTrackerBarPreview", UIParent, "BasicFrameTemplateWithInset")
	Q.preview = frame
	frame:SetSize(360, 140)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame.TitleText:SetText("Progress bar preview")
	local bar = Q.NewProgressBar(frame)
	bar:SetPoint("TOPLEFT", 20, -50)
	bar:SetSize(320, 6)
	Q.SetBarProgress(bar, "preview", 2, 10, false)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetPoint("BOTTOM", 0, 18)
	button:SetSize(150, 25)
	button:SetText("Add progress")
	local count = 2
	button:SetScript("OnClick", function()
		count = count >= 10 and 0 or count + 2
		Q.SetBarProgress(bar, "preview", count, 10, count == 10)
	end)
	tinsert(UISpecialFrames, "CleanQuestTrackerBarPreview")
end
