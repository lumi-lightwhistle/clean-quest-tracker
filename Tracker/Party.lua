-- Party badge: how many other members of your party have each quest, who they are, and one-click sharing.

local _, Q = ...
local P = {}
Q.Party = P

local ICON = "Interface\\AddOns\\CleanQuestTracker\\Media\\PartyIcon"
local ICON_SIZE = 13
local FULL = { r = 1, g = 0.82, b = 0 }
local GREY = { r = 0.55, g = 0.55, b = 0.55 }
local measure

local function Readable(value)
	return Q.Readable(value) and value or nil
end

local function ClassColor(class)
	if not class then
		return nil
	end
	if C_ClassColor and C_ClassColor.GetClassColor then
		return C_ClassColor.GetClassColor(class)
	end
	return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

local function Member(unit)
	local name = Readable(UnitName(unit))
	local _, class = UnitClass(unit)
	-- `full` is "Name-Realm" for someone from another realm; Questie files its party data under it.
	return { unit = unit, name = name, full = Readable(GetUnitName(unit, true)), class = Readable(class) }
end

------------------------------------------------------------------------------------------------------------------------
-- Who is on a quest. Forever has more than one way to ask, and they don't always agree, so a member counts when any
-- source says yes:
--   1. IsUnitOnQuest(questLogIndex, unit), the older global. Forever's own quest log (and Kerzo's) uses this, and it
--      is the one that sees members wherever they are.
--   2. C_QuestLog.IsUnitOnQuest(unit, questID), the newer API, which Blizzard's retail code uses.
--   3. The quest's party-progress data, which the game's party tooltip is built from. Read only when neither call
--      above gave a readable answer (a restricted "secret" value), since it is the most expensive.
--   4. Questie's party sync, when Questie is installed. Questie members send each other their quest logs by add-on
--      message, so this works at any distance, where the game's own sources only see nearby members. Kerzo's quest
--      log reads the same data (QuestieComms:GetQuest), read-only.
------------------------------------------------------------------------------------------------------------------------

-- Questie's comms module, or nil. Looked up through Questie's own loader, and only once Questie has loaded, so the
-- loader never creates an empty module on our behalf. A miss is retried next time; a hit is kept.
local questieComms
local function QuestieComms()
	if questieComms then
		return questieComms
	end
	local loader = rawget(_G, "QuestieLoader")
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return nil
	end
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")) then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, "QuestieComms")
	if ok and type(module) == "table" and type(module.GetQuest) == "function" then
		questieComms = module
	end
	return questieComms
end

local function ShortName(name)
	return type(name) == "string" and (name:match("^[^%-]+") or name) or nil
end

-- Names (full and short) of players Questie says have the quest, or nil when Questie has nothing for it.
local function QuestieNames(questID)
	local comms = QuestieComms()
	if not comms then
		return nil
	end
	local ok, players = pcall(comms.GetQuest, comms, questID)
	if not ok or type(players) ~= "table" then
		return nil
	end
	local names
	for name in pairs(players) do
		if Readable(name) and type(name) == "string" then
			names = names or {}
			names[name] = true
			names[ShortName(name)] = true
		end
	end
	return names
end

-- One member's objectives on a quest as Questie last received them ({ [index] = { fulfilled, required, finished } }),
-- or nil when Questie has nothing from them. This is what lets the tooltip show progress for members too far away
-- for the game's own party-progress data.
local function QuestieObjectives(questID, member)
	local comms = QuestieComms()
	if not comms then
		return nil
	end
	local ok, players = pcall(comms.GetQuest, comms, questID)
	if not ok or type(players) ~= "table" then
		return nil
	end
	-- The full "Name-Realm" first, so two members who share a name on different realms can't be mixed up.
	local exact = member.full and players[member.full]
	if type(exact) == "table" then
		return exact
	end
	for name, objectives in pairs(players) do
		if Readable(name) and type(name) == "string" and type(objectives) == "table" and ShortName(name) == member.name then
			return objectives
		end
	end
	return nil
end

-- A source's answer: true, false, or "secret" when the client won't let add-on code read it.
local function Answer(ok, value)
	if not ok then
		return false
	end
	if issecretvalue and issecretvalue(value) then
		return "secret"
	end
	return value and value ~= 0 and true or false
