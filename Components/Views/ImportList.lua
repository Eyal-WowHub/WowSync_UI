local _, addon = ...

--[[
    ImportList object (left panel, Imports tab).

    Fills an injected region with a title and a scrollable list of imported
    containers (one ImportRow each), grouped by class. Owns the selection state
    and exposes it through callbacks; never leaks its frames.

    addon:GetObject("ImportList"):Build(region)
        -> import-list frame {
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

local Verbs = {}

-- Height of a class group header row; the extra space over the text gives each
-- group a consistent leading gap. The container rows use UI.List.ItemHeight.
local CLASS_HEADER_HEIGHT = 26

local function CanDeleteSelectedImport(panel)
    local importID = panel._list:GetSelected()
    return importID ~= nil and ImportManager:GetImport(importID) ~= nil
end

local function UpdateDeleteEnabled(panel)
    if panel._deleteButton then
        panel._deleteButton:SetEnabled(CanDeleteSelectedImport(panel))
    end
end

function Verbs:Constructor(config)
    local panel = self

    local list = List:Build(self, {
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
                panel:Refresh()
                panel:Select(importID)
                return true
            end,
        },
    })
    self._list = list

    list:OnSelect(function(importID)
        UpdateDeleteEnabled(panel)
        if panel._onSelectionChanged then
            panel._onSelectionChanged(importID)
        end
    end)

    -- Import button, top-right of the header.
    Button:Build({
        parent = list,
        anchor = function(button)
            button:SetPoint("TOPRIGHT", -10, -6)
        end,
        width = 64,
        height = 24,
        text = L["Import"],
        onClick = function() panel:BeginImport() end,
    })

    -- Import delete button, bottom-left of the panel.
    self._deleteButton = Button:Build({
        parent = list,
        anchor = function(button)
            button:SetPoint("BOTTOMLEFT", 10, 10)
        end,
        width = 110,
        height = 24,
        text = L["Delete"],
        enabled = false,
        onClick = function()
            if not CanDeleteSelectedImport(panel) then return end

            local importID = list:GetSelected()
            local record = ImportManager:GetImport(importID)
            if not record then return end

            PopupDialogs:ConfirmDeleteImport(record.Name, function()
                ImportManager:DeleteImport(importID)
                panel:Refresh()
            end)
        end,
    })

    UpdateDeleteEnabled(self)
end

function ImportList:Build(region)
    C:IsTable(region, 2)
    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
    }, {
        frameType = "Frame",
        verbs = Verbs,
    })
end

function Verbs:OnSelect(callback)
    self._onSelectionChanged = callback
end

function Verbs:Refresh()
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

    self._list:SetData(dataProvider, visibleImports)

    UpdateDeleteEnabled(self)
end

function Verbs:Select(importID)
    self._list:Select(importID)
end

function Verbs:GetSelected()
    return self._list:GetSelected()
end

function Verbs:ClearSelection()
    self._list:ClearSelection()
end

-- Scrolls the list to bring the given container into view.
function Verbs:ScrollToImport(importID)
    self._list:ScrollTo(importID)
end

-- Opens the import dialog; on success refreshes the list and selects the new
-- container.
function Verbs:BeginImport()
    local panel = self
    ImportDialog:Show({
        onImported = function(importID)
            panel:Refresh()
            if importID then
                panel:Select(importID)
                panel:ScrollToImport(importID)
            end
        end,
    })
end
