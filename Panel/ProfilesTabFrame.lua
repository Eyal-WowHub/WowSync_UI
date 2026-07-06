local _, addon = ...

--[[
    ProfilesTabFrame object (right panel).

    Orchestrates the detail view for a selected character. Composes ProfileHeader,
    SnapshotList, ActionBar and UndoList, and drives the WowSync actions
    (apply/save/undo) routed through the PopupDialogs object. Holds no
    widget-building code of its own beyond layout regions and the empty state.

    The timeline shows the character's current head on top followed by its saved
    history. Apply targets the selected entry (the head by default); Save freezes
    the head into a new snapshot.

    addon:GetObject("ProfilesTabFrame"):Build(region)
        -> profile-details frame {
            SetProfile(charKey or nil),
            RequestSave(),                -- saves the logged-in character only
            OnSaved(callback),            -- called after a successful save
        }
]]

local ProfilesTabFrame = addon:NewObject("ProfilesTabFrame")

local C = addon.C
local L = addon.L
local UI = addon.UI

local ActionBar = addon:GetObject("ActionBar")
local ApplyPreviewDialog = addon:GetObject("ApplyPreviewDialog")
local GameDiffPreview = addon:GetObject("GameDiffPreview")
local ModuleSelectionDialog = addon:GetObject("ModuleSelectionDialog")
local PopupDialogs = addon:GetObject("PopupDialogs")
local ProfileHeader = addon:GetObject("ProfileHeader")
local ShareDialog = addon:GetObject("ShareDialog")
local SnapshotList = addon:GetObject("SnapshotList")
local SnapshotRow = addon:GetObject("SnapshotRow")
local UndoList = addon:GetObject("UndoList")

local ChangeBadge = WowSync:Import("ChangeBadge")
local Console = WowSync:Import("Console")
local Debugger = WowSync:Import("Debugger")
local ExportManager = WowSync:Import("ExportManager")
local ProfileManager = WowSync:Import("ProfileManager")
local SnapshotManager = WowSync:Import("SnapshotManager")
local UndoManager = WowSync:Import("UndoManager")

-- Status text colours { r, g, b, a } for in-sync/saved and out-of-sync states.
local SUCCESS_TEXT_COLOR = { 0.3, 0.85, 0.3, 1 }
local WARNING_TEXT_COLOR = { 0.95, 0.75, 0.2, 1 }

local Methods = {}

-- Distil a preview's per-module diff into the panel's syncDetail: one entry per
-- module that has a pending change, sorted by name. syncDetail backs the
-- unsaved-changes badge tooltip, each as { name, added, changed, removed }.
local function CollectModuleChanges(panel, preview)
    wipe(panel._syncDetail)
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
            tinsert(panel._syncDetail, { name = name, added = added, changed = changed, removed = removed })
        end
    end
end

-- Refresh the live "unsaved changes" badge for the selected profile: compare the
-- logged-in character's Current against the profile's latest snapshot. Hidden
-- when no profile is shown or the profile has no snapshot to compare against.
local function RefreshSyncStatus(panel)
    if not panel._currentProfileName or not panel._content:IsVisible() then
        wipe(panel._syncDetail)
        if panel._syncHover then panel._syncHover:Hide() end
        panel._syncLabel:Hide()
        return
    end

    -- Diff against the already-captured Current (kept fresh by the watcher while
    -- the window is open) rather than re-scanning the live setup, so selecting a
    -- profile stays responsive.
    local latest = ProfileManager:Latest(panel._currentProfileName)
    local preview = latest and SnapshotManager:Preview(latest, nil, true)
    if not preview then
        wipe(panel._syncDetail)
        if panel._syncHover then panel._syncHover:Hide() end
        panel._syncLabel:Hide()
        return
    end

    local totals = preview.totals
    if totals.added + totals.changed + totals.removed == 0 then
        wipe(panel._syncDetail)
        if panel._syncHover then panel._syncHover:Hide() end
        panel._syncLabel:SetText(L["Up to date"])
        panel._syncLabel:SetTextColor(unpack(SUCCESS_TEXT_COLOR))
    else
        CollectModuleChanges(panel, preview)
        if panel._syncHover then panel._syncHover:Show() end
        panel._syncLabel:SetText(L["Unsaved changes"] .. "  "
            .. ChangeBadge.FormatDiffString(totals))
        panel._syncLabel:SetTextColor(unpack(WARNING_TEXT_COLOR))
    end
    panel._syncLabel:Show()
