local _, addon = ...

--[[
    ApplyPreviewDialog object.

    A modal confirmation window shown before a snapshot is applied. It lists the
    snapshot's modules with their per-module change counts (added / updated /
    removed) against the live setup, lets the user narrow the apply to a subset,
    and only commits when confirmed. The dialog is "dumb" about the apply itself:
    it gathers the chosen module set and hands it back through onConfirm so the
    caller stays in charge of running and reporting the apply.

    addon:GetObject("ApplyPreviewDialog"):Show({
        snapshot    = <snapshot>,
        mode        = "exact" | "merge",         -- the default mode each row
                                                 -- starts in (rows can override)
        subject     = string,                    -- header label; defaults to the
                                                 -- snapshot's own subject
        preview     = <preview>,                 -- precomputed diff; defaults to a
                                                 -- live preview of the snapshot
        onConfirm   = function(moduleSet, overrides) end,
                                                 -- moduleSet: { [name] = true }
                                                 -- overrides: { [name] = mode }
    })
]]

local ApplyPreviewDialog = addon:NewObject("ApplyPreviewDialog")
local Dialog = addon:GetObject("Dialog")
local GameDiffPreview = addon:GetObject("GameDiffPreview")
local ModuleList = addon:GetObject("ModuleList")
local SnapshotRow = addon:GetObject("SnapshotRow")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

-- The module list is a fixed, non-scrolling column, so the dialog must be tall
-- enough to seat every module row clear of the action buttons. The shared
-- preview height is too short once all modules are listed; size to the full set
-- plus breathing room above the Apply/Cancel row.
local DIALOG_HEIGHT = 388

local SnapshotView = WowSync:GetSnapshotView()

local Verbs = {}

-- Keep the select-all toggle's label in sync with the current checkbox state.
local function RefreshToggle(panel)
    if not panel._toggleButton then return end
    panel._toggleButton:SetText(panel._moduleList:AreAllSelectableChecked() and L["Deselect All"] or L["Select All"])
end

function Verbs:Constructor(config)
    local panel = self

    local subjectLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subjectLabel:SetPoint("TOPLEFT", 14, -38)
    subjectLabel:SetPoint("TOPRIGHT", -14, -38)
    subjectLabel:SetJustifyH("LEFT")
    self._subjectLabel = subjectLabel

    local listHeader = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", 14, -60)
    listHeader:SetText(L["Modules to apply:"])

    local toggleButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("TOPLEFT", 12, -76)
        end,
        width = 100,
        height = 20,
        onClick = function()
            panel._moduleList:SetAllChecked(not panel._moduleList:AreAllSelectableChecked())
            RefreshToggle(panel)
        end,
    })
    self._toggleButton = toggleButton

    local listSlot = CreateFrame("Frame", nil, self)
    listSlot:SetPoint("TOPLEFT", 14, -102)
    listSlot:SetPoint("TOPRIGHT", -14, -102)
    listSlot:SetPoint("BOTTOM", self, "BOTTOM", 0, 44)
    self._moduleList = ModuleList:Build(listSlot, {
        onChanged = function() RefreshToggle(panel) end,
        -- Clicking a module name opens the read-only diff browser filtered to
        -- that module, in the row's current mode.
        onPreviewModule = function(name, mode)
            GameDiffPreview:Show({
                title = panel._currentSubject,
                preview = panel._currentPreview,
                mode = mode or panel._currentMode,
                moduleFilter = name,
            })
        end,
    })

    local applyButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 100,
        height = 22,
        text = L["Apply"],
        onClick = function()
            local moduleSet, overrides = panel._moduleList:GetStrategy()
            panel:Hide()
            if panel._onConfirm then
                panel._onConfirm(moduleSet, overrides)
            end
        end,
    })

    local cancelButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("RIGHT", applyButton, "LEFT", -8, 0)
        end,
        width = 100,
        height = 22,
        text = L["Cancel"],
        onClick = function() panel:Hide() end,
    })
end

function Verbs:Open(opts)
    self._onConfirm = opts.onConfirm
    self._currentMode = opts.mode or "exact"
    self._currentSubject = opts.subject
        or (SnapshotView:IsHead(opts.snapshot) and L["Current"] or SnapshotRow:FormatSubject(SnapshotView:GetTimestamp(opts.snapshot)))
    self:SetTitle(L["Apply snapshot"])
    self._subjectLabel:SetText(self._currentSubject)

    self._currentPreview = opts.preview or SnapshotView:Preview(opts.snapshot)
    self._moduleList:SetSnapshot(opts.snapshot, self._currentPreview, self._currentMode)
    RefreshToggle(self)

    self:Show()
end

local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncApplyPreview",
            title = L["Apply snapshot"],
            width = UI.Preview.Width,
            height = DIALOG_HEIGHT,
        }),
        verbs = Verbs,
    })
end

function ApplyPreviewDialog:Show(opts)
    C:IsTable(opts, 2)

    C:Ensures(type(opts.snapshot) == "table", "Show: 'opts.snapshot' must be a table")
    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function ApplyPreviewDialog:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
