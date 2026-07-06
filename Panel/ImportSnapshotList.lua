local _, addon = ...

--[[
    ImportSnapshotList object (Imports tab timeline).

    Fills an injected region with a scrollable, newest-first timeline of an
    imported container's snapshots (one ImportSnapshotRow each). Owns the
    selection state; never leaks its frames. Rows are pooled across containers.

    Clicking a row selects it (drives Apply) and toggles an inline detail panel
    below it: the export note plus a per-module change summary against the
    current setup. Expansion is an accordion -- at most one row is open, and the
    selection persists even when that row is collapsed again.

    addon:GetObject("ImportSnapshotList"):Build(region, {
        onSelect  = fn(snapshot or nil),   -- selection changed
        onContext = fn(snapshot, anchor),  -- right-click on a row
    })
        -> import-snapshot-list frame {
            SetImport(importID),   -- (re)populate from a container; clears selection
            Refresh(),             -- re-render in place from the current container
            GetSelected() -> snapshot or nil,
            Clear(),
        }
]]

local ImportSnapshotList = addon:NewObject("ImportSnapshotList")

local C = addon.C
local SnapshotDetailBuilder = addon.SnapshotDetailBuilder

local ExpandableContent = addon:GetObject("ExpandableContent")
local ImportSnapshotRow = addon:GetObject("ImportSnapshotRow")
local ScrollList = addon:GetObject("ScrollList")

local ImportedHashDictionary = WowSync:Import("ImportedHashDictionary")
local ImportManager = WowSync:Import("ImportManager")

local Methods = {}

-- Vertical gap between rows.
local ROW_PADDING = 2

-- Padding above and below a row's content stack, matching the row's content
-- anchor (inset from the top, lifted off the bottom).
local CONTENT_TOP_PAD = 6
local CONTENT_BOTTOM_PAD = 8

-- Right margin of the row content, matching the row's content anchor; paired
-- with the row's content inset to derive the wrap width for measuring.
local RIGHT_MARGIN = 8

-- Characters of the content hash forming a snapshot's selector. Imported
-- snapshots are addressed by their full hash and index.
local function SelectorFor(snapshot)
    return ("%s#%d"):format(snapshot.Hash, snapshot.Index or 0)
end

-- Diff the imported snapshot against the live setup and distil it into a small,
-- render-ready table (export note + changed-module counts).
local function BuildDetail(importID, snapshot)
    if not snapshot then
        return SnapshotDetailBuilder.Build(nil, nil)
    end

    return SnapshotDetailBuilder.Build(
        snapshot.Notes,
        ImportManager:PreviewApplySnapshot(importID, SelectorFor(snapshot))
    )
end

function Methods:Constructor(config)
    local panel = self

    panel._currentImportID = nil
    panel._selectedSnapshot = nil
    panel._expanded = nil          -- the one open row (accordion), independent of selection
    panel._expandedDetail = nil    -- cached diff/note for the expanded row
    panel._duplicates = {}         -- snapshot -> the older original it repeats, for repeat hashes
    panel._origin = {}             -- snapshot -> name of the container that imported its hash first
    panel._onSelect = config.onSelect

    local rowContext = {
        GetSelected = function()
            return panel._selectedSnapshot
        end,
        IsExpanded = function(snapshot)
            return snapshot == panel._expanded
        end,
        DuplicateOf = function(snapshot)
            return panel._duplicates[snapshot]
        end,
        OriginContainer = function(snapshot)
            return panel._origin[snapshot]
        end,
        GetDetail = function()
            return panel._expandedDetail
        end,
        Select = function(snapshot)
            panel:Select(snapshot)
        end,
        OpenMenu = config.onContext,
    }

    panel._scrollBox = ScrollList:Build({
        parent = self,
        anchor = function(sb)
            sb:SetPoint("TOPLEFT", 0, 0)
            sb:SetPoint("BOTTOMRIGHT", -16, 0)
        end,
        -- Variable extents: every row is sized to the content it renders,
        -- measured from the same line list (module names collapsed, the change
        -- summary expanded).
        extent = function(_, snapshot)
            local expanded = snapshot == panel._expanded
            local detail = expanded and panel._expandedDetail or nil
            local original = panel._duplicates[snapshot]
            local originName = panel._origin[snapshot]
            local width = panel._scrollBox:GetWidth() - ImportSnapshotRow.ContentInset - RIGHT_MARGIN
            local lines = ImportSnapshotRow:BuildLines(snapshot, expanded, detail, original, originName)
            return CONTENT_TOP_PAD + ExpandableContent:Measure(lines, width) + CONTENT_BOTTOM_PAD
        end,
        padding = ROW_PADDING,
        build = function(row)
            ImportSnapshotRow:Build(row, rowContext)
        end,
        update = function(row, snapshot)
            row:Render(snapshot)
        end,
    })