end

-- GUIDs of the party members listed in the quest's party-progress data, or nil when it can't be read. The second result
-- is true when some member's line couldn't be read, so the set may be missing someone.
local function ProgressGUIDs(questID)
	local info = C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress
	local lineTypes = Enum and Enum.TooltipDataLineType
	if not (info and lineTypes and lineTypes.QuestPlayer) then
		return nil
	end
	-- The whole read is guarded: any field of tooltip data can come back restricted.
	local ok, guids, partial = pcall(function()
		local data = info(questID, true, true)
		if type(data) ~= "table" or not Q.Readable(data.lines) or type(data.lines) ~= "table" then
			return nil
		end
		local found, missed = nil, false
		for _, line in ipairs(data.lines) do
			local lineType = type(line) == "table" and Readable(line.type)
			if type(line) == "table" and not lineType then
				missed = true
			elseif lineType == lineTypes.QuestPlayer then
				local guid = Readable(line.guid)
				if type(guid) == "string" then
					found = found or {}
					found[guid] = true
				else
					missed = true
				end
			end
		end
		return found, missed
	end)
	if not ok then
		return nil
	end
	return guids, partial
end

-- What each source says about one unit: whether they count, then each source's answer. `cache.guids` holds the
-- quest's party-progress GUIDs once read ("none" when unreadable), so it is read at most once per quest per pass.
-- `cache.always` reads it even when the calls answered plainly (for /cqt party).
local function Check(unit, questID, logIndex, cache)
	local legacy, modern = false, false
	if IsUnitOnQuest and logIndex then
		legacy = Answer(pcall(IsUnitOnQuest, logIndex, unit))
	end
	if C_QuestLog.IsUnitOnQuest then
		modern = Answer(pcall(C_QuestLog.IsUnitOnQuest, unit, questID))
	end
	local progress = false
	if legacy ~= true and modern ~= true and (legacy == "secret" or modern == "secret" or cache.always) then
		if cache.guids == nil then
			cache.guids = ProgressGUIDs(questID) or "none"
		end
		local guid = cache.guids ~= "none" and Readable(UnitGUID(unit))
		progress = guid and cache.guids[guid] and true or false
	end
	local questie = false
	if (legacy ~= true and modern ~= true and not progress) or cache.always then
		if cache.questie == nil then
			cache.questie = QuestieNames(questID) or "none"
		end
		if cache.questie ~= "none" then
			local full = Readable(GetUnitName(unit, true))
			local short = Readable(UnitName(unit))
			questie = (full and cache.questie[full]) or (short and cache.questie[short]) or false
		end
	end
	return legacy == true or modern == true or progress or questie, legacy, modern, progress, questie
end

