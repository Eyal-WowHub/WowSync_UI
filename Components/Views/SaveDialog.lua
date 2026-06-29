local _, addon = ...

--[[
    SaveDialog object.

    A modal window for choosing which modules a snapshot captures. It hands the
    chosen module set back through onConfirm so the caller runs the actual save.
    The dialog is "dumb" about saving itself — the owning character and the
    optional note are decided by the caller, not here.

    Unlike the apply preview, this dialog owns its own (non-pooled) checkbox
    rows rather than the shared ModuleList object, because that list is a
    singleton already used by ApplyPreviewDialog.

    addon:GetObject("SaveDialog"):Show({
        moduleNames = { name, ... }, -- restrict the offered modules (optional)
        onConfirm   = function(moduleSet, note) end,
    })
]]

local SaveDialog = addon:NewObject("SaveDialog")
local Dialog = addon:GetObject("Dialog")
local ModuleRow = addon:GetObject("ModuleRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ModuleRegistry = WowSync:GetModuleRegistry()

local dialog, frame
local toggleButton, noteBox
local checkboxes = {}    -- moduleName -> checkbox (one per registered module, created once)
local activeNames = {}   -- module names currently offered/shown
local onConfirm

local function IsActive(moduleName)
    for _, activeName in ipairs(activeNames) do
        if activeName == moduleName then return true end
    end
    return false
end

-- True only when there is at least one offered row and every offered row is
-- checked.
local function AreAllChecked()
    if #activeNames == 0 then return false end
    for _, name in ipairs(activeNames) do
        if not checkboxes[name]:GetChecked() then
            return false
        end
    end
    return true
end

local function RefreshToggle()
    if not toggleButton then return end
    toggleButton:SetText(AreAllChecked() and L["Deselect All"] or L["Select All"])
end

local function SetAllChecked(checked)
    for _, name in ipairs(activeNames) do
        checkboxes[name]:SetChecked(checked)
    end
end

-- Build one checkbox per registered module. The registered set is fixed at
-- runtime, so the checkboxes are created once; which of them are offered (and their
-- checked state) is decided per Show.
local function BuildRows(listParent)
    local moduleNames = {}
    for name in ModuleRegistry:Iterate() do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    for _, name in ipairs(moduleNames) do
        local checkbox = ModuleRow:Build(listParent)
        checkbox:HookScript("OnClick", RefreshToggle)
        checkboxes[name] = checkbox
        checkbox:Hide()
    end
end

-- Stack the offered module checkboxes top-to-bottom and hide the rest.
local function LayoutActiveRows()
    local yOffset = 0
    for _, name in ipairs(activeNames) do
        local checkbox = checkboxes[name]
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", 0, -yOffset)
        ModuleRow:Update(checkbox, name, true, nil, nil)
        checkbox:Show()
        yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
    end

    for name, checkbox in pairs(checkboxes) do
        if not IsActive(name) then
            checkbox:Hide()
        end
    end
end

-- Build the dialog frame and its module checkbox region.
local function Build()
    if frame then return end

    dialog = Dialog:Build({
        name = "WowSyncSaveDialog",
        title = L["Save snapshot"],
        width = UI.Preview.Width,
        height = UI.Preview.Height,
    })
    frame = dialog:GetFrame()

    -- Optional note attached to the snapshot when the player saves.
    local noteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteLabel:SetPoint("TOPLEFT", 14, -44)
    noteLabel:SetText(L["Note (optional):"])

    noteBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 2, -6)
    noteBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -60)
    noteBox:SetHeight(20)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(255)

    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", -2, -14)
    listHeader:SetText(L["Modules to save:"])

    toggleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggleButton:SetSize(100, 20)
    toggleButton:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 2, -6)
    toggleButton:SetScript("OnClick", function()
        SetAllChecked(not AreAllChecked())
        RefreshToggle()
    end)

    local listSlot = CreateFrame("Frame", nil, frame)
    listSlot:SetPoint("TOPLEFT", toggleButton, "BOTTOMLEFT", -2, -8)
    listSlot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, 0)
    listSlot:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    BuildRows(listSlot)

    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetSize(110, 22)
    saveButton:SetPoint("BOTTOMRIGHT", -14, 12)
    saveButton:SetText(L["Save"])
    saveButton:SetScript("OnClick", function()
        local moduleSet = {}
        for _, name in ipairs(activeNames) do
            if checkboxes[name]:GetChecked() then
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

    -- Enter in the note box confirms the save.
    noteBox:SetScript("OnEnterPressed", function() saveButton:Click() end)

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(110, 22)
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
    cancelButton:SetText(L["Cancel"])
    cancelButton:SetScript("OnClick", function() SaveDialog:Hide() end)
end

function SaveDialog:Show(opts)
    C:IsTable(opts, 2)

    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    Build()

    onConfirm = opts.onConfirm

    -- Decide which modules to offer: a given subset, or every registered module.
    wipe(activeNames)
    if opts.moduleNames then
        for _, name in ipairs(opts.moduleNames) do
            if checkboxes[name] then
                tinsert(activeNames, name)
            end
        end
    else
        for name in pairs(checkboxes) do
            tinsert(activeNames, name)
        end
    end
    table.sort(activeNames)

    dialog:SetTitle(L["Save snapshot"])

    noteBox:SetText("")
    noteBox:ClearFocus()

    LayoutActiveRows()
    RefreshToggle()

    dialog:Show()
end

function SaveDialog:Hide()
    if dialog then
        dialog:Hide()
    end
end
