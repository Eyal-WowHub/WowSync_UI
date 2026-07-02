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
        -> snapshot-list frame {
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
local ScrollList = addon:GetObject("ScrollList")
local ExpandableContent = addon:GetObject("ExpandableContent")

local C = LibStub("Contracts-1.0")
local SnapshotDetailBuilder = addon.SnapshotDetailBuilder

-- Height of a collapsed snapshot row.
local SNAPSHOT_ROW_HEIGHT = 40

-- Vertical gap between snapshot rows.
local SNAPSHOT_ROW_PADDING = 2

-- Padding above and below an expanded row's content stack, matching the row's
-- content anchor (inset from the top, lifted off the bottom).
local CONTENT_TOP_PAD = 6
local CONTENT_BOTTOM_PAD = 8

-- Right margin of the row content, matching the row's content anchor; paired
-- with the row's content inset to derive the wrap width for measuring.
local RIGHT_MARGIN = 8

local SnapshotView = WowSync:GetSnapshotView()
local SnapshotHandleCache = WowSync:GetSnapshotHandleCache()

local Methods = {}

-- Diff the chosen snapshot against the live setup and distil it into a small,
-- render-ready table (note + changed-module counts).
local function BuildDetail(snapshot)
    if not snapshot then
        return SnapshotDetailBuilder.Build(nil, nil)
    end

    return SnapshotDetailBuilder.Build(
        SnapshotView:GetNotes(snapshot),
        SnapshotView:Preview(snapshot)
    )
end

function Methods:Constructor(config)
    local panel = self

    panel._entries = {}            -- ordered display rows { snapshot = <handle>, isHead = bool }
    panel._currentProfile = nil    -- profile name, for diffing against the live setup
    panel._selected = nil          -- the selected snapshot handle (identity, not its hash)
    panel._expanded = nil          -- the one open row (accordion), independent of selection
    panel._expandedDetail = nil    -- cached diff/note for the expanded row
    panel._changeFlags = {}        -- snapshot -> has-changes-vs-live flag (memoised)
    panel._onSelectionChanged = config.onSelect
    panel._onContext = config.onContext   -- right-click handler (snapshot, subject, anchor)

    local rowContext = {
        GetSelected = function()
            return panel._selected
        end,
        IsExpanded = function(snapshot)
            return snapshot == panel._expanded
        end,
        GetDetail = function()
            return panel._expandedDetail
        end,
        HasChanges = function(snapshot)
            return panel:HasChanges(snapshot)
        end,
        Select = function(snapshot)
            panel:Select(snapshot)
        end,
        OpenMenu = function(snapshot, anchor)
            if snapshot and panel._onContext then
                panel._onContext(snapshot, SnapshotRow:FormatSubject(SnapshotView:GetTimestamp(snapshot)), anchor, SnapshotView:IsHead(snapshot))
            end
        end,
    }

    panel._scrollBox = ScrollList:Build({
        parent = self,
        anchor = function(sb)
            sb:SetPoint("TOPLEFT", 0, 0)
            sb:SetPoint("BOTTOMRIGHT", -16, 0)
        end,
        -- Variable extents: collapsed rows are uniform; the one expanded row is
        -- sized to the content it renders, measured from the same line list.
        extent = function(_, elementData)
            if elementData.snapshot ~= panel._expanded then
                return SNAPSHOT_ROW_HEIGHT
            end
            local width = panel._scrollBox:GetWidth() - SnapshotRow.ContentInset - RIGHT_MARGIN
            local lines = SnapshotRow:BuildLines(elementData.snapshot, elementData.isHead, true, panel._expandedDetail)
            return CONTENT_TOP_PAD + ExpandableContent:Measure(lines, width) + CONTENT_BOTTOM_PAD
        end,
        padding = SNAPSHOT_ROW_PADDING,
        build = function(row)
            SnapshotRow:Build(row, rowContext)
        end,
        update = function(row, elementData)
            row:Render(elementData)
        end,
    })
end

function SnapshotList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onSelect == nil or type(opts.onSelect) == "function", "Build: 'opts.onSelect' must be a function")
    C:Ensures(opts.onContext == nil or type(opts.onContext) == "function", "Build: 'opts.onContext' must be a function")

    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
        onSelect = opts.onSelect,
        onContext = opts.onContext,
    }, {
        frameType = "Frame",
        methods = Methods,
    })
