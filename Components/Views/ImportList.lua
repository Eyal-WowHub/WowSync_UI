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
local PopupDialogs = addon:GetObject("PopupDialogs")
local List = addon:GetObject("List")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local list
local deleteButton
local onSelectionChanged = nil

-- Height of a class group header row; the extra space over the text gives each
-- group a consistent leading gap. The container rows use UI.List.ItemHeight.
local CLASS_HEADER_HEIGHT = 26

local function CanDeleteSelectedImport()
    local importID = list:GetSelected()
    return importID ~= nil and ImportManager:GetImport(importID) ~= nil
end

local function UpdateDeleteEnabled()
    if deleteButton then
        deleteButton:SetEnabled(CanDeleteSelectedImport())
    end
end

function ImportList:Build(region)
    C:IsTable(region, 2)

    list = List:Build(region, {
        title = L["Imports"],
        rowRenderer = ImportRow,
        extent = function(elementData)
            if elementData.kind == "class" then
                return CLASS_HEADER_HEIGHT
            end
            return UI.List.ItemHeight
        end,
        rowContext = {
            Rename = function(importID, name)
                if not ImportManager:RenameImport(importID, name) then return false end
                ImportList:Refresh()
                ImportList:Select(importID)
                return true
            end,
        },
    })

    list:OnSelect(function(importID)
        UpdateDeleteEnabled()
        if onSelectionChanged then
            onSelectionChanged(importID)
        end
    end)

    -- Import button, top-right of the header.
    local importButton = Button:Build({
        parent = list,
        anchor = function(button)
            button:SetPoint("TOPRIGHT", -10, -6)
        end,
        width = 64,
        height = 24,
        text = L["Import"],
        onClick = function() ImportList:BeginImport() end,
    })

    -- Import delete button, bottom-left of the panel.
    deleteButton = Button:Build({
        parent = list,
        anchor = function(button)
            button:SetPoint("BOTTOMLEFT", 10, 10)
        end,
        width = 110,
        height = 24,
        text = L["Delete"],
        enabled = false,
        onClick = function()
            if not CanDeleteSelectedImport() then return end

            local importID = list:GetSelected()
            local record = ImportManager:GetImport(importID)
            if not record then return end

            PopupDialogs:ConfirmDeleteImport(record.Name, function()
                ImportManager:DeleteImport(importID)
                ImportList:Refresh()
            end)
        end,
    })

    UpdateDeleteEnabled()

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

    list:SetData(dataProvider, visibleImports)

    UpdateDeleteEnabled()
end

function ImportList:Select(importID)
    list:Select(importID)
end

function ImportList:GetSelected()
    return list:GetSelected()
end

function ImportList:ClearSelection()
    list:ClearSelection()
end

-- Scrolls the list to bring the given container into view.
function ImportList:ScrollToImport(importID)
    list:ScrollTo(importID)
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
