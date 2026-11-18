-- Clean Quest Tracker: the search box in the Quests bar.
--
-- A magnifying glass sits right of the zone tools (or first, without zones). Clicking it grows a box out of the icon
-- while the Quests title fades. Typing filters the list (TrackerSearch.lua). Clicking away or Enter keeps the filter
-- and gives the box a quieter resting look; clicking it again carries on typing. Esc, the X, or leaving the box empty
-- clears the search and closes the box. Motion follows the Animations setting.

local _, Q = ...
local F = Q.Frame

local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"
local ICON_SIZE = 18
local BOX_HEIGHT = 20
local BOX_RIGHT = 68 -- the box stops short of the cog and padlock
local CLOSED_WIDTH = ICON_SIZE + 4
local WIDTH_TWEEN = "qc-search-width"
-- Forever palette, as in the settings window.
local PANEL = { 0.071, 0.059, 0.047 }
local ACCENT = { 0.863, 0.655, 0.498 }
local TEAL = { 0.247, 0.663, 0.788 }
local INK = { 0.95, 0.93, 0.88 }

local BAND_TWEEN = "qc-search-band"
local RED = { 0.93, 0.32, 0.29 }

local header, box, edit, icon, placeholder, count, clear, noMatch
local band = {} -- fill, underline and rim behind the whole bar
local open = false

function F.SearchOpen()
	return open
end

local function Duration()
	return Q.Motion.Duration()
end

local function Solid(parent, layer, color, alpha)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	return texture
end

-- Where the box (and the icon under it) starts: after the pin and arrows, or first when zones are off.
local function LeftOffset()
	return (Q.db and Q.db.grouping) and 52 or 6
end

local function FullWidth()
	return math.max(60, header:GetWidth() - (LeftOffset() - 2) - BOX_RIGHT)
end

local function FadeTitle(alpha)
	local title = header.title
	Q.Motion.Tween(title, title:GetAlpha(), alpha, Duration() * 0.8, function(value)
		title:SetAlpha(value)
	end)
end

local function SetWidth(width, done)
	Q.Motion.Tween(WIDTH_TWEEN, box:GetWidth(), width, Duration(), function(value)
		box:SetWidth(value)
	end, done)
end

-- The dark band behind the whole Quests bar while a search is open: it carries the bar's bronze underline and teal
-- rim, so the box reads as part of the bar and not a separate widget.
local function SetBandAlpha(alpha)
	for _, texture in ipairs(band) do
		texture:SetAlpha(alpha)
	end
end

local function ShowBand(show)
	local target = show and 1 or 0
	if show then
		for _, texture in ipairs(band) do
			texture:Show()
		end
	end
	Q.Motion.Tween(BAND_TWEEN, band[1]:GetAlpha(), target, Duration(), SetBandAlpha, function()
		if not open then
			for _, texture in ipairs(band) do
				texture:Hide()
			end
		end
	end)
end

-- Typing: a slightly darker field on the band with a bronze underline and the teal rim. Resting (filter kept, not
-- typing): the field drops away and the text turns bronze; the band stays.
local function Paint()
	local focused = edit:HasFocus()
	local text = edit:GetText() or ""
	box.fill:SetShown(focused)
	box.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], focused and 0.62 or 0.3)
	box.rim:SetShown(focused)
	local color = focused and INK or ACCENT
	edit:SetTextColor(color[1], color[2], color[3])
	placeholder:SetShown(focused and text == "")
	clear:SetShown(text ~= "")
	count:SetShown(text ~= "")
end

function F.CloseSearch()
	if not open then
		return
	end
	open = false
	edit:SetText("")
	edit:ClearFocus()
	Q.Tracker.SetSearch("")
	FadeTitle(1)
	ShowBand(false)
	SetWidth(CLOSED_WIDTH, function()
		if not open then
			box:Hide()
		end
		F.ShowControls(header:IsMouseOver())
	end)
	-- With no quests tracked the frame hides again once the box is gone.
	F.Layout()
end

function F.OpenSearch()
	if open then
		edit:SetFocus()
		return
	end
	open = true
	F.PlaceSearch()
	if not box:IsShown() then
		box:SetWidth(CLOSED_WIDTH)
		box:Show()
	end
	F.ShowControls(header:IsMouseOver())
	FadeTitle(0)
	ShowBand(true)
	SetWidth(FullWidth())
	edit:SetFocus()
	Paint()
end

