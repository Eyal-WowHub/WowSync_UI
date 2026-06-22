local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    ApplyPreviewDialog object.

    A modal confirmation window shown before a snapshot is applied. It lists the
    snapshot's modules with their per-module change counts (added / updated /
    removed) against the live setup, lets the user narrow the apply to a subset,
    and only commits when confirmed. The dialog is "dumb" about the apply itself:
    it gathers the chosen module set and hands it back through onConfirm so the
    caller stays in charge of running and reporting the apply.

    addon:GetObject("ApplyPreviewDialog"):Show({
        profileName = string,
        snapshot    = <snapshot>,
        onConfirm   = function(moduleSet) end,   -- { [name] = true }
    })
]]

local ApplyPreviewDialog = addon:NewObject("ApplyPreviewDialog")
local ModuleList = addon:GetObject("ModuleList")
local SnapshotRow = addon:GetObject("SnapshotRow")

local pm
local frame
local subjectLabel, moduleList, toggleButton
local onConfirm

-- Keep the select-all toggle's label in sync with the current checkbox state.
local function RefreshToggle()
    if not toggleButton then return end
    toggleButton:SetText(moduleList:AreAllSelectableChecked() and L["Deselect All"] or L["Select All"])
end

local function Build()
    if frame then return end
    pm = WowSync:GetProfileManager()

    frame = CreateFrame("Frame", "WowSyncApplyPreview", UIParent, "BackdropTemplate")
    frame:SetSize(UI.PreviewWidth, UI.PreviewHeight)
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
    title:SetText(L["Apply snapshot"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, -2)
    close:SetScript("OnClick", function() ApplyPreviewDialog:Hide() end)

    subjectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subjectLabel:SetPoint("TOPLEFT", 14, -38)
    subjectLabel:SetPoint("TOPRIGHT", -14, -38)
    subjectLabel:SetJustifyH("LEFT")

    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", 14, -60)
    listHeader:SetText(L["Modules to apply:"])

    toggleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggleButton:SetSize(100, 20)
    toggleButton:SetPoint("TOPRIGHT", -14, -56)
    toggleButton:SetScript("OnClick", function()
        moduleList:SetAllChecked(not moduleList:AreAllSelectableChecked())
        RefreshToggle()
    end)

    local listSlot = CreateFrame("Frame", nil, frame)
    listSlot:SetPoint("TOPLEFT", 14, -82)
    listSlot:SetPoint("TOPRIGHT", -14, -82)
    listSlot:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    moduleList = ModuleList:Build(listSlot, {
        profileManager = pm,
        onChanged = RefreshToggle,
    })

    local applyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyButton:SetSize(110, 22)
    applyButton:SetPoint("BOTTOMRIGHT", -14, 12)
    applyButton:SetText(L["Apply"])
    applyButton:SetScript("OnClick", function()
        local moduleSet = moduleList:GetSelected()
        ApplyPreviewDialog:Hide()
        if onConfirm then
            onConfirm(moduleSet)
        end
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(110, 22)
    cancelButton:SetPoint("RIGHT", applyButton, "LEFT", -8, 0)
    cancelButton:SetText(L["Cancel"])
    cancelButton:SetScript("OnClick", function() ApplyPreviewDialog:Hide() end)

    -- ESC closes the dialog.
    tinsert(UISpecialFrames, "WowSyncApplyPreview")

    frame:Hide()
end

function ApplyPreviewDialog:Show(opts)
    Build()

    onConfirm = opts.onConfirm
    subjectLabel:SetText(SnapshotRow:FormatSubject(opts.snapshot.Timestamp))

    local preview = pm:PreviewApply(opts.profileName, opts.snapshot.Hash)
    moduleList:SetSnapshot(opts.snapshot, preview)
    RefreshToggle()

    frame:Show()
    frame:Raise()
end

function ApplyPreviewDialog:Hide()
    if frame then
        frame:Hide()
    end
end
