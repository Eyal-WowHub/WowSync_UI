local _, addon = ...

--[[
    ImportSnapshotList object (Imports tab timeline).

    Fills an injected region with a scrollable, newest-first timeline of an
    imported container's snapshots (one ImportSnapshotRow each). Owns the
    selection state; never leaks its frames. Rows are pooled across containers.

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

-- Height of a snapshot row; tall enough for the subject and the note line.
local ROW_HEIGHT = 40

-- Vertical gap between rows.
local ROW_PADDING = 2

function Verbs:Constructor(config)
    local panel = self

    panel._currentImportID = nil
    panel._selectedSnapshot = nil
    panel._onSelect = config.onSelect

    local rowContext = {
        GetSelected = function()
            return panel._selectedSnapshot
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
        extent = ROW_HEIGHT,
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

-- Render the container's snapshots, newest-first (GetImportSnapshots is
-- oldest-first).
function Verbs:SetImport(importID)
    self._currentImportID = importID
    self._selectedSnapshot = nil
    self:Refresh()
end

function Verbs:Refresh()
    local dataProvider = CreateDataProvider()
    if self._currentImportID then
        local snapshots = ImportManager:GetImportSnapshots(self._currentImportID)
        for index = #snapshots, 1, -1 do
            dataProvider:Insert(snapshots[index])
        end
    end
    self._scrollBox:SetDataProvider(dataProvider)
end

function Verbs:Select(snapshot)
    self._selectedSnapshot = snapshot
    self._scrollBox:ForEachFrame(function(row)
        if not row.snapshot then return end
        if row.snapshot == self._selectedSnapshot then
            row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    if self._onSelect then self._onSelect(self._selectedSnapshot) end
end

function Verbs:GetSelected()
    return self._selectedSnapshot
end

function Verbs:Clear()
    self._currentImportID = nil
    self._selectedSnapshot = nil
    if self._scrollBox then
        self._scrollBox:SetDataProvider(CreateDataProvider())
    end
end
