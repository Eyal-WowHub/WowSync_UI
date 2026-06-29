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

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local SnapshotView = WowSync:GetSnapshotView()

local dialog, frame
local subjectLabel, moduleList, toggleButton
local onConfirm
local currentMode, currentPreview, currentSubject

-- Keep the select-all toggle's label in sync with the current checkbox state.
local function RefreshToggle()
    if not toggleButton then return end
    toggleButton:SetText(moduleList:AreAllSelectableChecked() and L["Deselect All"] or L["Select All"])
end

local function Build()
    if frame then return end

    dialog = Dialog:Build({
        name = "WowSyncApplyPreview",
        title = L["Apply snapshot"],
        width = UI.Preview.Width,
        height = UI.Preview.Height,
    })
    frame = dialog:GetFrame()

    subjectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subjectLabel:SetPoint("TOPLEFT", 14, -38)
    subjectLabel:SetPoint("TOPRIGHT", -14, -38)
    subjectLabel:SetJustifyH("LEFT")

    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", 14, -60)
    listHeader:SetText(L["Modules to apply:"])

    toggleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggleButton:SetSize(100, 20)
    toggleButton:SetPoint("TOPLEFT", 12, -76)
    toggleButton:SetScript("OnClick", function()
        moduleList:SetAllChecked(not moduleList:AreAllSelectableChecked())
        RefreshToggle()
    end)

    local listSlot = CreateFrame("Frame", nil, frame)
    listSlot:SetPoint("TOPLEFT", 14, -102)
    listSlot:SetPoint("TOPRIGHT", -14, -102)
    listSlot:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    moduleList = ModuleList:Build(listSlot, {
        onChanged = RefreshToggle,
        -- Clicking a module name opens the read-only diff browser filtered to
        -- that module, in the row's current mode.
        onPreviewModule = function(name, mode)
            GameDiffPreview:Show({
                title = currentSubject,
                preview = currentPreview,
                mode = mode or currentMode,
                moduleFilter = name,
            })
        end,
    })

    local applyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyButton:SetSize(100, 22)
    applyButton:SetPoint("BOTTOMRIGHT", -14, 12)
    applyButton:SetText(L["Apply"])
    applyButton:SetScript("OnClick", function()
        local moduleSet, overrides = moduleList:GetStrategy()
        ApplyPreviewDialog:Hide()
        if onConfirm then
            onConfirm(moduleSet, overrides)
        end
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 22)
    cancelButton:SetPoint("RIGHT", applyButton, "LEFT", -8, 0)
    cancelButton:SetText(L["Cancel"])
    cancelButton:SetScript("OnClick", function() ApplyPreviewDialog:Hide() end)
end

function ApplyPreviewDialog:Show(opts)
    C:IsTable(opts, 2)

    C:Ensures(type(opts.snapshot) == "table", "Show: 'opts.snapshot' must be a table")
    C:Ensures(opts.onConfirm == nil or type(opts.onConfirm) == "function", "Show: 'opts.onConfirm' must be a function")

    Build()

    onConfirm = opts.onConfirm
    currentMode = opts.mode or "exact"
    currentSubject = opts.subject
        or (SnapshotView:IsHead(opts.snapshot) and L["Current"] or SnapshotRow:FormatSubject(SnapshotView:GetTimestamp(opts.snapshot)))
    dialog:SetTitle(L["Apply snapshot"])
    subjectLabel:SetText(currentSubject)

    currentPreview = opts.preview or SnapshotView:Preview(opts.snapshot)
    moduleList:SetSnapshot(opts.snapshot, currentPreview, currentMode)
    RefreshToggle()

    dialog:Show()
end

function ApplyPreviewDialog:Hide()
    if dialog then
        dialog:Hide()
    end
end
