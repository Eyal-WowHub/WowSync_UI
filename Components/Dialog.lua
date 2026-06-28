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

-- Horizontal gap between a dialog and the one it stacks beside.
local DIALOG_GAP = 12

-- Currently-open dialog frames in the order they were shown. A new dialog stacks
-- beside the last entry, and all are closed together when the main window closes.
local openDialogs = {}

-- Adds a dialog to the open set, ignoring one that is already tracked.
local function RememberOpenDialog(frame)
    for _, openFrame in ipairs(openDialogs) do
        if openFrame == frame then
            return
        end
    end
    tinsert(openDialogs, frame)
end

-- Removes a dialog from the open set.
local function ForgetOpenDialog(frame)
    for index = #openDialogs, 1, -1 do
        if openDialogs[index] == frame then
            tremove(openDialogs, index)
            return
        end
    end
end

-- Places a dialog as it opens: centered on the main window when it is the first
-- one open, otherwise stacked to the right of the last open dialog, or to its
-- left when the right edge would run off-screen. Positions are absolute so each
-- dialog can be dragged or closed without disturbing the others.
local function PositionDialog(frame)
    frame:ClearAllPoints()

    local anchorFrame = openDialogs[#openDialogs]
    local anchorLeft = anchorFrame and anchorFrame:GetLeft()
    if anchorLeft then
        local width = frame:GetWidth()
        local top = anchorFrame:GetTop()
        local fitsRight = (anchorFrame:GetRight() + DIALOG_GAP + width) <= UIParent:GetRight()
        if fitsRight then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorFrame:GetRight() + DIALOG_GAP, top)
        else
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft - DIALOG_GAP - width, top)
        end
        return
    end

    local mainFrame = _G.WowSyncUIFrame
    if mainFrame and mainFrame:IsShown() and mainFrame:GetLeft() then
        local centerX = mainFrame:GetLeft() + mainFrame:GetWidth() / 2
        local centerY = mainFrame:GetBottom() + mainFrame:GetHeight() / 2
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
    else
        frame:SetPoint("CENTER")
    end
end

-- Closing the main window closes every open dialog, so stale popups never linger
-- over the game world after WowSync is dismissed.
Dialog:RegisterEvent("WOWSYNC_UI_CLOSED", function()
    local closing = {}
    for index = 1, #openDialogs do
        closing[index] = openDialogs[index]
    end
    for index = 1, #closing do
        closing[index]:Hide()
    end
end)

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

    -- Position and track the dialog as it opens, and release it as it closes, so
    -- dialogs stack instead of overlapping and clear out of the open set.
    frame:SetScript("OnShow", function(self)
        PositionDialog(self)
        RememberOpenDialog(self)
        self:Raise()
    end)

    frame:SetScript("OnHide", function(self)
        ForgetOpenDialog(self)
        if opts.onHide then
            opts.onHide(self)
        end
    end)

    -- Registering with UISpecialFrames makes ESC close the dialog.
    tinsert(UISpecialFrames, opts.name)

    frame:Hide()

    return setmetatable({
        frame = frame,
        titleLabel = titleLabel,
    }, { __index = DialogMixin })
end