-- Keeps the icon and box beside the zone tools, and the box full width as the frame is resized.
function F.PlaceSearch()
	if not box then
		return
	end
	local find = header.find
	find:ClearAllPoints()
	find:SetPoint("LEFT", LeftOffset(), 0)
	box:ClearAllPoints()
	box:SetPoint("LEFT", header, "LEFT", LeftOffset() - 2, 0)
	if open and not Q.Motion.Target(WIDTH_TWEEN) then
		box:SetWidth(FullWidth())
	end
end

-- "3/9": quests shown out of quests tracked.
function F.SetSearchCount(shown, total)
	if count then
		count:SetFormattedText("%d/%d", shown or 0, total or 0)
	end
end

-- The line shown in place of the list when nothing matches. Returns the list height to use.
function F.ShowNoMatch(show, height)
	if not show then
		if noMatch then
			noMatch:Hide()
		end
		return height
	end
	if not noMatch then
		noMatch = F.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		noMatch:SetJustifyH("LEFT")
		noMatch:SetPoint("TOPLEFT", 26, -8)
		noMatch:SetPoint("RIGHT", F.content, "RIGHT", -8, 0)
	end
	Q.Font(noMatch, Q.db.fontSize)
	local color = Q.Color("colorObjective")
	noMatch:SetTextColor(color.r, color.g, color.b, 0.8)
	-- A typed "|" would otherwise start a colour code.
	local typed = strtrim(edit:GetText() or ""):gsub("||", "|"):gsub("|", "||")
	noMatch:SetFormattedText("No quests match \"%s\"", typed)
	noMatch:Show()
	return 8 + math.ceil(noMatch:GetStringHeight()) + 6
end

-- Settings highlight for the Search page: the box, or the icon when the box is closed.
function F.SearchRegion()
	return open and box or header.find
end

-- A click anywhere else on screen ends typing (the game otherwise keeps the cursor in a text box until Esc).
local clickWatch = CreateFrame("Frame")
clickWatch:SetScript("OnEvent", function()
	if edit and edit:HasFocus() and not box:IsMouseOver() then
		edit:ClearFocus()
	end
end)

local function WatchClicks(on)
	if on then
		pcall(clickWatch.RegisterEvent, clickWatch, "GLOBAL_MOUSE_DOWN")
	else
		pcall(clickWatch.UnregisterEvent, clickWatch, "GLOBAL_MOUSE_DOWN")
	end
end

-- The box, its text and its X take the mouse from the header, so leaving any of them runs the header's own check:
-- once the mouse is off the Quests bar, its icons fade out again.
local function HeaderLeave()
	if not header:IsMouseOver() then
		F.ShowControls(false)
	end
end

