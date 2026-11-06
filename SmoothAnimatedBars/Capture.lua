-- For the gallery, not for players: /sab capture photographs Forever's unit frame art, which lives in
-- the game's data files where tools/harness/gallery.py cannot read it.
--
-- Each piece of the art (built by Preview.lua, so placed exactly as on the preview frames) gets a cell
-- of its own in a grid over the whole screen, which is screenshotted on black and then on white. From
-- the two, tools/capture_art.py works out every pixel's colour and transparency and cuts out the
-- cells. Two red squares mark the grid so the tool can find it at any resolution and UI scale. Bar
-- masks are photographed as a white fill cut by the mask. The screenshot format is switched to TGA
-- (lossless) for the two shots and put back afterwards.

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

local grid, bg, step, oldFormat

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

local function Build()
    grid = CreateFrame("Frame", "SmoothAnimatedBarsCapture", UIParent)
    grid:SetFrameStrata("FULLSCREEN_DIALOG")
    grid:EnableMouse(true)
    local scale = 0.98 * math.min(UIParent:GetWidth() / GRID_W, UIParent:GetHeight() / GRID_H)
    grid:SetScale(scale)
    grid:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    grid:SetSize(UIParent:GetWidth() / scale, UIParent:GetHeight() / scale)
    bg = grid:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    for _, x in ipairs(MARKS) do
        local mark = grid:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetColorTexture(1, 0, 0, 1)
        mark:SetSize(6, 6)
        mark:SetPoint("TOPLEFT", x, -8)
    end
    for i, c in ipairs(CELLS) do
        local cell = CreateFrame("Frame", nil, grid)
        cell:SetSize(CELL_W, CELL_H)
        cell:SetPoint("TOPLEFT", 20 + (i - 1) % 4 * STEP_X, -(40 + math.floor((i - 1) / 4) * STEP_Y))
        Piece(cell, c[2], c[3])
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

function Capture.Start()
    if step then return end
    if InCombatLockdown() then
        ns.Core.Print("Capture needs you out of combat.")
        return
    end
    if not grid then Build() end
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
    ns.Core.Print(problem or "Captured the frame art: two screenshots, on black and on white. "
        .. "Run tools/capture_art.py to cut it out.")
end
