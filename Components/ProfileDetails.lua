local _, addon = ...

--[[
    ProfileDetails object (right panel).

    Orchestrates the detail view for a selected character. Composes ProfileHeader,
    SnapshotList, ActionBar and UndoList, and drives the WowSync actions
    (apply/save/undo/delete) routed through the PopupDialogs object. Holds no
    widget-building code of its own beyond layout regions and the empty state.

    The timeline shows the character's current head on top followed by its saved
    history. Apply targets the selected entry (the head by default); Save freezes
    the head into a new snapshot.

    addon:GetObject("ProfileDetails"):Build(region)
        -> self {
            SetProfile(charKey or nil),
            RequestSave(charKey or nil),  -- nil = logged-in character
            OnSaved(callback),            -- called after a successful save
            OnRefresh(callback),          -- called after delete
        }
]]

local ProfileDetails = addon:NewObject("ProfileDetails")
local PopupDialogs = addon:GetObject("PopupDialogs")
local ProfileHeader = addon:GetObject("ProfileHeader")
local SnapshotList = addon:GetObject("SnapshotList")
local SnapshotRow = addon:GetObject("SnapshotRow")
local UndoList = addon:GetObject("UndoList")
local ActionBar = addon:GetObject("ActionBar")
local ApplyPreviewDialog = addon:GetObject("ApplyPreviewDialog")
local GameDiffPreview = addon:GetObject("GameDiffPreview")
local SaveDialog = addon:GetObject("SaveDialog")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ProfileManager = WowSync:GetProfileManager()
local SnapshotManager = WowSync:GetSnapshotManager()
local SnapshotView = WowSync:GetSnapshotView()
local SnapshotHandleCache = WowSync:GetSnapshotHandleCache()
local Debugger = WowSync:GetDebugger()

-- Status text colours { r, g, b, a } for in-sync/saved and out-of-sync states.
local SUCCESS_TEXT_COLOR = { 0.3, 0.85, 0.3, 1 }
local WARNING_TEXT_COLOR = { 0.95, 0.75, 0.2, 1 }

local currentProfileName = nil
local onRefreshNeeded = nil
local onSaved = nil

local content, emptyLabel, statusLabel, syncLabel, syncHover
local header, actionBar, undoList, snapshotList

-- The changed modules backing the current unsaved-changes badge, each as
-- { name, added, changed, removed }, in stable name order for the badge tooltip.
local syncDetail = {}

-- Distil a preview's per-module diff into syncDetail: one entry per module that
-- has a pending change, sorted by name.
local function CollectModuleChanges(preview)
    wipe(syncDetail)
    if not (preview and preview.perModule) then return end

    local names = {}
    for name in pairs(preview.perModule) do
        tinsert(names, name)
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local moduleDiff = preview.perModule[name]
        local added = #(moduleDiff.added or {})
        local changed = #(moduleDiff.changed or {})
        local removed = #(moduleDiff.removed or {})
        if added + changed + removed > 0 then
            tinsert(syncDetail, { name = name, added = added, changed = changed, removed = removed })
        end
    end
end

-- Refresh the live "unsaved changes" badge for the selected profile: compare the
-- logged-in character's Current against the profile's latest snapshot. Hidden
-- when no profile is shown or the profile has no snapshot to compare against.
local function RefreshSyncStatus()
    if not currentProfileName or not content:IsVisible() then
        wipe(syncDetail)
        if syncHover then syncHover:Hide() end
        syncLabel:Hide()
        return
    end

    local preview = SnapshotManager:PreviewApplySnapshot(currentProfileName)
    if not preview then
        wipe(syncDetail)
        if syncHover then syncHover:Hide() end
        syncLabel:Hide()
        return
    end

    local totals = preview.totals
    if totals.added + totals.changed + totals.removed == 0 then
        wipe(syncDetail)
        if syncHover then syncHover:Hide() end
        syncLabel:SetText(L["Up to date"])
        syncLabel:SetTextColor(unpack(SUCCESS_TEXT_COLOR))
    else
        CollectModuleChanges(preview)
        if syncHover then syncHover:Show() end
        syncLabel:SetText(L["Unsaved changes"] .. "  "
            .. L["+A ~C -R"]:format(totals.added, totals.changed, totals.removed))
        syncLabel:SetTextColor(unpack(WARNING_TEXT_COLOR))
    end
    syncLabel:Show()