end

-- Coalesce bursts of live Current changes (the watcher flushes several modules
-- at once) into a single badge refresh.
local function ScheduleSyncRefresh(panel)
    panel._syncRefreshToken = panel._syncRefreshToken + 1
    local token = panel._syncRefreshToken
    C_Timer.After(0.1, function()
        if token == panel._syncRefreshToken then
            RefreshSyncStatus(panel)
            -- Keep the per-snapshot change tags in step with the live badge.
            if panel._snapshotList and panel._content:IsVisible() then
                panel._snapshotList:Refresh()
            end
        end
    end)
end

-- Save only ever freezes the logged-in character's live setup, so it is
-- offered only while viewing your own profile (and only with captured data).
local function IsViewingOwnProfile(panel)
    return panel._currentProfileName ~= nil
        and panel._currentProfileName == SnapshotManager:GetCurrentCharKey()
end

local function RefreshSaveState(panel)
    panel._actionBar:SetSaveEnabled(
        IsViewingOwnProfile(panel) and SnapshotManager:HasCapturedGameData())
end

-- Reflect the current undo point in whichever view is visible
local function ApplyUndoState(panel)
    local hasUndo = UndoManager:CanUndo()
    if panel._content:IsShown() then
        panel._actionBar:SetUndoEnabled(hasUndo)
        RefreshSaveState(panel)
    else
        -- Empty state: show the full undo history, or the placeholder when the
        -- stack is empty.
        local hasEntries = panel._undoList:Refresh()
        panel._emptyLabel:SetShown(not hasEntries)
    end
    RefreshSyncStatus(panel)
end

-- Show a one-line summary of the last apply inside the panel
local function SetApplyStatus(panel, applied, skipped)
    if skipped > 0 then
        panel._statusLabel:SetText(L["Applied X, skipped Y (see chat)"]:format(applied, skipped))
        panel._statusLabel:SetTextColor(unpack(WARNING_TEXT_COLOR))
    else
        panel._statusLabel:SetText(L["Applied X modules"]:format(applied))
        panel._statusLabel:SetTextColor(unpack(SUCCESS_TEXT_COLOR))
    end
    panel._statusLabel:Show()
end

-- Action handlers

local function DoUndo(panel)
    if SnapshotManager:IsCombatLocked() then
        Console:Print(L["You can't do that while in combat."])
        return
    end

    local undoPoint = UndoManager:GetNextUndoPoint()
    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "undo", Subject = undoPoint and undoPoint.Subject })
    end
    local undoResult = UndoManager:UndoLastApply()
    if undoResult then
        Console:Print(L["Undid the last apply (X)."]:format(undoPoint and undoPoint.Subject or L["Unknown"]))
        for _, name in ipairs(undoResult:Applied()) do
            Console:Print(L["  X: restored"]:format(name))
        end
    end
    ApplyUndoState(panel)
end

local function ApplySnapshot(panel, snapshot, moduleSet, mode, overrides)
    if not panel._currentProfileName or not snapshot then return end

    if SnapshotManager:IsCombatLocked() then
        Console:Print(L["You can't do that while in combat."])
        return
    end

    if not next(moduleSet) then
        Console:Print(L["No modules selected."])
        return
    end

    -- Apply only the chosen modules of the snapshot, each in its own mode (the
    -- preview's per-module overrides over the dialog's default). A head is just a
    -- Snapshot, so an own-head, an alt's head, and a stored snapshot all flow
    -- through the same Apply.
    local strategy = { default = mode or "exact", overrides = overrides }
    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "apply", Profile = panel._currentProfileName, Mode = strategy.default })
    end
    local applyResult = SnapshotManager:Apply(snapshot, strategy, moduleSet)
    if applyResult and applyResult:Any() then
        for _, name in ipairs(applyResult:Applied()) do
            local outcome = applyResult:Get(name)
            local message = L["X: applied"]:format(name)
            if outcome.warning then
                message = L["X (Y)"]:format(message, outcome.warning)
            end
            Console:Print(message)
        end
        for _, name in ipairs(applyResult:Skipped()) do
            Console:Print(L["X: skipped - Y"]:format(name, applyResult:Get(name).reason or L["unknown"]))
        end
        local applied, skipped = applyResult:Counts()
        SetApplyStatus(panel, applied, skipped)
    else
        Console:Print(L["Nothing to apply."])
    end

    ApplyUndoState(panel)
