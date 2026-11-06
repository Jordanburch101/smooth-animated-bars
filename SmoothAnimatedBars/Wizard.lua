-- First-time setup in four short steps: which bars, their colours, how lively they are and whether to mark
-- the player's DoTs on the target (Marker.lua). Each pick
-- is applied at once, on the real frames and on the preview player and target frames at the top of
-- the window (Preview.lua); Skip (or closing the window) puts the settings back as they were, Finish
-- keeps them. Opens once, on the first login with the addon,
-- and again with /sab setup or from the settings page.
--
-- Built from the game's own window (as Road to Sixty's), button, radio button and font templates;
-- colours are SetColorTexture and never game files by path (see the project rules about Forever).

local _, ns = ...

local Wizard = {}
ns.Wizard = Wizard

local W, H = 620, 430
local GOLD = { 1, 0.82, 0 }
local EDGE = { 0.32, 0.30, 0.36 }

local BARS = {
    { key = "all", label = "Player and target", desc = "Health and power on your frame and your target's.",
      set = { playerHealth = true, playerPower = true, targetHealth = true, targetPower = true } },
    { key = "mine", label = "Just mine", desc = "Your health and power. Your target's stay the game's.",
      set = { playerHealth = true, playerPower = true, targetHealth = false, targetPower = false } },
    { key = "health", label = "Just health", desc = "Health on both frames. Power bars stay the game's.",
      set = { playerHealth = true, playerPower = false, targetHealth = true, targetPower = false } },
}
-- A few favourites; every theme is in the settings.
local COLORS = { "game", "class", "fire", "frost", "arcane", "void" }
local EFFECTS = {
    { key = "full", label = "Everything", desc = "Waves, swirl, bubbles, sparkles, theme particles and lightning.",
      set = { waves = true, swirl = true, bubbles = true, sparkles = true, ambient = true, lightning = true } },
    { key = "gentle", label = "Gentle", desc = "Waves and the swirl inside, without particles or lightning.",
      set = { waves = true, swirl = true, bubbles = false, sparkles = false, ambient = false, lightning = false } },
    { key = "still", label = "Still", desc = "A plain liquid colour that eases to the bar's value.",
      set = { waves = false, swirl = false, bubbles = false, sparkles = false, ambient = false, lightning = false } },
}
local DOTS = {
    { key = "both", label = "Marker and skull", desc = "What your DoTs will still deal, on the target's health, and a skull when they will kill it.",
      set = { dots = true, dotKillIcon = true } },
    { key = "marker", label = "Just the marker", desc = "What your DoTs will still deal, on the target's health. No skull.",
      set = { dots = true, dotKillIcon = false } },
    { key = "off", label = "Off", desc = "For classes without damage over time.",
      set = { dots = false } },
}
local PAGES = { "bars", "colors", "effects", "dots" }

local frame, ui, page, saved, closing

local function ColorName(key)
    return key == "game" and "Game Colour" or ns.Themes.list[key].name
end

-- Which of a list's sets the settings match now, if any. A set only names the settings it decides.
local function Matching(list)
    for _, item in ipairs(list) do
        local match = true
        for k, v in pairs(item.set) do
            if v ~= ns.Core.Get(k) then match = false end
        end
        if match then return item.key end
    end
end

--------------------------------------------------------------------------------
-- Building blocks: the game's templates and font objects
--------------------------------------------------------------------------------

