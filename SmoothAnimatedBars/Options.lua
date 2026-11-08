-- Settings page in the game's AddOns options, built on the native Settings API.
-- Values live directly in SmoothAnimatedBarsDB; changes are forwarded to ns.Core.OnSettingChanged.
--
-- The page is a canvas: one frame of ours, with every row drawn by the game's own row template on a
-- frame of ours, so it looks like the game's pages. It is not a vertical layout list. The game
-- reuses that list's row frames for every category, and on Forever rows set up by an addon's code
-- carry its taint into the Social page, which then has its protected IsUserOAuthed blocked in the
-- addon's name. So nothing is added to the game's lists, and every row is built once at login while
-- the page is hidden, never while the settings panel is open.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

-- The settings list's own measurements (Blizzard_SettingsList.xml), so the page lines up with the
-- game's: the header strip, where the list sits under it, the row padding, and the row heights.
local HEADER_H, TITLE_X, TITLE_Y = 50, 7, -22
local LIST_X, LIST_Y, LIST_RIGHT, LIST_BOTTOM = -15, -2, -20, -2
local PAD, PAD_LEFT, SPACING = 10, 25, 9
local ROW_H, SECTION_H = 26, 45

local category, canvas, content, db, defaults
local rows = {} -- { frame, initializer, height, shown }, in page order
local registered = {}
local LayoutRows

local function Register(key, name)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), name, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
        -- A row that shows only with some settings comes and goes with them.
        if content then LayoutRows() end
    end)
    registered[key] = setting
    return setting
end

-- A row: a frame of ours made from the initializer's template. The template's code finds its
-- initializer through GetElementData, as it does in the game's list. opts.indent indents its label as the game's
-- list does a setting that belongs to the one above; opts.shown, a function, shows it only while it is true.
local function Row(initializer, height, opts)
    opts = opts or {}
    if opts.indent and initializer.Indent then initializer:Indent() end
    local frame = CreateFrame("Frame", nil, content, initializer:GetTemplate())
    frame.GetElementData = function() return initializer end
    initializer:InitFrame(frame)
    rows[#rows + 1] = { frame = frame, initializer = initializer, height = height or ROW_H, shown = opts.shown }
end

local function Header(text)
    Row(CreateSettingsListSectionHeaderInitializer(text), SECTION_H)
end

local function Checkbox(key, name, tooltip)
    Row(Settings.CreateCheckboxInitializer(Register(key, name), nil, tooltip))
end

local function Dropdown(key, name, tooltip, getOptions, opts)
    Row(Settings.CreateDropdownInitializer(Register(key, name), getOptions, tooltip), nil, opts)
end

-- The fifth argument is whether the row adds search tags; the game asserts it is given, and a
-- canvas has nothing for the search to find.
local function Button(name, text, onClick, tooltip)
    Row(CreateSettingsButtonInitializer(name, text, onClick, tooltip, false))
end

-- The bar's own colour first, then every theme.
local function ColorOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("game", "Game Colour")
    for _, key in ipairs(ns.Themes.order) do
        container:Add(key, ns.Themes.list[key].name)
    end
    return container:GetData()
end

-- The same for another frame's bar, which can also follow the player's or the target's: label names whose.
local function SameAsOptions(label)
    return function()
        local container = Settings.CreateControlTextContainer()
        container:Add("same", label)
        container:Add("game", "Game Colour")
        for _, key in ipairs(ns.Themes.order) do
            container:Add(key, ns.Themes.list[key].name)
        end
        return container:GetData()
    end
end

local function MobOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("reaction", "Reaction")
    container:Add("game", "Game Colour")
    container:Add("class", "Mob's Class")
    container:Add("own", "Your Class")
    return container:GetData()
end

-- The page frame: the title and divider the game's list draws above its rows, and a scroll frame
-- for the rows where the list would be. The game parents and shows it when the category opens.
local function BuildPage(title)
    canvas = CreateFrame("Frame")
    canvas:Hide()

    local text = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    text:SetPoint("TOPLEFT", TITLE_X, TITLE_Y)
    text:SetText(title)

    local divider = canvas:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 0, -HEADER_H)
    divider:SetPoint("TOPRIGHT", LIST_RIGHT, -HEADER_H)
    divider:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, canvas)
    scroll:SetPoint("TOPLEFT", LIST_X, -HEADER_H + LIST_Y)
    scroll:SetPoint("BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
    end)

    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, canvas, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -4)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -1, 7)
    else
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local offset = self:GetVerticalScroll() - delta * 30
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
        end)
    end

    -- Each time the page opens every row reads its setting again, as the game's list does, so
    -- changes made elsewhere (/sab on, /sab off) show.
    canvas:SetScript("OnShow", function()
        for _, row in ipairs(rows) do
            row.initializer:Resetter(row.frame)
            row.initializer:InitFrame(row.frame)
        end
        LayoutRows()
    end)
end

function LayoutRows()
    local y = PAD
    for _, row in ipairs(rows) do
        local shown = not row.shown or row.shown()
        row.frame:SetShown(shown)
        if shown then
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_LEFT, -y)
            row.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row.frame:SetHeight(row.height)
            y = y + row.height + SPACING
        end
    end
    content:SetHeight(y - SPACING + PAD)
