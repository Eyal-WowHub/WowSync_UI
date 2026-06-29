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
        -> self {
            SetImport(importID),   -- (re)populate from a container; clears selection
            Refresh(),             -- re-render in place from the current container
            GetSelected() -> snapshot or nil,
            Clear(),
        }
]]

local ImportSnapshotList = addon:NewObject("ImportSnapshotList")
local ImportSnapshotRow = addon:GetObject("ImportSnapshotRow")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local scrollBox
local currentImportID = nil
local selectedSnapshot = nil
local onSelect = nil

-- Height of a snapshot row; tall enough for the subject and the note line.
local ROW_HEIGHT = 40

-- Vertical gap between rows.
local ROW_PADDING = 2

function ImportSnapshotList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}
    onSelect = opts.onSelect

    scrollBox = CreateFrame("Frame", nil, region, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)

    local scrollBar = CreateFrame("EventFrame", nil, region, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local rowContext = {
        GetSelected = function()
            return selectedSnapshot
        end,
        Select = function(snapshot)
            ImportSnapshotList:Select(snapshot)
        end,
        OpenMenu = opts.onContext,
    }

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function()
        return ROW_HEIGHT
    end)
    view:SetPadding(0, 0, 0, 0, ROW_PADDING)
    view:SetElementInitializer("Frame", function(row, snapshot)
        if not row.initialized then
            ImportSnapshotRow:Build(row, rowContext)
            row.initialized = true
        end
        ImportSnapshotRow:Update(row, snapshot, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return self
end

-- Render the container's snapshots, newest-first (GetImportSnapshots is
-- oldest-first).
function ImportSnapshotList:SetImport(importID)
    currentImportID = importID
    selectedSnapshot = nil
    self:Refresh()
end

function ImportSnapshotList:Refresh()
    local dataProvider = CreateDataProvider()
    if currentImportID then
        local snapshots = ImportManager:GetImportSnapshots(currentImportID)
        for index = #snapshots, 1, -1 do
            dataProvider:Insert(snapshots[index])
        end
    end
    scrollBox:SetDataProvider(dataProvider)
end

function ImportSnapshotList:Select(snapshot)
    selectedSnapshot = snapshot
    scrollBox:ForEachFrame(function(row)
        if not row.snapshot then return end
        if row.snapshot == selectedSnapshot then
            row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    if onSelect then onSelect(selectedSnapshot) end
end

function ImportSnapshotList:GetSelected()
    return selectedSnapshot
end

function ImportSnapshotList:Clear()
    currentImportID = nil
    selectedSnapshot = nil
    if scrollBox then
        scrollBox:SetDataProvider(CreateDataProvider())
    end
end
