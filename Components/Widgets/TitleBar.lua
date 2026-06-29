local _, addon = ...

--[[
    TitleBar object.

    Fills an injected region with a centred title over a header banner, a lock
    toggle, and a close button. A divider separates the header from the content
    beneath it. The lock toggle (a composed LockButton) sits immediately left of
    the close button; clicking it reports the new state through onToggleLock(locked)
    so the owner can enable or disable window moving, resizing, and the splitter.

    addon:GetObject("TitleBar"):Build(region, {
        title = string,
        onClose = function,
        onToggleLock = function(locked),
        locked = boolean,
    }) -> self { SetTitle(text), SetLocked(locked) }
]]

local TitleBar = addon:NewObject("TitleBar")
local LockButton = addon:GetObject("LockButton")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Inset that tucks the header art just inside the window's 1px border so the
-- banner meets the frame edge cleanly, with no gap or overlap at the corners.
local BORDER_INSET = 1

-- Header banner gradient: faintly lighter at the top, darker at the base, so the
-- bar catches the light like a Blizzard banner instead of reading as a flat block
-- of colour.
local HEADER_TOP = { 0.18, 0.19, 0.22, 0.95 }
local HEADER_BOTTOM = { 0.09, 0.09, 0.11, 0.95 }

-- A cool 1px highlight skimming the top edge of the banner (the lit side of the
-- bevel), and a soft highlight beneath the divider (the lit side of the groove).
-- Together they give the banner and its lower edge a recessed, bevelled feel.
local HEADER_HIGHLIGHT = { 0.35, 0.40, 0.50, 0.45 }
local DIVIDER_HIGHLIGHT = { 0.6, 0.6, 0.65, 0.15 }

local titleText
local lockButton

function TitleBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onClose == nil or type(opts.onClose) == "function", "Build: 'opts.onClose' must be a function")
    C:Ensures(opts.onToggleLock == nil or type(opts.onToggleLock) == "function", "Build: 'opts.onToggleLock' must be a function")

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    -- Header strip behind the title, giving the bar a distinct banner like the
    -- Blizzard Options window. A faint vertical gradient (lighter at the top)
    -- catches the light instead of reading as one flat block of colour.
    local header = root:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", BORDER_INSET, -BORDER_INSET)
    header:SetPoint("BOTTOMRIGHT", -BORDER_INSET, 0)
    header:SetColorTexture(1, 1, 1, 1)
    header:SetGradient("VERTICAL", CreateColor(unpack(HEADER_BOTTOM)), CreateColor(unpack(HEADER_TOP)))

    -- A 1px highlight along the very top edge reads as light hitting the bevel,
    -- lifting the banner off the metal border above it.
    local topHighlight = root:CreateTexture(nil, "ARTWORK")
    topHighlight:SetPoint("TOPLEFT", BORDER_INSET, -BORDER_INSET)
    topHighlight:SetPoint("TOPRIGHT", -BORDER_INSET, -BORDER_INSET)
    topHighlight:SetHeight(1)
    topHighlight:SetColorTexture(unpack(HEADER_HIGHLIGHT))

    -- Divider separating the header from the content beneath it. A darker rule
    -- over a faint highlight gives it a recessed, bevelled edge rather than a
    -- single flat line.
    local divider = root:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", BORDER_INSET, 1)
    divider:SetPoint("BOTTOMRIGHT", -BORDER_INSET, 1)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(UI.Backdrop.Separator))

    local dividerHighlight = root:CreateTexture(nil, "ARTWORK")
    dividerHighlight:SetPoint("BOTTOMLEFT", BORDER_INSET, 0)
    dividerHighlight:SetPoint("BOTTOMRIGHT", -BORDER_INSET, 0)
    dividerHighlight:SetHeight(1)
    dividerHighlight:SetColorTexture(unpack(DIVIDER_HIGHLIGHT))

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", 0, 0)
    titleText:SetText(opts.title or "")

    local closeButton = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("RIGHT", -3, -1)
    closeButton:SetScript("OnClick", function()
        if opts.onClose then
            opts.onClose()
        end
    end)

    lockButton = LockButton:Build(root, closeButton, {
        onToggle = opts.onToggleLock,
        locked = opts.locked,
    })

    return self
end

function TitleBar:SetTitle(text)
    titleText:SetText(text)
end

-- Reflect the locked state in the composed lock toggle.
function TitleBar:SetLocked(locked)
    if lockButton then
        lockButton:SetLocked(locked)
    end
end
