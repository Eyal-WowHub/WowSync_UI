local _, addon = ...

--[[
    List widget (reusable left-panel scroll list).

    Builds a bordered panel with a title and a virtualised, single-selection
    scroll list, owning the selection state and scroll plumbing shared by the
    profile and import lists. The owner supplies the row renderer, per-element
    extents, and the data; it attaches its own buttons to list.root and feeds
    rows by building a data provider and calling list:SetData.

    A row carries its identifier on row.id (set by the row renderer), which the
    selection highlight and scroll-to predicate rely on.

    local list = addon:GetObject("List"):Build(region, {
        title = L["Profiles"],
        rowRenderer = ProfileRow,                  -- :Build(row, ctx) / :Update(row, data, ctx)
        extent = function(elementData) -> height,  -- optional, default UI.List.ItemHeight
        rowContext = { Rename = fn, ... },          -- optional extras merged into the row ctx
        bottomInset = 40,                           -- optional, room for owner bottom buttons
    })

    list.root                                       -- the panel Frame, for owner buttons
    list:OnSelect(callback)                         -- callback(id or nil)
    list:SetData(dataProvider, visibleIDs)          -- swap contents; drops a vanished selection
    list:GetSelected() -> id or nil
    list:Select(id)
    list:ClearSelection()
    list:ScrollTo(id)
]]

local List = addon:NewObject("List")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Leaves room below the scroll area for the owner's bottom-left buttons.
local DEFAULT_BOTTOM_INSET = 40

local ListMethods = {}
local ListMeta = { __index = ListMethods }

function List:Build(region, config)
    C:IsTable(region, 2)
    C:IsTable(config, 3)
    C:Ensures(type(config.rowRenderer) == "table", "Build: 'config.rowRenderer' must be a table")

    local list = setmetatable({}, ListMeta)
    list.selectedID = nil
    list.onSelectionChanged = nil

    local root = CreateFrame("Frame", nil, region, "BackdropTemplate")
    root:SetAllPoints(region)
    root:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(unpack(UI.Backdrop.Panel))
    root:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))
    list.root = root

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(config.title or "")
    list.title = title

    local bottomInset = config.bottomInset or DEFAULT_BOTTOM_INSET

    local scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -36)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, bottomInset)
    list.scrollBox = scrollBox

    local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    -- Row context: the shared selection hooks plus any owner extras (e.g. Rename).
    local rowContext = {
        GetSelected = function()
            return list.selectedID
        end,
        Select = function(id)
            list:Select(id)
        end,
    }
    if config.rowContext then
        for key, value in pairs(config.rowContext) do
            rowContext[key] = value
        end
    end

    local rowRenderer = config.rowRenderer
    local extent = config.extent

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, elementData)
        if extent then
            return extent(elementData)
        end
        return UI.List.ItemHeight
    end)
    view:SetPadding(0, 0, 0, 0, UI.List.ItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            rowRenderer:Build(row, rowContext)
            row.initialized = true
        end
        rowRenderer:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return list
end

function ListMethods:OnSelect(callback)
    self.onSelectionChanged = callback
end

-- Swap the list contents. Drops the selection (notifying once) when the
-- selected id is no longer among the visible ids.
function ListMethods:SetData(dataProvider, visibleIDs)
    self.scrollBox:SetDataProvider(dataProvider)

    if self.selectedID and visibleIDs and not visibleIDs[self.selectedID] then
        self.selectedID = nil
        if self.onSelectionChanged then
            self.onSelectionChanged(nil)
        end
    end
end

function ListMethods:GetSelected()
    return self.selectedID
end

function ListMethods:Select(id)
    self.selectedID = id
    self.scrollBox:ForEachFrame(function(frame)
        if not frame.id then return end
        if frame.id == id then
            frame.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    if self.onSelectionChanged then
        self.onSelectionChanged(id)
    end
end

function ListMethods:ClearSelection()
    self:Select(nil)
end

-- Scroll the list so the element with the given id is visible (no-op if absent).
function ListMethods:ScrollTo(id)
    if not id then return end
    self.scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.id == id
    end, ScrollBoxConstants.AlignNearest)
end