end

-- Coalesce bursts of live Current changes (the watcher flushes several modules
-- at once) into a single badge refresh.
local syncRefreshToken = 0
local function ScheduleSyncRefresh()
    syncRefreshToken = syncRefreshToken + 1
    local token = syncRefreshToken
    C_Timer.After(0.1, function()
        if token == syncRefreshToken then
            RefreshSyncStatus()
        end
    end)
end

-- Reflect the current undo point in whichever view is visible
local function ApplyUndoState()
    local hasUndo = SnapshotManager:CanUndo()
    if content:IsShown() then
        actionBar:SetUndoEnabled(hasUndo)
    else
        -- Empty state: show the full undo history, or the placeholder when the
        -- stack is empty.
        local hasEntries = undoList:Refresh()
        emptyLabel:SetShown(not hasEntries)
    end
    RefreshSyncStatus()
end

-- Show a one-line summary of the last apply inside the panel
local function SetApplyStatus(applied, skipped)
    if skipped > 0 then
        statusLabel:SetText(L["Applied X, skipped Y (see chat)"]:format(applied, skipped))
        statusLabel:SetTextColor(unpack(WARNING_TEXT_COLOR))
    else
        statusLabel:SetText(L["Applied X modules"]:format(applied))
        statusLabel:SetTextColor(unpack(SUCCESS_TEXT_COLOR))
    end
    statusLabel:Show()
end

-- Action handlers

local function DoUndo()
    if SnapshotManager:IsCombatLocked() then
        WowSync:Print(L["You can't do that while in combat."])
        return
    end

    local undoPoint = SnapshotManager:GetNextUndoPoint()
    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "undo", Subject = undoPoint and undoPoint.Subject })
    end
    local undoResult = SnapshotManager:UndoLastApply()
    if undoResult then
        WowSync:Print(L["Undid the last apply (X)."]:format(undoPoint and undoPoint.Subject or L["Unknown"]))
        for _, name in ipairs(undoResult:Applied()) do
            WowSync:Print(L["  X: restored"]:format(name))
        end
    end
    ApplyUndoState()
end

local function ApplySnapshot(snapshot, moduleSet, mode, overrides)
    if not currentProfileName or not snapshot then return end

    if SnapshotManager:IsCombatLocked() then
        WowSync:Print(L["You can't do that while in combat."])
        return
    end

    if not next(moduleSet) then
        WowSync:Print(L["No modules selected."])
        return
    end

    -- Apply only the chosen modules of the snapshot, each in its own mode (the
    -- preview's per-module overrides over the dialog's default). The current head
    -- is not a stored snapshot, so it routes through ApplyHeadByCharKey.
    local strategy = { default = mode or "exact", overrides = overrides }
    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "apply", Profile = currentProfileName, Mode = strategy.default })
    end
    local applyResult = SnapshotView:Apply(snapshot, strategy, moduleSet)
    if applyResult and applyResult:Any() then
        for _, name in ipairs(applyResult:Applied()) do
            local outcome = applyResult:Get(name)
            local message = L["X: applied"]:format(name)
            if outcome.warning then
                message = L["X (Y)"]:format(message, outcome.warning)
            end
            WowSync:Print(message)
        end
        for _, name in ipairs(applyResult:Skipped()) do
            WowSync:Print(L["X: skipped - Y"]:format(name, applyResult:Get(name).reason or L["unknown"]))
        end
        local applied, skipped = applyResult:Counts()
        SetApplyStatus(applied, skipped)
    else
        WowSync:Print(L["Nothing to apply."])
    end

    ApplyUndoState()
end

