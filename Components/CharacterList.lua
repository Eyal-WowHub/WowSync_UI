local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    CharacterList object (left panel, Characters view).

    Fills an injected region with a title and a scrollable list of the other
    characters that have a captured setup (one CharacterRow each). Owns the
    selection state and exposes it through callbacks; never leaks its frames.
    Shows a placeholder when no other characters have been seen yet.

    addon:GetObject("CharacterList"):Build(region)
        -> self {
            OnSelect(callback),   -- callback(elementData or nil)
            Refresh(),
            Select(elementData),
            GetSelected() -> charKey or nil,
            ClearSelection(),
        }
]]

local CharacterList = addon:NewObject("CharacterList")
local CharacterRow = addon:GetObject("CharacterRow")

local pm
local scrollBox
local emptyLabel
local selectedKey = nil
local onSelectionChanged = nil

function CharacterList:Build(region)
    pm = WowSync:GetProfileManager()

    local root = CreateFrame("Frame", nil, region, "BackdropTemplate")
    root:SetAllPoints(region)
    root:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(unpack(UI.PanelBackdropColor))
    root:SetBackdropBorderColor(unpack(UI.PanelBorderColor))

    -- Title
    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["Characters"])

    -- Placeholder shown when there are no other characters to list
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLabel:SetPoint("TOPLEFT", 12, -40)
    emptyLabel:SetPoint("TOPRIGHT", -12, -40)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:SetText(L["No other characters yet"])
    emptyLabel:Hide()

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
            return selectedKey
        end,
        Select = function(elementData)
            CharacterList:Select(elementData)
        end,
    }

    -- List view
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UI.ListItemHeight)
    view:SetPadding(0, 0, 0, 0, UI.ListItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            CharacterRow:Build(row, rowContext)
            row.initialized = true
        end
        CharacterRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return self
end

function CharacterList:OnSelect(callback)
    onSelectionChanged = callback
end

function CharacterList:Refresh()
    local characters = pm:GetOtherCharacters()

    local dataProvider = CreateDataProvider()
    for _, entry in ipairs(characters) do
        dataProvider:Insert(entry)
    end
    scrollBox:SetDataProvider(dataProvider)

    emptyLabel:SetShown(#characters == 0)

    -- Drop the selection if the selected character is no longer listed.
    if selectedKey then
        local stillListed = false
        for _, entry in ipairs(characters) do
            if entry.Key == selectedKey then
                stillListed = true
                break
            end
        end
        if not stillListed then
            selectedKey = nil
            if onSelectionChanged then
                onSelectionChanged(nil)
            end
        end
    end
end

function CharacterList:Select(elementData)
    selectedKey = elementData and elementData.Key or nil
    scrollBox:ForEachFrame(function(frame)
        if frame.charKey == selectedKey then
            frame.bg:SetColorTexture(UI.RowSelectedColor:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
    if onSelectionChanged then onSelectionChanged(elementData) end
end

function CharacterList:GetSelected()
    return selectedKey
end

function CharacterList:ClearSelection()
    self:Select(nil)
end
