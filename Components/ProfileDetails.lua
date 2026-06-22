local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    ProfileDetails object (right panel).

    Orchestrates the detail view for a selected profile. Composes ProfileHeader,
    ModuleList, ActionBar and RevertBanner, and drives the WowSync actions
    (apply/revert/delete/rename) routed through the Dialogs object. Holds no
    widget-building code of its own beyond layout regions and the empty state.

    addon:GetObject("ProfileDetails"):Build(region)
        -> self {
            SetProfile(profileName or nil),
            OnRefresh(callback),   -- called after delete/rename
        }
]]

local ProfileDetails = addon:NewObject("ProfileDetails")
local Dialogs = addon:GetObject("Dialogs")
local ProfileHeader = addon:GetObject("ProfileHeader")
local ModuleList = addon:GetObject("ModuleList")
local RevertBanner = addon:GetObject("RevertBanner")
local ActionBar = addon:GetObject("ActionBar")

local pm
local currentProfileName = nil
local onRefreshNeeded = nil
local allSelected = true

local content, emptyLabel
local header, moduleList, actionBar, banner, selectAllButton

-- Reflect the current revert point in whichever view is visible
local function ApplyRevertState()
    local hasRevert = WowSync:HasRevertPoint()
    if content:IsShown() then
        actionBar:SetRevertEnabled(hasRevert)
    else
        banner:SetState(hasRevert, hasRevert and WowSync:GetRevertInfo() or nil)
    end
end

-- Action handlers

local function DoRevert()
    local info = WowSync:GetRevertInfo()
    local results = WowSync:Revert()
    if results then
        WowSync:Print(L["Reverted changes from profile 'X':"]:format(info and info.ProfileName or L["Unknown"]))
        for name, result in pairs(results) do
            if result.applied then
                WowSync:Print(L["  X: reverted"]:format(name))
            end
        end
    end
    ApplyRevertState()
end

local function DoApply()
    if not currentProfileName then return end

    local selected = moduleList:GetSelected()
    if not next(selected) then
        WowSync:Print(L["No modules selected."])
        return
    end

    local results = pm:Apply(currentProfileName, selected)
    if results and next(results) then
        for name, result in pairs(results) do
            if result.applied then
                local msg = L["X: applied"]:format(name)
                if result.warning then
                    msg = L["X (Y)"]:format(msg, result.warning)
                end
                WowSync:Print(msg)
            else
                WowSync:Print(L["X: skipped - Y"]:format(name, result.reason or L["unknown"]))
            end
        end
    else
        WowSync:Print(L["Nothing to apply."])
    end

    ApplyRevertState()
end

local function DoDelete()
    if currentProfileName then
        pm:Delete(currentProfileName)
        currentProfileName = nil
        if onRefreshNeeded then
            onRefreshNeeded()
        end
    end
end

local function DoRename(newName)
    if newName ~= "" and currentProfileName then
        if pm:Rename(currentProfileName, newName) then
            currentProfileName = newName
            if onRefreshNeeded then
                onRefreshNeeded()
            end
        else
            WowSync:Print(L["Rename failed — name may already exist."])
        end
    end
end

local function RequestRevert()
    local info = WowSync:GetRevertInfo()
    if info then
        Dialogs:ConfirmRevert(info.ProfileName, DoRevert)
    end
end

function ProfileDetails:Build(region)
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

    -- Empty state label
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetText(L["Select a profile"])

    -- Empty-state revert banner (covers the panel; behind the content frame)
    local bannerSlot = CreateFrame("Frame", nil, root)
    bannerSlot:SetAllPoints(root)

    -- Detail content (hidden until a profile is selected)
    content = CreateFrame("Frame", nil, root)
    content:SetAllPoints()
    content:Hide()

    -- Header region
    local headerSlot = CreateFrame("Frame", nil, content)
    headerSlot:SetPoint("TOPLEFT", 10, -8)
    headerSlot:SetPoint("TOPRIGHT", -10, -8)
    headerSlot:SetHeight(38)
    header = ProfileHeader:Build(headerSlot)

    -- Separator
    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", headerSlot, "BOTTOMLEFT", -2, -6)
    separator:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(UI.SeparatorColor))

    -- "Modules to apply" label
    local modulesLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modulesLabel:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    modulesLabel:SetText(L["Modules to apply:"])

    -- Select All / Deselect All
    selectAllButton = CreateFrame("Button", nil, content)
    selectAllButton:SetPoint("TOPRIGHT", separator, "BOTTOMRIGHT", 0, -6)
    selectAllButton:SetNormalFontObject("GameFontHighlightSmall")
    selectAllButton:SetHighlightFontObject("GameFontNormalSmall")

    -- Size to the wider of the two labels so the toggled text never overflows
    -- the clickable area.
    selectAllButton:SetText(L["Deselect All"])
    local labelFontString = selectAllButton:GetFontString()
    local labelWidth = labelFontString:GetStringWidth()
    selectAllButton:SetText(L["Select All"])
    labelWidth = math.max(labelWidth, labelFontString:GetStringWidth())
    selectAllButton:SetSize(labelWidth + 8, 18)

    -- Module list region
    local moduleSlot = CreateFrame("Frame", nil, content)
    moduleSlot:SetPoint("TOPLEFT", modulesLabel, "BOTTOMLEFT", 0, -6)
    moduleSlot:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    moduleSlot:SetPoint("BOTTOM", content, "BOTTOM", 0, 44)
    moduleList = ModuleList:Build(moduleSlot, { profileManager = pm })

    -- Action bar region
    local actionSlot = CreateFrame("Frame", nil, content)
    actionSlot:SetPoint("BOTTOMLEFT", 10, 10)
    actionSlot:SetPoint("BOTTOMRIGHT", -10, 10)
    actionSlot:SetHeight(24)

    -- Composed children

    banner = RevertBanner:Build(bannerSlot, {
        onRevert = RequestRevert,
    })

    actionBar = ActionBar:Build(actionSlot, {
        onApply = DoApply,
        onRevert = RequestRevert,
        onRename = function()
            if currentProfileName then
                Dialogs:PromptRename(currentProfileName, DoRename)
            end
        end,
        onDelete = function()
            if currentProfileName then
                Dialogs:ConfirmDelete(currentProfileName, DoDelete)
            end
        end,
    })

    -- Select All toggle
    selectAllButton:SetScript("OnClick", function()
        allSelected = not allSelected
        moduleList:SetAllChecked(allSelected)
        selectAllButton:SetText(allSelected and L["Deselect All"] or L["Select All"])
    end)

    return self
end

function ProfileDetails:SetProfile(profileName)
    currentProfileName = profileName

    if not profileName then
        content:Hide()
        emptyLabel:Show()
        ApplyRevertState()
        return
    end

    local profile = pm:GetProfile(profileName)
    if not profile then
        content:Hide()
        emptyLabel:Show()
        ApplyRevertState()
        return
    end

    emptyLabel:Hide()
    banner:SetState(false)
    content:Show()

    header:SetProfile(profileName, profile.Meta)
    moduleList:SetProfile(profile)
    ApplyRevertState()

    allSelected = true
    selectAllButton:SetText(L["Deselect All"])
end

function ProfileDetails:OnRefresh(callback)
    onRefreshNeeded = callback
end
