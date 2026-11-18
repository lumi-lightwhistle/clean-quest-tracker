-- Clean Quest Tracker: quest search. What counts as a match, the colour codes put around matched letters, and the
-- marker strips drawn behind them. The search box itself lives in the Quests bar (Frame.lua).
--
-- The search text is never saved: it starts empty each session. While it is set, the list shows only quests whose
-- title or objectives contain it (and, with the setting on, every quest in a zone whose name contains it). Folded zones
-- with matches are shown open; the saved folding is left alone, so clearing the search puts every zone back.

local _, Q = ...
local T = Q.Tracker

local needle -- the lowercased search text, or nil when there is no search
-- Matched letters in Marker style are white, in a shade nothing else in the list uses, so the marker pass can find them
-- again in the finished text.
local MARK = "|cfffffffe"
local MARK_ALPHA = 0.4

local Hex = T.Hex

function T.SearchActive()
	return needle ~= nil
end

-- Sets the search text (from the box). Only redraws when what is being matched changes.
function T.SetSearch(text)
	text = type(text) == "string" and strtrim(text):gsub("||", "|"):lower() or ""
	local new = text ~= "" and text or nil
	if new == needle then
		return
	end
	needle = new
	T.MarkDirty()
end

-- Plain, case-insensitive "contains".
function T.Matches(text)
	if not needle or type(text) ~= "string" or not Q.Readable(text) then
		return false
	end
	return text:lower():find(needle, 1, true) ~= nil
end

-- The title as the list shows it, without the level: "Name", or "Name (Complete)".
function T.QuestName(questID, info, isComplete)
	local name = C_QuestLog.GetTitleForQuestID(questID) or (info and info.title) or ""
	if isComplete then
		name = ("%s (%s)"):format(name, COMPLETE or "Complete")
	end
	return name
end

-- A quest matches on its title, or on an objective line that is on screen. Finished quests that fold to their title
-- only match on the title.
function T.QuestMatches(quest)
	local questID, logIndex = quest.id, quest.logIndex
	local isComplete = C_QuestLog.IsComplete(questID) and true or false
	if T.Matches(T.QuestName(questID, quest.info, isComplete)) then
		return true
	end
	if isComplete and Q.db.foldComplete then
		return false
	end
	for index = 1, (logIndex and GetNumQuestLeaderBoards(logIndex)) or 0 do
		local text = GetQuestLogLeaderBoard(index, logIndex, true)
		if T.Matches(text) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------------------------------
-- Marker placement. The client can report where any run of letters sits on screen, line by line, so a strip can sit
-- behind matched letters even when a title wraps. How it counts letters (with or without colour codes) and which
-- units it answers in are checked once, on a hidden test line, before any strip is drawn.
------------------------------------------------------------------------------------------------------------------------
-- nil until checked; false when strips can't be placed; otherwise { raw, screen, relative }: letters counted with
-- colour codes or without, answers in screen units or the line's own, and measured from the screen or from the line.
local spanMode
local probe
local attempts = 0
local MAX_ATTEMPTS = 5 -- redraws to wait for the test line to be measured before giving up on strips
local fellBack = false -- one redraw once strips are ruled out, so matches switch to coloured letters
local pendingRetry, retryQueued = false, false -- a strip pass that found unmeasured text tries once more next frame

