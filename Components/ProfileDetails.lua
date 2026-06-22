local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    ProfileDetails object (right panel).

    Orchestrates the detail view for a selected profile. Composes ProfileHeader,
    SnapshotList, ActionBar and UndoList, and drives the WowSync actions
    (apply/undo/delete/rename) routed through the Dialogs object. Holds no
    widget-building code of its own beyond layout regions and the empty state.

    Apply targets the snapshot currently selected in the timeline (the latest by
    default).

    addon:GetObject("ProfileDetails"):Build(region)
        -> self {
            SetProfile(profileName or nil),
            OnRefresh(callback),   -- called after delete/rename
        }
]]

local ProfileDetails = addon:NewObject("ProfileDetails")
local Dialogs = addon:GetObject("Dialogs")
local ProfileHeader = addon:GetObject("ProfileHeader")
local SnapshotList = addon:GetObject("SnapshotList")
local UndoList = addon:GetObject("UndoList")
local ActionBar = addon:GetObject("ActionBar")
local ApplyPreviewDialog = addon:GetObject("ApplyPreviewDialog")

local pm
local currentProfileName = nil
local onRefreshNeeded = nil

local content, emptyLabel, statusLabel
local header, actionBar, undoList, snapshotList

-- Reflect the current undo point in whichever view is visible
local function ApplyUndoState()
    local hasUndo = WowSync:HasUndo()
    if content:IsShown() then
        actionBar:SetUndoEnabled(hasUndo)
    else
        -- Empty state: show the full undo history, or the placeholder when the
        -- stack is empty.
        local hasEntries = undoList:Refresh()
        emptyLabel:SetShown(not hasEntries)
    end
end

-- Show a one-line summary of the last apply inside the panel
local function SetApplyStatus(applied, skipped)
    if skipped > 0 then
        statusLabel:SetText(L["Applied X, skipped Y (see chat)"]:format(applied, skipped))
        statusLabel:SetTextColor(unpack(UI.WarningTextColor))
    else
        statusLabel:SetText(L["Applied X modules"]:format(applied))
        statusLabel:SetTextColor(unpack(UI.SuccessTextColor))
    end
    statusLabel:Show()
end

-- Action handlers

local function DoUndo()
    local info = WowSync:GetUndoInfo()
    local results = WowSync:Undo()
    if results then
        WowSync:Print(L["Undid the last apply (X)."]:format(info and info.Subject or L["Unknown"]))
        for name, result in pairs(results) do
            if result.applied then
                WowSync:Print(L["  X: restored"]:format(name))
            end
        end
    end
    ApplyUndoState()
end

local function ApplySnapshot(snapshot, moduleSet, mode)
    if not currentProfileName or not snapshot then return end

    if not next(moduleSet) then
        WowSync:Print(L["No modules selected."])
        return
    end

    -- Apply only the chosen modules of the snapshot, in the requested mode.
    local strategy = { default = mode or "merge" }
    local results = pm:Apply(currentProfileName, snapshot.Hash, strategy, moduleSet)
    if results and next(results) then
        local applied, skipped = 0, 0
        for name, result in pairs(results) do
            if result.applied then
                applied = applied + 1
                local msg = L["X: applied"]:format(name)
                if result.warning then
                    msg = L["X (Y)"]:format(msg, result.warning)
                end
                WowSync:Print(msg)
            else
                skipped = skipped + 1
                WowSync:Print(L["X: skipped - Y"]:format(name, result.reason or L["unknown"]))
            end
        end
        SetApplyStatus(applied, skipped)
    else
        WowSync:Print(L["Nothing to apply."])
    end

    ApplyUndoState()
end

-- Open the preview dialog for a snapshot (defaulting to the selected one) in the
-- given mode. Once the user picks a module subset, a final mode-aware prompt
-- spells out what will happen and gives one last chance to confirm or cancel.
local function RequestApply(snapshot, mode)
    if not currentProfileName then return end

    snapshot = snapshot or snapshotList:GetSelected()
    if not snapshot then return end

    mode = mode or "merge"
    ApplyPreviewDialog:Show({
        profileName = currentProfileName,
        snapshot = snapshot,
        mode = mode,
        onConfirm = function(moduleSet)
            Dialogs:ConfirmApply(mode, function()
                ApplySnapshot(snapshot, moduleSet, mode)
            end)
        end,
    })
end

local function DoDelete()
    if currentProfileName then
        pm:DeleteProfile(currentProfileName)
        currentProfileName = nil
        if onRefreshNeeded then
            onRefreshNeeded()
        end
    end
end

local function DoRename(newName)
    if newName ~= "" and currentProfileName then
        if pm:RenameProfile(currentProfileName, newName) then
            currentProfileName = newName
            if onRefreshNeeded then
                onRefreshNeeded()
            end
        else
            WowSync:Print(L["Rename failed — name may already exist."])
        end
    end
end

local function RequestUndo()
    local info = WowSync:GetUndoInfo()
    if info then
        Dialogs:ConfirmUndo(info.Subject, DoUndo)
    end
end

-- Roll back the most recent `count` applies (a cascade from the undo list).
local function DoUndoSteps(count, entry)
    local results = WowSync:UndoSteps(count)
    if results then
        if count > 1 then
            WowSync:Print(L["Undid X changes."]:format(count))
        else
            WowSync:Print(L["Undid the last apply (X)."]:format(entry and entry.Subject or L["Unknown"]))
        end
        for name, result in pairs(results) do
            if result.applied then
                WowSync:Print(L["  X: restored"]:format(name))
            end
        end
    end
    ApplyUndoState()
end

