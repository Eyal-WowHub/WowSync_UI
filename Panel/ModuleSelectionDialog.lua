local _, addon = ...

--[[
    ModuleSelectionDialog object.

    A modal window for choosing which modules an action covers, plus an optional
    note. It hands the chosen module set and note back through onConfirm so the
    caller runs the actual save or share. The dialog is "dumb" about the action
    itself — the owning character, the title and what happens with the result are
    decided by the caller, not here.

    Unlike the apply preview, this dialog owns its own (non-pooled) checkbox
    rows rather than the shared ModuleList object, because that list is a
    singleton already used by ApplyPreviewDialog.

    addon:GetObject("ModuleSelectionDialog"):Show({
        title       = L["Save snapshot"], -- window/header title
        confirmText = L["Save"],          -- confirm button label
        moduleNames = { name, ... },      -- restrict the offered modules (optional)
        note        = "prefill",          -- initial note text (optional)
        onConfirm   = function(moduleSet, note) end,
    })
]]

local ModuleSelectionDialog = addon:NewObject("ModuleSelectionDialog")
local Dialog = addon:GetObject("Dialog")
local ModuleRow = addon:GetObject("ModuleRow")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ModuleRegistry = WowSync:Import("ModuleRegistry")

local Methods = {}

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

-- True when at least one offered row is checked.
local function AreAnyChecked(panel)
    for _, name in ipairs(panel._activeNames) do
        if panel._checkboxes[name]:GetChecked() then
            return true
        end
    end
    return false
end

-- Keep the confirm button disabled until at least one module is selected, so
-- the action can never run on an empty set.
local function RefreshConfirm(panel)
    if not panel._confirmButton then return end
    panel._confirmButton:SetEnabled(AreAnyChecked(panel))
end

-- React to any change in the offered rows: both the select-all label and the
-- confirm button's enabled state depend on the current checks.
local function RefreshState(panel)
    RefreshToggle(panel)
    RefreshConfirm(panel)
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
        checkbox:HookScript("OnClick", function() RefreshState(panel) end)
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
function Methods:Constructor(config)
    local panel = self

    panel._checkboxes = {}    -- moduleName -> checkbox (one per registered module, created once)
    panel._activeNames = {}   -- module names currently offered/shown
    panel._onConfirm = nil

    -- Optional note attached to the snapshot for this action.
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
    listHeader:SetText(L["Modules:"])

    local toggleButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 2, -6)
        end,
        width = 100,
        height = 20,
        onClick = function()
            SetAllChecked(panel, not AreAllChecked(panel))
            RefreshState(panel)
        end,
    })
    self._toggleButton = toggleButton

    local listSlot = CreateFrame("Frame", nil, self)
    listSlot:SetPoint("TOPLEFT", toggleButton, "BOTTOMLEFT", -2, -8)
    listSlot:SetPoint("TOPRIGHT", self, "TOPRIGHT", -14, 0)
    listSlot:SetPoint("BOTTOM", self, "BOTTOM", 0, 44)
    self._listSlot = listSlot
    BuildRows(panel, listSlot)

    local confirmButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        onClick = function()
            local moduleSet = {}
            for _, name in ipairs(panel._activeNames) do
                if panel._checkboxes[name]:GetChecked() then
                    moduleSet[name] = true
                end
            end
            -- The confirm button is disabled while the set is empty, so this is
            -- only ever reached with at least one module chosen.
            if not next(moduleSet) then return end

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
    self._confirmButton = confirmButton

    -- Enter in the note box confirms when a selection exists.
    noteBox:SetScript("OnEnterPressed", function()
        if confirmButton:IsEnabled() then confirmButton:Click() end
    end)

    local cancelButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("RIGHT", confirmButton, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = L["Cancel"],
        onClick = function() panel:Hide() end,
    })
end

-- Offer a module set, apply the caller's labels and note, lay out the rows, and
-- show the dialog.
function Methods:Open(opts)
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

    self:SetTitle(opts.title or L["Save snapshot"])
    self._confirmButton:SetLabel(opts.confirmText or L["Save"])

    self._noteBox:SetText(opts.note or "")
    self._noteBox:ClearFocus()

    LayoutActiveRows(self)
    RefreshState(self)

    -- Grow the dialog to fit the offered rows so none hide behind the buttons.
    -- The list region is pinned between fixed top and bottom chrome, so the
    -- difference between the dialog and the list is a constant; add the exact
    -- height the stacked rows need on top of it.
    local rowsHeight = #self._activeNames * (UI.ModuleRow.Height + UI.ModuleRow.Padding)
    local chrome = self:GetHeight() - self._listSlot:GetHeight()
    self:SetHeight(chrome + rowsHeight)

    self:Show()
end

-- Build the dialog on first use, adopting the shared Dialog shell so the body
-- lives directly on the dialog frame.
local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncModuleSelectionDialog",
            title = L["Save snapshot"],
            width = UI.Preview.Width,
            height = UI.Preview.Height,
        }),
        methods = Methods,
    })
end

function ModuleSelectionDialog:Show(opts)
    C:IsTable(opts, 2)

    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function ModuleSelectionDialog:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
