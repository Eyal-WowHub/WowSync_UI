local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    ProfileDetails object (right panel).

    Orchestrates the detail view for a selected profile. Composes ProfileHeader,
    SnapshotList, ActionBar and UndoBanner, and drives the WowSync actions
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
local UndoBanner = addon:GetObject("UndoBanner")
local ActionBar = addon:GetObject("ActionBar")

local pm
local currentProfileName = nil
local onRefreshNeeded = nil

local content, emptyLabel, statusLabel
local header, actionBar, banner, snapshotList

-- Reflect the current undo point in whichever view is visible
local function ApplyUndoState()
    local hasUndo = WowSync:HasUndo()
    if content:IsShown() then
        actionBar:SetUndoEnabled(hasUndo)
    else
        banner:SetState(hasUndo, hasUndo and WowSync:GetUndoInfo() or nil)
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

local function DoApply()
    if not currentProfileName then return end

    local snapshot = snapshotList:GetSelected()
    if not snapshot then return end

    -- Apply the snapshot selected in the timeline (all of its modules).
    local results = pm:Apply(currentProfileName, snapshot.Hash, nil, nil)
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

    -- Empty-state undo banner (covers the panel; behind the content frame)
    local bannerSlot = CreateFrame("Frame", nil, root)
    bannerSlot:SetAllPoints(root)

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

    banner = UndoBanner:Build(bannerSlot, {
        onUndo = RequestUndo,
    })

    actionBar = ActionBar:Build(actionSlot, {
        onApply = DoApply,
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
    banner:SetState(false)
    content:Show()
    statusLabel:Hide()

    header:SetProfile(profileName, latest)
    snapshotList:SetProfile(profileName)
    ApplyUndoState()
end

function ProfileDetails:OnRefresh(callback)
    onRefreshNeeded = callback
end
