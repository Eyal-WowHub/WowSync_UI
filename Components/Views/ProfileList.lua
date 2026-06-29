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
local PopupDialogs = addon:GetObject("PopupDialogs")
local List = addon:GetObject("List")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local CharacterManager = WowSync:GetCharacterManager()
local ProfileManager = WowSync:GetProfileManager()
local SnapshotHandleCache = WowSync:GetSnapshotHandleCache()
local SnapshotView = WowSync:GetSnapshotView()

local list
local deleteButton
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

local function GetDeleteLabel(profileName)
    local latestSnapshot = profileName and SnapshotHandleCache:GetLatestSaved(profileName)
    return (latestSnapshot and SnapshotView:GetCharacterInfo(latestSnapshot).Character) or profileName
end

local function CanDeleteSelectedProfile()
    return list:GetSelected() ~= nil
end

local function UpdateDeleteEnabled()
    if deleteButton then
        deleteButton:SetEnabled(CanDeleteSelectedProfile())
    end
end

function ProfileList:Build(region)
    C:IsTable(region, 2)

    list = List:Build(region, {
        title = L["Profiles"],
        rowRenderer = ProfileRow,
        extent = function(elementData)
            if elementData.kind == "realm" then
                return REALM_HEADER_HEIGHT
            end
            return UI.List.ItemHeight
        end,
    })

    list:OnSelect(function(profileName)
        UpdateDeleteEnabled()
        if onSelectionChanged then
            onSelectionChanged(profileName)
        end
    end)

    -- Profile delete button, bottom-left of the panel.
    deleteButton = Button:Build({
        parent = list,
        anchor = function(button)
            button:SetPoint("BOTTOMLEFT", 10, 10)
        end,
        width = 80,
        height = 24,
        text = L["Delete"],
        enabled = false,
        onClick = function()
            if not CanDeleteSelectedProfile() then return end

            local profileName = list:GetSelected()
            local label = GetDeleteLabel(profileName)
            PopupDialogs:ConfirmDelete(label, function()
                ProfileManager:DeleteProfile(profileName)
                ProfileList:Refresh()
            end)
        end,
    })

    UpdateDeleteEnabled()

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

    list:SetData(dataProvider, visibleProfiles)

    UpdateDeleteEnabled()
end

function ProfileList:Select(profileName)
    list:Select(profileName)
end

function ProfileList:GetSelected()
    return list:GetSelected()
end

-- Select the logged-in character when nothing is selected yet, so opening the
-- window lands on a useful profile.
function ProfileList:SelectCurrentWhenNone()
    if list:GetSelected() or not currentProfileName then return end
    list:Select(currentProfileName)
    list:ScrollTo(currentProfileName)
end

-- Scroll the list so the named profile is visible (no-op if already on screen).
function ProfileList:ScrollToProfile(profileName)
    list:ScrollTo(profileName)
end

function ProfileList:ClearSelection()
    list:ClearSelection()
end
