-- Thin rounded progress bars under counted objectives, with an eased fill animation when progress changes.

local _, Q = ...
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\Bar"
local DURATION = 0.32
local TRACK = { r = 0.08, g = 0.12, b = 0.17, a = 0.8 }

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

local function Draw(bar)
	local inner = bar.inner
	local width, height = inner:GetWidth(), inner:GetHeight()
	if not width or width <= 0 then
		return
	end
	Paint(bar.track, width, height, TRACK.r, TRACK.g, TRACK.b, TRACK.a)
	local color = bar.complete and Q.CompleteColor() or Q.Color("colorBar")
	Paint(bar.fill, width * (bar.display or 0), height, color.r, color.g, color.b)
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
