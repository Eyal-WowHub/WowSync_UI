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
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ModuleRegistry = WowSync:GetModuleRegistry()

local Verbs = {}

local function IsActive(panel, moduleName)
    for _, activeName in ipairs(panel._activeNames) do
        if activeName == moduleName then return true end
    end
    return false
end

-- True only when there is at least one offered row and every offered row is
-- checked.
local function AreAllChecked(panel)
    if #panel._activeNames == 0 then return false end
    for _, name in ipairs(panel._activeNames) do
        if not panel._checkboxes[name]:GetChecked() then
            return false
        end
    end
    return true
end

local function RefreshToggle(panel)
    if not panel._toggleButton then return end
    panel._toggleButton:SetText(AreAllChecked(panel) and L["Deselect All"] or L["Select All"])
end

local function SetAllChecked(panel, checked)
    for _, name in ipairs(panel._activeNames) do
        panel._checkboxes[name]:SetChecked(checked)
    end
end

-- Build one checkbox per registered module. The registered set is fixed at
-- runtime, so the checkboxes are created once; which of them are offered (and their
-- checked state) is decided per Show.
local function BuildRows(panel, listParent)
    local moduleNames = {}
    for name in ModuleRegistry:Iterate() do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    for _, name in ipairs(moduleNames) do
        local checkbox = ModuleRow:Build(listParent)
        checkbox:HookScript("OnClick", function() RefreshToggle(panel) end)
        panel._checkboxes[name] = checkbox
        checkbox:Hide()
    end
end

-- Stack the offered module checkboxes top-to-bottom and hide the rest.
local function LayoutActiveRows(panel)
    local yOffset = 0
    for _, name in ipairs(panel._activeNames) do
        local checkbox = panel._checkboxes[name]
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", 0, -yOffset)
        checkbox:Update(name, true, nil, nil)
        checkbox:Show()
        yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
    end

    for name, checkbox in pairs(panel._checkboxes) do
        if not IsActive(panel, name) then
            checkbox:Hide()
        end
    end
end

-- Build the dialog body and its module checkbox region onto the adopted shell.
function Verbs:Constructor(config)
    local panel = self

    panel._checkboxes = {}    -- moduleName -> checkbox (one per registered module, created once)
    panel._activeNames = {}   -- module names currently offered/shown
    panel._onConfirm = nil

    -- Optional note attached to the snapshot when the player saves.
    local noteLabel = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteLabel:SetPoint("TOPLEFT", 14, -44)
    noteLabel:SetText(L["Note (optional):"])

    local noteBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
    noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 2, -6)
    noteBox:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -60)
    noteBox:SetHeight(20)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(255)
    self._noteBox = noteBox

    local listHeader = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", -2, -14)
    listHeader:SetText(L["Modules to save:"])

    local toggleButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 2, -6)
        end,
        width = 100,
        height = 20,
        onClick = function()
            SetAllChecked(panel, not AreAllChecked(panel))
            RefreshToggle(panel)
        end,
    })
    self._toggleButton = toggleButton

    local listSlot = CreateFrame("Frame", nil, self)
    listSlot:SetPoint("TOPLEFT", toggleButton, "BOTTOMLEFT", -2, -8)
    listSlot:SetPoint("TOPRIGHT", self, "TOPRIGHT", -14, 0)
    listSlot:SetPoint("BOTTOM", self, "BOTTOM", 0, 44)
    BuildRows(panel, listSlot)

    local saveButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        text = L["Save"],
        onClick = function()
            local moduleSet = {}
            for _, name in ipairs(panel._activeNames) do
                if panel._checkboxes[name]:GetChecked() then
                    moduleSet[name] = true
                end
            end
            if not next(moduleSet) then
                WowSync:Print(L["No modules selected."])
                return
            end

            local note = strtrim(panel._noteBox:GetText())
            if note == "" then
                note = nil
            end

            panel:Hide()
            if panel._onConfirm then
                panel._onConfirm(moduleSet, note)
            end
        end,
    })

    -- Enter in the note box confirms the save.
    noteBox:SetScript("OnEnterPressed", function() saveButton:Click() end)

    local cancelButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = L["Cancel"],
        onClick = function() panel:Hide() end,
    })
end

-- Offer a module set, reset the note, lay out the rows, and show the dialog.
function Verbs:Open(opts)
    self._onConfirm = opts.onConfirm

    -- Decide which modules to offer: a given subset, or every registered module.
    wipe(self._activeNames)
    if opts.moduleNames then
        for _, name in ipairs(opts.moduleNames) do
            if self._checkboxes[name] then
                tinsert(self._activeNames, name)
            end
        end
    else
        for name in pairs(self._checkboxes) do
            tinsert(self._activeNames, name)
        end
    end
    table.sort(self._activeNames)

    self:SetTitle(L["Save snapshot"])

    self._noteBox:SetText("")
    self._noteBox:ClearFocus()

    LayoutActiveRows(self)
    RefreshToggle(self)

    self:Show()
end

-- Build the dialog on first use, adopting the shared Dialog shell so the body
-- lives directly on the dialog frame.
local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncSaveDialog",
            title = L["Save snapshot"],
            width = UI.Preview.Width,
            height = UI.Preview.Height,
        }),
        verbs = Verbs,
    })
end

function SaveDialog:Show(opts)
    C:IsTable(opts, 2)

    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function SaveDialog:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
