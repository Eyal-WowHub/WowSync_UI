local _, addon = ...

--[[
    ProfileList object (left panel).

    Fills an injected region with a title, a Save button, and a scrollable list
    of profiles (one ProfileRow each). Owns the selection state and exposes it
    through callbacks; never leaks its frames.

    addon:GetObject("ProfileList"):Build(region)
        -> self {
            OnSelect(callback),       -- callback(profileName or nil)
            OnSave(callback),         -- callback(); open the save dialog
            Refresh(),
            GetSelected() -> profileName or nil,
            ClearSelection(),
        }
]]

local ProfileList = addon:NewObject("ProfileList")
local ProfileRow = addon:GetObject("ProfileRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local pm
local scrollBox
local saveButton
local selectedProfileName = nil
local onSelectionChanged = nil
local onSaveRequested = nil

function ProfileList:Build(region)
    C:IsTable(region, 2)

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
    title:SetText(L["Profiles"])

    -- Save button, top-right of the header (aligned with the title). The note
    -- is collected by the save dialog, so the header only needs the button.
    saveButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    saveButton:SetPoint("TOPRIGHT", -10, -6)
    saveButton:SetSize(56, 22)
    saveButton:SetText(L["Save"])
    saveButton:SetScript("OnClick", function()
        if not saveButton:IsEnabled() then return end
        if onSaveRequested then onSaveRequested() end
    end)

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
            return selectedProfileName
        end,
        Select = function(name)
            ProfileList:Select(name)
        end,
    }

    -- List view
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UI.List.ItemHeight)
    view:SetPadding(0, 0, 0, 0, UI.List.ItemPadding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.initialized then
            ProfileRow:Build(row, rowContext)
            row.initialized = true
        end
        ProfileRow:Update(row, elementData, rowContext)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    -- The Save button is only meaningful when the logged-in character has
    -- something captured; track that live and on first build.
    WowSync:RegisterEvent("WOWSYNC_CURRENT_CHANGED", function()
        ProfileList:SetSaveEnabled(pm:HasCurrent())
    end)
    self:SetSaveEnabled(pm:HasCurrent())

    return self
end

function ProfileList:OnSelect(callback)
    onSelectionChanged = callback
end

function ProfileList:OnSave(callback)
    onSaveRequested = callback
end

-- Enable or disable the header's Save button.
function ProfileList:SetSaveEnabled(enabled)
    if saveButton then
        saveButton:SetEnabled(enabled)
    end
end

function ProfileList:Refresh()
    -- Every character with saved history and/or a captured Current, the
    -- logged-in one first. Each is one row; its detail panel shows the current
    -- head plus saved history.
    local characters = pm:ListCharacters()

    local dataProvider = CreateDataProvider()
    local present = {}

    for _, entry in ipairs(characters) do
        present[entry.Key] = true
        dataProvider:Insert({
            id = entry.Key,
            classID = entry.ClassID,
            character = entry.Key,
            timestamp = entry.LastSeen,
            isCurrent = entry.IsCurrent,
        })
    end

    scrollBox:SetDataProvider(dataProvider)

    -- Drop the selection if the selected character is no longer listed.
    if selectedProfileName and not present[selectedProfileName] then
        selectedProfileName = nil
        if onSelectionChanged then
            onSelectionChanged(nil)
        end
    end

    self:SetSaveEnabled(pm:HasCurrent())
end

function ProfileList:Select(profileName)
    selectedProfileName = profileName
    scrollBox:ForEachFrame(function(frame)
        if frame.profileName == selectedProfileName then
            frame.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
        else
            frame.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
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
        return data.id == name
    end, ScrollBoxConstants.AlignNearest)
end

function ProfileList:ClearSelection()
    self:Select(nil)
end