end

-- Apply is a no-op when the chosen entry already matches the logged-in
-- character's current setup (same content hash) -- its own head, or its latest
-- save when nothing has changed. It is meaningful for anything that would change
-- the live setup (an alt's head, an older save, a differing snapshot).
local function CanApplySnapshot(snapshot)
    if not snapshot then
        return false
    end
    -- Meaningful only when the snapshot differs from the logged-in character's
    -- live setup; its own head (and its latest save when nothing changed) already
    -- match. Nil head (nothing captured) never matches, so apply stays offered.
    local head = ProfileManager:GetLiveSnapshot()
    return not (head and snapshot:CompareTo(head))
end

-- Open the preview dialog for a snapshot (defaulting to the selected one) in the
-- given mode. Once the user picks a module subset, a final mode-aware prompt
-- spells out what will happen and gives one last chance to confirm or cancel.
local function RequestApply(panel, snapshot, mode)
    if not panel._currentProfileName then return end

    snapshot = snapshot or panel._snapshotList:GetSelected()
    if not snapshot then return end

    if not CanApplySnapshot(snapshot) then
        Console:Print(L["Already matches your current setup."])
        return
    end

    mode = mode or "exact"
    ApplyPreviewDialog:Show({
        profileName = panel._currentProfileName,
        snapshot = snapshot,
        mode = mode,
        onConfirm = function(moduleSet, overrides)
            PopupDialogs:ConfirmApply(mode, function()
                ApplySnapshot(panel, snapshot, moduleSet, mode, overrides)
            end)
        end,
    })
end

-- Open the diff viewer on what undoing the most recent apply would restore.
local function PreviewUndoChanges(undoPoint)
    local preview = UndoManager:PreviewUndo()
    if preview then
        GameDiffPreview:Show({
            title = undoPoint.Subject,
            preview = preview,
            mode = "exact",
        })
    end
end

local function RequestUndo(panel)
    local undoPoint = UndoManager:GetNextUndoPoint()
    if undoPoint then
        PopupDialogs:ConfirmUndo(undoPoint.Subject, function()
            DoUndo(panel)
        end, function()
            PreviewUndoChanges(undoPoint)
        end)
    end
end

-- Roll back the most recent `count` applies (a cascade from the undo list).
local function DoUndoSteps(panel, count, undoPoint)
    if SnapshotManager:IsCombatLocked() then
        Console:Print(L["You can't do that while in combat."])
        return
    end

    if Debugger:IsEnabled() then
        Debugger:RecordUI({ Action = "undo-steps", Count = count })
    end
    local undoResult = UndoManager:UndoApplies(count)
    if undoResult then
        if count > 1 then
            Console:Print(L["Undid X changes."]:format(count))
        else
            Console:Print(L["Undid the last apply (X)."]:format(undoPoint and undoPoint.Subject or L["Unknown"]))
        end
        for _, name in ipairs(undoResult:Applied()) do
            Console:Print(L["  X: restored"]:format(name))
        end
    end
    ApplyUndoState(panel)
end

-- Clicking an undo-history row rolls back every apply down to and including it.
local function RequestUndoSteps(panel, count, undoPoint)
    if not undoPoint then return end

    if count and count > 1 then
        PopupDialogs:ConfirmUndoSteps(count, undoPoint.Subject, function()
            DoUndoSteps(panel, count, undoPoint)
        end)
    else
        PopupDialogs:ConfirmUndo(undoPoint.Subject, function()
            DoUndoSteps(panel, 1, undoPoint)
        end, function()
            PreviewUndoChanges(undoPoint)
        end)
    end
end

-- Lets the player pick which modules (and an optional note) to share, encodes
-- that subset to a share string, and opens the copy dialog. The note defaults to
-- the snapshot's own note so a re-share keeps it unless the player edits it.
local function ShareSnapshot(panel, snapshot)
    local isHead = snapshot:IsLive()
    local subject, charKey, selector
    if isHead then
        subject = panel._currentProfileName .. " — " .. L["Current"]
        charKey = snapshot:GetCharacterInfo().Key
    else
        subject = panel._currentProfileName .. " — " .. SnapshotRow:FormatSubject(snapshot:GetTimestamp())
        selector = snapshot:GetSelector()
    end

    ModuleSelectionDialog:Show({
        title = L["Share snapshot"],
        confirmText = L["Share…"],
        moduleNames = snapshot:GetModuleNames(),
        note = snapshot:GetNotes(),
        onConfirm = function(moduleSet, note)
            -- The picker's note is authoritative for a share: pass an explicit
            -- empty string (not nil) so clearing the prefilled note actually
            -- drops it, instead of the export falling back to the saved note.
            local opts = { modules = moduleSet, notes = note or "" }
            local share, reason
            if isHead then
                share, reason = ExportManager:ExportLiveSnapshot(charKey, opts)
            else
                share, reason = ExportManager:ExportSavedSnapshot(panel._currentProfileName, selector, opts)
            end
            if share then
                ShareDialog:Show({ text = share, subject = subject })
            else
                Console:Print(reason or L["Couldn't export that snapshot."])
            end
        end,
    })
end

-- Open the diff preview for a snapshot, or report when there is no baseline to
-- compare against yet (own head before its first saved snapshot).
local function OpenPreview(snapshot, title)
    local preview = SnapshotManager:Preview(snapshot)
    if not preview then
        Console:Print(L["Nothing saved yet to compare against."])
        return
    end
    GameDiffPreview:Show({ title = title, preview = preview, mode = "exact" })
end

-- Right-click actions for a single snapshot. The list forwards the snapshot,
-- its display subject, the row to anchor the menu to, and whether the row is
-- the current head.
local function OpenSnapshotMenu(panel, snapshot, subject, anchor, isHead)
    if not snapshot or not panel._currentProfileName then return end

    -- The current head is a live view, not a stored snapshot: it can be applied
    -- (when it differs from the logged-in setup) and, on your own profile,
    -- frozen via "Save now". Saving is never offered while viewing an alt.
    if isHead then
        MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
            rootDescription:CreateTitle(L["Current"])

            if CanApplySnapshot(snapshot) then
                rootDescription:CreateButton(L["Apply"], function()
                    RequestApply(panel, snapshot, "exact")
                end)
            end

            rootDescription:CreateButton(L["Preview changes"], function()
                OpenPreview(snapshot, L["Current"])
            end)
            rootDescription:CreateDivider()

            if IsViewingOwnProfile(panel) then
                rootDescription:CreateButton(L["Save now"], function()
                    panel:RequestSave()
                end)
            end

            rootDescription:CreateButton(L["Share…"], function()
                ShareSnapshot(panel, snapshot)
            end)
        end)
        return
    end

    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        rootDescription:CreateTitle(subject)

        rootDescription:CreateButton(L["Apply"], function()
            RequestApply(panel, snapshot, "exact")
        end)

        rootDescription:CreateButton(L["Preview changes"], function()
            OpenPreview(snapshot, subject)
        end)

        rootDescription:CreateDivider()

        if snapshot:IsPinned() then
            rootDescription:CreateButton(L["Unpin"], function()
                ProfileManager:Unpin(snapshot)
                panel._snapshotList:Refresh()
            end)
        else
            rootDescription:CreateButton(L["Pin"], function()
                ProfileManager:Pin(snapshot)
                panel._snapshotList:Refresh()
            end)
        end

        rootDescription:CreateButton(L["Edit note…"], function()
            PopupDialogs:PromptEditNote(snapshot:GetNotes(), function(text)
                ProfileManager:SetNotes(snapshot, text)
                panel._snapshotList:Refresh()
            end)
        end)

        rootDescription:CreateButton(L["Share…"], function()
            ShareSnapshot(panel, snapshot)
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(L["Delete snapshot"], function()
            PopupDialogs:ConfirmDeleteSnapshot(subject, function()
                ProfileManager:Remove(snapshot)
                -- Deleting the latest snapshot changes what the header shows, so
                -- refresh the whole panel rather than just the list.
                panel:SetProfile(panel._currentProfileName)
            end)
        end)
    end)
