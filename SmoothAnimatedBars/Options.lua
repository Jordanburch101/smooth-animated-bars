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
local rows = {} -- { frame, initializer, height }, in page order
local registered = {}

local function Register(key, name)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), name, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
    end)
    registered[key] = setting
    return setting
end

-- A row: a frame of ours made from the initializer's template. The template's code finds its
-- initializer through GetElementData, as it does in the game's list.
local function Row(initializer, height)
    local frame = CreateFrame("Frame", nil, content, initializer:GetTemplate())
    frame.GetElementData = function() return initializer end
    initializer:InitFrame(frame)
    rows[#rows + 1] = { frame = frame, initializer = initializer, height = height or ROW_H }
end

local function Header(text)
    Row(CreateSettingsListSectionHeaderInitializer(text), SECTION_H)
end

local function Checkbox(key, name, tooltip)
    Row(Settings.CreateCheckboxInitializer(Register(key, name), nil, tooltip))
end

local function Dropdown(key, name, tooltip, getOptions)
    Row(Settings.CreateDropdownInitializer(Register(key, name), getOptions, tooltip))
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
    end)
end

local function LayoutRows()
    local y = PAD
    for _, row in ipairs(rows) do
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_LEFT, -y)
        row.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row.frame:SetHeight(row.height)
        y = y + row.height + SPACING
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

    Header("Bars")
    Checkbox("playerHealth", "Player Health", "Liquid in your health bar.")
    Checkbox("playerPower", "Player Power", "Liquid in your mana, rage, energy or focus bar.")
    Checkbox("targetHealth", "Target Health", "Liquid in your target's health bar.")
    Checkbox("targetPower", "Target Power", "Liquid in your target's power bar.")

    Header("Colours")
    Dropdown("healthColor", "Health Colour",
        "Game Colour keeps health green. A theme brings its own colours and particles.", ColorOptions)
    Dropdown("powerColor", "Power Colour",
        "Game Colour follows the power type: blue mana, red rage, yellow energy. A theme brings its own colours and particles.",
        ColorOptions)

    Header("Effects")
    Checkbox("waves", "Liquid Waves", "Wobbling liquid front that ripples when the bar changes.")
    Checkbox("swirl", "Magic Swirl", "Glowing veins, clouds and light drifting inside the liquid.")
    Checkbox("bubbles", "Bubbles", "Bubbles rising through the liquid.")
    Checkbox("sparkles", "Sparkles", "Motes thrown off the front when the bar changes.")
    Checkbox("ambient", "Theme Particles", "Embers, snow, spores, stars and the like from themes that have them.")
    Checkbox("lightning", "Lightning", "Faint flashes in the liquid that build into a storm when the bar changes a lot.")

    Header("Setup")
    Button("Setup Wizard", "Open", function() ns.Wizard.Open() end,
        "Pick the bars, their colours and how lively they are again, seeing each choice on your frame.")

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
