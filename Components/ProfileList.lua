local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    ProfileList object (left panel).

    Fills an injected region with a title, a SaveBar, and a scrollable list of
    profiles (one ProfileRow each). Owns the selection state and exposes it
    through callbacks; never leaks its frames.

    addon:GetObject("ProfileList"):Build(region)
        -> self {
            OnSelect(callback),       -- callback(profileName or nil)
            OnSave(callback),         -- callback(name)
            Refresh(),
            GetSelected() -> profileName or nil,
            ClearSelection(),
        }
]]

local ProfileList = addon:NewObject("ProfileList")
local SaveBar = addon:GetObject("SaveBar")
local ProfileRow = addon:GetObject("ProfileRow")

local pm
local scrollBox
local selectedProfileName = nil
local onSelectionChanged = nil
local onSaveRequested = nil

function ProfileList:Build(region)
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
    title:SetText(L["Profiles"])

    -- Save bar region
    local saveSlot = CreateFrame("Frame", nil, root)
    saveSlot:SetPoint("TOPLEFT", 10, -32)
    saveSlot:SetPoint("RIGHT", root, "RIGHT", -10, 0)
    saveSlot:SetHeight(22)
    SaveBar:Build(saveSlot, {
        onSave = function(name)
            if onSaveRequested then onSaveRequested(name) end
        end,
    })

    -- Scroll area
    scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -60)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    -- Shared selection context for the pooled rows
    local rowContext = {
        GetSelected = function()
            return selectedProfileName
        end,
        Select = function(name)
            ProfileList:Select(name)
        end,
    }

    -- List view
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UI.ListItemHeight)
    view:SetPadding(0, 0, 0, 0, UI.ListItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            ProfileRow:Build(row, rowContext)
            row.initialized = true
        end
        ProfileRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return self
end

function ProfileList:OnSelect(callback)
    onSelectionChanged = callback
end

function ProfileList:OnSave(callback)
    onSaveRequested = callback
end

function ProfileList:Refresh()
    local profiles = pm:GetProfiles()

    local dataProvider = CreateDataProvider()
    local sorted = {}

    for name, profile in pairs(profiles) do
        tinsert(sorted, { name = name, meta = profile.Meta })
    end

    table.sort(sorted, function(a, b)
        return a.name < b.name
    end)

    for _, entry in ipairs(sorted) do
        dataProvider:Insert(entry)
    end

    scrollBox:SetDataProvider(dataProvider)

    -- Restore selection if the profile still exists
    if selectedProfileName and not profiles[selectedProfileName] then
        selectedProfileName = nil
        if onSelectionChanged then
            onSelectionChanged(nil)
        end
    end
end

function ProfileList:Select(profileName)
    selectedProfileName = profileName
    scrollBox:ForEachFrame(function(frame)
        if frame.profileName == selectedProfileName then
            frame.bg:SetColorTexture(UI.RowSelectedColor:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
    if onSelectionChanged then onSelectionChanged(selectedProfileName) end
end

function ProfileList:GetSelected()
    return selectedProfileName
end

-- Scroll the list so the named profile is visible (no-op if already on screen).
function ProfileList:ScrollToProfile(name)
    if not name then return end
    scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.name == name
    end, ScrollBoxConstants.AlignNearest)
end

function ProfileList:ClearSelection()
    self:Select(nil)
end
