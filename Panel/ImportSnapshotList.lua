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
local ImportSnapshotRow = addon:GetObject("ImportSnapshotRow")
local ScrollList = addon:GetObject("ScrollList")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local Verbs = {}

-- Vertical gap between rows.
local ROW_PADDING = 2

-- Gaps inside a row's body, mirroring the anchors in ImportSnapshotRow so the
-- reserved height matches what is rendered.
local NOTE_GAP = 2     -- subject -> note (or header when there is no note)
local SECTION_GAP = 14 -- note -> header (a blank line's worth, both states)
local HEADER_GAP = 2   -- header -> list

-- Padding below the last list line.
local BOTTOM_PAD = 8

-- Left inset of the row body, matching ROW_INSET in ImportSnapshotRow; used to
-- derive the note's wrap width.
local ROW_INSET = 10

-- Characters of the content hash forming a snapshot's selector. Imported
-- snapshots are addressed by their full hash and index.
local function SelectorFor(snapshot)
    return ("%s#%d"):format(snapshot.Hash, snapshot.Index or 0)
end

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

-- The wrapped height the expanded note will render at, measured with the same
-- font and width as the row's note so the reserved height tracks the content
-- exactly (no trailing dead space from a fixed-size box).
local noteProbe
local function MeasuredNoteHeight(panel, text)
    local lineHeight = DetailLineHeight()
    if not text or text == "" then return lineHeight end

    local width = panel._scrollBox and panel._scrollBox:GetWidth() or 0
    width = width - ROW_INSET - 8
    if width <= 0 then return lineHeight end

    if not noteProbe then
        noteProbe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noteProbe:SetJustifyH("LEFT")
        noteProbe:SetWordWrap(true)
        noteProbe:Hide()
    end
    noteProbe:SetWidth(width)
    noteProbe:SetText(text)
    local measured = noteProbe:GetStringHeight()
    return (measured and measured > 0) and math.ceil(measured) or lineHeight
end

-- The height a row needs, including its subject line, for the given note-block
-- height (0 when there is no note) and body line count.
local function RowExtent(noteHeight, lineCount)
    local lineHeight = DetailLineHeight()
    local height = UI.SnapshotDetail.SubjectZone + NOTE_GAP
    if noteHeight > 0 then
        height = height + noteHeight + SECTION_GAP
    end
    -- The section header (plus the gap to the first line), then the list lines.
    height = height + lineHeight + HEADER_GAP
    height = height + math.max(1, lineCount) * lineHeight
    height = height + BOTTOM_PAD
    return height
end

-- Number of modules an imported snapshot carries (one collapsed list line each).
local function ModuleCount(snapshot)
    local count = 0
    for _ in pairs(snapshot.Modules or {}) do
        count = count + 1
    end
    return count
end

-- Diff the imported snapshot against the live setup and distil it into a small,
-- render-ready table (export note + changed-module counts).
local function BuildDetail(importID, snapshot)
    local detail = { hasNote = false, note = nil, modules = {} }
    if not snapshot then return detail end

    local note = snapshot.Notes
    if note and note ~= "" then
        detail.hasNote = true
        detail.note = note
    end

    local preview = ImportManager:PreviewApplySnapshot(importID, SelectorFor(snapshot))
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

    panel._currentImportID = nil
    panel._selectedSnapshot = nil
    panel._expanded = nil          -- the one open row (accordion), independent of selection
    panel._expandedDetail = nil    -- cached diff/note for the expanded row
    panel._onSelect = config.onSelect

    local rowContext = {
        GetSelected = function()
            return panel._selectedSnapshot
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
        OpenMenu = config.onContext,
    }

    panel._scrollBox = ScrollList:Build({
        parent = self,
        anchor = function(sb)
            sb:SetPoint("TOPLEFT", 0, 0)
            sb:SetPoint("BOTTOMRIGHT", -16, 0)
        end,
        -- Variable extents: a row is sized for its note and its list (the
        -- exported modules collapsed, the change summary expanded).
        extent = function(_, snapshot)
            if snapshot == panel._expanded then
                local detail = panel._expandedDetail
                local noteHeight = (detail and detail.hasNote) and MeasuredNoteHeight(panel, detail.note) or 0
                return RowExtent(noteHeight, detail and #detail.modules or 0)
            end
            local hasNote = snapshot.Notes ~= nil and snapshot.Notes ~= ""
            return RowExtent(hasNote and DetailLineHeight() or 0, ModuleCount(snapshot))
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
        verbs = Verbs,
    })
end

-- Rebuild the data provider from the current container, newest-first
-- (GetImportSnapshots is oldest-first). Re-setting the provider reruns the
-- extent calculator, so it is also how an expand/collapse relayout is triggered.
local function Rebuild(panel)
    local dataProvider = CreateDataProvider()
    if panel._currentImportID then
        local snapshots = ImportManager:GetImportSnapshots(panel._currentImportID)
        for index = #snapshots, 1, -1 do
            dataProvider:Insert(snapshots[index])
        end
    end
    panel._scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

-- Render the container's snapshots, newest-first.
function Verbs:SetImport(importID)
    self._currentImportID = importID
    self._selectedSnapshot = nil
    self._expanded = nil
    self._expandedDetail = nil
    Rebuild(self)
end

function Verbs:Refresh()
    if self._expanded then
        self._expandedDetail = BuildDetail(self._currentImportID, self._expanded)
    end
    Rebuild(self)
end

-- Select a row and toggle its inline detail panel. Re-clicking the open row
-- collapses it but keeps it selected.
function Verbs:Select(snapshot)
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

function Verbs:GetSelected()
    return self._selectedSnapshot
end

function Verbs:Clear()
    self._currentImportID = nil
    self._selectedSnapshot = nil
    self._expanded = nil
    self._expandedDetail = nil
    if self._scrollBox then
        self._scrollBox:SetDataProvider(CreateDataProvider())
    end
end
