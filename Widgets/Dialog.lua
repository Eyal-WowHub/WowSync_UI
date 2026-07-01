local _, addon = ...

--[[
    Dialog object.

    A reusable, movable popup shell: a bordered backdrop carrying a title and a
    close button (X), draggable anywhere on its body. The shell owns no content
    of its own — callers build one, anchor their widgets into the returned
    frame, and drive Show/Hide. ESC closes the dialog.

    local dialog = addon:GetObject("Dialog"):Build({
        name   = "WowSyncExampleDialog", -- global frame name (required, for ESC)
        title  = L["Save snapshot"],     -- initial title text (optional)
        width  = number,                 -- defaults to UI.Preview.Width
        height = number,                 -- defaults to UI.Preview.Height
        onHide = function() end,          -- optional OnHide hook
    })

    dialog                -- the backdrop frame itself; parent/anchor content into it
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

-- The horizontal direction the current dialog cascade grows in. The first
-- dialog decides it from the room beside the main window, and the rest of the
-- stack keeps it so they fan out consistently instead of overlapping the
-- semi-transparent window.
local cascadeDirection = "right"

-- Places a dialog as it opens. The first dialog of a stack anchors to the top of
-- the main window -- to its right when there is room, otherwise to its left --
-- and that choice fixes the cascade direction. Each later dialog stacks beside
-- the previous one in that direction, flipping to the opposite side only when it
-- would run off-screen. Positions are absolute so each dialog can be dragged or
-- closed without disturbing the others.
local function PositionDialog(frame)
    frame:ClearAllPoints()

    local width = frame:GetWidth()
    local screenLeft = UIParent:GetLeft()
    local screenRight = UIParent:GetRight()

    local anchorFrame = openDialogs[#openDialogs]
    if anchorFrame and anchorFrame:GetLeft() then
        local top = anchorFrame:GetTop()
        if cascadeDirection == "right" then
            local rightX = anchorFrame:GetRight() + DIALOG_GAP
            if rightX + width <= screenRight then
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rightX, top)
            else
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorFrame:GetLeft() - DIALOG_GAP - width, top)
            end
        else
            local leftX = anchorFrame:GetLeft() - DIALOG_GAP - width
            if leftX >= screenLeft then
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, top)
            else
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorFrame:GetRight() + DIALOG_GAP, top)
            end
        end
        return
    end

    local mainFrame = _G.WowSyncUIFrame
    if mainFrame and mainFrame:IsShown() and mainFrame:GetLeft() then
        local top = mainFrame:GetTop()
        local rightX = mainFrame:GetRight() + DIALOG_GAP
        if rightX + width <= screenRight then
            cascadeDirection = "right"
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", rightX, top)
        else
            cascadeDirection = "left"
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mainFrame:GetLeft() - DIALOG_GAP - width, top)
        end
        return
    end

    frame:SetPoint("CENTER")
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

-- The methods every built dialog carries. The dialog IS its backdrop frame, so
-- Show and Hide are the native frame methods -- their OnShow/OnHide scripts
-- position, track, and release the dialog -- and only the title needs spelling
-- out.
local Methods = {}

function Methods:SetTitle(text)
    self._title:SetText(text or "")
end

function Methods:Constructor(config)
    self:SetPoint("CENTER")
    self:SetFrameStrata("FULLSCREEN_DIALOG")
    self:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    self:SetBackdropColor(unpack(UI.Backdrop.Main))
    self:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))
    self:EnableMouse(true)
    self:SetClampedToScreen(true)

    -- Drag the whole body to move the window; content widgets capture their own
    -- clicks, so only empty areas start a drag.
    self:SetMovable(true)
    self:RegisterForDrag("LeftButton")
    self:SetScript("OnDragStart", self.StartMoving)
    self:SetScript("OnDragStop", self.StopMovingOrSizing)

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("TOPLEFT", 14, -12)
    titleLabel:SetText(config.title or "")
    self._title = titleLabel

    local close = CreateFrame("Button", nil, self, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() self:Hide() end)

    -- Position and track the dialog as it opens, and release it as it closes, so
    -- dialogs stack instead of overlapping and clear out of the open set.
    local onHide = config.onHide
    self:SetScript("OnShow", function(dialog)
        PositionDialog(dialog)
        RememberOpenDialog(dialog)
        dialog:Raise()
    end)

    self:SetScript("OnHide", function(dialog)
        ForgetOpenDialog(dialog)
        if onHide then
            onHide(dialog)
        end
    end)

    -- Registering with UISpecialFrames makes ESC close the dialog.
    tinsert(UISpecialFrames, self:GetName())

    self:Hide()
end

function Dialog:Build(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.name) == "string", "Build: 'opts.name' must be a string")
    C:Ensures(opts.onHide == nil or type(opts.onHide) == "function", "Build: 'opts.onHide' must be a function")

    return addon:NewWidget({
        parent = UIParent,
        width = opts.width or UI.Preview.Width,
        height = opts.height or UI.Preview.Height,
        title = opts.title,
        onHide = opts.onHide,
    }, {
        frameType = "Frame",
        template = "BackdropTemplate",
        name = opts.name,
        methods = Methods,
    })
end
