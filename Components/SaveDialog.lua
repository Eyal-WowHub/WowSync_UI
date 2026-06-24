local _, addon = ...

--[[
    SaveDialog object.

    A modal window for saving a snapshot to a profile with an optional note and
    an optional module subset. It hands the chosen module set and note (and, in
    cross-character mode, the chosen profile name) back through onConfirm so the
    caller runs the actual save. The dialog is "dumb" about saving itself.

    Two modes:
      * Fixed profile (default): the target profile is given up front and shown
        as a static label; every registered module is offered.
        onConfirm(moduleSet, note)
      * Cross-character (pickProfile): the caller is saving another character's
        captured setup, so a profile-name field is shown (type a new name or
        pick an existing one) and only the given modules are offered.
        onConfirm(profileName, moduleSet, note)

    Unlike the apply preview, this dialog owns its own (non-pooled) checkbox
    rows rather than the shared ModuleList object, because that list is a
    singleton already used by ApplyPreviewDialog.

    addon:GetObject("SaveDialog"):Show({
        profileName      = string,        -- fixed mode: the target profile
        pickProfile      = boolean,       -- cross-char: show a profile-name field
        moduleNames      = { name, ... }, -- restrict the offered modules (cross-char)
        existingProfiles = { name, ... }, -- suggestions for the pick-existing menu
        onConfirm        = function(...) end,
    })
]]

local SaveDialog = addon:NewObject("SaveDialog")
local ModuleRow = addon:GetObject("ModuleRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

-- Extra height added to the preview size to fit the note field this dialog adds.
local NOTE_FIELD_HEIGHT = 60

local pm
local frame
local title, nameLabel, nameBox, pickButton, noteBox, toggleButton
local rows = {}          -- name -> checkbox (one per registered module, created once)
local activeNames = {}   -- names currently offered/shown (a subset of rows)
local pickProfile = false
local existingProfiles = nil
local onConfirm

local function IsActive(name)
    for _, n in ipairs(activeNames) do
        if n == name then return true end
    end
    return false
end

-- True only when there is at least one offered row and every offered row is
-- checked.
local function AreAllChecked()
    if #activeNames == 0 then return false end
    for _, name in ipairs(activeNames) do
        if not rows[name]:GetChecked() then
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
        rows[name]:SetChecked(checked)
    end
end

-- Build one checkbox per registered module. The registered set is fixed at
-- runtime, so the rows are created once; which of them are offered (and their
-- checked state) is decided per Show.
local function BuildRows(listParent)
    local names = {}
    for name in pm:IterableModules() do
        tinsert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local cb = ModuleRow:Build(listParent)
        cb:HookScript("OnClick", RefreshToggle)
        rows[name] = cb
        cb:Hide()
    end
end

-- Stack the offered rows top-to-bottom (reset to checked) and hide the rest.
local function LayoutActiveRows()
    local yOffset = 0
    for _, name in ipairs(activeNames) do
        local cb = rows[name]
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 0, -yOffset)
        ModuleRow:Update(cb, name, true, nil, nil)
        cb:Show()
        yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
    end

    for name, cb in pairs(rows) do
        if not IsActive(name) then
            cb:Hide()
        end
    end
end

-- Offer the existing profile names in a menu; choosing one fills the name box.
local function OpenExistingMenu()
    if not existingProfiles or #existingProfiles == 0 then return end
    MenuUtil.CreateContextMenu(pickButton, function(_, rootDescription)
        rootDescription:CreateTitle(L["Existing profiles"])
        for _, name in ipairs(existingProfiles) do
            rootDescription:CreateButton(name, function()
                nameBox:SetText(name)
                nameBox:SetCursorPosition(0)
            end)
        end
    end)
end

local function Build()
    if frame then return end
    pm = WowSync:GetProfileManager()

    -- Taller than the apply preview to keep room for the full module list below
    -- the extra name and note rows.
    frame = CreateFrame("Frame", "WowSyncSaveDialog", UIParent, "BackdropTemplate")
    frame:SetSize(UI.Preview.Width, UI.Preview.Height + NOTE_FIELD_HEIGHT)
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

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L["Save snapshot"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, -2)
    close:SetScript("OnClick", function() SaveDialog:Hide() end)

    -- Target profile: a static label (fixed mode) or an editable name field with
    -- a pick-existing menu (cross-character mode). They share the same row.
    nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 14, -38)
    nameLabel:SetPoint("TOPRIGHT", -14, -38)
    nameLabel:SetJustifyH("LEFT")

    pickButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pickButton:SetSize(24, 20)
    pickButton:SetPoint("TOPRIGHT", -14, -36)
    pickButton:SetText("▼")
    pickButton:SetScript("OnClick", OpenExistingMenu)
    pickButton:Hide()

    nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", 16, -36)
    nameBox:SetPoint("RIGHT", pickButton, "LEFT", -6, 0)
    nameBox:SetHeight(20)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(50)
    nameBox:Hide()

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
        for _, name in ipairs(activeNames) do
            if rows[name]:GetChecked() then
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

        if pickProfile then
            local profileName = strtrim(nameBox:GetText())
            if profileName == "" then
                WowSync:Print(L["Enter a profile name."])
                return
            end
            SaveDialog:Hide()
            if onConfirm then
                onConfirm(profileName, moduleSet, note)
            end
        else
            SaveDialog:Hide()
            if onConfirm then
                onConfirm(moduleSet, note)
            end
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
    C:IsTable(opts, 2)

    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    Build()

    onConfirm = opts.onConfirm
    pickProfile = opts.pickProfile or false
    existingProfiles = opts.existingProfiles

    -- Decide which modules to offer: a given subset, or every registered module.
    wipe(activeNames)
    if opts.moduleNames then
        for _, name in ipairs(opts.moduleNames) do
            if rows[name] then
                tinsert(activeNames, name)
            end
        end
    else
        for name in pairs(rows) do
            tinsert(activeNames, name)
        end
    end
    table.sort(activeNames)

    -- Target profile field
    if pickProfile then
        title:SetText(L["Save to profile"])
        nameLabel:Hide()
        nameBox:SetText("")
        nameBox:Show()
        pickButton:SetShown(existingProfiles ~= nil and #existingProfiles > 0)
    else
        title:SetText(L["Save snapshot"])
        nameLabel:SetText(L["Saving to: X"]:format(opts.profileName or ""))
        nameLabel:Show()
        nameBox:Hide()
        pickButton:Hide()
    end

    noteBox:SetText("")

    LayoutActiveRows()
    RefreshToggle()

    frame:Show()
    frame:Raise()
end

function SaveDialog:Hide()
    if frame then
        frame:Hide()
    end
end