-- Apply is a no-op when the chosen entry already matches the logged-in
-- character's current setup (same content hash) -- its own head, or its latest
-- save when nothing has changed. It is meaningful for anything that would change
-- the live setup (an alt's head, an older save, a differing snapshot).
local function CanApplySnapshot(snapshot)
    if not snapshot then
        return false
    end
    return not SnapshotView:IsCurrent(snapshot)
end

-- Open the preview dialog for a snapshot (defaulting to the selected one) in the
-- given mode. Once the user picks a module subset, a final mode-aware prompt
-- spells out what will happen and gives one last chance to confirm or cancel.
local function RequestApply(snapshot, mode)
    if not currentProfileName then return end

    snapshot = snapshot or snapshotList:GetSelected()
    if not snapshot then return end

    if not CanApplySnapshot(snapshot) then
        WowSync:Print(L["Already matches your current setup."])
        return
    end

    mode = mode or "exact"
    ApplyPreviewDialog:Show({
        profileName = currentProfileName,
        snapshot = snapshot,
        mode = mode,
        onConfirm = function(moduleSet, overrides)
            PopupDialogs:ConfirmApply(mode, function()
                ApplySnapshot(snapshot, moduleSet, mode, overrides)
            end)
        end,
    })
end

local function DoDelete()
    if currentProfileName then
        ProfileManager:DeleteProfile(currentProfileName)
        currentProfileName = nil
        if onRefreshNeeded then
            onRefreshNeeded()
        end
    end
end

-- Open the diff viewer on what undoing the most recent apply would restore.
local function PreviewUndoChanges(undoPoint)
    local preview = SnapshotManager:PreviewUndo()
    if preview then
        GameDiffPreview:Show({
            title = undoPoint.Subject,
            preview = preview,
            mode = "exact",
        })
    end
end

local function RequestUndo()
    local undoPoint = SnapshotManager:GetNextUndoPoint()
    if undoPoint then
        PopupDialogs:ConfirmUndo(undoPoint.Subject, DoUndo, function()
            PreviewUndoChanges(undoPoint)
        end)
    end
end

-- Roll back the most recent `count` applies (a cascade from the undo list).
local function DoUndoSteps(count, undoPoint)
    if SnapshotManager:IsCombatLocked() then
        WowSync:Print(L["You can't do that while in combat."])
        return
    end

    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "undo-steps", Count = count })
    end
    local undoResult = SnapshotManager:UndoApplies(count)
    if undoResult then
        if count > 1 then
            WowSync:Print(L["Undid X changes."]:format(count))
        else
            WowSync:Print(L["Undid the last apply (X)."]:format(undoPoint and undoPoint.Subject or L["Unknown"]))
        end
        for _, name in ipairs(undoResult:Applied()) do
            WowSync:Print(L["  X: restored"]:format(name))
        end
    end
    ApplyUndoState()
end

-- Clicking an undo-history row rolls back every apply down to and including it.
local function RequestUndoSteps(count, undoPoint)
    if not undoPoint then return end

    if count and count > 1 then
        PopupDialogs:ConfirmUndoSteps(count, undoPoint.Subject, function()
            DoUndoSteps(count, undoPoint)
        end)
    else
        PopupDialogs:ConfirmUndo(undoPoint.Subject, function()
            DoUndoSteps(1, undoPoint)
        end, function()
            PreviewUndoChanges(undoPoint)
        end)
    end
end