end

function Methods:Constructor(config)
    local panel = self

    panel._currentProfileName = nil
    panel._onSaved = nil
    -- The changed modules backing the current unsaved-changes badge, each as
    -- { name, added, changed, removed }, in stable name order for the tooltip.
    panel._syncDetail = {}
    panel._syncRefreshToken = 0

    self:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    self:SetBackdropColor(unpack(UI.Backdrop.Panel))
    self:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))

    -- Empty state label
    local emptyLabel = self:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetText(L["Select a character"])
    self._emptyLabel = emptyLabel

    -- Empty-state undo history (covers the panel; behind the content frame)
    local undoSlot = CreateFrame("Frame", nil, self)
    undoSlot:SetAllPoints(self)

    -- Detail content (hidden until a profile is selected)
    local content = CreateFrame("Frame", nil, self)
    content:SetAllPoints()
    content:Hide()
    self._content = content

    -- Header region
    local headerSlot = CreateFrame("Frame", nil, content)
    headerSlot:SetPoint("TOPLEFT", 10, -8)
    headerSlot:SetPoint("TOPRIGHT", -10, -8)
    headerSlot:SetHeight(38)
    self._header = ProfileHeader:Build(headerSlot)

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
    self._snapshotList = SnapshotList:Build(listSlot, {
        -- Switching snapshots clears any stale apply status and re-gates the
        -- Apply button against the newly selected entry.
        onSelect = function(snapshot)
            panel._statusLabel:Hide()
            panel._actionBar:SetApplyEnabled(CanApplySnapshot(snapshot))
        end,
        onContext = function(snapshot, subject, anchor, isHead)
            OpenSnapshotMenu(panel, snapshot, subject, anchor, isHead)
        end,
    })

    -- Action bar region
    local actionSlot = CreateFrame("Frame", nil, content)
    actionSlot:SetPoint("BOTTOMLEFT", 10, 10)
    actionSlot:SetPoint("BOTTOMRIGHT", -10, 10)
    actionSlot:SetHeight(24)

    -- One-line apply status, shown just above the action bar
    local statusLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("BOTTOMLEFT", actionSlot, "TOPLEFT", 2, 4)
    statusLabel:SetPoint("BOTTOMRIGHT", actionSlot, "TOPRIGHT", -2, 4)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetWordWrap(false)
    statusLabel:Hide()
    self._statusLabel = statusLabel

    -- Live "unsaved changes" badge, top-right of the header. Refreshed on
    -- selection, after apply/undo, and live as the watcher mirrors changes.
    local syncLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncLabel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -12)
    syncLabel:SetJustifyH("RIGHT")
    syncLabel:SetWordWrap(false)
    syncLabel:Hide()
    self._syncLabel = syncLabel

    -- An invisible mouse-catcher over the badge: on hover it lists which modules
    -- the unsaved changes belong to, so the summary count is also explainable.
    local syncHover = CreateFrame("Frame", nil, content)
    syncHover:SetAllPoints(syncLabel)
    syncHover:EnableMouse(true)
    syncHover:SetScript("OnEnter", function(frame)
        if #panel._syncDetail == 0 then return end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Unsaved changes"])
        for _, change in ipairs(panel._syncDetail) do
            GameTooltip:AddLine(ChangeBadge.FormatDiffString(change, change.name))
        end
        GameTooltip:Show()
    end)
    syncHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncHover:Hide()
    self._syncHover = syncHover

    -- The core fires this whenever a module's live data updates (the watcher
    -- mirroring edits into Current); refresh the badge to match.
    WowSync:RegisterEvent("WOWSYNC_MODULE_DATA_UPDATED", function()
        ScheduleSyncRefresh(panel)
    end)

    -- While the panel is hidden the badge ignores live changes (see
    -- RefreshSyncStatus); recompute when it becomes visible again, which covers
    -- reopening the window and switching back to the Profiles tab.
    content:HookScript("OnShow", function()
        RefreshSyncStatus(panel)
    end)

    -- Composed children

    self._undoList = UndoList:Build(undoSlot, {
        onActivate = function(count, undoPoint)
            RequestUndoSteps(panel, count, undoPoint)
        end,
    })

    self._actionBar = ActionBar:Build(actionSlot, {
        onApply = function() RequestApply(panel, nil, "exact") end,
        onUndo = function() RequestUndo(panel) end,
        onSave = function() panel:RequestSave() end,
    })

    -- Save only targets the logged-in character, so it stays disabled unless
    -- you are viewing your own profile and have captured data. Track the
    -- capture state live; SetProfile drives the viewed-profile half.
    RefreshSaveState(self)
    WowSync:RegisterEvent("WOWSYNC_MODULE_DATA_UPDATED", function()
        RefreshSaveState(panel)
    end)

    -- Animate the Save button for the duration of any save (including the
    -- command line), then show a brief confirmation.
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_SAVE_STARTED", function()
        panel._actionBar:BeginSaving()
    end)
    WowSync:RegisterEvent("WOWSYNC_SNAPSHOT_SAVE_FINISHED", function(_, _, storedSnapshot)
        panel._actionBar:EndSaving(storedSnapshot)
    end)

    -- Initialise the empty state (undo history or placeholder) so it is correct
    -- the moment the panel first appears, before any profile is selected.
    ApplyUndoState(self)