local function CreateClear()
	clear = CreateFrame("Button", nil, box)
	clear:SetSize(18, 18)
	clear:SetPoint("RIGHT", -2, 0)
	local hover = Solid(clear, "BACKGROUND", RED, 0.22)
	hover:SetAllPoints()
	hover:Hide()
	local strokes = {}
	for _, angle in ipairs({ 45, -45 }) do
		local stroke = Solid(clear, "ARTWORK", RED, 1)
		stroke:SetSize(13, 2.5)
		stroke:SetPoint("CENTER")
		stroke:SetRotation(math.rad(angle))
		strokes[#strokes + 1] = stroke
	end
	clear:SetScript("OnEnter", function(self)
		hover:Show()
		for _, stroke in ipairs(strokes) do
			stroke:SetColorTexture(1, 0.5, 0.45, 1)
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Clear search")
		GameTooltip:Show()
	end)
	clear:SetScript("OnLeave", function()
		hover:Hide()
		for _, stroke in ipairs(strokes) do
			stroke:SetColorTexture(RED[1], RED[2], RED[3], 1)
		end
		GameTooltip:Hide()
		HeaderLeave()
	end)
	clear:SetScript("OnClick", F.CloseSearch)
end

local function CreateEdit()
	edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("LEFT", 20, 0)
	edit:SetPoint("RIGHT", -58, 0)
	edit:SetHeight(BOX_HEIGHT)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(40)
	edit:SetFontObject(GameFontHighlight)
	local file = GameFontHighlight:GetFont()
	if file then
		edit:SetFont(file, 12, "")
	end
	edit:SetTextInsets(0, 0, 0, 0)

	placeholder = edit:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	Q.Font(placeholder, 12)
	placeholder:SetPoint("LEFT")
	placeholder:SetText("Search quests")
	placeholder:SetTextColor(1, 1, 1, 0.34)

	count = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	count:SetPoint("RIGHT", -24, 0)
	count:SetTextColor(1, 1, 1, 0.5)

	edit:SetScript("OnTextChanged", function()
		Paint()
		Q.Debounce("qc-search", 0.05, function()
			if open then
				Q.Tracker.SetSearch(edit:GetText())
			end
		end)
	end)
	edit:SetScript("OnLeave", HeaderLeave)
	edit:SetScript("OnEscapePressed", F.CloseSearch)
	edit:SetScript("OnEnterPressed", edit.ClearFocus)
	edit:SetScript("OnEditFocusGained", function()
		-- Clicked while the box was still shrinking shut: open it again rather than type into a closing box.
		if not open then
			F.OpenSearch()
		end
		WatchClicks(true)
		Paint()
	end)
	edit:SetScript("OnEditFocusLost", function()
		WatchClicks(false)
		if strtrim(edit:GetText() or "") == "" then
			F.CloseSearch()
		elseif open then
			Paint()
		end
	end)
end

function F.CreateSearch(parent)
	header = parent
	local find = F.HeaderButton(MEDIA .. "Search", function()
		return "Search quests"
	end, F.OpenSearch)
	-- The box takes the icon's place while it's open.
	find.available = function()
		return not open
	end
	header.find = find

	box = CreateFrame("Frame", nil, header)
	box:SetHeight(BOX_HEIGHT)
	box:SetWidth(CLOSED_WIDTH)
	box:SetFrameLevel(header:GetFrameLevel() + 5)
	box:SetClipsChildren(true)
	box:EnableMouse(true)
	box:Hide()
	box.fill = Solid(box, "BACKGROUND", { 0, 0, 0 }, 0.3)
	box.fill:SetAllPoints()
	box.line = Solid(box, "BORDER", ACCENT, 0.62)
	box.line:SetPoint("BOTTOMLEFT")
	box.line:SetPoint("BOTTOMRIGHT")
	box.line:SetHeight(1)
	-- The band behind the whole bar, drawn on the header itself so every icon and the box sit above it. It matches the
	-- bar's own artwork in width.
	local overhang = Q.HasAtlas("UI-QuestTracker-Secondary-Objective-Header") and 10 or 0
	local fill = header:CreateTexture(nil, "BACKGROUND", nil, 3)
	fill:SetPoint("TOPLEFT", -overhang, 0)
	fill:SetPoint("BOTTOMRIGHT", overhang, 0)
	fill:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], 0.93)
	local rule = header:CreateTexture(nil, "BACKGROUND", nil, 4)
	rule:SetPoint("BOTTOMLEFT", -overhang, 0)
	rule:SetPoint("BOTTOMRIGHT", overhang, 0)
	rule:SetHeight(1)
	rule:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
	-- Teal rim light along the bottom edge, strongest toward the right, as on the Forever window art.
	local bandRim = header:CreateTexture(nil, "BACKGROUND", nil, 5)
	bandRim:SetPoint("BOTTOMRIGHT", overhang, 0)
	bandRim:SetPoint("BOTTOMLEFT", header, "BOTTOM", -60, 0)
	bandRim:SetHeight(1)
	bandRim:SetColorTexture(1, 1, 1, 1)
	if not (CreateColor and pcall(bandRim.SetGradient, bandRim, "HORIZONTAL",
		CreateColor(TEAL[1], TEAL[2], TEAL[3], 0), CreateColor(TEAL[1], TEAL[2], TEAL[3], 0.8))) then
		bandRim:SetColorTexture(TEAL[1], TEAL[2], TEAL[3], 0.4)
	end
	band[1], band[2], band[3] = fill, rule, bandRim
	for _, texture in ipairs(band) do
		texture:SetAlpha(0)
		texture:Hide()
	end
	-- The field's own teal rim while typing.
	box.rim = box:CreateTexture(nil, "ARTWORK")
	box.rim:SetPoint("BOTTOMLEFT", 1, 0)
	box.rim:SetPoint("BOTTOMRIGHT", -1, 0)
	box.rim:SetHeight(1)
	box.rim:SetColorTexture(1, 1, 1, 1)
	local ok = CreateColor and pcall(box.rim.SetGradient, box.rim, "HORIZONTAL",
		CreateColor(TEAL[1], TEAL[2], TEAL[3], 0.1), CreateColor(TEAL[1], TEAL[2], TEAL[3], 0.85))
	if not ok then
		box.rim:SetColorTexture(TEAL[1], TEAL[2], TEAL[3], 0.5)
	end
	icon = box:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MEDIA .. "Search")
	icon:SetSize(13, 13)
	icon:SetPoint("LEFT", 4, 0)
	icon:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	box:SetScript("OnMouseDown", F.OpenSearch)
	box:SetScript("OnLeave", HeaderLeave)

	CreateEdit()
	CreateClear()
	header:HookScript("OnSizeChanged", F.PlaceSearch)
	F.PlaceSearch()
	Paint()
end
