local _, addon = ...

--[[
    ImportDetails object (right panel, Imports tab).

    Shows the selected imported container: an empty-state prompt until one is
    picked, then the container's name, a rename bar and its snapshot
    timeline. A snapshot can be applied to the logged-in character (through the
    shared apply-preview dialog), have its note edited, or be deleted.

    addon:GetObject("ImportDetails"):Build(region)
        -> import-details frame {
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
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()
local SnapshotManager = WowSync:GetSnapshotManager()

local Verbs = {}

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
local function ApplySnapshot(panel, snapshot, moduleSet, mode, overrides)
    if SnapshotManager:IsCombatLocked() then
        WowSync:Print(L["You can't do that while in combat."])
        return
    end
    if not next(moduleSet) then
        WowSync:Print(L["No modules selected."])
        return
    end

    local strategy = { default = mode or "exact", overrides = overrides }
    local applyResult = ImportManager:ApplySnapshot(panel._currentImportID, SelectorFor(snapshot), strategy, moduleSet)
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
local function RequestApply(panel, snapshot)
    if not panel._currentImportID or not snapshot then return end

    local selector = SelectorFor(snapshot)
    ApplyPreviewDialog:Show({
        snapshot = HandleFor(snapshot),
        preview = ImportManager:PreviewApplySnapshot(panel._currentImportID, selector),
        subject = SnapshotRow:FormatSubject(snapshot.Timestamp),
        mode = "exact",
        onConfirm = function(moduleSet, overrides)
            PopupDialogs:ConfirmApply("exact", function()
                ApplySnapshot(panel, snapshot, moduleSet, "exact", overrides)
            end)
        end,
    })
end

local function OpenSnapshotMenu(panel, snapshot, anchor)
    if not panel._currentImportID or not snapshot then return end

    local subject = SnapshotRow:FormatSubject(snapshot.Timestamp)
    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(subject)

        rootDescription:CreateButton(L["Apply"], function()
            RequestApply(panel, snapshot)
        end)

        rootDescription:CreateButton(L["Preview changes"], function()
            local preview = ImportManager:PreviewApplySnapshot(panel._currentImportID, SelectorFor(snapshot))
            if not preview then
                WowSync:Print(L["Nothing saved yet to compare against."])
                return
            end
            GameDiffPreview:Show({ title = subject, preview = preview, mode = "exact" })
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(L["Delete snapshot"], function()
            local dependents = ImportManager:CountDependentDuplicates(panel._currentImportID, SelectorFor(snapshot))
            PopupDialogs:ConfirmDeleteSnapshot(subject, function()
                ImportManager:DeleteSnapshot(panel._currentImportID, SelectorFor(snapshot))
                panel:SetImport(panel._currentImportID)
                if panel._onRefresh then panel._onRefresh() end
            end, dependents)
        end)
    end)
end

function Verbs:Constructor(config)
    local panel = self

    self:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    self:SetBackdropColor(unpack(UI.Backdrop.Panel))
    self:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))

    -- Empty state, shown until a container is selected.
    self._emptyLabel = self:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    self._emptyLabel:SetPoint("CENTER")
    self._emptyLabel:SetText(L["Select an import"])

    -- Content, revealed once a container is selected.
    local content = CreateFrame("Frame", nil, self)
    content:SetPoint("TOPLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    content:Hide()
    self._content = content

    -- Rename, top-right of the header.
    local renameButton = Button:Build({
        parent = content,
        anchor = function(button)
            button:SetPoint("TOPRIGHT", 0, 2)
        end,
        width = 70,
        height = 24,
        text = L["Rename"],
        onClick = function()
            local record = panel._currentImportID and ImportManager:GetImport(panel._currentImportID)
            if not record then return end
            PopupDialogs:PromptRename(record.Name, function(name)
                if ImportManager:RenameImport(panel._currentImportID, name) then
                    panel._titleText:SetText(name)
                    if panel._onRefresh then panel._onRefresh() end
                end
            end)
        end,
    })

    local titleText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 0, 0)
    titleText:SetPoint("RIGHT", renameButton, "LEFT", -8, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    self._titleText = titleText

    -- Separator between the header and the snapshot timeline.
    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", -2, -6)
    separator:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(UI.Backdrop.Separator))

    -- Action bar: Apply selected snapshot.
    local applyButton = Button:Build({
        parent = content,
        anchor = function(button)
            button:SetPoint("BOTTOMLEFT", 0, 0)
        end,
        width = 80,
        height = 24,
        text = L["Apply"],
        onClick = function()
            RequestApply(panel, panel._timeline:GetSelected())
        end,
    })
    self._applyButton = applyButton

    -- Snapshot timeline, filling the space between the title and the action bar.
    local timelineSlot = CreateFrame("Frame", nil, content)
    timelineSlot:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    timelineSlot:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    timelineSlot:SetPoint("BOTTOM", applyButton, "TOP", 0, 8)
    self._timeline = ImportSnapshotList:Build(timelineSlot, {
        onSelect = function(snapshot)
            applyButton:SetEnabled(snapshot ~= nil)
        end,
        onContext = function(snapshot, anchor)
            OpenSnapshotMenu(panel, snapshot, anchor)
        end,
    })
end

function ImportDetails:Build(region)
    C:IsTable(region, 2)
    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
    }, {
        frameType = "Frame",
        template = "BackdropTemplate",
        verbs = Verbs,
    })
end

function Verbs:OnRefresh(callback)
    self._onRefresh = callback
end

function Verbs:SetImport(importID)
    self._currentImportID = importID
    local record = importID and ImportManager:GetImport(importID)
    if not record then
        self._content:Hide()
        self._emptyLabel:Show()
        self._timeline:Clear()
        return
    end

    self._emptyLabel:Hide()
    self._titleText:SetText(record.Name or "")
    self._timeline:SetImport(importID)
    self._applyButton:SetEnabled(false)
    self._content:Show()
end