-- Right-click actions for a single snapshot. The list forwards the snapshot,
-- its display subject, the row to anchor the menu to, and whether the row is
-- the current head.
local function OpenSnapshotMenu(snapshot, subject, anchor, isHead)
    if not snapshot or not currentProfileName then return end

    -- The current head is a live view, not a stored snapshot: it can be applied
    -- (when it differs from the logged-in setup) and frozen via "Save now".
    if isHead then
        MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
            rootDescription:CreateTitle(L["Current"])

            if CanApplySnapshot(snapshot) then
                rootDescription:CreateButton(L["Apply"], function()
                    RequestApply(snapshot, "exact")
                end)
            end

            rootDescription:CreateButton(L["Preview changes"], function()
                GameDiffPreview:Show({
                    title = L["Current"],
                    preview = SnapshotView:Preview(snapshot),
                    mode = "exact",
                })
            end)
            rootDescription:CreateDivider()

            rootDescription:CreateButton(L["Save now"], function()
                ProfileDetails:RequestSave(SnapshotView:GetCharacterInfo(snapshot).Key)
            end)
        end)
        return
    end

    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(subject)

        rootDescription:CreateButton(L["Apply"], function()
            RequestApply(snapshot, "exact")
        end)

        rootDescription:CreateButton(L["Preview changes"], function()
            GameDiffPreview:Show({
                title = subject,
                preview = SnapshotView:Preview(snapshot),
                mode = "exact",
            })
        end)

        rootDescription:CreateDivider()

        if SnapshotView:IsPinned(snapshot) then
            rootDescription:CreateButton(L["Unpin"], function()
                SnapshotView:Unpin(snapshot)
                snapshotList:Refresh()
            end)
        else
            rootDescription:CreateButton(L["Pin"], function()
                SnapshotView:Pin(snapshot)
                snapshotList:Refresh()
            end)
        end

        rootDescription:CreateButton(L["Edit note…"], function()
            PopupDialogs:PromptEditNote(SnapshotView:GetNotes(snapshot), function(text)
                SnapshotView:SetNotes(snapshot, text)
                snapshotList:Refresh()
            end)
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(L["Delete snapshot"], function()
            PopupDialogs:ConfirmDeleteSnapshot(subject, function()
                SnapshotView:Delete(snapshot)
                -- Deleting the latest snapshot changes what the header shows, so
                -- refresh the whole panel rather than just the list.
                ProfileDetails:SetProfile(currentProfileName)
            end)
        end)
    end)
end

