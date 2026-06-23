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

local UI = addon.UI

-- Inset that tucks the header art just inside the window's metal border so the
-- banner reaches the frame edges.
local BORDER_INSET = 3

local titleText
local lockButton

function TitleBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    -- Header strip behind the title, giving the bar a distinct banner like the
    -- Blizzard Options window.
    local header = root:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", BORDER_INSET, -BORDER_INSET)
    header:SetPoint("BOTTOMRIGHT", -BORDER_INSET, 0)
    header:SetColorTexture(unpack(UI.Backdrop.Header))

    -- Divider separating the header from the content beneath it.
    local divider = root:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", BORDER_INSET, 0)
    divider:SetPoint("BOTTOMRIGHT", -BORDER_INSET, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(UI.Backdrop.Separator))

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
