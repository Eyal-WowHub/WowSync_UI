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

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Height of a collapsed snapshot row.
local SNAPSHOT_ROW_HEIGHT = 40

-- Vertical gap between snapshot rows.
local SNAPSHOT_ROW_PADDING = 2

-- Gap between the detail panel's header and its first change line.
local SNAPSHOT_DETAIL_HEADER_GAP = 2

-- Padding below the last line of an expanded row's detail panel.
local SNAPSHOT_DETAIL_BOTTOM_PAD = 8

local SnapshotView = WowSync:GetSnapshotView()
local SnapshotHandleCache = WowSync:GetSnapshotHandleCache()

local Verbs = {}

-- The detail font's real line height, measured once so reserved row height
-- matches the rendered text exactly (a fixed guess leaves a trailing gap).
local detailLineHeight
local function DetailLineHeight()
    if detailLineHeight then return detailLineHeight end
    local probe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    probe:SetText("Ag")
    local measured = probe:GetStringHeight()
    probe:Hide()
    if measured and measured > 0 then
        detailLineHeight = math.ceil(measured)
    end
    return detailLineHeight or 12
end

-- The extra height an expanded row needs for its detail panel, derived purely
-- from the cached detail so the scroll box can size elements deterministically.
local function DetailExtent(detail)
    if not detail then return 0 end

    local lineHeight = DetailLineHeight()
    local height = UI.SnapshotDetail.TopPad
    if detail.hasNote then
        height = height + UI.SnapshotDetail.NoteHeight
    end
    -- The "Changes vs current setup:" header (plus the gap to the first line),
    -- then one line per changed module (or a single "matches" line).
    height = height + lineHeight + SNAPSHOT_DETAIL_HEADER_GAP
    height = height + math.max(1, #detail.modules) * lineHeight
    height = height + SNAPSHOT_DETAIL_BOTTOM_PAD
    return height
end

-- Diff the chosen snapshot against the live setup and distil it into a small,
-- render-ready table (note + changed-module counts).
local function BuildDetail(snapshot)
    local detail = { hasNote = false, note = nil, modules = {} }
    if not snapshot then return detail end

    local note = SnapshotView:GetNotes(snapshot)
    if note ~= "" then
        detail.hasNote = true
        detail.note = note
    end

    local preview = SnapshotView:Preview(snapshot)
    if preview and preview.perModule then
        local moduleNames = {}
        for name in pairs(preview.perModule) do
            tinsert(moduleNames, name)
        end
        table.sort(moduleNames)

        for _, name in ipairs(moduleNames) do
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

function Verbs:Constructor(config)
    local panel = self

    panel._entries = {}            -- ordered display rows { snapshot = <handle>, isHead = bool }
    panel._currentProfile = nil    -- profile name, for diffing against the live setup
    panel._selected = nil          -- the selected snapshot handle (identity, not its hash)
    panel._expanded = nil          -- the one open row (accordion), independent of selection
    panel._expandedDetail = nil    -- cached diff/note for the expanded row
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
        -- Variable extents: the one expanded row is taller by its detail panel.
        extent = function(_, elementData)
            if elementData.snapshot == panel._expanded then
                return UI.SnapshotDetail.SubjectZone + DetailExtent(panel._expandedDetail)
            end
            return SNAPSHOT_ROW_HEIGHT
        end,
        padding = SNAPSHOT_ROW_PADDING,
        build = function(row)
            SnapshotRow:Build(row, rowContext)
        end,
        update = function(row, elementData)
            SnapshotRow:Update(row, elementData, rowContext)
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
        verbs = Verbs,
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

-- Populate the timeline for a character: the current head always sits on top as
-- a live view of the character's present setup (live for the logged-in
-- character, last-captured for an alt), followed by the saved history (newest
-- first). Selects the head, or the latest saved snapshot when there is none.
function Verbs:SetProfile(profileName)
    self._currentProfile = profileName
    LoadEntries(self)

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
function Verbs:Select(snapshot)
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
function Verbs:Refresh()
    LoadEntries(self)
    if self._expanded then
        self._expandedDetail = BuildDetail(self._expanded)
    end
    Rebuild(self)
end

function Verbs:GetSelected()
    return self._selected
end

function Verbs:Clear()
    wipe(self._entries)
    self._currentProfile = nil
    self._selected = nil
    self._expanded = nil
    self._expandedDetail = nil
    if self._scrollBox then
        self._scrollBox:SetDataProvider(CreateDataProvider())
    end
end
