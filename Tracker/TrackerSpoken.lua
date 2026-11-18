-- Clean Quest Tracker: Spoken's play button on each quest, when the Spoken add-on is installed.

local _, Q = ...
local T = Q.Tracker

------------------------------------------------------------------------------------------------------------------------
-- Spoken's play button (optional). Spoken attaches it to Blizzard's tracker only, so the same button is drawn here.
------------------------------------------------------------------------------------------------------------------------
local function SpokenUI()
	local env = rawget(_G, "VoiceOver")
	local ui = type(env) == "table" and rawget(env, "QuestOverlayUI")
	local spoken = rawget(_G, "Spoken")
	if
		type(ui) == "table"
		and type(spoken) == "table"
		and type(spoken.DressBoxButton) == "function"
		and type(ui.ShowsTrackerButton) == "function"
		and type(ui.BindPlayButton) == "function"
		and type(ui.SetPlayButtonState) == "function"
	then
		return ui, spoken
	end
end

function T.SpokenShows(questID)
	local ui = SpokenUI()
	if not ui then
		return false
	end
	local ok, shows = pcall(ui.ShowsTrackerButton, ui, questID)
	return ok and shows and true or false
end

function T.DressSpoken(block, offsetX)
	local ui, spoken = SpokenUI()
	if not ui or block.qcSpoken == false then
		return
	end
	local button = block.qcSpoken
	if not button then
		button = CreateFrame("Button", nil, block)
		button:SetSize(T.SPOKEN_SIZE, T.SPOKEN_SIZE)
		button:SetHitRectInsets(1, 1, 1, 1)
		local ok = pcall(spoken.DressBoxButton, spoken, button)
		if ok and button.SetBox then
			ok = pcall(button.SetBox, button, "QuestLog-icon-ticksquare", T.SPOKEN_SIZE, T.SPOKEN_SIZE)
		end
		if not ok then
			button:Hide()
			block.qcSpoken = false
			return
		end
		button.setPlayState = ui.FollowQueue
		local back = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		back:SetPoint("TOPLEFT", 1, -1)
		back:SetPoint("BOTTOMRIGHT", -1, 1)
		back:SetColorTexture(0, 0, 0, 0.6)
		block.qcSpoken = button
	end
	button:SetFrameLevel(block:GetFrameLevel() + 3)
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", block, "TOPRIGHT", offsetX, -1)
	if button.qcQuestID ~= block.id then
		button.soundData = nil
		button.qcQuestID = block.id
	end
	local title = C_QuestLog.GetTitleForQuestID(block.id) or ""
	if pcall(ui.BindPlayButton, ui, button, block.id, title, "Clean Quest Tracker's tracker") then
		button:Show()
		pcall(ui.SetPlayButtonState, ui, button)
	else
		button:Hide()
	end
end
