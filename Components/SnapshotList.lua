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
local snapshotsByHash = {}   -- hash -> snapshot (current profile)
local currentProfile = nil   -- profile name, for diffing against the live setup
local selectedHash = nil
local expandedHash = nil     -- the one open row (accordion), independent of selection
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
local function BuildDetail(hash)
    local snapshot = snapshotsByHash[hash]
    local detail = { hasNote = false, note = nil, modules = {} }
    if not snapshot then return detail end

    if snapshot.Body and snapshot.Body ~= "" then
        detail.hasNote = true
        detail.note = snapshot.Body
    end

    local preview = pm:PreviewApply(currentProfile, hash)
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
            return selectedHash
        end,
        IsExpanded = function(hash)
            return hash == expandedHash
        end,
        GetDetail = function()
            return expandedDetail
        end,
        Select = function(hash)
            SnapshotList:Select(hash)
        end,
        OpenMenu = function(hash, anchor)
            local snapshot = snapshotsByHash[hash]
            if snapshot and onContext then
                onContext(snapshot, SnapshotRow:FormatSubject(snapshot.Timestamp), anchor)
            end
        end,
    }

    local view = CreateScrollBoxListLinearView()
    -- Variable extents: the one expanded row is taller by its detail panel.
    view:SetElementExtentCalculator(function(_, elementData)
        if elementData.snapshot.Hash == expandedHash then
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

-- Populate the timeline from a profile's history (newest first) and select the
-- latest snapshot. Any open detail panel is collapsed.
function SnapshotList:SetProfile(profileName)
    currentProfile = profileName
    wipe(entries)
    wipe(snapshotsByHash)

    local profile = profileName and pm:GetProfile(profileName)
    local list = profile and profile.Snapshots or {}
    local count = #list

    -- The history is stored oldest-first; walk it in reverse for newest-first.
    for i = count, 1, -1 do
        local snapshot = list[i]
        snapshotsByHash[snapshot.Hash] = snapshot
        tinsert(entries, {
            snapshot = snapshot,
            isLatest = (i == count),
            isOldest = (i == 1),
        })
    end

    selectedHash = count > 0 and list[count].Hash or nil
    expandedHash = nil
    expandedDetail = nil
    Rebuild()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

-- Select a row and toggle its inline detail panel. Re-clicking the open row
-- collapses it but keeps it selected.
function SnapshotList:Select(hash)
    selectedHash = hash

    if expandedHash == hash then
        expandedHash = nil
        expandedDetail = nil
    else
        expandedHash = hash
        expandedDetail = BuildDetail(hash)
    end

    Rebuild()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

-- Re-render the visible rows in place after a snapshot was mutated (pinned or
-- had its note edited) without disturbing the current selection or expansion.
function SnapshotList:Refresh()
    if expandedHash then
        expandedDetail = BuildDetail(expandedHash)
    end
    Rebuild()
end

function SnapshotList:GetSelected()
    return selectedHash and snapshotsByHash[selectedHash] or nil
end

function SnapshotList:Clear()
    wipe(entries)
    wipe(snapshotsByHash)
    currentProfile = nil
    selectedHash = nil
    expandedHash = nil
    expandedDetail = nil
    if scrollBox then
        scrollBox:SetDataProvider(CreateDataProvider())
    end
end
