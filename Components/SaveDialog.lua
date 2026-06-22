local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    SaveDialog object.

    A modal window for saving a snapshot to a profile with an optional note and
    an optional module subset. It lists every module as a checkbox (all checked
    by default) plus a note field, and hands the chosen module set and note back
    through onConfirm so the caller runs the actual save. The dialog is "dumb"
    about saving itself.

    Unlike the apply preview, this dialog owns its own (non-pooled) checkbox
    rows rather than the shared ModuleList object, because that list is a
    singleton already used by ApplyPreviewDialog.

    addon:GetObject("SaveDialog"):Show({
        profileName = string,
        onConfirm   = function(moduleSet, note) end,   -- moduleSet = { [name] = true }, note = string|nil
    })
]]

local SaveDialog = addon:NewObject("SaveDialog")
local ModuleRow = addon:GetObject("ModuleRow")

local pm
local frame
local nameLabel, noteBox, toggleButton
local rows = {}   -- name -> checkbox
local onConfirm

-- True only when there is at least one row and every row is checked.
local function AreAllChecked()
    local any = false
    for _, cb in pairs(rows) do
        any = true
        if not cb:GetChecked() then
            return false
        end
    end
    return any
end

local function RefreshToggle()
    if not toggleButton then return end
    toggleButton:SetText(AreAllChecked() and L["Deselect All"] or L["Select All"])
end

local function SetAllChecked(checked)
    for _, cb in pairs(rows) do
        cb:SetChecked(checked)
    end
end

-- Build one checkbox per registered module. The module set is fixed at runtime,
-- so the rows are created once and only their checked state is reset on Show.
local function BuildRows(listParent)
    local names = {}
    for name in pm:IterableModules() do
        tinsert(names, name)
    end
    table.sort(names)

    local yOffset = 0
    for _, name in ipairs(names) do
        local cb = ModuleRow:Build(listParent)
        cb:SetPoint("TOPLEFT", 0, -yOffset)
        cb:HookScript("OnClick", RefreshToggle)
        ModuleRow:Update(cb, name, true, nil, nil)
        rows[name] = cb
        yOffset = yOffset + UI.ModuleRowHeight + UI.ModuleRowPadding
    end
end

local function Build()
    if frame then return end
    pm = WowSync:GetProfileManager()

    -- Taller than the apply preview to keep room for the full module list below
    -- the extra name and note rows.
    frame = CreateFrame("Frame", "WowSyncSaveDialog", UIParent, "BackdropTemplate")
    frame:SetSize(UI.PreviewWidth, UI.PreviewHeight + 60)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(UI.MainBackdropColor))
    frame:SetBackdropBorderColor(unpack(UI.MainBorderColor))
    frame:EnableMouse(true)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L["Save snapshot"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, -2)
    close:SetScript("OnClick", function() SaveDialog:Hide() end)

    nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 14, -38)
    nameLabel:SetPoint("TOPRIGHT", -14, -38)
    nameLabel:SetJustifyH("LEFT")

    local noteHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteHeader:SetPoint("TOPLEFT", 14, -60)
    noteHeader:SetText(L["Note (optional):"])

    noteBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    noteBox:SetPoint("TOPLEFT", 16, -76)
    noteBox:SetPoint("TOPRIGHT", -14, -76)
    noteBox:SetHeight(22)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(255)

    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", 14, -104)
    listHeader:SetText(L["Modules to save:"])

    toggleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggleButton:SetSize(100, 20)
    toggleButton:SetPoint("TOPRIGHT", -14, -100)
    toggleButton:SetScript("OnClick", function()
        SetAllChecked(not AreAllChecked())
        RefreshToggle()
    end)

    local listSlot = CreateFrame("Frame", nil, frame)
    listSlot:SetPoint("TOPLEFT", 14, -126)
    listSlot:SetPoint("TOPRIGHT", -14, -126)
    listSlot:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    BuildRows(listSlot)

    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetSize(110, 22)
    saveButton:SetPoint("BOTTOMRIGHT", -14, 12)
    saveButton:SetText(L["Save"])
    saveButton:SetScript("OnClick", function()
        local moduleSet = {}
        for name, cb in pairs(rows) do
            if cb:GetChecked() then
                moduleSet[name] = true
            end
        end
        if not next(moduleSet) then
            WowSync:Print(L["No modules selected."])
            return
        end

        local note = strtrim(noteBox:GetText())
        if note == "" then
            note = nil
        end

        SaveDialog:Hide()
        if onConfirm then
            onConfirm(moduleSet, note)
        end
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(110, 22)
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
    cancelButton:SetText(L["Cancel"])
    cancelButton:SetScript("OnClick", function() SaveDialog:Hide() end)

    -- ESC closes the dialog.
    tinsert(UISpecialFrames, "WowSyncSaveDialog")

    frame:Hide()
end

function SaveDialog:Show(opts)
    Build()

    onConfirm = opts.onConfirm
    nameLabel:SetText(L["Saving to: X"]:format(opts.profileName))
    noteBox:SetText("")

    -- Default to capturing everything each time the dialog opens.
    for name, cb in pairs(rows) do
        ModuleRow:Update(cb, name, true, nil, nil)
    end
    RefreshToggle()

    frame:Show()
    frame:Raise()
end

function SaveDialog:Hide()
    if frame then
        frame:Hide()
    end
end
