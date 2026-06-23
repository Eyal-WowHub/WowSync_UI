local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    MainFrame object.

    The top-level movable window shell and composition root. Owns the backdrop,
    title bar, drag and escape handling, and a tab strip that switches between
    two top-level views: Profiles (ProfileList + ProfileDetails) and Characters
    (CharacterList + CharacterDetails). Builds and wires those panels, and is
    built lazily on the first Toggle().

    addon:GetObject("MainFrame"):Toggle()
]]

local MainFrame = addon:NewObject("MainFrame")
local TitleBar = addon:GetObject("TitleBar")
local ProfileList = addon:GetObject("ProfileList")
local ProfileDetails = addon:GetObject("ProfileDetails")
local CharacterList = addon:GetObject("CharacterList")
local CharacterDetails = addon:GetObject("CharacterDetails")
local SaveDialog = addon:GetObject("SaveDialog")

local frame
local profileList, profileDetails
local characterList, characterDetails
local showView

-- A slim tab that switches the active top-level view. Active tabs show an accent
-- underline and a highlighted background; inactive tabs are dimmed.
local function CreateTab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(110, UI.TabStripHeight)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(label)

    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
    tab.underline:SetHeight(2)
    tab.underline:SetColorTexture(UI.TabUnderlineColor:GetRGBA())
    tab.underline:Hide()

    tab.active = false

    function tab:SetActive(active)
        self.active = active
        self.underline:SetShown(active)
        self.text:SetFontObject(active and "GameFontNormal" or "GameFontDisable")
        self.bg:SetColorTexture((active and UI.RowSelectedColor or UI.RowNormalColor):GetRGBA())
    end

    tab:SetScript("OnEnter", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.RowHoverColor:GetRGBA())
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
    tab:SetScript("OnClick", onClick)

    return tab
end

local function Build()
    if frame then return end

    frame = CreateFrame("Frame", "WowSyncUIFrame", UIParent, "BackdropTemplate")
    frame:SetSize(UI.FrameWidth, UI.FrameHeight)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(UI.MainBackdropColor))
    frame:SetBackdropBorderColor(unpack(UI.MainBorderColor))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Registering with UISpecialFrames makes ESC close the window.
    tinsert(UISpecialFrames, "WowSyncUIFrame")

    -- Title bar region
    local titleSlot = CreateFrame("Frame", nil, frame)
    titleSlot:SetPoint("TOPLEFT", 0, 0)
    titleSlot:SetPoint("TOPRIGHT", 0, 0)
    titleSlot:SetHeight(UI.TitleBarHeight)
    TitleBar:Build(titleSlot, {
        title = "|c" .. UI.AccentHex .. "WowSync|r",
        onClose = function() frame:Hide() end,
    })

    -- Tab strip (Profiles | Characters)
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT", 8, -28)
    tabStrip:SetPoint("TOPRIGHT", -8, -28)
    tabStrip:SetHeight(UI.TabStripHeight)

    local profilesTab = CreateTab(tabStrip, L["Profiles"], function() showView("profiles") end)
    profilesTab:SetPoint("LEFT", 0, 0)

    local charactersTab = CreateTab(tabStrip, L["Characters"], function() showView("characters") end)
    charactersTab:SetPoint("LEFT", profilesTab, "RIGHT", 4, 0)

    local contentTop = -(28 + UI.TabStripHeight)

    -- Profiles view: profile list (left) + profile details (right)
    local profilesView = CreateFrame("Frame", nil, frame)
    profilesView:SetPoint("TOPLEFT", 8, contentTop)
    profilesView:SetPoint("BOTTOMRIGHT", -8, 8)

    local leftSlot = CreateFrame("Frame", nil, profilesView)
    leftSlot:SetPoint("TOPLEFT", 0, 0)
    leftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    leftSlot:SetWidth(UI.LeftPanelWidth)

    local rightSlot = CreateFrame("Frame", nil, profilesView)
    rightSlot:SetPoint("TOPLEFT", leftSlot, "TOPRIGHT", 6, 0)
    rightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    profileList = ProfileList:Build(leftSlot)
    profileDetails = ProfileDetails:Build(rightSlot)

    profileList:OnSelect(function(profileName)
        profileDetails:SetProfile(profileName)
    end)

    -- Capture a snapshot (optionally a subset, optionally a note) and reflect it
    -- in the list. Shared by the quick Save and the Save… dialog.
    local function DoSave(name, moduleSet, note)
        local pm = WowSync:GetProfileManager()
        local snapshot, reason = pm:Save(name, moduleSet, note)
        if snapshot then
            WowSync:Print(L["Profile 'X' saved."]:format(name))
            profileList:Refresh()

            -- Select the freshly saved profile so the list highlights it and
            -- the detail panel updates through the selection callback.
            profileList:Select(name)
            profileList:ScrollToProfile(name)
        elseif reason == "unchanged" then
            WowSync:Print(L["Profile 'X': nothing changed."]:format(name))
        end
    end

    profileList:OnSave(function(name)
        DoSave(name)
    end)

    profileList:OnSaveAdvanced(function(name)
        SaveDialog:Show({
            profileName = name,
            onConfirm = function(moduleSet, note)
                DoSave(name, moduleSet, note)
            end,
        })
    end)

    profileDetails:OnRefresh(function()
        profileList:Refresh()
        profileList:ClearSelection()
        profileDetails:SetProfile(nil)
    end)

    -- Characters view: character list (left) + character details (right)
    local charactersView = CreateFrame("Frame", nil, frame)
    charactersView:SetPoint("TOPLEFT", 8, contentTop)
    charactersView:SetPoint("BOTTOMRIGHT", -8, 8)
    charactersView:Hide()

    local charLeftSlot = CreateFrame("Frame", nil, charactersView)
    charLeftSlot:SetPoint("TOPLEFT", 0, 0)
    charLeftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    charLeftSlot:SetWidth(UI.LeftPanelWidth)

    local charRightSlot = CreateFrame("Frame", nil, charactersView)
    charRightSlot:SetPoint("TOPLEFT", charLeftSlot, "TOPRIGHT", 6, 0)
    charRightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    characterList = CharacterList:Build(charLeftSlot)
    characterDetails = CharacterDetails:Build(charRightSlot)

    characterList:OnSelect(function(entry)
        characterDetails:SetCharacter(entry)
    end)

    -- A cross-character save creates or updates a profile, so refresh the
    -- profile list to reflect it the next time that view is shown.
    characterDetails:OnSaved(function()
        profileList:Refresh()
    end)

    -- Switch the active top-level view and reflect it in the tab visuals.
    showView = function(which)
        if which == "characters" then
            profilesView:Hide()
            charactersView:Show()
            characterList:Refresh()
            characterList:ClearSelection()
        else
            which = "profiles"
            charactersView:Hide()
            profilesView:Show()
            profileList:Refresh()
        end
        profilesTab:SetActive(which == "profiles")
        charactersTab:SetActive(which == "characters")
    end

    -- CreateFrame leaves the window shown; start hidden so the first Toggle()
    -- reveals it instead of hiding it.
    frame:Hide()
end

function MainFrame:Toggle()
    Build()

    if frame:IsShown() then
        frame:Hide()
    else
        showView("profiles")
        frame:Show()
    end
end
