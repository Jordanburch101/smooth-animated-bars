-- The addon's page in the game's AddOns settings: a landing page that opens the editor (Editor.lua), where every setting
-- is, beside a live preview. The page has the addon's name, a preview of the player and target frames, what the addon
-- does, and Open Editor and Run Setup.
--
-- Every setting is still registered with the game's Settings API (Settings.RegisterAddOnSetting), with nothing laid out
-- for it: the editor and the setup change settings through those (Options.Set), so each change reaches
-- Core.OnSettingChanged and the editor alike, as any control of the game's would.
--
-- The page is a canvas: one frame of ours, not the game's vertical layout list. The game reuses that list's row frames
-- for every category, and on Forever rows set up by an addon's code carry its taint into the Social page, which then has
-- its protected IsUserOAuthed blocked in the addon's name. So nothing is added to the game's lists, and the page is
-- built while the settings panel is closed: its frames at login, its preview once the player is in the world.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

-- The settings list's own header (Blizzard_SettingsList.xml), so the page lines up with the game's.
local HEADER_H, TITLE_X, TITLE_Y = 50, 7, -22
local PAGE_RIGHT = -20

local category, canvas, db, defaults
local registered = {}

local function Register(key)
    local default = defaults[key]
    local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, db, type(default), key, default)
    setting:SetValueChangedCallback(function(_, value)
        ns.Core.OnSettingChanged(key, value)
        -- The editor follows a change made anywhere (the setup, /sab on, its own controls).
        if ns.Editor and ns.Editor.Refresh then ns.Editor.Refresh() end
    end)
    registered[key] = setting
end

local function Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- The version from the toc, only when it is a release's (a working copy has the packager's placeholder).
local function Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = get and get(ADDON_NAME, "Version")
    return type(v) == "string" and v:match("^%d+%.%d+%.%d+") and v or nil
end

-- The page frame. The game parents and shows it when the category opens.
local function BuildPage(title)
    canvas = CreateFrame("Frame")
    canvas:Hide()

    local text = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    text:SetPoint("TOPLEFT", TITLE_X, TITLE_Y)
    text:SetText(title)
    local version = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", text, "BOTTOMRIGHT", 10, 2)
    version:SetText(Version() or "")

    local divider = canvas:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 0, -HEADER_H)
    divider:SetPoint("TOPRIGHT", PAGE_RIGHT, -HEADER_H)
    divider:SetHeight(1)

    -- The preview's dark strip (Options.BuildPreview puts the frames on it).
    local strip = CreateFrame("Frame", nil, canvas)
    strip:SetPoint("TOPLEFT", 10, -HEADER_H - 16)
    strip:SetPoint("TOPRIGHT", PAGE_RIGHT - 10, -HEADER_H - 16)
    strip:SetHeight(124)
    local bg = strip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    canvas.strip = strip

    local about = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    about:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 6, -18)
    about:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
    about:SetJustifyH("LEFT")
    about:SetWordWrap(true)
    about:SetText("Animated liquid in your health and power bars: your own frame, your target, focus, pet and party, "
        .. "raid frames, nameplates and the Personal Resource Display, with markers for your DoTs, heals, mana and rage.")

    canvas.open = Button(canvas, "Open Editor", 170, 32, function() ns.Core.OpenEditor() end)
    canvas.open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -22)
    canvas.setup = Button(canvas, "Run Setup", 130, 32, function() ns.Wizard.Open() end)
    canvas.setup:SetPoint("LEFT", canvas.open, "RIGHT", 10, 0)
    canvas.whatsNew = Button(canvas, "What's New", 130, 32, function() ns.WhatsNew.Open() end)
    canvas.whatsNew:SetPoint("LEFT", canvas.setup, "RIGHT", 10, 0)

    local hint = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", canvas.open, "BOTTOMLEFT", 0, -14)
    hint:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetTextColor(0.66, 0.64, 0.60)
    hint:SetText("The editor shows every option beside a live preview. Type /sab to open it anywhere, or right-click "
        .. "your player, target, pet, focus or party frame.")
end

-- The preview on the page: the player and target frames playing their fight (Preview.lua), built once the player is
-- in the world, with the settings panel closed, and running only while the page shows.
function Options.BuildPreview()
    if not canvas or canvas.preview then return end
    canvas.preview = ns.Preview.Create(canvas.strip)
    canvas.preview:SetPoint("CENTER")
end

