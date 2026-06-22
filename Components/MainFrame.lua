local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    MainFrame object.

    The top-level movable window shell and composition root. Owns the backdrop,
    title bar, drag and escape handling, lays out the left/right panel regions,
    builds the ProfileList and ProfileDetails objects into them, and wires them
    together. Built lazily on the first Toggle().

    addon:GetObject("MainFrame"):Toggle()
]]

local MainFrame = addon:NewObject("MainFrame")
local TitleBar = addon:GetObject("TitleBar")
local ProfileList = addon:GetObject("ProfileList")
local ProfileDetails = addon:GetObject("ProfileDetails")

local frame
local profileList, profileDetails

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

    -- Left panel region
    local leftSlot = CreateFrame("Frame", nil, frame)
    leftSlot:SetPoint("TOPLEFT", 8, -28)
    leftSlot:SetPoint("BOTTOMLEFT", 8, 8)
    leftSlot:SetWidth(UI.LeftPanelWidth)

    -- Right panel region
    local rightSlot = CreateFrame("Frame", nil, frame)
    rightSlot:SetPoint("TOPLEFT", leftSlot, "TOPRIGHT", 6, 0)
    rightSlot:SetPoint("BOTTOMRIGHT", -8, 8)

    -- Build and wire the panels
    profileList = ProfileList:Build(leftSlot)
    profileDetails = ProfileDetails:Build(rightSlot)

    profileList:OnSelect(function(profileName)
        profileDetails:SetProfile(profileName)
    end)

    profileList:OnSave(function(name)
        local pm = WowSync:GetProfileManager()
        local snapshot, reason = pm:Save(name)
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
    end)

    profileDetails:OnRefresh(function()
        profileList:Refresh()
        profileList:ClearSelection()
        profileDetails:SetProfile(nil)
    end)

    -- CreateFrame leaves the window shown; start hidden so the first Toggle()
    -- reveals it instead of hiding it.
    frame:Hide()
end

function MainFrame:Toggle()
    Build()

    if frame:IsShown() then
        frame:Hide()
    else
        profileList:Refresh()
        frame:Show()
    end
end