end

function ImportSnapshotList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

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

-- Rebuild the data provider from the current container, newest capture first
-- (GetSnapshots is import-ordered). Re-setting the provider reruns the
-- extent calculator, so it is also how an expand/collapse relayout is triggered.
local function Rebuild(panel)
    local dataProvider = CreateDataProvider()
    local duplicates = {}
    local origin = {}
    if panel._currentImportID then
        local snapshots = ImportManager:GetSnapshots(panel._currentImportID)
        -- A hash's "owner" is the container that imported it first. When this
        -- container is not the owner, every copy here points at that owner by
        -- name. Only when this container owns the hash do repeats fall back to
        -- the in-container "#N" flag against the earlier copy; the first stays
        -- unflagged either way. Owners are resolved in one pass up front so the
        -- per-row work below is a plain lookup.
        local owners = ImportedHashDictionary:GetHashOwners()
        local seen = {}
        for index = 1, #snapshots do
            local snapshot = snapshots[index]
            local hash = snapshot.Hash
            local owner = hash and owners[hash]
            if owner and owner.ID ~= panel._currentImportID then
                origin[snapshot] = owner.Name
            elseif hash then
                if seen[hash] then
                    duplicates[snapshot] = seen[hash]
                else
                    seen[hash] = snapshot
                end
            end
        end
        -- Pinned snapshots float to the top; the rest show newest capture first
        -- so the timeline reads top-to-bottom like the profile history. Same-hash
        -- copies share a timestamp, so ties fall back to import order (later
        -- import first). This ordering is display only -- ownership/duplicate
        -- flags above are derived from import order.
        local ordered = {}
        for index = 1, #snapshots do
            ordered[index] = snapshots[index]
        end
        table.sort(ordered, function(a, b)
            local ap, bp = a.Pinned == true, b.Pinned == true
            if ap ~= bp then
                return ap
            end
            if (a.Timestamp or 0) ~= (b.Timestamp or 0) then
                return (a.Timestamp or 0) > (b.Timestamp or 0)
            end
            return (a.Index or 0) > (b.Index or 0)
        end)
        for index = 1, #ordered do
            dataProvider:Insert(ordered[index])
        end
    end
    panel._duplicates = duplicates
    panel._origin = origin
    panel._scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

-- Render the container's snapshots, newest capture first.
function Methods:SetImport(importID)
    self._currentImportID = importID
    self._selectedSnapshot = nil
    self._expanded = nil
    self._expandedDetail = nil
    Rebuild(self)
end

function Methods:Refresh()
    if self._expanded then
        self._expandedDetail = BuildDetail(self._currentImportID, self._expanded)
    end
    Rebuild(self)
end

-- Select a row and toggle its inline detail panel. Re-clicking the open row
-- collapses it but keeps it selected.
function Methods:Select(snapshot)
    self._selectedSnapshot = snapshot

    if self._expanded == snapshot then
        self._expanded = nil
        self._expandedDetail = nil
    else
        self._expanded = snapshot
        self._expandedDetail = BuildDetail(self._currentImportID, snapshot)
    end

    Rebuild(self)

    if self._onSelect then self._onSelect(self._selectedSnapshot) end
end

function Methods:GetSelected()
    return self._selectedSnapshot
end

function Methods:Clear()
    self._currentImportID = nil
    self._selectedSnapshot = nil
    self._expanded = nil
    self._expandedDetail = nil
    self._duplicates = {}
    self._origin = {}
    if self._scrollBox then
        self._scrollBox:SetDataProvider(CreateDataProvider())
    end
end