-- "Open Editor" at the bottom of the right-click menus of the frames the liquid is on, through Menu.ModifyMenu, the
-- game's way for addons to add to a menu. The same menus open from chat names, the friends list and party frames,
-- so only a menu whose owner is one of these frames gets it. The target of target has no menu.
local UNIT_MENUS = { "SELF", "VEHICLE", "PET", "OTHERPET", "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "TARGET",
                     "FOCUS" }
local MENU_FRAMES = { "PlayerFrame", "TargetFrame", "PetFrame", "FocusFrame" }
-- The editor's section each frame's menu opens at.
local MENU_SECTIONS = { PlayerFrame = "player", TargetFrame = "target", PetFrame = "pet", FocusFrame = "focus" }

-- The section a menu's owner opens the editor at, or nil if the liquid is not on it. The party's member frames are
-- pooled buttons without names (PartyFrame.lua), told by their parent.
local function MenuSection(owner, frames)
    if type(owner) ~= "table" then return nil end
    if frames[owner] then return MENU_SECTIONS[owner:GetName() or ""] or "" end
    local party = rawget(_G, "PartyFrame")
    -- Every hooked menu's owner comes here (chat names, raid frames): one the client will not answer for is passed by.
    if not party then return nil end
    local ok, parent = pcall(function() return owner:GetParent() end)
    if ok and parent == party then return "party" end
end

-- Whether the menu's unit has a secret identity (a mob or player in an instance or battleground). The menu's title is
-- then its secret name, and the game can lay that out only while untainted: with our entries in it, the layout ran
-- tainted, failed on the title's secret width ("attempt to perform arithmetic on local 'frameLeft' (a secret number
-- value, while execution tainted by 'SmoothAnimatedBars')", FrameUtil.lua GetUnscaledFrameRect) and drew the whole
-- menu on one line without its background (seen in game). Such a menu is left alone.
local function SecretIdentity(unit)
    if type(unit) ~= "string" then return false end
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and C_Secrets.ShouldUnitIdentityBeSecret(unit) then
        return true
    end
    return issecretvalue ~= nil and issecretvalue((UnitName(unit))) or false
end

-- Whether the game's controller interface is on. A menu opened there takes the gamepad's focus, which pushes the
-- menu's bindings and has the gamepad action bar call SetPreferredGamepadInteractTarget, a protected function
-- (Blizzard_GamepadActionBars, UpdateInteractIcons). With our entries in the menu that ran tainted and was blocked
-- ("ADDON_ACTION_FORBIDDEN ... SetPreferredGamepadInteractTarget()", seen in game), and players reported the
-- controller interface broken until a /reload. So the menus are left alone there.
local function GamepadUI()
    local style = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
    local types = Enum and Enum.InputDeviceInterfaceType
    if not (style and types and types.Gamepad) then return false end
    local ok, current = pcall(style)
    return ok and current == types.Gamepad
end
-- The editor's picker opens a menu of the game's too, so it asks the same.
Options.GamepadUI = GamepadUI

local function AddToUnitMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    local frames = {}
    for _, name in ipairs(MENU_FRAMES) do
        local f = rawget(_G, name)
        if f then frames[f] = true end
    end
    for _, which in ipairs(UNIT_MENUS) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, function(_, rootDescription, contextData)
            local section = type(contextData) == "table" and MenuSection(contextData.ownerFrame, frames)
            if not section or GamepadUI() or SecretIdentity(contextData.unit) then return end
            rootDescription:CreateDivider()
            rootDescription:CreateTitle("Smooth Animated Bars")
            rootDescription:CreateButton("Open Editor", function()
                ns.Core.OpenEditor(section ~= "" and section or nil)
            end)
        end)
    end
end

function Options.Register(savedDB, defaultValues)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnSetting) then return end
    db, defaults = savedDB, defaultValues
    local title = "Smooth Animated Bars"

    BuildPage(title)
    category = Settings.RegisterCanvasLayoutCategory(canvas, title)
    local keys = {}
    for key in pairs(defaults) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do Register(key) end

    Settings.RegisterAddOnCategory(category)
    AddToUnitMenus()
end

-- Change one setting through its registered setting, as a control of the game's would. False when there is none.
function Options.Set(key, value)
    local setting = registered[key]
    if not setting then return false end
    setting:SetValue(value)
    return true
end

-- For the tests: the page frame.
function Options.Page()
    return canvas
end