-- Clicking an undo-history row rolls back every apply down to and including it.
local function RequestUndoSteps(count, entry)
    if not entry then return end

    if count and count > 1 then
        Dialogs:ConfirmUndoSteps(count, entry.Subject, function()
            DoUndoSteps(count, entry)
        end)
    else
        Dialogs:ConfirmUndo(entry.Subject, function()
            DoUndoSteps(1, entry)
        end)
    end
end

-- Right-click actions for a single snapshot. The list forwards the snapshot,
-- its display subject, and the row to anchor the menu to.
local function OpenSnapshotMenu(snapshot, subject, anchor)
    if not snapshot or not currentProfileName then return end
    local hash = snapshot.Hash

    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(subject)

        local applyMenu = rootDescription:CreateButton(L["Apply"])
        applyMenu:CreateButton(L["Merge"], function()
            RequestApply(snapshot, "merge")
        end)
        applyMenu:CreateButton(L["Exact"], function()
            RequestApply(snapshot, "exact")
        end)

        rootDescription:CreateDivider()

        if snapshot.Pinned then
            rootDescription:CreateButton(L["Unpin"], function()
                pm:UnpinSnapshot(currentProfileName, hash)
                snapshotList:Refresh()
            end)
        else
            rootDescription:CreateButton(L["Pin"], function()
                pm:PinSnapshot(currentProfileName, hash)
                snapshotList:Refresh()
            end)
        end

        rootDescription:CreateButton(L["Edit note…"], function()
            Dialogs:PromptEditNote(snapshot.Body or "", function(text)
                pm:SetSnapshotBody(currentProfileName, hash, text)
                snapshotList:Refresh()
            end)
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(L["Delete snapshot"], function()
            Dialogs:ConfirmDeleteSnapshot(subject, function()
                pm:DeleteSnapshot(currentProfileName, hash)
                -- Deleting the latest snapshot changes what the header shows, so
                -- refresh the whole panel rather than just the list.
                ProfileDetails:SetProfile(currentProfileName)
            end)
        end)
    end)
end

function ProfileDetails:Build(region)
    pm = WowSync:GetProfileManager()

    local root = CreateFrame("Frame", nil, region, "BackdropTemplate")
    root:SetAllPoints(region)
    root:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(unpack(UI.PanelBackdropColor))
    root:SetBackdropBorderColor(unpack(UI.PanelBorderColor))

    -- Empty state label
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetText(L["Select a profile"])

    -- Empty-state undo history (covers the panel; behind the content frame)
    local undoSlot = CreateFrame("Frame", nil, root)
    undoSlot:SetAllPoints(root)

    -- Detail content (hidden until a profile is selected)
    content = CreateFrame("Frame", nil, root)
    content:SetAllPoints()
    content:Hide()

    -- Header region
    local headerSlot = CreateFrame("Frame", nil, content)
    headerSlot:SetPoint("TOPLEFT", 10, -8)
    headerSlot:SetPoint("TOPRIGHT", -10, -8)
    headerSlot:SetHeight(38)
    header = ProfileHeader:Build(headerSlot)

    -- Separator
    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", headerSlot, "BOTTOMLEFT", -2, -6)
    separator:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(UI.SeparatorColor))

    -- Snapshot timeline region
    local listSlot = CreateFrame("Frame", nil, content)
    listSlot:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    listSlot:SetPoint("RIGHT", content, "RIGHT", -8, 0)
    listSlot:SetPoint("BOTTOM", content, "BOTTOM", 0, 60)
    snapshotList = SnapshotList:Build(listSlot, {
        -- Switching snapshots clears any stale apply status from the last one.
        onSelect = function()
            statusLabel:Hide()
        end,
        onContext = OpenSnapshotMenu,
    })

    -- Action bar region
    local actionSlot = CreateFrame("Frame", nil, content)
    actionSlot:SetPoint("BOTTOMLEFT", 10, 10)
    actionSlot:SetPoint("BOTTOMRIGHT", -10, 10)
    actionSlot:SetHeight(24)

    -- One-line apply status, shown just above the action bar
    statusLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("BOTTOMLEFT", actionSlot, "TOPLEFT", 2, 4)
    statusLabel:SetPoint("BOTTOMRIGHT", actionSlot, "TOPRIGHT", -2, 4)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetWordWrap(false)
    statusLabel:Hide()

    -- Composed children

    undoList = UndoList:Build(undoSlot, {
        onActivate = RequestUndoSteps,
    })

    actionBar = ActionBar:Build(actionSlot, {
        onApply = function() RequestApply(nil, "merge") end,
        onUndo = RequestUndo,
        onRename = function()
            if currentProfileName then
                Dialogs:PromptRename(currentProfileName, DoRename)
            end
        end,
        onDelete = function()
            if currentProfileName then
                Dialogs:ConfirmDelete(currentProfileName, DoDelete)
            end
        end,
    })

    -- Initialise the empty state (undo history or placeholder) so it is correct
    -- the moment the panel first appears, before any profile is selected.
    ApplyUndoState()

    return self
end

function ProfileDetails:SetProfile(profileName)
    currentProfileName = profileName

    if not profileName then
        content:Hide()
        emptyLabel:Show()
        ApplyUndoState()
        return
    end

    local profile = pm:GetProfile(profileName)
    if not profile then
        content:Hide()
        emptyLabel:Show()
        ApplyUndoState()
        return
    end

    -- The detail header reflects the profile's most recent snapshot.
    local latest = profile.Snapshots[#profile.Snapshots]

    emptyLabel:Hide()
    undoList:Hide()
    content:Show()
    statusLabel:Hide()

    header:SetProfile(profileName, latest)
    snapshotList:SetProfile(profileName)
    ApplyUndoState()
end

function ProfileDetails:OnRefresh(callback)
    onRefreshNeeded = callback
end