local function Font(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetText(text or "")
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 26)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A 1 px outline of solid colour around a frame.
local function Outline(f, color)
    local edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[1]:sub(1, 3) == side[2]:sub(1, 3) then t:SetHeight(1) else t:SetWidth(1) end
        edges[#edges + 1] = t
    end
    return edges
end

-- An option: a radio button and title, an optional description, a gold outline when picked.
local function Card(parent, w, h, title, desc, onPick)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(w, h)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    local edges = Outline(c, EDGE)
    c.radio = CreateFrame("CheckButton", nil, c, "UIRadioButtonTemplate")
    c.radio:SetPoint("TOPLEFT", 8, -8)
    c.radio:SetScript("OnClick", onPick)
    c.title = Font(c, "GameFontNormal", title, "LEFT")
    c.title:SetPoint("LEFT", c.radio, "RIGHT", 4, 0)
    if desc then
        c.desc = Font(c, "GameFontHighlightSmall", desc, "LEFT")
        c.desc:SetPoint("TOPLEFT", 12, -32)
        c.desc:SetWidth(w - 24)
        c.desc:SetJustifyV("TOP")
        c.desc:SetWordWrap(true)
    end
    c:SetScript("OnClick", onPick)
    function c.SetSelected(_, on)
        c.radio:SetChecked(on)
        local color = on and GOLD or EDGE
        for _, t in ipairs(edges) do t:SetColorTexture(color[1], color[2], color[3], 1) end
        bg:SetColorTexture(on and 0.12 or 0, on and 0.09 or 0, on and 0.02 or 0, on and 0.55 or 0.45)
    end
    return c
end

local function Heading(parent, title, sub)
    local h = Font(parent, "GameFontNormalLarge", title, "LEFT")
    h:SetPoint("TOPLEFT", 0, 0)
    local s = Font(parent, "GameFontHighlightSmall", sub, "LEFT")
    s:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local Refresh

-- Every pick goes straight into the settings, through their controls so the settings page follows.
local function Set(values)
    for key, value in pairs(values) do ns.Core.SetSetting(key, value) end
    Refresh()
end

local function Cards(parent, list, y)
    local cards, w = {}, 168
    for i, item in ipairs(list) do
        local c = Card(parent, w, 92, item.label, item.desc, function() Set(item.set) end)
        c:SetPoint("TOPLEFT", (i - 1) * (w + 12), y)
        cards[item.key] = c
    end
    return cards
end

local BUILD = {}

function BUILD.bars(p)
    Heading(p, "Which bars?", "The frames above show each choice as you pick it.")
    ui.cards.bars = Cards(p, BARS, -46)
end

function BUILD.colors(p)
    Heading(p, "Pick the colours", "A few favourites. Every theme is in the settings.")
    ui.cards.healthColor, ui.cards.powerColor = {}, {}
    for row, key in ipairs({ "healthColor", "powerColor" }) do
        local y = -56 - (row - 1) * 82
        Font(p, "GameFontNormal", row == 1 and "Health" or "Power", "LEFT"):SetPoint("TOPLEFT", 0, y)
        for i, color in ipairs(COLORS) do
            local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
            local c = Card(p, 150, 30, ColorName(color), nil, function() Set({ [key] = color }) end)
            c:SetPoint("TOPLEFT", 60 + col * 160, y + 6 - line * 36)
            ui.cards[key][color] = c
        end
    end
end

function BUILD.effects(p)
    Heading(p, "How lively?", "Each effect can be turned on or off in the settings later.")
    ui.cards.effects = Cards(p, EFFECTS, -46)
end

function BUILD.dots(p)
    Heading(p, "Show your DoTs?", "Marks the health your damage over time will still burn away. Watch the target above.")
    ui.cards.dots = Cards(p, DOTS, -46)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
end

function Refresh()
    local picked = {
        bars = Matching(BARS), effects = Matching(EFFECTS), dots = Matching(DOTS),
        healthColor = ns.Core.Get("healthColor"), powerColor = ns.Core.Get("powerColor"),
    }
    for field, cards in pairs(ui.cards) do
        for key, c in pairs(cards) do c:SetSelected(picked[field] == key) end
    end
    local index = IndexOf(PAGES, page)
    ui.back:SetEnabled(index > 1)
    ui.next:SetText(index == #PAGES and "Finish" or "Next")
    ui.step:SetText(string.format("Step %d of %d", index, #PAGES))
end

local function ShowPage(name)
    page = name
    if not ui.pages[name] then
        local p = CreateFrame("Frame", nil, ui.body)
        p:SetAllPoints()
        ui.pages[name] = p
        BUILD[name](p)
    end
    for key, p in pairs(ui.pages) do p:SetShown(key == name) end
    Refresh()
end

local function Step(delta)
    ShowPage(PAGES[math.max(1, math.min(#PAGES, IndexOf(PAGES, page) + delta))])
end

-- The game's own window: metal border, dark background, gold title, without the portrait, the
-- button bar or the inset, the background started below the title bar so the bar stays dark.
local function Window()
    local ok, f = pcall(CreateFrame, "Frame", "SmoothAnimatedBarsSetup", UIParent, "ButtonFrameTemplate")
    if not ok then return end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.Inset then f.Inset:Hide() end
    if f.Bg then
        f.Bg:SetPoint("TOPLEFT", 6, -21)
        if f.TopTileStreaks then f.TopTileStreaks:SetPoint("TOPLEFT", 6, -21) end
    end
    return f
end

local function Build()
    -- A plain dark panel should the client not have the window template.
    frame = Window()
    if not frame then
        frame = CreateFrame("Frame", "SmoothAnimatedBarsSetup", UIParent)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
        Outline(frame, EDGE)
        local close = Button(frame, "Close", 80, function() frame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
    end
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Escape closes it like the game's windows; closing without finishing is Skip.
    table.insert(UISpecialFrames, "SmoothAnimatedBarsSetup")
    frame:SetScript("OnHide", function()
        if not closing then Wizard.Close("skip") end
        closing = nil
    end)
    if frame.SetTitle then
        frame:SetTitle("Smooth Animated Bars Setup")
    elseif frame.TitleText then
        frame.TitleText:SetText("Smooth Animated Bars Setup")
    else
        Font(frame, "GameFontNormal", "Smooth Animated Bars Setup", "CENTER"):SetPoint("TOP", 0, -6)
    end

    ui = { cards = {}, pages = {} }
    -- Preview frames on a dark strip under the title, the steps below them.
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", 36, -34)
    strip:SetPoint("TOPRIGHT", -36, -34)
    strip:SetHeight(116)
    local stripBg = strip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints()
    stripBg:SetColorTexture(0, 0, 0, 0.45)
    Outline(strip, EDGE)
    ui.preview = ns.Preview.Create(strip)
    ui.preview:SetPoint("CENTER")
    ui.body = CreateFrame("Frame", nil, frame)
    ui.body:SetPoint("TOPLEFT", 36, -170)
    ui.body:SetPoint("BOTTOMRIGHT", -36, 56)

    ui.footer = CreateFrame("Frame", nil, frame)
    ui.footer:SetPoint("BOTTOMLEFT", 16, 14)
    ui.footer:SetPoint("BOTTOMRIGHT", -16, 14)
    ui.footer:SetHeight(30)
    ui.skip = Button(ui.footer, "Skip", 100, function() Wizard.Close("skip") end)
    ui.skip:SetPoint("LEFT", 0, 0)
    ui.next = Button(ui.footer, "Next", 110, function()
        if IndexOf(PAGES, page) == #PAGES then Wizard.Close("done") else Step(1) end
    end)
    ui.next:SetPoint("RIGHT", 0, 0)
    ui.back = Button(ui.footer, "Back", 100, function() Step(-1) end)
    ui.back:SetPoint("RIGHT", ui.next, "LEFT", -8, 0)
    ui.step = Font(ui.footer, "GameFontHighlightSmall", "", "CENTER")
    ui.step:SetPoint("CENTER")
end

function Wizard.Open()
    if not frame then Build() end
    if frame:IsShown() then return end
    -- What Skip goes back to.
    saved = {}
    for key in pairs(ns.Core.Defaults()) do saved[key] = ns.Core.Get(key) end
    frame:SetScale(math.min(1, (UIParent:GetHeight() - 40) / H))
    frame:Show()
    ShowPage(PAGES[1])
end

-- At login: once out of combat, so it never covers the screen mid-fight.
function Wizard.OpenWhenReady()
    if ns.Core.Get("setupDone") or (frame and frame:IsShown()) then return end
    if InCombatLockdown() then
        C_Timer.After(5, Wizard.OpenWhenReady)
        return
    end
    Wizard.Open()
end

-- how: "skip" puts the settings back as they were when the wizard opened; "done" keeps them.
function Wizard.Close(how)
    if how == "skip" and saved then
        for key, value in pairs(saved) do
            if ns.Core.Get(key) ~= value then ns.Core.SetSetting(key, value) end
        end
    end
    saved = nil
    ns.Core.db.setupDone = true
    closing = true
    frame:Hide()
    if how == "done" then ns.Core.Print("All set. Change any of it with /sab.") end
end

-- For the tests: the window's controls and the page shown.
function Wizard.State()
    return { frame = frame, ui = ui, page = page }
end
