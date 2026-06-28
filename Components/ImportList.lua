local _, addon = ...

--[[
    ImportList object (left panel, Imports tab).

    Fills an injected region with a title and a scrollable list of imported
    containers (one ImportRow each), grouped by class. Owns the selection state
    and exposes it through callbacks; never leaks its frames.

    addon:GetObject("ImportList"):Build(region)
        -> self {
            OnSelect(callback),     -- callback(importID or nil)
            Refresh(),
            GetSelected() -> importID or nil,
            Select(importID),
            ClearSelection(),
            BeginImport(),          -- opens the import dialog
        }
]]

local ImportList = addon:NewObject("ImportList")
local ImportRow = addon:GetObject("ImportRow")
local ImportDialog = addon:GetObject("ImportDialog")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local scrollBox
local selectedImportID = nil
local onSelectionChanged = nil

-- Height of a class group header row; the extra space over the text gives each
-- group a consistent leading gap. The container rows use UI.List.ItemHeight.
local CLASS_HEADER_HEIGHT = 26

function ImportList:Build(region)
    C:IsTable(region, 2)

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

    -- Title
    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["Imports"])

    -- Import button, top-right of the header.
    local importButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    importButton:SetPoint("TOPRIGHT", -10, -6)
    importButton:SetSize(64, 22)
    importButton:SetText(L["Import"])
    importButton:SetScript("OnClick", function() ImportList:BeginImport() end)

    -- Scroll area
    scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -36)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    -- Shared selection context for the pooled rows
    local rowContext = {
        GetSelected = function()
            return selectedImportID
        end,
        Select = function(importID)
            ImportList:Select(importID)
        end,
    }

    -- List view
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, elementData)
        if elementData.kind == "class" then
            return CLASS_HEADER_HEIGHT
        end
        return UI.List.ItemHeight
    end)
    view:SetPadding(0, 0, 0, 0, UI.List.ItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            ImportRow:Build(row, rowContext)
            row.initialized = true
        end
        ImportRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return self
end

function ImportList:OnSelect(callback)
    onSelectionChanged = callback
end

function ImportList:Refresh()
    -- Imported containers grouped by class. GetImportedProfiles already returns
    -- them sorted by class then name, so a class header is emitted whenever the
    -- class changes.
    local imports = ImportManager:GetImportedProfiles()

    local visibleImports = {}
    local dataProvider = CreateDataProvider()
    local lastClassID

    for _, entry in ipairs(imports) do
        visibleImports[entry.ID] = true

        if entry.ClassID ~= lastClassID then
            dataProvider:Insert({ kind = "class", classID = entry.ClassID })
            lastClassID = entry.ClassID
        end

        dataProvider:Insert({
            kind = "import",
            id = entry.ID,
            name = entry.Name,
            classID = entry.ClassID,
            snapshotCount = entry.SnapshotCount,
        })
    end

    scrollBox:SetDataProvider(dataProvider)

    -- Drop the selection if the selected container is no longer listed.
    if selectedImportID and not visibleImports[selectedImportID] then
        selectedImportID = nil
        if onSelectionChanged then
            onSelectionChanged(nil)
        end
    end
end

function ImportList:Select(importID)
    selectedImportID = importID
    scrollBox:ForEachFrame(function(frame)
        if not frame.importID then return end
        if frame.importID == selectedImportID then
            frame.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    if onSelectionChanged then onSelectionChanged(selectedImportID) end
end

function ImportList:GetSelected()
    return selectedImportID
end

function ImportList:ClearSelection()
    self:Select(nil)
end

-- Scrolls the list to bring the given container into view.
function ImportList:ScrollToImport(importID)
    if not importID then return end
    scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.id == importID
    end, ScrollBoxConstants.AlignNearest)
end

-- Opens the import dialog; on success refreshes the list and selects the new
-- container.
function ImportList:BeginImport()
    ImportDialog:Show({
        onImported = function(importID)
            ImportList:Refresh()
            if importID then
                ImportList:Select(importID)
                ImportList:ScrollToImport(importID)
            end
        end,
    })
end
