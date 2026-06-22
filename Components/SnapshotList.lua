local _, addon = ...

local UI = addon.UI

--[[
    SnapshotList object (right-panel timeline).

    Fills an injected region with a scrollable, newest-first timeline of a
    profile's snapshots (one SnapshotRow each). Owns the selection state and
    exposes it through a callback; never leaks its frames. Rows are pooled by
    the scroll box across profile selections.

    addon:GetObject("SnapshotList"):Build(region, { onSelect = function(snapshot or nil) })
        -> self {
            SetProfile(profile),       -- (re)populate; selects the latest snapshot
            GetSelected() -> snapshot or nil,
            Clear(),
        }
]]

local SnapshotList = addon:NewObject("SnapshotList")
local SnapshotRow = addon:GetObject("SnapshotRow")

local scrollBox
local selectedHash = nil
local snapshotsByHash = {}   -- hash -> snapshot (current profile)
local onSelectionChanged = nil

function SnapshotList:Build(region, opts)
    opts = opts or {}
    onSelectionChanged = opts.onSelect

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
        Select = function(hash)
            SnapshotList:Select(hash)
        end,
    }

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UI.SnapshotRowHeight)
    view:SetPadding(0, 0, 0, 0, UI.SnapshotRowPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            SnapshotRow:Build(row, rowContext)
            row.initialized = true
        end
        SnapshotRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return self
end

-- Populate the timeline from a profile's history (newest first) and select the
-- latest snapshot.
function SnapshotList:SetProfile(profile)
    wipe(snapshotsByHash)

    local list = profile and profile.Snapshots or {}
    local count = #list

    local dataProvider = CreateDataProvider()

    -- The history is stored oldest-first; walk it in reverse for newest-first.
    for i = count, 1, -1 do
        local snapshot = list[i]
        snapshotsByHash[snapshot.Hash] = snapshot
        dataProvider:Insert({
            snapshot = snapshot,
            isLatest = (i == count),
            isOldest = (i == 1),
        })
    end

    scrollBox:SetDataProvider(dataProvider)

    selectedHash = count > 0 and list[count].Hash or nil
    self:RefreshHighlights()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

function SnapshotList:Select(hash)
    selectedHash = hash
    self:RefreshHighlights()

    if onSelectionChanged then
        onSelectionChanged(self:GetSelected())
    end
end

-- Repaint row backgrounds to match the current selection.
function SnapshotList:RefreshHighlights()
    scrollBox:ForEachFrame(function(frame)
        if frame.snapshotHash == selectedHash then
            frame.bg:SetColorTexture(UI.RowSelectedColor:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
end

function SnapshotList:GetSelected()
    return selectedHash and snapshotsByHash[selectedHash] or nil
end

function SnapshotList:Clear()
    wipe(snapshotsByHash)
    selectedHash = nil
    if scrollBox then
        scrollBox:SetDataProvider(CreateDataProvider())
    end
end