-- Other members of your party (your raid subgroup in a raid) who have the quest, and how many others are in it.
function P.Members(questID)
	if P.fake then -- /cqt fakeparty
		local fakes = {}
		for index = 1, P.fake do
			fakes[index] = { unit = "party" .. index, name = "Tester" .. index, class = "WARRIOR" }
		end
		return fakes, 4
	end
	if not (Q.db.party and IsInGroup()) then
		return nil
	end
	local size = GetNumSubgroupMembers()
	if size == 0 then
		return nil
	end
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	local cache = {}
	local members = {}
	for index = 1, size do
		local unit = "party" .. index
		if UnitExists(unit) and Check(unit, questID, logIndex, cache) then
			members[#members + 1] = Member(unit)
		end
	end
	if #members == 0 then
		return nil
	end
	return members, size
end

-- How many other members have the quest, without building member records. For the once-a-second watchdog.
function P.Count(questID)
	if P.fake then
		return P.fake
	end
	if not (Q.db.party and IsInGroup()) then
		return 0
	end
	local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	local cache, count = {}, 0
	for index = 1, GetNumSubgroupMembers() do
		local unit = "party" .. index
		if UnitExists(unit) and Check(unit, questID, logIndex, cache) then
			count = count + 1
		end
	end
	return count
end

-- /cqt party: what every source reports for each tracked quest and party member, to see which one the client answers.
function P.Report()
	if not IsInGroup() or GetNumSubgroupMembers() == 0 then
		Q.Print("You're not in a party.")
		return
	end
	local function Show(value)
		if value == "secret" then
			return "|cffff8040hidden|r"
		end
		return value and "|cff20ff20yes|r" or "|cff808080no|r"
	end
	Q.Print(("Party check (setting %s). Sources: old API / new API / tooltip data / Questie%s."):format(
		Q.db.party and "on" or "OFF",
		QuestieComms() and "" or " (not installed)"
	))
	local any = false
	for watchIndex = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(watchIndex)
		local logIndex = questID and C_QuestLog.GetLogIndexForQuestID(questID)
		if logIndex then
			local cache = { always = true }
			local parts = {}
			for index = 1, GetNumSubgroupMembers() do
				local unit = "party" .. index
				if UnitExists(unit) then
					local has, legacy, modern, progress, questie = Check(unit, questID, logIndex, cache)
					any = any or has
					parts[#parts + 1] = ("%s %s/%s/%s/%s"):format(
						Readable(UnitName(unit)) or unit,
						Show(legacy),
						Show(modern),
						Show(progress),
						Show(questie)
					)
				end
			end
			-- Whether the tracker actually has a badge on screen for it, to tell a detection problem from a drawing one.
			local module = Q.Tracker.module
			local block = module and module:GetExistingBlock(questID)
			local badge
			if not block then
				badge = "not drawn (zone folded?)"
			else
				badge = (block.qcBadge and block.qcBadge:IsVisible()) and "badge shown" or "no badge"
			end
			print(("  %s [%s]: %s"):format(
				C_QuestLog.GetTitleForQuestID(questID) or questID,
				badge,
				table.concat(parts, ", ")
			))
		end
	end
	if not any then
		Q.Print("No source reports a party member on any tracked quest.")
	end
end

local function Missing(members)
	local have = {}
	for _, member in ipairs(members) do
		have[member.unit] = true
	end
	local missing = {}
	for index = 1, GetNumSubgroupMembers() do
		local unit = "party" .. index
		if UnitExists(unit) and not have[unit] then
			local name = Readable(UnitName(unit))
			if name then
				missing[#missing + 1] = name
			end
		end
	end
	return missing
end

local function LabelSize()
	return math.max(10, Q.db.fontSize - 1)
end

local function Label(count)
	if Q.db.partyStyle == "text" then
		return ("[%d %s]"):format(count, PARTY and PARTY:lower() or "party")
	end
	return tostring(count)
end

------------------------------------------------------------------------------------------------------------------------
-- Badge styles. All but Plain draw the count in a small container, so it can't be mistaken for the zone's quest
-- count. The containers are rounded images, nine-sliced so their corners keep their shape at any width. Every style
-- takes the Party badge colour from the Colours page, a lighter shade once the whole party has the quest.
------------------------------------------------------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\CleanQuestTracker\\Media\\"
local HEIGHT = 18
local PAD_LEFT, PAD_RIGHT, ICON_GAP, SPLIT_ICON = 5, 6, 3, 18
local BADGE_GAP = 3 -- clear space kept between badges on neighbouring rows
local SHAPES = {
	round = { file = MEDIA .. "BadgeRound", edge = MEDIA .. "BadgeRoundEdge", margin = 6 },
	pill = { file = MEDIA .. "BadgePill", edge = MEDIA .. "BadgePillEdge", margin = 9 },
}
local DARK = { r = 0.055, g = 0.043, b = 0.035 }
local INK = { r = 0.11, g = 0.075, b = 0.05 } -- icon and text on a light fill
local LIGHT_TEXT = { r = 0.94, g = 0.9, b = 0.81 }
local TEAL = { r = 0.247, g = 0.663, b = 0.788 }

-- In the order the settings window shows them.
P.STYLES = {
	{ key = "pill", name = "Pill", note = "Soft fill, rounded ends" },
	{ key = "chip", name = "Dark chip", note = "Quiet, with a faint edge" },
	{ key = "solid", name = "Solid", note = "Filled, the most visible" },
	{ key = "rim", name = "Forever rim", note = "Dark, with a teal rim light" },
	{ key = "split", name = "Split", note = "Icon block and number" },
	{ key = "plain", name = "Plain", note = "No container, as before" },
}
local KNOWN = {}
for _, style in ipairs(P.STYLES) do
	KNOWN[style.key] = true
end

local function CurrentStyle()
	local key = Q.db and Q.db.badgeStyle
	return KNOWN[key] and key or "pill"
end

local function Shade(color, amount)
	return { r = color.r * amount, g = color.g * amount, b = color.b * amount }
end

-- Points a texture at a container shape and nine-slices it. Where slicing isn't available it falls back to a plain
-- rectangle, which still takes the colour.
local function SetShape(texture, shape, edge)
	local info = SHAPES[shape]
	texture:SetTexture(edge and info.edge or info.file)
	local sliced = texture.SetTextureSliceMargins
		and pcall(texture.SetTextureSliceMargins, texture, info.margin, info.margin, info.margin, info.margin)
	if sliced and texture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
		pcall(texture.SetTextureSliceMode, texture, Enum.UITextureSliceMode.Stretched)
	elseif not sliced then
		texture:SetColorTexture(1, 1, 1, 1)
	end
end

local function TextWidth(text)
	if not measure then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:Hide()
		measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	end
	Q.Font(measure, LabelSize())
	measure:SetText(text)
	return math.ceil(measure:GetStringWidth() or 0)
end

-- Room for the widest label the badge can show at the current size and mode. Digits aren't all the same width in the
-- game font ("1" is narrower than "2"), so sizing the badge to its own count would make badges differ in size and the
-- layout shift whenever a count changed. Every badge uses this width, with its number centred in it. A party has at
-- most four other members, so only 1 to 4 are measured. A zero (the font not ready yet) is never kept.
local slotKey, slotWidth
local function SlotWidth()
	local key = LabelSize() .. Label(1)
	if key ~= slotKey then
		local widest = 0
		for count = 1, 4 do
			widest = math.max(widest, TextWidth(Label(count)))
		end
		if widest <= 0 then
			return slotWidth or 0
		end
		slotKey, slotWidth = key, widest
	end
	return slotWidth
end

-- The shortest a quest's row may be, with a badge on it, so badges on neighbouring rows keep BADGE_GAP between them. A
-- row of one line (a finished quest, or any quest folded by focus mode) is shorter than the badge, so stacked badges
-- would otherwise touch or overlap. The distance between two badges' tops is a row's height plus the gap below it.
function P.MinRow()
	return HEIGHT + BADGE_GAP - (Q.db.questGap or 0)
end

-- How wide the badge is. Every style and every count uses the Pill's width, so switching styles never moves the
-- titles or the badge. The tracker reserves this much room so titles wrap clear of it.
function P.BadgeWidth()
	local textMode = Q.db.partyStyle == "text"
	return PAD_LEFT + (textMode and 2 or ICON_SIZE + ICON_GAP) + SlotWidth() + PAD_RIGHT
end

------------------------------------------------------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------------------------------------------------------

-- The game's own party-progress tooltip lists each member close by with their objectives. Their names are recoloured to
-- class colours afterwards so the list reads like the raid frames; members it leaves out are added after it.
local function RecolorNames(members)
	local classes = {}
	for _, member in ipairs(members) do
		if member.name then
			classes[member.name] = member.class
		end
	end
	for index = 1, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. index]
		local text = line and Readable(line:GetText())
		if text then
			local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			local class = classes[plain] or classes[plain:match("^([^%-]+)") or ""]
			local color = ClassColor(class)
			if color then
				line:SetTextColor(color.r, color.g, color.b)
			end
		end
	end
end

-- Whether the game's own tooltip already lists this member (it only lists members close by). Read from the same
-- party-progress data the tooltip is built from (`guids`) when it can be; otherwise from the tooltip's text. If any line
-- can't be read, the member counts as listed, since a second copy of someone is worse than a missing one.
local function Listed(member, guids)
	local guid = guids and Readable(UnitGUID(member.unit))
	if guid then
		return guids[guid] and true or false
	end
	local unreadable = false
	for index = 1, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. index]
		local text = line and Readable(line:GetText())
		if text then
			local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if plain == member.name or plain == member.full or ShortName(plain) == member.name then
				return true
			end
		elseif line then
			unreadable = true
		end
	end
	return unreadable
