local _, addon = ...

--[[
    SnapshotList object (right-panel timeline).

    Fills an injected region with a scrollable, newest-first timeline of a
    profile's snapshots (one SnapshotRow each). Owns the selection state and
    exposes it through a callback; never leaks its frames. Rows are pooled by
    the scroll box across profile selections.

    addon:GetObject("SnapshotList"):Build(region, {
        onSelect = function(snapshot or nil) end,
        onContext = function(snapshot, subject, anchor) end,  -- right-click menu
    })
        -> self {
            SetProfile(profileName),   -- (re)populate; selects the latest snapshot
            Refresh(),                 -- re-render in place, keeping selection/expansion
            GetSelected() -> snapshot or nil,
            Clear(),
        }

    Clicking a row selects it (drives Apply) and toggles an inline detail panel
    below it: the optional note plus a per-module change summary against the
    current setup. Expansion is an accordion -- at most one row is open, and the
    selection persists even when that row is collapsed again.
]]

local SnapshotList = addon:NewObject("SnapshotList")
local SnapshotRow = addon:GetObject("SnapshotRow")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Height of a collapsed snapshot row.
local SNAPSHOT_ROW_HEIGHT = 40

-- Vertical gap between snapshot rows.
local SNAPSHOT_ROW_PADDING = 2

-- Height of a single text line in an expanded row's detail panel.
local SNAPSHOT_DETAIL_LINE_HEIGHT = 15

-- Padding below the last line of an expanded row's detail panel.
local SNAPSHOT_DETAIL_BOTTOM_PAD = 8

local pm
local scrollBox
local entries = {}           -- ordered newest-first { snapshot, isLatest, isOldest }
local currentProfile = nil   -- profile name, for diffing against the live setup
local selected = nil         -- the selected snapshot (object identity, not its hash)
local expanded = nil         -- the one open row (accordion), independent of selection
local expandedDetail = nil   -- cached diff/note for the expanded row
local onSelectionChanged = nil
local onContext = nil        -- right-click handler (snapshot, subject, anchor)

