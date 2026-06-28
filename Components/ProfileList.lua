local _, addon = ...

--[[
    ProfileList object (left panel).

    Fills an injected region with a title and a scrollable list of profiles (one
    ProfileRow each). Owns the selection state and exposes it through callbacks;
    never leaks its frames.

    addon:GetObject("ProfileList"):Build(region)
        -> self {
            OnSelect(callback),       -- callback(profileName or nil)
            Refresh(),
            GetSelected() -> profileName or nil,
            ClearSelection(),
            SelectCurrentWhenNone(),
        }
]]

local ProfileList = addon:NewObject("ProfileList")
local ProfileRow = addon:GetObject("ProfileRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local CharacterManager = WowSync:GetCharacterManager()

local scrollBox
local selectedProfileName = nil
local currentProfileName = nil
local onSelectionChanged = nil

-- Height of a realm group header row; the extra space over the text gives each
-- group a consistent leading gap. The character rows below use UI.List.ItemHeight.
local REALM_HEADER_HEIGHT = 26

-- Split a "Name - Realm" profile key on its first dash; realm is empty when the
-- key carries no dash.
local function SplitNameRealm(key)
    local name, realm = key:match("^(.-)%s*%-%s*(.*)$")
    if name then
        return strtrim(name), strtrim(realm)
    end
    return strtrim(key), ""
end

function ProfileList:Build(region)
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
    title:SetText(L["Profiles"])

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
    view:SetElementExtentCalculator(function(_, elementData)
        if elementData.kind == "realm" then
            return REALM_HEADER_HEIGHT
        end
        return UI.List.ItemHeight
    end)
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

    return self
end

function ProfileList:OnSelect(callback)
    onSelectionChanged = callback
end

function ProfileList:Refresh()
    -- Every character with saved history and/or a captured Current, grouped
    -- under its realm. The logged-in character's realm leads, then realms by
    -- most-recently-seen; within a realm the order GetSavedCharacters returns is
    -- kept (logged-in character first, then by recency).
    local characters = CharacterManager:GetSavedCharacters()

    local groups = {}
    local realmOrder = {}
    local visibleProfiles = {}
    currentProfileName = nil

    for _, character in ipairs(characters) do
        visibleProfiles[character.Key] = true

        local name, realm = SplitNameRealm(character.Key)
        if realm == "" then
            realm = L["Unknown"]
        end

        local group = groups[realm]
        if not group then
            group = { realm = realm, characters = {}, lastSeen = 0, hasCurrent = false }
            groups[realm] = group
            tinsert(realmOrder, group)
        end

        tinsert(group.characters, {
            id = character.Key,
            name = name,
            classID = character.ClassID,
            timestamp = character.LastSeen,
            isCurrent = character.IsCurrent,
        })
        group.lastSeen = math.max(group.lastSeen, character.LastSeen or 0)
        if character.IsCurrent then
            group.hasCurrent = true
            currentProfileName = character.Key
        end
    end

    table.sort(realmOrder, function(left, right)
        if left.hasCurrent ~= right.hasCurrent then
            return left.hasCurrent
        end
        return left.lastSeen > right.lastSeen
    end)

    local dataProvider = CreateDataProvider()
    for _, group in ipairs(realmOrder) do
        dataProvider:Insert({ kind = "realm", realm = group.realm })
        for _, entry in ipairs(group.characters) do
            dataProvider:Insert({
                kind = "character",
                id = entry.id,
                classID = entry.classID,
                character = entry.name,
                timestamp = entry.timestamp,
                isCurrent = entry.isCurrent,
            })
        end
    end

    scrollBox:SetDataProvider(dataProvider)

    -- Drop the selection if the selected character is no longer listed.
    if selectedProfileName and not visibleProfiles[selectedProfileName] then
        selectedProfileName = nil
        if onSelectionChanged then
            onSelectionChanged(nil)
        end
    end
end

function ProfileList:Select(profileName)
    selectedProfileName = profileName
    scrollBox:ForEachFrame(function(frame)
        if not frame.profileName then return end
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

-- Select the logged-in character when nothing is selected yet, so opening the
-- window lands on a useful profile.
function ProfileList:SelectCurrentWhenNone()
    if selectedProfileName or not currentProfileName then return end
    self:Select(currentProfileName)
    self:ScrollToProfile(currentProfileName)
end

-- Scroll the list so the named profile is visible (no-op if already on screen).
function ProfileList:ScrollToProfile(profileName)
    if not profileName then return end
    scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.id == profileName
    end, ScrollBoxConstants.AlignNearest)
end

function ProfileList:ClearSelection()
    self:Select(nil)
end
