local _, addon = ...

--[[
    TitleBar object.

    Fills an injected region with a title label, a lock toggle, and a close
    button. The lock toggle (a composed LockButton) sits immediately left of the
    close button; clicking it reports the new state through onToggleLock(locked)
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

local titleText
local lockButton

function TitleBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
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
