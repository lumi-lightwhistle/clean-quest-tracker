-- The look (Appearance page): themes are presets for the look's settings, a hand-made mix becomes Custom and is kept,
-- trying a theme never saves it, and zone and bar colours follow the look or the Colours page.
local Q, T, db, check = TEST.Q, TEST.T, TEST.Q.db, TEST.check
local F = Q.Frame
local saved = { backdrop = db.backdrop, border = db.border, opacity = db.opacity, colorZone = db.colorZone,
	theme = db.theme, lookFrom = db.lookFrom, lookCustom = db.lookCustom }
for _, key in ipairs(Q.LOOK_KEYS) do
	saved[key] = db[key]
end

-- The defaults are the Classic theme, the look the tracker always had.
local same = true
for _, key in ipairs(Q.LOOK_KEYS) do
	if Q.defaults[key] ~= Q.THEMES.classic[key] then
		same = false
	end
end
check("TH1 the defaults are the Classic theme", same)
for name, look in pairs(Q.THEMES) do
	local ok = true
	for _, key in ipairs(Q.LOOK_KEYS) do
		if not Q.LookValueOK(key, look[key]) then
			ok = false
		end
	end
	check("TH2 every value of the " .. name .. " theme is one its setting can take", ok)
end

Q.ApplyTheme("classic")
db.backdrop, db.border, db.opacity = false, false, 0.3
check("TH3 Classic is the theme in use", db.theme == "classic" and Q.Look("moonSky") == "plain")

-- Trying.
Q.TryTheme("moonglow")
check("TH4 trying shows the theme's look", Q.Theme() == "moonglow" and Q.Look("lookTitle") == "moonlit", Q.Look("lookTitle"))
check("TH5 trying saves nothing", db.theme == "classic" and db.lookTitle == "gold")
check("TH6 a try borrows a background and border", F.ShowsPanel() and F.ShowsBorder())
check("TH7 a borrowed background uses the default darkness", F.PanelDarkness() == Q.defaults.opacity, F.PanelDarkness())
Q.EndTrial(false)
check("TH8 Go back puts the look back", Q.Look("lookTitle") == "gold" and Q.trial == nil and not F.ShowsPanel())
Q.TryTheme("moonglow")
Q.EndTrial(true)
check("TH9 Keep puts the theme's look in place", db.theme == "moonglow" and db.lookTitle == "moonlit" and Q.trial == nil)
check("TH10 Keep leaves the frame as it was", db.backdrop == false and db.border == false)
Q.TryTheme("moonglow")
check("TH11 trying the theme in use is no try", Q.trial == nil)

-- Custom.
db.moonBars = "glass"
Q.UpdateThemeName()
check("TH12 a change by hand makes the look Custom", db.theme == "custom" and db.lookFrom == "moonglow", db.theme)
check("TH13 the Custom mix is kept", type(db.lookCustom) == "table" and db.lookCustom.moonBars == "glass")
Q.ApplyTheme("classic")
check("TH14 using a theme keeps the Custom mix", db.theme == "classic" and db.lookCustom and db.lookCustom.moonBars == "glass")
Q.ApplyTheme("custom")
check("TH15 Custom brings the mix back", db.theme == "custom" and db.moonBars == "glass" and db.lookTitle == "moonlit")
db.moonBars = Q.THEMES.moonglow.moonBars
Q.UpdateThemeName()
check("TH16 a mix that matches a theme is that theme", db.theme == "moonglow", db.theme)

-- Colours.
db.colorZone = "112233"
db.lookZones = "silver"
local silver = T.ZoneColor()
check("TH17 moonsilver zone names", silver.r > 0.85 and silver.b == 1, silver.r)
db.lookZones = "mine"
check("TH18 My colour zone names use the Colours page", math.abs(T.ZoneColor().r - 0x11 / 255) < 0.001)
local readable = true
for key, hex in pairs(Q.BAR_COLOURS) do
	if not (Q.LOOK_CHOICES.lookBarColour[key] and Q.ColorOf(hex)) then
		readable = false
	end
end
check("TH19 every theme bar colour can be read and picked", readable)

-- Migrating a schema 6 save (origin of every player before themes).
local Migrate = Q._internal.Migrate
local function Saved(fields)
	local saved = { schema = 6, enabled = true, borderFinish = "polished", backdrop = false, border = false }
	for key, value in pairs(fields or {}) do
		saved[key] = value
	end
	Migrate(saved)
	return saved
end
local plain = Saved()
check("TH20 a plain save keeps the Classic look", plain.borderOrnament == nil and plain.lookCrest == nil and plain.theme == nil)
local ornate = Saved({ borderFlourish = true, borderCrest = true })
check("TH21 flourishes and crest carry over", ornate.borderOrnament == "flourish" and ornate.lookCrest == "diamond"
	and ornate.borderFlourish == nil and ornate.borderCrest == nil)
local old = Saved({ bgTheme = "moonglow", backdrop = true })
check("TH22 the old Moonglow background becomes the Moonglow theme", old.theme == "moonglow" and old.lookFrom == "moonglow"
	and old.borderFinish == "moonsilver" and old.moonSky == "midnight" and old.bgTheme == nil, old.borderFinish)
local bronze = Saved({ bgTheme = "moonglow", backdrop = true, border = true, borderFinish = "aged" })
check("TH23 an old Moonglow background keeps its bronze border", bronze.borderFinish == "aged" and bronze.theme == "moonglow")
local test = Saved({ theme = "moonglow", moonBorder = "silver", moonCorners = "bracket", moonCrest = "off", moonBars = "sheen",
	moonBeam = "sweep", moonGlint = true, moonCustom = {}, moonPreset = "custom" })
check("TH24 a test build's Moonglow carries over", test.borderFinish == "moonsilver" and test.borderOrnament == "bracket"
	and test.moonBars == "glass" and test.moonBeam == true and test.moonGleam == "tide" and test.lookTitle == "moonlit"
	and test.moonStars == true and test.lookCrest == "none" and test.moonCustom == nil and test.moonGlint == nil
	and test.moonPreset == nil, test.lookCrest)
local off = Saved({ theme = "moonglow", moonCorners = "off", moonCrest = "live" })
check("TH25 a test build's corners turned off stay off", off.borderOrnament == "none" and off.lookCrest == "tonight",
	off.borderOrnament)

for key, value in pairs(saved) do
	db[key] = value
end
db.lookCustom = saved.lookCustom -- pairs skips a nil, so put the mix back by hand
Q.trial = nil
