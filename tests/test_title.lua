-- Quest title colours come from the difficulty of the individual quest, even without a displayed quest level.
local T, db, check = TEST.T, TEST.Q.db, TEST.check
local savedPlayerInfo, savedPalette, savedGeneric = C_PlayerInfo, GetDifficultyColor, GetQuestDifficultyColor
local savedDifficulty, savedLevels, savedTitle, savedDone = db.difficulty, db.levels, db.colorTitle, db.colorDone
db.difficulty, db.levels, db.colorTitle, db.colorDone = true, false, "123456", "abcdef"

local rating = 0
C_PlayerInfo = {}
function C_PlayerInfo.GetContentDifficultyQuestForPlayer(id)
	if id == 42 then return rating end
end
local function Palette(value)
	if value == 0 then return { r = 1, g = 0, b = 0 }, { r = 1, g = 0.5, b = 0.5 } end
end
GetDifficultyColor = Palette
-- The generic level-based helper deliberately disagrees with the quest-ID result.
GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 0 } end

local normal, hover = T.Title(42, {}, false)
check("T1 quest ID determines the colour when the level is missing", normal == "|cffff0000Quest 42|r", normal)
check("T2 hovering uses the client's highlight for the same rating", hover == "|cffff8080Quest 42|r", hover)

local info = { level = 30, difficultyLevel = 26 }
db.levels = true
normal = T.Title(42, info, false)
check("T3 prefix uses the quest's difficulty level", normal == "|cffff0000[26] Quest 42|r", normal)
db.levels = false
normal = T.Title(42, info, true)
check("T4 completed quests keep the chosen finished colour", normal == "|cffabcdefQuest 42 (Complete)|r", normal)
db.difficulty = false
normal = T.Title(42, info, false)
check("T5 turning difficulty off uses the chosen title colour", normal == "|cff123456Quest 42|r", normal)

db.difficulty = true
local titleText = "Quest 42|r"
local fallback = "|cff123456" .. titleText
local fallbackHover = T.Hex(TEST.Q.Color("colorTitle").reverse) .. titleText
local function CheckFallback(label)
	local title, highlight = T.Title(42, info, false)
	check(label, title == fallback and highlight == fallbackHover, title .. " / " .. highlight)
end
WOW.secret[0] = true
CheckFallback("T6 restricted rating uses the title colour")
WOW.secret[0] = nil
rating = nil
CheckFallback("T7 missing rating uses the title colour")
C_PlayerInfo.GetContentDifficultyQuestForPlayer = function() error("quest difficulty unavailable") end
CheckFallback("T8 failed query uses the title colour")
GetDifficultyColor = nil
C_PlayerInfo.GetContentDifficultyQuestForPlayer = function() return 0 end
CheckFallback("T9 missing difficulty palette uses the title colour")
GetDifficultyColor = Palette
C_PlayerInfo = nil
CheckFallback("T10 missing quest difficulty API uses the title colour")

C_PlayerInfo, GetDifficultyColor, GetQuestDifficultyColor = savedPlayerInfo, savedPalette, savedGeneric
db.difficulty, db.levels, db.colorTitle, db.colorDone = savedDifficulty, savedLevels, savedTitle, savedDone