end

-- The objective names from your own quest log ("Smotts' Chest"), to label a member's counts. Questie sends only the
-- counts, in the same order as the log.
local function ObjectiveNames(questID)
	local names = {}
	local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
	if ok and type(objectives) == "table" then
		for index, objective in ipairs(objectives) do
			local text = type(objective) == "table" and Readable(objective.text)
			if type(text) == "string" then
				-- "0/1 Smotts' Chest" or "Smotts' Chest: 0/1" -> "Smotts' Chest"
				text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
				names[index] = text ~= "" and text or nil
			end
		end
	end
	return names
end

-- A member's name in their class colour, then their progress on each objective as Questie reports it, laid out like
-- the game's own party-progress lines. Without Questie data the name stands alone, with a note when `nearbyNote` says
-- the game's own list would show them once they come close.
local function AddMemberProgress(member, questID, names, nearbyNote)
	local color = ClassColor(member.class) or HIGHLIGHT_FONT_COLOR
	GameTooltip:AddLine(member.name or UNKNOWN or "Unknown", color.r, color.g, color.b)
	local objectives = QuestieObjectives(questID, member)
	if not objectives then
		if nearbyNote then
			GameTooltip:AddLine("  Progress shows when they're nearby", GREY.r, GREY.g, GREY.b)
		end
		return
	end
	local indexes = {}
	for index in pairs(objectives) do
		if type(index) == "number" then
			indexes[#indexes + 1] = index
		end
	end
	table.sort(indexes)
	local done = Q.CompleteColor()
	for _, index in ipairs(indexes) do
		local objective = objectives[index]
		if type(objective) == "table" then
			local have, need = tonumber(objective.fulfilled), tonumber(objective.required)
			local finished = objective.finished or (have and need and have >= need)
			local label = names[index] or ("Objective %d"):format(index)
			local text
			if have and need then
				text = ("  - %d/%d %s"):format(have, need, label)
			else
				text = ("  - %s%s"):format(label, finished and "" or " (not done)")
			end
			local tint = finished and done or HIGHLIGHT_FONT_COLOR
			GameTooltip:AddLine(text, tint.r, tint.g, tint.b)
		end
	end
	if #indexes == 0 then
		GameTooltip:AddLine("  - " .. (QUEST_WATCH_QUEST_READY or "Ready for turn-in"), done.r, done.g, done.b)
	end
end

local function CanShare(questID, missing)
	return Q.db.partyShare and #missing > 0 and C_QuestLog.IsPushableQuest(questID)
end

local function ShowTooltip(badge)
	local questID, members, size = badge.questID, badge.members, badge.size
	local missing = Missing(members)
	local summary = ("Shared with %d of %d party members"):format(#members, size)
	GameTooltip:SetOwner(badge, Q.Frame.TooltipAnchor())
	local native = false
	if GameTooltip.SetQuestPartyProgress then
		native = pcall(GameTooltip.SetQuestPartyProgress, GameTooltip, questID) and GameTooltip:NumLines() > 0
	end
	local names = ObjectiveNames(questID)
	if native then
		RecolorNames(members)
		-- The game lists only members close by; anyone else on the quest is added with Questie's copy of their progress.
		-- A set with an unreadable line may be missing someone, so the text check (which errs towards "listed") decides.
		local guids, partial = ProgressGUIDs(questID)
		if partial then
			guids = nil
		end
		for _, member in ipairs(members) do
			if not Listed(member, guids) then
				AddMemberProgress(member, questID, names, true)
			end
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(summary, FULL.r, FULL.g, FULL.b)
	else
		GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(questID) or "", FULL.r, FULL.g, FULL.b)
		GameTooltip:AddLine(summary, 1, 1, 1)
		for _, member in ipairs(members) do
			AddMemberProgress(member, questID, names, false)
		end
	end
	if #missing > 0 then
		GameTooltip:AddLine(("Not on this quest: %s"):format(table.concat(missing, ", ")), GREY.r, GREY.g, GREY.b, true)
	end
	if CanShare(questID, missing) then
		GameTooltip:AddLine("Click to share this quest with them", 0.1, 1, 0.1)
	end
	GameTooltip:Show()
end

------------------------------------------------------------------------------------------------------------------------
-- Badge
------------------------------------------------------------------------------------------------------------------------
local function OnClick(badge, mouseButton)
	local block = badge:GetParent()
	-- Shift-click passes through to the title, which links the quest in chat.
	if mouseButton == "LeftButton" and not IsModifiedClick("CHATLINK") and CanShare(badge.questID, Missing(badge.members)) then
		Q.Tracker.ShareQuest(badge.questID)
		GameTooltip:Hide()
		return
	end
	if block and block.OnHeaderClick then
		block:OnHeaderClick(mouseButton)
	end
end

-- The layers every style draws from; each style shows the ones it needs.
local function Build(badge)
	badge:SetHeight(HEIGHT)
	badge.fill = badge:CreateTexture(nil, "BACKGROUND")
	badge.fill:SetAllPoints()
	badge.edge = badge:CreateTexture(nil, "BORDER")
	badge.edge:SetAllPoints()
	badge.block = badge:CreateTexture(nil, "BORDER", nil, 1) -- Split: the icon's own block
	badge.block:SetPoint("TOPLEFT")
	badge.block:SetPoint("BOTTOMLEFT")
	badge.block:SetWidth(SPLIT_ICON)
	badge.rim = badge:CreateTexture(nil, "ARTWORK") -- Forever rim: the teal line along the bottom
	badge.rim:SetHeight(1)
	badge.rim:SetPoint("BOTTOMLEFT", 4, 1)
	badge.rim:SetPoint("BOTTOMRIGHT", -4, 1)
	badge.icon = badge:CreateTexture(nil, "ARTWORK", nil, 2)
	badge.icon:SetTexture(ICON)
	badge.icon:SetSize(ICON_SIZE - 1, ICON_SIZE - 1)
	badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
end

-- Draws a badge for `count` of `size` party members in a style.
local function Paint(badge, count, size, style)
	local textMode = Q.db.partyStyle == "text"
	local full = count >= size
	local base = Q.Color("colorBadge")
	local tint = full and base.reverse or base
	local fill, edge, block, rim, icon, label = badge.fill, badge.edge, badge.block, badge.rim, badge.icon, badge.label

	Q.Font(label, LabelSize())
	label:SetText(Label(count))
	local width = P.BadgeWidth()
	badge:SetWidth(width)
	-- Centres this count's label in the shared width (a narrow "1" sits in the middle, not against the icon).
	local nudge = math.floor((SlotWidth() - TextWidth(Label(count))) / 2)
	fill:Hide()
	edge:Hide()
	block:Hide()
	rim:Hide()
	icon:SetShown(not textMode)
	icon:ClearAllPoints()
	label:ClearAllPoints()

	local iconColor, textColor = tint, LIGHT_TEXT
	if style ~= "plain" then
		SetShape(fill, style == "pill" and "pill" or "round")
		fill:Show()
	end
	if style == "pill" then
		fill:SetVertexColor(tint.r, tint.g, tint.b, full and 0.32 or 0.18)
		SetShape(edge, "pill", true)
		edge:SetVertexColor(tint.r, tint.g, tint.b, full and 0.95 or 0.6)
		edge:Show()
	elseif style == "chip" then
		fill:SetVertexColor(DARK.r, DARK.g, DARK.b, 0.82)
		SetShape(edge, "round", true)
		if full then
			edge:SetVertexColor(tint.r, tint.g, tint.b, 0.75)
		else
			edge:SetVertexColor(1, 1, 1, 0.14)
		end
		edge:Show()
	elseif style == "solid" then
		-- A gentle top-to-bottom shade; plain vertex colour where gradients aren't available.
		local top, bottom = tint, Shade(tint, 0.82)
		local ok = CreateColor and pcall(fill.SetGradient, fill, "VERTICAL",
			CreateColor(bottom.r, bottom.g, bottom.b, 1), CreateColor(top.r, top.g, top.b, 1))
		if not ok then
			fill:SetVertexColor(tint.r, tint.g, tint.b, 1)
		end
		iconColor, textColor = INK, INK
	elseif style == "rim" then
		fill:SetVertexColor(0.078, 0.063, 0.051, 0.9)
		SetShape(edge, "round", true)
		edge:SetVertexColor(tint.r, tint.g, tint.b, full and 0.7 or 0.35)
		edge:Show()
		rim:SetColorTexture(TEAL.r, TEAL.g, TEAL.b, full and 1 or 0.75)
		rim:Show()
	elseif style == "split" then
		fill:SetVertexColor(DARK.r, DARK.g, DARK.b, 0.85)
		SetShape(edge, "round", true)
		edge:SetVertexColor(tint.r, tint.g, tint.b, 0.5)
		edge:Show()
		if not textMode then
			SetShape(block, "round")
			block:SetVertexColor(tint.r, tint.g, tint.b, 0.9)
			block:Show()
		end
		iconColor = INK
	end

	icon:SetVertexColor(iconColor.r, iconColor.g, iconColor.b)
	label:SetTextColor(textColor.r, textColor.g, textColor.b)
	-- Plain places its icon and number where the Pill does, just without the container.
	if style == "split" then
		icon:SetPoint("CENTER", block, "CENTER", 0, 0)
		-- The number is centred in what the icon block leaves. The game font's digits sit about a pixel high in their
		-- line (the line leaves room for letters that hang below), and its "1" has its ink to the right of its cell,
		-- so both are pulled back to the box's centre.
		local left = textMode and 0 or SPLIT_ICON
		local inkX = (not textMode and count == 1) and -1 or 0
		label:SetPoint("LEFT", left + math.floor((width - left - SlotWidth()) / 2) + nudge + inkX, -1)
	elseif textMode then
		label:SetPoint("LEFT", PAD_LEFT + 2 + nudge, 0)
	else
		icon:SetPoint("LEFT", PAD_LEFT, 0)
		label:SetPoint("LEFT", icon, "RIGHT", ICON_GAP + nudge, 0)
	end
end

local function Create(block)
	local badge = CreateFrame("Button", nil, block)
	badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Build(badge)
	local highlight = badge:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.1)
	badge:SetScript("OnEnter", ShowTooltip)
	badge:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	badge:SetScript("OnClick", OnClick)
	block.qcBadge = badge
	return badge