local function Probe()
	if spanMode ~= nil then
		return spanMode
	end
	if not probe then
		probe = CreateFrame("Frame", nil, UIParent)
		-- An odd scale and an offset from the screen corner, so none of the possible readings give the same answer.
		probe:SetScale(0.5)
		probe:SetSize(400, 40)
		probe:SetPoint("BOTTOMLEFT", 300, 200)
		probe:SetAlpha(0)
		probe.text = probe:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		probe.text:SetPoint("BOTTOMLEFT")
		probe.ref = probe:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		probe.ref:SetPoint("TOPLEFT")
		if not probe.text.CalculateScreenAreaFromCharacterSpan then
			spanMode = false
			probe:Hide()
			return false
		end
		probe.text:SetText("AB|cffff0000CD|rEF")
		probe.ref:SetText("ABCD")
	end
	local function Wait()
		attempts = attempts + 1
		if attempts < MAX_ATTEMPTS then
			return nil -- not measured yet; checked again on the next redraw
		end
		spanMode = false
		probe:Hide()
		return false
	end
	local left, bottom = probe.text:GetLeft(), probe.text:GetBottom()
	local width = probe.ref:GetStringWidth()
	local height = probe.text:GetStringHeight()
	if not (left and bottom and width and width > 0 and height and height > 0) then
		return Wait()
	end
	local scale = probe.text:GetEffectiveScale()
	local answered = false
	-- "E" is the 5th letter shown, or the 17th character of the text counting the colour codes. Its left edge should
	-- sit just after "ABCD", and its bottom on the line's bottom.
	for _, raw in ipairs({ false, true }) do
		local ok, areas = pcall(probe.text.CalculateScreenAreaFromCharacterSpan, probe.text, raw and 17 or 5, raw and 17 or 5)
		local area = ok and type(areas) == "table" and areas[1]
		if area and type(area.left) == "number" and type(area.bottom) == "number" then
			answered = true
			for _, screen in ipairs({ false, true }) do
				local k = screen and 1 / scale or 1
				for _, relative in ipairs({ false, true }) do
					local x = area.left * k - (relative and 0 or left)
					local y = area.bottom * k - (relative and 0 or bottom)
					if math.abs(x - width) < 2 and math.abs(y) < height then
						spanMode = { raw = raw, screen = screen, relative = relative }
						probe:Hide()
						return spanMode
					end
				end
			end
		end
	end
	if not answered then
		return Wait()
	end
	spanMode = false
	probe:Hide()
	return false
end