function ProfileDetails:Build(region)
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

    -- Empty state label
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetText(L["Select a character"])

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
    separator:SetColorTexture(unpack(UI.Backdrop.Separator))

    -- Snapshot timeline region
    local listSlot = CreateFrame("Frame", nil, content)
    listSlot:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    listSlot:SetPoint("RIGHT", content, "RIGHT", -8, 0)
    listSlot:SetPoint("BOTTOM", content, "BOTTOM", 0, 60)
    snapshotList = SnapshotList:Build(listSlot, {
        -- Switching snapshots clears any stale apply status and re-gates the
        -- Apply button against the newly selected entry.
        onSelect = function(snapshot)
            statusLabel:Hide()
            actionBar:SetApplyEnabled(CanApplySnapshot(snapshot))
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

    -- Live "unsaved changes" badge, top-right of the header. Refreshed on
    -- selection, after apply/undo, and live as the watcher mirrors changes.
    syncLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncLabel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -12)
    syncLabel:SetJustifyH("RIGHT")
    syncLabel:SetWordWrap(false)
    syncLabel:Hide()

    -- An invisible mouse-catcher over the badge: on hover it lists which modules
    -- the unsaved changes belong to, so the summary count is also explainable.
    syncHover = CreateFrame("Frame", nil, content)
    syncHover:SetAllPoints(syncLabel)
    syncHover:EnableMouse(true)
    syncHover:SetScript("OnEnter", function(self)
        if #syncDetail == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Unsaved changes"])
        for _, change in ipairs(syncDetail) do
            GameTooltip:AddLine(L["X: +A ~C -R"]:format(
                change.name, change.added, change.changed, change.removed))
        end
        GameTooltip:Show()
    end)
    syncHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncHover:Hide()

    -- The core fires this whenever a character's live setup changes (the watcher
    -- mirroring edits into Current); refresh the badge to match.
    WowSync:RegisterEvent("WOWSYNC_CURRENT_CHANGED", ScheduleSyncRefresh)

    -- While the panel is hidden the badge ignores live changes (see
    -- RefreshSyncStatus); recompute when it becomes visible again, which covers
    -- reopening the window and switching back to the Profiles tab.
    content:HookScript("OnShow", RefreshSyncStatus)

    -- Composed children

    undoList = UndoList:Build(undoSlot, {
        onActivate = RequestUndoSteps,
    })

    actionBar = ActionBar:Build(actionSlot, {
        onApply = function() RequestApply(nil, "exact") end,
        onUndo = RequestUndo,
        onDelete = function()
            if currentProfileName then
                local latestSnapshot = SnapshotHandleCache:GetLatestSaved(currentProfileName)
                local label = (latestSnapshot and SnapshotView:GetCharacterInfo(latestSnapshot).Character) or currentProfileName
                PopupDialogs:ConfirmDelete(label, DoDelete)
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

    local headHandle = SnapshotHandleCache:GetHead(profileName)
    local latestHandle = SnapshotHandleCache:GetLatestSaved(profileName)

    -- A listed character always has a head and/or saved history; guard anyway.
    if not headHandle and not latestHandle then
        content:Hide()
        emptyLabel:Show()
        ApplyUndoState()
        return
    end

    emptyLabel:Hide()
    undoList:Hide()
    content:Show()
    statusLabel:Hide()

    -- The header headlines the character's CURRENT setup (its head); fall back
    -- to the latest saved snapshot for a character with history but no capture.
    header:SetProfile(profileName, headHandle or latestHandle)

    snapshotList:SetProfile(profileName)

    -- Delete removes the saved history, so it only applies when some exists.
    actionBar:SetDeleteEnabled(latestHandle ~= nil)

    ApplyUndoState()
end

-- Freeze a character's current setup into a new saved snapshot. The logged-in
-- character saves its live Current (every registered module is selectable); an
-- alt saves its last-captured Current (limited to the modules it captured). On
-- success the head collapses into the new latest snapshot and onSaved fires so
-- the list can refresh and re-select the character.
function ProfileDetails:RequestSave(charKey)
    charKey = charKey or SnapshotManager:GetCurrentCharKey()

    local headHandle = SnapshotHandleCache:GetHead(charKey)
    if not headHandle then
        WowSync:Print(L["That character has nothing captured yet."])
        return
    end

    local isOwn = SnapshotView:IsOwnCharacter(headHandle)

    local moduleNames
    if not isOwn then
        moduleNames = SnapshotView:GetModuleNames(headHandle)
    end

    SaveDialog:Show({
        moduleNames = moduleNames,
        onConfirm = function(moduleSet, note)
            local evicted = SnapshotHandleCache:GetPendingEviction(charKey)

            local function commit()
                local function OnSaveComplete(snapshot, reason)
                    if snapshot then
                        WowSync:Print(L["Snapshot saved."])
                        if evicted then
                            WowSync:Print(L["Reached the snapshot limit — removed the oldest (X)."]:format(
                                SnapshotRow:FormatSubject(SnapshotView:GetTimestamp(evicted))))
                        end
                        ProfileDetails:SetProfile(charKey)
                        if onSaved then
                            onSaved(charKey)
                        end
                    elseif reason == "unknown-character" then
                        WowSync:Print(L["Could not save from that character."])
                    elseif reason == "busy" then
                        WowSync:Print(L["A save is already in progress."])
                    elseif reason == "combat" then
                        WowSync:Print(L["You can't do that while in combat."])
                    else
                        WowSync:Print(L["Could not save. Try again."])
                    end
                end

                if Debugger:IsEnabled() then
                    Debugger:RecordUI({ Action = "save", CharKey = charKey, Note = note })
                end
                if isOwn then
                    SnapshotManager:SaveCurrentSnapshot(note, moduleSet, OnSaveComplete)
                else
                    SnapshotManager:SaveSnapshotByCharKey(charKey, moduleSet, note, OnSaveComplete)
                end
            end

            if evicted then
                PopupDialogs:ConfirmSaveAtLimit(SnapshotManager:GetSnapshotLimit(),
                    SnapshotRow:FormatSubject(SnapshotView:GetTimestamp(evicted)), commit)
            else
                commit()
            end
        end,
    })
end

function ProfileDetails:OnSaved(callback)
    onSaved = callback
end

function ProfileDetails:OnRefresh(callback)
    onRefreshNeeded = callback
end