end

function Options.Register(savedDB, defaultValues)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.CreateCheckboxInitializer
        and CreateSettingsButtonInitializer and CreateSettingsListSectionHeaderInitializer) then
        return
    end
    db, defaults = savedDB, defaultValues
    local title = "Smooth Animated Bars"

    BuildPage(title)
    category = Settings.RegisterCanvasLayoutCategory(canvas, title)

    -- One section per frame: each bar on or off, and while it is on, its colour under it.
    local function On(key) return function() return db[key] end end
    local function Frame(title, prefix, healthColor, powerColor, sameAs, extra)
        Header(title)
        Checkbox(prefix .. "Health", "Health", "Liquid in " .. extra.whose .. " health bar.")
        Dropdown(healthColor, "Colour", extra.health, sameAs or ColorOptions,
            { indent = true, shown = On(prefix .. "Health") })
        Checkbox(prefix .. "Power", "Power", "Liquid in " .. extra.whose .. " power bar.")
        Dropdown(powerColor, "Colour", extra.power, sameAs or ColorOptions,
            { indent = true, shown = On(prefix .. "Power") })
    end
    local SAME_TARGET = "Same as Target follows your target's colour, which can itself follow yours."
    Frame("Player", "player", "healthColor", "powerColor", nil, { whose = "your",
        health = "Game Colour keeps health green. A theme brings its own colours and particles. Class Color shows yours.",
        power = "Game Colour follows the power type: blue mana, red rage, yellow energy. A theme brings its own colours "
            .. "and particles." })
    Frame("Target", "target", "targetHealthColor", "targetPowerColor", SameAsOptions("Same as Yours"), {
        whose = "your target's",
        health = "Same as Yours follows your own health colour. Class Color shows a targeted player's class.",
        power = "Same as Yours follows your own power colour. Class Color shows a targeted player's class." })
    Dropdown("mobClassColor", "Class Color on Mobs",
        "What Class Color shows when your target, focus or target of target is a mob. Reaction: red if hostile, yellow "
        .. "if neutral, green if friendly. Game Colour: the bar's own colour, so only players show a class. Mob's "
        .. "Class: the class the game gives it, which most mobs do not show. Your Class: your own.",
        MobOptions, { indent = true, shown = ns.Core.TargetUsesClass })
    Frame("Pet", "pet", "petHealthColor", "petPowerColor", SameAsOptions("Same as Yours"), { whose = "your pet's",
        health = "Same as Yours follows your own health colour; with Class Color your pet takes your class.",
        power = "Same as Yours follows your own power colour." })
    Frame("Focus", "focus", "focusHealthColor", "focusPowerColor", SameAsOptions("Same as Target"), {
        whose = "your focus's", health = SAME_TARGET, power = SAME_TARGET })
    Frame("Target of Target", "tot", "totHealthColor", "totPowerColor", SameAsOptions("Same as Target"), {
        whose = "your target's target's and your focus's target's", health = SAME_TARGET, power = SAME_TARGET })

    Header("Effects")
    Checkbox("waves", "Liquid Waves", "Wobbling liquid front that ripples when the bar changes.")
    Checkbox("swirl", "Magic Swirl", "Glowing veins, clouds and light drifting inside the liquid.")
    Checkbox("bubbles", "Bubbles", "Bubbles rising through the liquid.")
    Checkbox("sparkles", "Sparkles", "Motes thrown off the front when the bar changes.")
    Checkbox("ambient", "Theme Particles", "Embers, snow, spores, stars and the like from themes that have them.")
    Checkbox("lightning", "Lightning", "Faint flashes in the liquid that build into a storm when the bar changes a lot.")

    Header("Damage Over Time")
    Checkbox("dots", "DoT Marker",
        "The health your damage-over-time spells will still burn away turns into a liquid of their own colour, "
        .. "eating into your target's health. If no health liquid is left, they will kill the target.")
    Checkbox("dotKillIcon", "Kill Icon",
        "The game's skull on your target's portrait when your DoTs will finish it off.")

    Header("Healing")
    Checkbox("heals", "Heal Marker",
        "The health your own heals over time, bandages and heals you are casting on yourself will still bring back "
        .. "shows ahead of your health as a liquid of its own: Holy gold for priest and paladin heals, spring green "
        .. "for druid and shaman heals and for bandages. Food and drink show too, ahead of your health and your mana.")

    Header("Mana")
    Checkbox("manaBuild", "Mana Regen Build-Up",
        "After a spell that costs mana, your mana stops regenerating from Spirit for five seconds. Your mana bar builds "
        .. "up through that wait and lets go in a burst of stars as regeneration returns.")

    Header("Setup")
    Button("Setup Wizard", "Open", function() ns.Wizard.Open() end,
        "Pick the bars, their colours, how lively they are and the DoT marker again, seeing each choice on your frame.")

    LayoutRows()
    Settings.RegisterAddOnCategory(category)
end

-- Change one setting through its control, as the player would. False when there is no control.
function Options.Set(key, value)
    local setting = registered[key]
    if not setting then return false end
    setting:SetValue(value)
    return true
end

function Options.Open()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
end