-- Wraps each match in `text` in the highlight colour, then `resume` (the colour the text had, or "|r" for the line's
-- own colour). Marker style uses MARK, and falls back to coloured letters if strips can't be placed on this client.
function T.MarkSearch(text, resume)
	if not needle or type(text) ~= "string" or text == "" or not Q.Readable(text) then
		return text
	end
	local low = text:lower()
	local start = low:find(needle, 1, true)
	if not start then
		return text
	end
	local letters = Q.db.searchStyle == "letters" or spanMode == false
	local open = letters and Hex(Q.Color("colorSearch")) or MARK
	resume = resume or "|r"
	local out, from = {}, 1
	while start do
		local stop = start + #needle - 1
		out[#out + 1] = text:sub(from, start - 1)
		out[#out + 1] = open .. text:sub(start, stop) .. resume
		from = stop + 1
		start = low:find(needle, from, true)
	end
	out[#out + 1] = text:sub(from)
	return table.concat(out)
end

-- The runs of MARK-coloured letters in a font string's text, as { first, last } letter positions, counted the way
-- the client counts them: shown letters only, or every byte including colour codes.
local function Segments(text, raw)
	local segments = {}
	local count, i, n = 0, 1, #text
	local first -- start of the run being read, or nil
	local function Close()
		if first and count >= first then
			segments[#segments + 1] = { first, count }
		end
		first = nil
	end
	while i <= n do
		local byte = text:byte(i)
		local nextChar = text:sub(i + 1, i + 1)
		if byte == 124 and nextChar == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
			Close()
			if raw then
				count = count + 10
			end
			if text:sub(i, i + 9) == MARK then
				first = count + 1
			end
			i = i + 10
		elseif byte == 124 and nextChar == "r" then
			Close()
			if raw then
				count = count + 2
			end
			i = i + 2
		else
			local size = 1
			if byte == 124 and nextChar == "|" then
				size = 2 -- an escaped "|" shows as one letter
			elseif byte >= 240 then
				size = 4
			elseif byte >= 224 then
				size = 3
			elseif byte >= 192 then
				size = 2
			end
			count = count + (raw and size or 1)
			i = i + size
		end
	end
	Close()
	return segments
end

local function Strip(block, index, color)
	block.qcMarks = block.qcMarks or {}
	local strip = block.qcMarks[index]
	if not strip then
		-- Behind the title (a font string on the block) and behind objective lines (child frames of the block).
		strip = block:CreateTexture(nil, "BACKGROUND", nil, 1)
		block.qcMarks[index] = strip
	end
	strip:SetColorTexture(color.r, color.g, color.b, MARK_ALPHA)
	strip:ClearAllPoints()
	strip:Show()
	return strip
end

local function Place(block, fontString, used, mode, color)
	local text = fontString and fontString:IsVisible() and fontString:GetText()
	if type(text) ~= "string" or not text:find(MARK, 1, true) then
		return used
	end
	local left, bottom = fontString:GetLeft(), fontString:GetBottom()
	if not (left and bottom) then
		return used
	end
	local k = mode.screen and 1 / fontString:GetEffectiveScale() or 1
	local originX, originY = mode.relative and 0 or left, mode.relative and 0 or bottom
	local boxWidth, boxHeight = fontString:GetWidth() or 0, fontString:GetHeight() or 0
	for _, segment in ipairs(Segments(text, mode.raw)) do
		local ok, areas = pcall(fontString.CalculateScreenAreaFromCharacterSpan, fontString, segment[1], segment[2])
		if not (ok and type(areas) == "table" and areas[1]) then
			pendingRetry = true -- the line may not be measured yet; placed again next frame
		else
			for _, area in ipairs(areas) do
				if type(area.left) == "number" and type(area.bottom) == "number" and area.width and area.width > 0 then
					local x, y = area.left * k - originX, area.bottom * k - originY
					local w, h = area.width * k, (area.height or 0) * k
					-- Letters cut off by a title's two-line limit fall outside the line's box; they get no strip.
					if x >= -2 and x + w <= boxWidth + 2 and y >= -2 and y + h <= boxHeight + 2 then
						used = used + 1
						local strip = Strip(block, used, color)
						-- A pixel of room each side, like a highlighter stroke.
						strip:SetPoint("BOTTOMLEFT", fontString, "BOTTOMLEFT", x - 1, y)
						strip:SetSize(w + 2, h)
					end
				end
			end
		end
	end
	return used
end

function T.HideSearchMarks(block)
	for _, strip in ipairs(block.qcMarks or {}) do
		strip:Hide()
	end
end

-- After each layout: strips behind every run of matched letters in Marker style; none otherwise. `isRetry` is the one
-- extra pass on the next frame, which never queues another.
function T.ApplySearchMarks(isRetry)
	local module = T.module
	if not module then
		return
	end
	local mode
	if needle and Q.db.searchStyle ~= "letters" then
		mode = Probe()
		if mode == nil then
			-- The test line isn't measured yet: redraw shortly (Probe gives up after a few tries).
			C_Timer.After(0.2, function()
				T.MarkDirty(true)
			end)
		elseif mode == false and not fellBack then
			-- Strips can't be placed here: redraw once so matches use coloured letters instead.
			fellBack = true
			T.MarkDirty(true)
		end
	end
	local color = Q.Color("colorSearch")
	pendingRetry = false
	module:EnumerateActiveBlocks(function(block)
		local used = 0
		if mode and block:IsVisible() then
			used = Place(block, block.HeaderText, used, mode, color)
			for _, line in pairs(block.usedLines or {}) do
				used = Place(block, line.Text, used, mode, color)
			end
		end
		for index = used + 1, #(block.qcMarks or {}) do
			block.qcMarks[index]:Hide()
		end
	end)
	-- Freshly set text can be unmeasured in the frame it was set; place the strips once more on the next frame.
	if pendingRetry and not retryQueued and not isRetry then
		retryQueued = true
		C_Timer.After(0, function()
			retryQueued = false
			if needle then
				T.ApplySearchMarks(true)
			end
		end)
	end
end
