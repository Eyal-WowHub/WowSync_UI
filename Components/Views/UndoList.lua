local _, addon = ...

--[[
    UndoList object (right-panel empty-state undo history).

    Fills an injected region with a newest-first, scrollable list of the current
    character's undo points (one row per past apply). Clicking a row asks the
    caller to roll back every apply from the top down to and including that row
    (a cascade), since undo is strictly last-in-first-out. The list owns no undo
    logic of its own; it forwards the chosen depth through onActivate.

    addon:GetObject("UndoList"):Build(region, {
        onActivate = function(count, undoPoint) end,   -- undo `count` newest applies; undoPoint = the deepest one
    })
        -> self {
            Refresh() -> hasEntries,   -- repopulate from the live undo points
            Hide(),
        }
]]

local UndoList = addon:NewObject("UndoList")

local L = addon.L
local UI = addon.UI
local C = LibStub("Contracts-1.0")

local SnapshotManager = WowSync:GetSnapshotManager()

-- Height of an undo history row and the gap between rows.
local UNDO_ROW_HEIGHT = 34
local UNDO_ROW_PADDING = 2

local root
local scrollBox
local onActivate

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(UI.Row.Hover:GetRGBA())

    row.subjectText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.subjectText:SetPoint("TOPLEFT", 8, -4)
    row.subjectText:SetJustifyH("LEFT")

    row.modulesText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.modulesText:SetPoint("TOPLEFT", row.subjectText, "BOTTOMLEFT", 0, -2)
    row.modulesText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.modulesText:SetJustifyH("LEFT")
    row.modulesText:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if onActivate and self.undoPoint then
            onActivate(self.index, self.undoPoint)
        end
    end)
end

local function UpdateRow(row, elementData)
    row.index = elementData.index
    row.undoPoint = elementData.undoPoint

    row.subjectText:SetText(elementData.undoPoint.Subject or L["Unknown"])
    row.modulesText:SetText(table.concat(elementData.undoPoint.ModuleNames or {}, ", "))
end

function UndoList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onActivate == nil or type(opts.onActivate) == "function", "Build: 'opts.onActivate' must be a function")

    onActivate = opts.onActivate

    root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L["Recent changes"])

    local hint = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    hint:SetText(L["Click an entry to undo back to that point."])

    scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    scrollBox:SetPoint("BOTTOMRIGHT", -16, 10)

    local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UNDO_ROW_HEIGHT)
    view:SetPadding(0, 0, 0, 0, UNDO_ROW_PADDING)
    view:SetElementInitializer("Button", function(row, elementData)
        if not row.initialized then
            BuildRow(row)
            row.initialized = true
        end
        UpdateRow(row, elementData)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    root:Hide()
    return self
end

-- Repopulate from the live undo points (newest first) and show the list only
-- when there is something to undo. Returns whether any entries exist.
function UndoList:Refresh()
    local undoPoints = SnapshotManager:GetUndoPoints()

    local dataProvider = CreateDataProvider()
    for i, undoPoint in ipairs(undoPoints) do
        dataProvider:Insert({ index = i, undoPoint = undoPoint })
    end
    scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.DiscardScrollPosition)

    local hasEntries = #undoPoints > 0
    root:SetShown(hasEntries)
    return hasEntries
end

function UndoList:Hide()
    if root then
        root:Hide()
    end
end