end

-- A sample badge for the settings window's style picker: drawn exactly like the real one, but not clickable.
function P.CreatePreview(parent)
	local preview = CreateFrame("Frame", nil, parent)
	Build(preview)
	function preview:ShowStyle(style, wholeParty)
		Paint(self, wholeParty and 4 or 1, 4, style)
	end
	return preview
end

function P.Attach(block, members, size, offsetX)
	if not members then
		P.Detach(block)
		return
	end
	local badge = block.qcBadge or Create(block)
	local count = #members
	badge.questID, badge.members, badge.size = block.id, members, size
	Paint(badge, count, size, CurrentStyle())
	badge:SetFrameLevel(block:GetFrameLevel() + 3)
	badge:ClearAllPoints()
	badge:SetPoint("TOPRIGHT", block, "TOPRIGHT", offsetX, 2)
	badge:Show()
	if GameTooltip:IsOwned(badge) then
		ShowTooltip(badge)
	end
end

function P.Detach(block)
	if block.qcBadge then
		block.qcBadge:Hide()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Redraw as soon as Questie receives or drops party quest data: the same hook points Kerzo's quest log uses. These
-- are post-hooks (hooksecurefunc), so Questie's own code runs exactly as before. Anything they miss, the tracker's
-- once-a-second check picks up.
------------------------------------------------------------------------------------------------------------------------
local QUESTIE_METHODS = {
	"InsertQuestDataPacket",
	"InsertQuestDataPacketV2",
	"InsertQuestDataPacketV2_noclass_RenameMe",
	"RemoveRemotePlayer",
	"ResetAll",
}

local function HookQuestie()
	local comms = QuestieComms()
	if not comms or P.questieHooked then
		return
	end
	P.questieHooked = true
	local function Changed()
		Q.Debounce("party", 0.25, Q.Refresh)
	end
	for _, method in ipairs(QUESTIE_METHODS) do
		if type(comms[method]) == "function" then
			hooksecurefunc(comms, method, Changed)
		end
	end
end

-- Questie finishes setting up its modules after login, so the hooks go in a moment later.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	C_Timer.After(2, HookQuestie)
end)
