local _, addon = ...

--[[
    Dialog object.

    A reusable, movable popup shell: a bordered backdrop carrying a title and a
    close button (X), draggable anywhere on its body. The shell owns no content
    of its own — callers build one, anchor their widgets into the returned
    frame, and drive Show/Hide. ESC closes the dialog.

    local dialog = addon:GetObject("Dialog"):Build({
        name   = "WowSyncSaveDialog",   -- global frame name (required, for ESC)
        title  = L["Save snapshot"],     -- initial title text (optional)
        width  = number,                 -- defaults to UI.Preview.Width
        height = number,                 -- defaults to UI.Preview.Height
        onHide = function() end,          -- optional OnHide hook
    })

    dialog:GetFrame()    -- backdrop frame to parent/anchor content into
    dialog:SetTitle(text)
    dialog:Show()
    dialog:Hide()
]]

local Dialog = addon:NewObject("Dialog")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Shared method table for every built dialog instance.
local DialogMixin = {}

function DialogMixin:GetFrame()
    return self.frame
end

function DialogMixin:SetTitle(text)
    self.titleLabel:SetText(text or "")
end

function DialogMixin:Show()
    self.frame:Show()
    self.frame:Raise()
end

function DialogMixin:Hide()
    self.frame:Hide()
end

function Dialog:Build(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.name) == "string", "Build: 'opts.name' must be a string")
    C:Ensures(opts.onHide == nil or type(opts.onHide) == "function", "Build: 'opts.onHide' must be a function")

    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:SetSize(opts.width or UI.Preview.Width, opts.height or UI.Preview.Height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(UI.Backdrop.Main))
    frame:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Drag the whole body to move the window; content widgets capture their own
    -- clicks, so only empty areas start a drag.
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("TOPLEFT", 14, -12)
    titleLabel:SetText(opts.title or "")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)

    if opts.onHide then
        frame:SetScript("OnHide", opts.onHide)
    end

    -- Registering with UISpecialFrames makes ESC close the dialog.
    tinsert(UISpecialFrames, opts.name)

    frame:Hide()

    return setmetatable({
        frame = frame,
        titleLabel = titleLabel,
    }, { __index = DialogMixin })
end