end

function ProfilesTabFrame:Build(region)
    C:IsTable(region, 2)
    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
    }, {
        frameType = "Frame",
        template = "BackdropTemplate",
        methods = Methods,
    })
end

function Methods:SetProfile(profileName)
    self._currentProfileName = profileName

    if not profileName then
        self._content:Hide()
        self._emptyLabel:Show()
        ApplyUndoState(self)
        return
    end

    local headHandle = ProfileManager:GetLiveSnapshot(profileName)
    local latestHandle = ProfileManager:Latest(profileName)

    -- A listed character always has a head and/or saved history; guard anyway.
    if not headHandle and not latestHandle then
        self._content:Hide()
        self._emptyLabel:Show()
        ApplyUndoState(self)
        return
    end

    self._emptyLabel:Hide()
    self._undoList:Hide()
    self._content:Show()
    self._statusLabel:Hide()

    -- The header headlines the character's CURRENT setup (its head); fall back
    -- to the latest saved snapshot for a character with history but no capture.
    self._header:SetProfile(profileName, headHandle or latestHandle)

    self._snapshotList:SetProfile(profileName)

    ApplyUndoState(self)
end

-- Freeze the logged-in character's live setup into a new saved snapshot. Save
-- is offered only for your own character, so every registered module is
-- selectable. On success the head collapses into the new latest snapshot and
-- onSaved fires so the list can refresh and re-select the character.
function Methods:RequestSave()
    local charKey = SnapshotManager:GetCurrentCharKey()

    local headHandle = ProfileManager:GetLiveSnapshot(charKey)
    if not headHandle then
        Console:Print(L["That character has nothing captured yet."])
        return
    end

    ModuleSelectionDialog:Show({
        title = L["Save snapshot"],
        confirmText = L["Save"],
        onConfirm = function(moduleSet, note)
            local evicted = ProfileManager:PendingEviction(charKey)

            local function commit()
                local function OnSaveComplete(snapshot, reason)
                    if snapshot then
                        Console:Print(L["Snapshot saved."])
                        if evicted then
                            Console:Print(L["Reached the snapshot limit — removed the oldest (X)."]:format(
                                SnapshotRow:FormatSubject(evicted:GetTimestamp())))
                        end
                        self:SetProfile(charKey)
                        if self._onSaved then
                            self._onSaved(charKey)
                        end
                    elseif reason == "unknown-character" then
                        Console:Print(L["Could not save from that character."])
                    elseif reason == "busy" then
                        Console:Print(L["A save is already in progress."])
                    elseif reason == "combat" then
                        Console:Print(L["You can't do that while in combat."])
                    else
                        Console:Print(L["Could not save. Try again."])
                    end
                end

                if Debugger:IsEnabled() then
                    Debugger:RecordUI({ Action = "save", CharKey = charKey, Note = note })
                end
                SnapshotManager:SaveCurrentSnapshot(note, moduleSet, OnSaveComplete)
            end

            if evicted then
                PopupDialogs:ConfirmSaveAtLimit(SnapshotManager:GetSnapshotLimit(),
                    SnapshotRow:FormatSubject(evicted:GetTimestamp()), commit)
            else
                commit()
            end
        end,
    })
end

-- Exports the selected snapshot to a copy dialog, or asks for a selection first.
function Methods:ShareSelected()
    local snapshot = self._snapshotList:GetSelected()
    if not snapshot then
        Console:Print(L["Select a snapshot to share first."])
        return
    end
    ShareSnapshot(self, snapshot)
end

function Methods:OnSaved(callback)
    self._onSaved = callback
end
