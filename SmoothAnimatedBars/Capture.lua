-- For the gallery, not for players: /sab capture photographs Forever's unit frame art, which lives in
-- the game's data files where tools/harness/gallery.py cannot read it.
--
-- Each piece of the art (built by Preview.lua, so placed exactly as on the preview frames) gets a cell
-- of its own in a grid over the whole screen, which is screenshotted on black and then on white. From
-- the two, tools/capture_art.py works out every pixel's colour and transparency and cuts out the
-- cells. Two red squares mark the grid so the tool can find it at any resolution and UI scale. Bar
-- masks are photographed as a white fill cut by the mask. The screenshot format is switched to TGA
-- (lossless) for the two shots and put back afterwards.
--
-- /sab capture plates does the same for the Classic style nameplate (Blizzard_NamePlateUnitFrame.lua, forever
-- branch): its border, the bottom half of Interface\Tooltips\Nameplate-Border, 128 x 16 with the level box on the
-- right, and its bar fill, on a grid of its own drawn much larger, so the cut-out is sharp. Game files by path are
-- used here only, for the gallery, never in what players see. The source leaves the bar's place inside the border
-- to the plate's container, so a real plate (the target's, if it has one up) is measured too and saved as
-- SmoothAnimatedBarsDB.plateArt for capture_art.py --plates.

local _, ns = ...

local Capture = {}
ns.Capture = Capture

local CELL_W, CELL_H, STEP_X, STEP_Y = 232, 100, 252, 120 -- a frame, and the grid's pitch
local GRID_W, GRID_H = 1030, 420                           -- room the grid needs, in its own units
local MARKS = { 8, 1008 }                                  -- red squares' left edges, 6 wide, 8 down
local SETTLE, FADE = 0.5, 4 -- seconds before the first shot, and before the second, so the game's
                            -- "screen captured" notice has gone

-- Cells in grid order (four to a row): file name, frame, piece.
local CELLS = {
    { "player-art", "player", "art" }, { "player-portrait", "player", "portrait" },
    { "player-circle", "player", "circle" }, { "player-health-mask", "player", "health" },
    { "player-power-mask", "player", "power" }, { "target-art", "target", "art" },
    { "target-portrait", "target", "portrait" }, { "target-circle", "target", "circle" },
    { "target-banner", "target", "banner" }, { "target-health-mask", "target", "health" },
    { "target-power-mask", "target", "power" }, { "target-killicon", "target", "killicon" },
}
Capture.CELLS = CELLS

