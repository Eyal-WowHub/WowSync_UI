local _, addon = ...

--[[
    ImportDetails object (right panel, Imports tab).

    Shows the selected imported container: an empty-state prompt until one is
    picked, then the container's name, a rename bar and its snapshot
    timeline. A snapshot can be applied to the logged-in character (through the
    shared apply-preview dialog), have its note edited, or be deleted.

    addon:GetObject("ImportDetails"):Build(region)
        -> self {
            SetImport(importID or nil),
            OnRefresh(callback),   -- fired after a rename
        }
]]

local ImportDetails = addon:NewObject("ImportDetails")
local ImportSnapshotList = addon:GetObject("ImportSnapshotList")
local ApplyPreviewDialog = addon:GetObject("ApplyPreviewDialog")
local GameDiffPreview = addon:GetObject("GameDiffPreview")
local PopupDialogs = addon:GetObject("PopupDialogs")
local SnapshotRow = addon:GetObject("SnapshotRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()
local SnapshotManager = WowSync:GetSnapshotManager()

local emptyLabel
local content
local titleText
local timeline
local applyButton
local currentImportID
local onRefresh

-- The core selector for an imported snapshot: its full hash pinned to its index.
local function SelectorFor(snapshot)
    return ("%s#%d"):format(snapshot.Hash, snapshot.Index or 0)
end

-- A snapshot handle the apply dialog and ModuleList can read; never applied
-- through directly (apply routes through ImportManager).
local function HandleFor(snapshot)
    return { isHead = false, raw = snapshot }
end

-- Apply the chosen modules of an imported snapshot to the logged-in character,
-- reporting per-module outcomes in chat.
local function ApplySnapshot(snapshot, moduleSet, mode, overrides)
    if SnapshotManager:IsCombatLocked() then
        WowSync:Print(L["You can't do that while in combat."])
        return
    end
    if not next(moduleSet) then
        WowSync:Print(L["No modules selected."])
        return
    end

    local strategy = { default = mode or "exact", overrides = overrides }
    local applyResult = ImportManager:ApplySnapshot(currentImportID, SelectorFor(snapshot), strategy, moduleSet)
    if applyResult and applyResult:Any() then
        for _, name in ipairs(applyResult:Applied()) do
            WowSync:Print(L["X: applied"]:format(name))
        end
        for _, name in ipairs(applyResult:Skipped()) do
            WowSync:Print(L["X: skipped - Y"]:format(name, applyResult:Get(name).reason or L["unknown"]))
        end
    else
        WowSync:Print(L["Nothing to apply."])
    end
end

-- Open the apply-preview dialog for an imported snapshot, defaulting to Exact.
local function RequestApply(snapshot)
    if not currentImportID or not snapshot then return end

    local selector = SelectorFor(snapshot)
    ApplyPreviewDialog:Show({
        snapshot = HandleFor(snapshot),
        preview = ImportManager:PreviewApplySnapshot(currentImportID, selector),
        subject = SnapshotRow:FormatSubject(snapshot.Timestamp),
        mode = "exact",
        onConfirm = function(moduleSet, overrides)
            PopupDialogs:ConfirmApply("exact", function()
                ApplySnapshot(snapshot, moduleSet, "exact", overrides)
            end)
        end,
    })
end

local function OpenSnapshotMenu(snapshot, anchor)
    if not currentImportID or not snapshot then return end

    local subject = SnapshotRow:FormatSubject(snapshot.Timestamp)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(subject)

        rootDescription:CreateButton(L["Apply"], function()
            RequestApply(snapshot)
        end)

        rootDescription:CreateButton(L["Preview changes"], function()
            GameDiffPreview:Show({
                title = subject,
                preview = ImportManager:PreviewApplySnapshot(currentImportID, SelectorFor(snapshot)),
                mode = "exact",
            })
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(L["Edit note…"], function()
            PopupDialogs:PromptEditNote(snapshot.Notes, function(text)
                ImportManager:SetSnapshotNotes(currentImportID, SelectorFor(snapshot), text)
                timeline:Refresh()
            end)
        end)

        rootDescription:CreateButton(L["Delete snapshot"], function()
            PopupDialogs:ConfirmDeleteSnapshot(subject, function()
                ImportManager:DeleteSnapshot(currentImportID, SelectorFor(snapshot))
                ImportDetails:SetImport(currentImportID)
                if onRefresh then onRefresh() end
            end)
        end)
    end)
end

function ImportDetails:Build(region)
    C:IsTable(region, 2)

    local root = CreateFrame("Frame", nil, region, "BackdropTemplate")
    root:SetAllPoints(region)
    root:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(unpack(UI.Backdrop.Panel))
    root:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))

    -- Empty state, shown until a container is selected.
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetText(L["Select an import"])

    -- Content, revealed once a container is selected.
    content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    content:Hide()

    -- Rename, top-right of the header.
    local renameButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    renameButton:SetPoint("TOPRIGHT", 0, 2)
    renameButton:SetSize(70, 22)
    renameButton:SetText(L["Rename"])
    renameButton:SetScript("OnClick", function()
        local record = currentImportID and ImportManager:GetImport(currentImportID)
        if not record then return end
        PopupDialogs:PromptRename(record.Name, function(name)
            if ImportManager:RenameImport(currentImportID, name) then
                titleText:SetText(name)
                if onRefresh then onRefresh() end
            end
        end)
    end)

    titleText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 0, 0)
    titleText:SetPoint("RIGHT", renameButton, "LEFT", -8, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)

    -- Separator between the header and the snapshot timeline.
    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", -2, -6)
    separator:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(UI.Backdrop.Separator))

    -- Action bar: Apply selected snapshot.
    applyButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    applyButton:SetPoint("BOTTOMLEFT", 0, 0)
    applyButton:SetSize(80, 24)
    applyButton:SetText(L["Apply"])
    applyButton:SetScript("OnClick", function()
        RequestApply(timeline:GetSelected())
    end)

    -- Snapshot timeline, filling the space between the title and the action bar.
    local timelineSlot = CreateFrame("Frame", nil, content)
    timelineSlot:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    timelineSlot:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    timelineSlot:SetPoint("BOTTOM", applyButton, "TOP", 0, 8)
    timeline = ImportSnapshotList:Build(timelineSlot, {
        onSelect = function(snapshot)
            applyButton:SetEnabled(snapshot ~= nil)
        end,
        onContext = OpenSnapshotMenu,
    })

    return self
end

function ImportDetails:OnRefresh(callback)
    onRefresh = callback
end

function ImportDetails:SetImport(importID)
    currentImportID = importID
    local record = importID and ImportManager:GetImport(importID)
    if not record then
        content:Hide()
        emptyLabel:Show()
        timeline:Clear()
        return
    end

    emptyLabel:Hide()
    titleText:SetText(record.Name or "")
    timeline:SetImport(importID)
    applyButton:SetEnabled(false)
    content:Show()
end