end

-- Rebuild the data provider from the cached entries. Re-setting the provider is
-- what reruns the extent calculator and the row initializers, so it is also how
-- an expand/collapse relayout is triggered.
local function Rebuild(panel)
    local dataProvider = CreateDataProvider()
    for _, entry in ipairs(panel._entries) do
        dataProvider:Insert(entry)
    end
    panel._scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

-- Newest-first ordering for saved history, with the persistent index as a
-- tiebreaker so snapshots captured in the same second stay deterministic.
local function LoadEntries(panel)
    wipe(panel._entries)
    if not panel._currentProfile then return end
    for _, handle in ipairs(SnapshotHandleCache:GetTimeline(panel._currentProfile)) do
        tinsert(panel._entries, {
            snapshot = handle,
            isHead = SnapshotView:IsHead(handle),
        })
    end
end

-- Whether a saved snapshot differs from the live setup, memoised per snapshot so
-- the flag is computed once per data load rather than on every relayout. Diffs
-- against the already-captured Current (no live re-scan), so it matches the
-- expanded summary's verdict while staying cheap enough to switch profiles
-- without a hitch. The head is the live setup itself, so it never tags.
function Methods:HasChanges(snapshot)
    if not snapshot or SnapshotView:IsHead(snapshot) then
        return false
    end

    local cached = self._changeFlags[snapshot]
    if cached == nil then
        cached = SnapshotDetailBuilder.HasChanges(SnapshotView:Preview(snapshot, nil, true))
        self._changeFlags[snapshot] = cached
    end
    return cached
end

-- Populate the timeline for a character: the current head always sits on top as
-- a live view of the character's present setup (live for the logged-in
-- character, last-captured for an alt), followed by the saved history (newest
-- first). Selects the head, or the latest saved snapshot when there is none.
function Methods:SetProfile(profileName)
    self._currentProfile = profileName
    LoadEntries(self)
    wipe(self._changeFlags)

    -- Default selection: the head when present, else the latest saved snapshot.
    self._selected = profileName and (SnapshotHandleCache:GetHead(profileName) or SnapshotHandleCache:GetLatestSaved(profileName))
    self._expanded = nil
    self._expandedDetail = nil
    Rebuild(self)

    if self._onSelectionChanged then
        self._onSelectionChanged(self:GetSelected())
    end
end

-- Select a row and toggle its inline detail panel. Re-clicking the open row
-- collapses it but keeps it selected.
function Methods:Select(snapshot)
    self._selected = snapshot

    if self._expanded == snapshot then
        self._expanded = nil
        self._expandedDetail = nil
    else
        self._expanded = snapshot
        self._expandedDetail = BuildDetail(snapshot)
    end

    Rebuild(self)

    if self._onSelectionChanged then
        self._onSelectionChanged(self:GetSelected())
    end
end

-- Re-render the visible rows in place after a snapshot was mutated (pinned or
-- had its note edited) without disturbing the current selection or expansion.
-- A pin/unpin changes the row's group, so the order is re-derived too.
function Methods:Refresh()
    LoadEntries(self)
    wipe(self._changeFlags)
    if self._expanded then
        self._expandedDetail = BuildDetail(self._expanded)
    end
    Rebuild(self)
end

function Methods:GetSelected()
    return self._selected
end

function Methods:Clear()
    wipe(self._entries)
    wipe(self._changeFlags)
    self._currentProfile = nil
    self._selected = nil
    self._expanded = nil
    self._expandedDetail = nil
    if self._scrollBox then
        self._scrollBox:SetDataProvider(CreateDataProvider())
    end
end
