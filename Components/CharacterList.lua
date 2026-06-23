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
local CharacterGrouping = addon.CharacterGrouping

-- Height of a realm group header row.
local REALM_HEADER_HEIGHT = 20

-- Colour of a realm group header label.
local REALM_HEADER_COLOR = CreateColor(0.55, 0.7, 0.95, 1)

local pm
local scrollBox
local emptyLabel
local selectedKey = nil
local onSelectionChanged = nil

-- Build the realm-header label once, alongside the character visuals, so a
-- pooled row can render either kind. CharacterRow owns the character children.
local function BuildRow(row, rowContext)
    CharacterRow:Build(row, rowContext)

    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("BOTTOMLEFT", 8, 4)
    row.headerText:SetPoint("RIGHT", -6, 0)
    row.headerText:SetJustifyH("LEFT")
    row.headerText:SetTextColor(REALM_HEADER_COLOR:GetRGB())
    row.headerText:Hide()
end

local function RenderHeader(row, elementData)
    row.kind = "header"
    row.charKey = nil
    row:EnableMouse(false)
    CharacterRow:SetShown(row, false)
    row.headerText:SetText(elementData.Realm)
    row.headerText:Show()
end

local function RenderCharacter(row, elementData, rowContext)
    row.kind = "character"
    row:EnableMouse(true)
    row.headerText:Hide()
    CharacterRow:SetShown(row, true)
    CharacterRow:Update(row, elementData, rowContext)
end

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
    root:SetBackdropColor(unpack(UI.Backdrop.Panel))
    root:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))

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
    view:SetElementExtentCalculator(function(_, elementData)
        if elementData.kind == "header" then
            return REALM_HEADER_HEIGHT
        end
        return UI.List.ItemHeight
    end)
    view:SetPadding(0, 0, 0, 0, UI.List.ItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            BuildRow(row, rowContext)
            row.initialized = true
        end
        if elementData.kind == "header" then
            RenderHeader(row, elementData)
        else
            RenderCharacter(row, elementData, rowContext)
        end
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return self
end

function CharacterList:OnSelect(callback)
    onSelectionChanged = callback
end

function CharacterList:Refresh()
    local characters = pm:GetOtherCharacters()
    local sections, grouped = CharacterGrouping:Group(characters)

    -- Headers add realm context. They are pointless for a single own-realm list
    -- (the realm is implicit), but a lone foreign realm still needs its label.
    local showHeaders = grouped or (sections[1] ~= nil and not sections[1].IsOwnRealm)

    local dataProvider = CreateDataProvider()
    for _, section in ipairs(sections) do
        if showHeaders then
            dataProvider:Insert({ kind = "header", Realm = section.Realm })
        end
        for _, entry in ipairs(section.Characters) do
            entry.kind = "character"
            dataProvider:Insert(entry)
        end
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
        -- Realm headers are inert and carry no charKey; skip their highlight.
        if frame.kind ~= "character" then
            return
        end
        if frame.charKey == selectedKey then
            frame.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
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
