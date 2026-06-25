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

local SnapshotManager = WowSync:GetSnapshotManager()
local CharacterManager = WowSync:GetCharacterManager()

local scrollBox
local saveButton
local selectedProfileName = nil
local onSelectionChanged = nil
local onSaveRequested = nil
local savingStartedAt = nil

-- Keep the spinner up at least this long so a fast save is still perceptible,
-- then let the confirmation flourish linger for this long before restoring.
local SAVE_SPINNER_MIN_SECONDS = 0.5
local SAVED_FLOURISH_SECONDS = 0.9

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

    -- A loading spinner shown over the button while a save is in flight. The save
    -- work is deferred a frame, so the animation is actually visible. Scaled down
    -- from the 142px shared template art.
    local spinner = CreateFrame("Frame", nil, saveButton, "SpinnerTemplate")
    spinner:SetSize(18, 18)
    spinner:SetPoint("CENTER")
    spinner:Hide()
    saveButton.spinner = spinner

    -- A brief "Saved" confirmation that rises and fades after a successful save.
    local savedText = saveButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    savedText:SetPoint("CENTER")
    savedText:SetText(L["Saved"])
    savedText:SetTextColor(0.3, 1, 0.3)
    savedText:Hide()
    saveButton.savedText = savedText

    local flourish = savedText:CreateAnimationGroup()
    local fade = flourish:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.2)
    fade:SetDuration(SAVED_FLOURISH_SECONDS - 0.2)
    local rise = flourish:CreateAnimation("Translation")
    rise:SetOffset(0, 14)
    rise:SetDuration(SAVED_FLOURISH_SECONDS)
    flourish:SetScript("OnPlay", function() savedText:Show() end)
    flourish:SetScript("OnStop", function() savedText:Hide() end)
    flourish:SetScript("OnFinished", function() savedText:Hide() end)
    saveButton.flourish = flourish

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
        ProfileList:SetSaveEnabled(SnapshotManager:HasCapturedGameData())
    end)
    self:SetSaveEnabled(SnapshotManager:HasCapturedGameData())

    -- Animate the button for the duration of any save (including the command
    -- line), then show a brief confirmation.
    WowSync:RegisterEvent("WOWSYNC_SAVE_STARTED", function()
        ProfileList:BeginSaving()
    end)
    WowSync:RegisterEvent("WOWSYNC_SAVE_FINISHED", function(_, _, storedSnapshot)
        ProfileList:EndSaving(storedSnapshot)
    end)

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

-- Enter the saving state: hide the label, spin, and lock the button until the
-- save finishes.
function ProfileList:BeginSaving()
    if not saveButton then
        return
    end
    savingStartedAt = GetTime()
    saveButton.flourish:Stop()
    saveButton:SetEnabled(false)
    saveButton:SetText("")
    saveButton.spinner:Show()
end

-- Leave the saving state once the spinner has shown for its minimum time, then
-- play the confirmation flourish (only for a save that actually stored) and
-- restore the button.
function ProfileList:EndSaving(storedSnapshot)
    if not saveButton then
        return
    end
    local startedAt = savingStartedAt
    local elapsed = GetTime() - (startedAt or 0)
    local remaining = math.max(0, SAVE_SPINNER_MIN_SECONDS - elapsed)

    C_Timer.After(remaining, function()
        if not saveButton then
            return
        end
        -- A newer save began while this one was waiting out its minimum spin
        -- time; let that cycle own the button instead of restoring it here.
        if savingStartedAt ~= startedAt then
            return
        end
        saveButton.spinner:Hide()
        saveButton:SetText(L["Save"])
        ProfileList:SetSaveEnabled(SnapshotManager:HasCapturedGameData())
        if storedSnapshot then
            saveButton.flourish:Restart()
        end
    end)
end

function ProfileList:Refresh()
    -- Every character with saved history and/or a captured Current, the
    -- logged-in one first. Each is one row; its detail panel shows the current
    -- head plus saved history.
    local characters = CharacterManager:GetSavedCharacters()

    local dataProvider = CreateDataProvider()
    local visibleProfiles = {}

    for _, character in ipairs(characters) do
        visibleProfiles[character.Key] = true
        dataProvider:Insert({
            id = character.Key,
            classID = character.ClassID,
            character = character.Key,
            timestamp = character.LastSeen,
            isCurrent = character.IsCurrent,
        })
    end

    scrollBox:SetDataProvider(dataProvider)

    -- Drop the selection if the selected character is no longer listed.
    if selectedProfileName and not visibleProfiles[selectedProfileName] then
        selectedProfileName = nil
        if onSelectionChanged then
            onSelectionChanged(nil)
        end
    end

    self:SetSaveEnabled(SnapshotManager:HasCapturedGameData())
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
function ProfileList:ScrollToProfile(profileName)
    if not profileName then return end
    scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.id == profileName
    end, ScrollBoxConstants.AlignNearest)
end

function ProfileList:ClearSelection()
    self:Select(nil)
end