-- The plate grid: in its own units, scaled to fill the screen; marks as above, 280 apart. Cells: file name, left, top,
-- width, height, and a texture file with its coordinates or an atlas. The first row is the Classic style; the second
-- the other styles' background and fill (UI-HUD-CoolDownManager-Bar), which the game stretches around a bar, so they
-- are drawn at a 128 x 10 bar's size: the background 2 left, 3 up, 6 right and 6 down of it. Then Forever's own pieces
-- (Camelot/Blizzard_NamePlateLevelFrame.xml and Camelot/Blizzard_NamePlateConstants.lua): the level box, its outline
-- on the target, the skull for a mob far above the player, the target's yellow glow around the bar, and the darkening
-- every plate but the target's gets.
local PLATE_GRID_W, PLATE_GRID_H = 300, 145
local PLATE_MARKS = { 8, 288 }
local PLATE_CELLS = {
    { "plate-border", 20, 40, 128, 16, file = "Interface\\Tooltips\\Nameplate-Border", coords = { 0, 1, 0.5, 1 } },
    { "plate-fill", 160, 43, 128, 10, file = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
    { "plate-modern-bg", 20, 66, 136, 19, atlas = "UI-HUD-CoolDownManager-Bar-BG" },
    { "plate-modern-fill", 160, 69, 128, 10, atlas = "UI-HUD-CoolDownManager-Bar" },
    { "plate-level", 20, 92, 28, 25, atlas = "ui-hud-nameplates-levelindicator" },
    { "plate-level-selected", 60, 92, 34, 32, atlas = "ui-hud-nameplates-levelindicator-rectangle-selected" },
    { "plate-level-skull", 105, 92, 18, 18, atlas = "ui-hud-nameplates-levelindicator-skull" },
    { "plate-selected", 140, 92, 139, 19, atlas = "UI-HUD-CoolDownManager-Selected-yellow" },
    { "plate-deselected", 20, 130, 128, 10, atlas = "ui-hud-nameplates-deselected-overlay" },
}
Capture.PLATE_CELLS = PLATE_CELLS

local grid, bg, step, oldFormat
local grids, mode = {}, nil

local function Piece(cell, which, piece)
    local P = ns.Preview
    if piece == "art" then
        P.Art(cell, which)
    elseif piece == "portrait" then
        P.Portrait(cell, which)
    elseif piece == "circle" then
        P.Circle(cell, which)
    elseif piece == "banner" then
        P.Banner(cell):SetVertexColor(1, 1, 1) -- untinted; the gallery tints it
    elseif piece == "killicon" then
        -- The DoT marker's kill icon, centred on the target's portrait as Marker.lua puts it.
        local p = P.LAYOUT.target.portrait
        local icon = cell:CreateTexture(nil, "OVERLAY")
        if ns.Marker.KillIcon(icon) then
            icon:SetPoint("CENTER", cell, "TOPRIGHT", p.x - p.size / 2, p.y - p.size / 2)
        else
            icon:Hide()
        end
    else
        -- A bar's mask: a white fill over the whole cell, cut by the mask where the game puts it.
        local spec = P.LAYOUT[which][piece]
        local fill = cell:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints()
        fill:SetColorTexture(1, 1, 1, 1)
        local mask = cell:CreateMaskTexture()
        if P.PlaceMask(mask, spec, cell, spec.x, spec.y) then fill:AddMaskTexture(mask) else fill:Hide() end
    end
end

local function Build(which)
    local plates = which == "plates"
    local gridW, gridH = plates and PLATE_GRID_W or GRID_W, plates and PLATE_GRID_H or GRID_H
    grid = CreateFrame("Frame", plates and "SmoothAnimatedBarsCapturePlates" or "SmoothAnimatedBarsCapture", UIParent)
    grid:SetFrameStrata("FULLSCREEN_DIALOG")
    grid:EnableMouse(true)
    local scale = 0.98 * math.min(UIParent:GetWidth() / gridW, UIParent:GetHeight() / gridH)
    grid:SetScale(scale)
    grid:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    grid:SetSize(UIParent:GetWidth() / scale, UIParent:GetHeight() / scale)
    bg = grid:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    grids[which] = { grid = grid, bg = bg }
    for _, x in ipairs(plates and PLATE_MARKS or MARKS) do
        local mark = grid:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetColorTexture(1, 0, 0, 1)
        mark:SetSize(6, 6)
        mark:SetPoint("TOPLEFT", x, -8)
    end
    if plates then
        for _, c in ipairs(PLATE_CELLS) do
            local t = grid:CreateTexture(nil, "ARTWORK")
            if c.atlas then
                if not t:SetAtlas(c.atlas) then t:Hide() end
            else
                t:SetTexture(c.file)
                t:SetTexCoord(unpack(c.coords or { 0, 1, 0, 1 }))
            end
            t:SetPoint("TOPLEFT", c[2], -c[3])
            t:SetSize(c[4], c[5])
        end
    else
        for i, c in ipairs(CELLS) do
            local cell = CreateFrame("Frame", nil, grid)
            cell:SetSize(CELL_W, CELL_H)
            cell:SetPoint("TOPLEFT", 20 + (i - 1) % 4 * STEP_X, -(40 + math.floor((i - 1) / 4) * STEP_Y))
            Piece(cell, c[2], c[3])
        end
    end
    grid:Hide()
    grid:SetScript("OnEvent", function(_, event)
        if event == "SCREENSHOT_FAILED" then
            Capture.Finish("The screenshot failed.")
        elseif step == "black" then
            step = "white"
            bg:SetColorTexture(1, 1, 1, 1)
            C_Timer.After(FADE, function() Screenshot() end)
        else
            Capture.Finish()
        end
    end)
end

-- A number the client lets the addon read, else nil.
local function Readable(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Edges(region)
    if type(region) ~= "table" or not region.GetLeft then return nil end
    local ok, l, r, t, b = pcall(function() return region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom() end)
    if not ok then return nil end
    l, r, t, b = Readable(l), Readable(r), Readable(t), Readable(b)
    if l and r and t and b and r > l and t > b then return { l = l, r = r, t = t, b = b } end
end

-- Where a real plate puts its bar, level and name inside the border, in the border's own units (128 across), from
-- the target's plate. Saved for capture_art.py --plates; nil when no plate can be measured.
local function MeasurePlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    local uf = ok and type(plate) == "table" and plate.UnitFrame
    local bar = type(uf) == "table" and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local border = Edges(bar and bar.bgTexture)
    local fill = Edges(bar)
    if not (border and fill) then return nil end
    local u = (border.r - border.l) / 128
    local function In(e)
        return e and { left = (e.l - border.l) / u, right = (e.r - border.l) / u, top = (border.t - e.t) / u,
                       bottom = (border.t - e.b) / u }
    end
    local out = { border = { width = 128, height = (border.t - border.b) / u }, bar = In(fill),
                  level = In(Edges(uf.LevelFrame)), name = In(Edges(uf.name)) }
    local okFont, _, size = pcall(function() return uf.name:GetFont() end)
    if okFont and Readable(size) then out.nameSize = size / u end
    return out
end

function Capture.Start(which)
    which = which or "frames"
    if step then return end
    if InCombatLockdown() then
        ns.Core.Print("Capture needs you out of combat.")
        return
    end
    if not grids[which] then Build(which) end
    grid, bg, mode = grids[which].grid, grids[which].bg, which
    if which == "plates" then
        local geometry = MeasurePlate()
        ns.Core.db.plateArt = geometry
        ns.Core.Print(geometry and "Measured your target's nameplate." or "No nameplate on your target to measure: "
            .. "target a mob with its nameplate showing for the exact layout. Capturing the art anyway.")
    end
    bg:SetColorTexture(0, 0, 0, 1)
    grid:Show()
    grid:RegisterEvent("SCREENSHOT_SUCCEEDED")
    grid:RegisterEvent("SCREENSHOT_FAILED")
    oldFormat = GetCVar("screenshotFormat")
    SetCVar("screenshotFormat", "tga")
    step = "black"
    C_Timer.After(SETTLE, function() Screenshot() end)
end

function Capture.Finish(problem)
    grid:UnregisterEvent("SCREENSHOT_SUCCEEDED")
    grid:UnregisterEvent("SCREENSHOT_FAILED")
    grid:Hide()
    if oldFormat then SetCVar("screenshotFormat", oldFormat) end
    step, oldFormat = nil, nil
    local plates = mode == "plates"
    mode = nil
    ns.Core.Print(problem or ("Captured the " .. (plates and "nameplate" or "frame") .. " art: two screenshots, on black "
        .. "and on white. " .. (plates and "/reload, then run tools/capture_art.py --plates to cut it out."
        or "Run tools/capture_art.py to cut it out.")))
end
