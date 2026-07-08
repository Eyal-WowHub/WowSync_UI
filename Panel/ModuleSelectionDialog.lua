local _, addon = ...

--[[
    ModuleSelectionDialog object.

    A modal window for choosing which modules an action covers, plus an optional
    note. It hands the chosen module set and note back through onConfirm so the
    caller runs the actual save or share. The dialog is "dumb" about the action
    itself — the owning character, the title and what happens with the result are
    decided by the caller, not here.

    The module list itself is the shared ModuleList widget (also used by the apply
    preview), so plugin/submodule selection lives in one place; this dialog only
    owns its note box, Select All toggle and confirm/cancel chrome.

    addon:GetObject("ModuleSelectionDialog"):Show({
        title       = L["Save snapshot"], -- window/header title
        confirmText = L["Save"],          -- confirm button label
        moduleNames = { name, ... },      -- restrict the offered modules (optional)
        note        = "prefill",          -- initial note text (optional)
        onConfirm   = function(moduleSet, note) end,
                                          -- moduleSet: nested { [name]=true | [Plugin]={ [plugin]={ [sub]=true } } }
    })
]]

local ModuleSelectionDialog = addon:NewObject("ModuleSelectionDialog")

local C = addon.C
local L = addon.L
local UI = addon.UI

local Button = addon:GetObject("Button")
local Dialog = addon:GetObject("Dialog")
local ModuleList = addon:GetObject("ModuleList")

-- The module list scrolls once it would grow taller than this; the dialog is
-- capped to this viewport plus its fixed chrome so a big module set never pushes
-- the window off-screen.
local MAX_LIST_HEIGHT = 300

local Methods = {}

-- Keep the select-all label and the confirm button in step with the current
-- selection: confirm stays disabled until at least one module is chosen.
local function RefreshState(panel)
    if panel._toggleButton then
        panel._toggleButton:SetText(panel._list:AreAllSelectableChecked() and L["Deselect All"] or L["Select All"])
    end
    if panel._confirmButton then
        panel._confirmButton:SetEnabled(panel._list:HasSelection())
    end
end

-- Build the dialog body: note box, Select All toggle, the shared module list, and
-- the confirm/cancel buttons.
function Methods:Constructor(config)
    local panel = self

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
            panel._list:SetAllChecked(not panel._list:AreAllSelectableChecked())
            RefreshState(panel)
        end,
    })
    self._toggleButton = toggleButton

    local listSlot = CreateFrame("Frame", nil, self)
    listSlot:SetPoint("TOPLEFT", toggleButton, "BOTTOMLEFT", -2, -8)
    listSlot:SetPoint("TOPRIGHT", self, "TOPRIGHT", -14, 0)
    listSlot:SetPoint("BOTTOM", self, "BOTTOM", 0, 44)
    self._listSlot = listSlot

    self._list = ModuleList:Build(listSlot, {
        onChanged = function() RefreshState(panel) end,
    })

    local confirmButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        onClick = function()
            local moduleSet = panel._list:GetSelected()
            -- The confirm button is disabled while the selection is empty, so this
            -- is only ever reached with at least one module chosen.
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

-- Offer a module set, apply the caller's labels and note, and show the dialog.
function Methods:Open(opts)
    self._onConfirm = opts.onConfirm

    self:SetTitle(opts.title or L["Save snapshot"])
    self._confirmButton:SetLabel(opts.confirmText or L["Save"])

    self._noteBox:SetText(opts.note or "")
    self._noteBox:ClearFocus()

    self._list:SetModuleNames(opts.moduleNames)
    RefreshState(self)

    -- Grow the dialog to fit the offered rows so none hide behind the buttons.
    -- The list region is pinned between fixed top and bottom chrome, so the gap
    -- between the dialog and the list is constant; add exactly the height the
    -- rows need on top of it.
    local rowsHeight = math.min(self._list:GetContentHeight(), MAX_LIST_HEIGHT)
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