-- The extra height an expanded row needs for its detail panel, derived purely
-- from the cached detail so the scroll box can size elements deterministically.
local function DetailExtent(detail)
    if not detail then return 0 end

    local height = UI.SnapshotDetail.TopPad
    if detail.hasNote then
        height = height + UI.SnapshotDetail.NoteHeight
    end
    -- The "Changes vs current setup:" header, then one line per changed module
    -- (or a single "matches" line when there is nothing to show).
    height = height + SNAPSHOT_DETAIL_LINE_HEIGHT
    height = height + math.max(1, #detail.modules) * SNAPSHOT_DETAIL_LINE_HEIGHT
    height = height + SNAPSHOT_DETAIL_BOTTOM_PAD
    return height
end

-- Diff the chosen snapshot against the live setup and distil it into a small,
-- render-ready table (note + changed-module counts).
local function BuildDetail(snapshot)
    local detail = { hasNote = false, note = nil, modules = {} }
    if not snapshot then return detail end

    if snapshot.Body and snapshot.Body ~= "" then
        detail.hasNote = true
        detail.note = snapshot.Body
    end

    local preview
    if snapshot.IsHead then
        preview = pm:PreviewApplyCurrentOf(snapshot.CharKey)
    else
        preview = pm:PreviewApply(currentProfile, WowSync:GetSnapshotSelector(snapshot))
    end
    if preview and preview.perModule then
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
                tinsert(detail.modules, {
                    name = name,
                    added = added,
                    changed = changed,
                    removed = removed,
                })
            end
        end
    end

    return detail
end

function SnapshotList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onSelect == nil or type(opts.onSelect) == "function", "Build: 'opts.onSelect' must be a function")
    C:Ensures(opts.onContext == nil or type(opts.onContext) == "function", "Build: 'opts.onContext' must be a function")

    onSelectionChanged = opts.onSelect
    onContext = opts.onContext
    pm = WowSync:GetProfileManager()

    scrollBox = CreateFrame("Frame", nil, region, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)

    local scrollBar = CreateFrame("EventFrame", nil, region, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local rowContext = {
        GetSelected = function()
            return selected
        end,
        IsExpanded = function(snapshot)
            return snapshot == expanded
        end,
        GetDetail = function()
            return expandedDetail
        end,
        Select = function(snapshot)
            SnapshotList:Select(snapshot)
        end,
        OpenMenu = function(snapshot, anchor)
            if snapshot and onContext then
                -- A collapsed head is a real saved snapshot, so head-ness lives
                -- on the entry, not the snapshot object; pass it through so the
                -- menu can still offer the head actions (e.g. "Save now").
                local isHead = false
                for _, entry in ipairs(entries) do
                    if entry.snapshot == snapshot then
                        isHead = entry.isHead or false
                        break
                    end
                end
                onContext(snapshot, SnapshotRow:FormatSubject(snapshot.Timestamp), anchor, isHead)
            end
        end,
    }

    local view = CreateScrollBoxListLinearView()
    -- Variable extents: the one expanded row is taller by its detail panel.
    view:SetElementExtentCalculator(function(_, elementData)
        if elementData.snapshot == expanded then
            return UI.SnapshotDetail.SubjectZone + DetailExtent(expandedDetail)
        end
        return SNAPSHOT_ROW_HEIGHT
    end)
    view:SetPadding(0, 0, 0, 0, SNAPSHOT_ROW_PADDING)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            SnapshotRow:Build(row, rowContext)
            row.initialized = true
        end
        SnapshotRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return self
end

-- Rebuild the data provider from the cached entries. Re-setting the provider is
-- what reruns the extent calculator and the row initializers, so it is also how
-- an expand/collapse relayout is triggered.
local function Rebuild()
    local dataProvider = CreateDataProvider()
    for _, entry in ipairs(entries) do
        dataProvider:Insert(entry)
    end
    scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

-- Newest-first ordering for saved history, with the persistent index as a
-- tiebreaker so snapshots captured in the same second stay deterministic.
local function HistoryNewerFirst(a, b)
    local at, bt = a.snapshot.Timestamp or 0, b.snapshot.Timestamp or 0
    if at ~= bt then
        return at > bt
    end
    return (a.snapshot.Index or 0) > (b.snapshot.Index or 0)
end

-- Re-partition the current entries so the head stays on top, pinned snapshots
-- float above the rest of the history, and everything else falls back to its
-- newest-first slot. Operates on the existing entry objects (preserving their
-- identity, so selection/expansion survive) and is what a pin/unpin toggle
-- calls to move a row between the pinned and unpinned groups. Sorting each
-- group by time means unpinning returns a snapshot to its original position.
local function Reorder()
    local headEntries = {}
    local pinnedEntries = {}
    local unpinnedEntries = {}
    for _, entry in ipairs(entries) do
        if entry.isHead then
            tinsert(headEntries, entry)
        elseif entry.snapshot.Pinned then
            tinsert(pinnedEntries, entry)
        else
            tinsert(unpinnedEntries, entry)
        end
    end

    table.sort(pinnedEntries, HistoryNewerFirst)
    table.sort(unpinnedEntries, HistoryNewerFirst)

    wipe(entries)
    for _, entry in ipairs(headEntries) do
        tinsert(entries, entry)
    end
    for _, entry in ipairs(pinnedEntries) do
        tinsert(entries, entry)
    end
    for _, entry in ipairs(unpinnedEntries) do
        tinsert(entries, entry)
    end
end

-- Build the derived "current head" pseudo-snapshot for a character, or nil when
-- nothing is captured. It carries Modules + Hash like a real snapshot but is
-- marked IsHead (so apply/preview route through the *CurrentOf core paths), has
-- no Index/Pinned/Body, and uses LastSeen as its timestamp.
local function HeadSnapshot(charKey)
    local head = pm:GetCurrentHead(charKey)
    if not head then
        return nil
    end
    return {
        IsHead = true,
        CharKey = charKey,
        IsOwn = head.IsCurrent,
        Hash = head.Hash,
        Timestamp = head.LastSeen,
        Modules = head.Modules,
        Source = { Character = charKey, ClassID = head.ClassID },
    }
end

-- Populate the timeline for a character: the current head always sits on top as
-- a live view of the character's present setup (live for the logged-in
-- character, last-captured for an alt), followed by the saved history (newest
-- first). Selects the head, or the latest saved snapshot when there is none.
function SnapshotList:SetProfile(profileName)
    currentProfile = profileName
    wipe(entries)

    local profile = profileName and pm:GetProfile(profileName)
    local list = profile and profile.Snapshots or {}
    local count = #list

    local head = profileName and HeadSnapshot(profileName)

    -- The head is always the top row: the character's current state, distinct
    -- from the saved history below it.
    if head then
        tinsert(entries, {
            snapshot = head,
            isHead = true,
        })
    end

    -- The history is stored oldest-first; walk it in reverse for newest-first.
    for i = count, 1, -1 do
        tinsert(entries, {
            snapshot = list[i],
        })
    end

    -- Float pinned snapshots above the rest of the history (but below the head).
    Reorder()

    -- Default selection: the head when present, else the latest saved snapshot.
    selected = head or list[count]
    expanded = nil
    expandedDetail = nil
    Rebuild()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

-- Select a row and toggle its inline detail panel. Re-clicking the open row
-- collapses it but keeps it selected.
function SnapshotList:Select(snapshot)
    selected = snapshot

    if expanded == snapshot then
        expanded = nil
        expandedDetail = nil
    else
        expanded = snapshot
        expandedDetail = BuildDetail(snapshot)
    end

    Rebuild()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

-- Re-render the visible rows in place after a snapshot was mutated (pinned or
-- had its note edited) without disturbing the current selection or expansion.
-- A pin/unpin changes the row's group, so the order is re-derived too.
function SnapshotList:Refresh()
    if expanded then
        expandedDetail = BuildDetail(expanded)
    end
    Reorder()
    Rebuild()
end

function SnapshotList:GetSelected()
    return selected
end

function SnapshotList:Clear()
    wipe(entries)
    currentProfile = nil
    selected = nil
    expanded = nil
    expandedDetail = nil
    if scrollBox then
        scrollBox:SetDataProvider(CreateDataProvider())
    end
end
