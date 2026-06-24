local _, addon = ...

--[[
    CharacterDetails object (right panel, Characters view).

    Shows the selected character's identity (class-colored name, class, last
    seen) and a scrollable, read-only list of the modules it has captured, plus
    a "Save to profile…" action. The action opens the SaveDialog in cross-
    character mode (profile-name field + module subset + note) and, on confirm,
    routes the chosen character's setup into the named profile.

    addon:GetObject("CharacterDetails"):Build(region)
        -> self {
            SetCharacter(elementData or nil),
            OnSaved(callback),   -- called after a successful cross-character save
        }
]]

local CharacterDetails = addon:NewObject("CharacterDetails")
local SaveDialog = addon:GetObject("SaveDialog")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local pm
local currentEntry = nil
local onSaved = nil

local content, emptyLabel
local titleText, infoText, moduleScrollBox, saveButton

-- Sorted names of the modules the current character has captured, plus the raw
-- Current table (nil when the character is unknown).
local function CurrentModuleNames()
    local current = currentEntry and pm:GetCharacterCurrent(currentEntry.Key)
    local names = {}
    if current then
        for name in pairs(current) do
            tinsert(names, name)
        end
        table.sort(names)
    end
    return names, current
end

local function SortedProfileNames()
    local names = {}
    for name in pairs(pm:GetProfiles()) do
        tinsert(names, name)
    end
    table.sort(names)
    return names
end

local function RequestSave()
    if not currentEntry then return end

    local names = CurrentModuleNames()
    if #names == 0 then
        WowSync:Print(L["That character has nothing captured yet."])
        return
    end

    SaveDialog:Show({
        pickProfile = true,
        moduleNames = names,
        existingProfiles = SortedProfileNames(),
        onConfirm = function(profileName, moduleSet, note)
            local snapshot, reason = pm:SaveFromCharacter(profileName, currentEntry.Key, moduleSet, note)
            if snapshot then
                WowSync:Print(L["Saved X to 'Y'."]:format(currentEntry.Key, profileName))
                if onSaved then
                    onSaved(profileName)
                end
            elseif reason == "unchanged" then
                WowSync:Print(L["Profile 'X': nothing changed."]:format(profileName))
            else
                WowSync:Print(L["Could not save from that character."])
            end
        end,
    })
end

function CharacterDetails:Build(region)
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

    -- Empty state label
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER", 0, 20)
    emptyLabel:SetText(L["Select a character"])

    -- Detail content (hidden until a character is selected)
    content = CreateFrame("Frame", nil, root)
    content:SetAllPoints()
    content:Hide()

    -- Header
    titleText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetPoint("TOPRIGHT", -12, -10)
    titleText:SetJustifyH("LEFT")

    infoText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    infoText:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    infoText:SetJustifyH("LEFT")

    -- Separator
    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", 10, -52)
    separator:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(UI.Backdrop.Separator))

    local listHeader = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHeader:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 2, -8)
    listHeader:SetText(L["Captured modules:"])

    -- Module preview list (read-only, scrollable)
    moduleScrollBox = CreateFrame("Frame", nil, content, "WowScrollBoxList")
    moduleScrollBox:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -6)
    moduleScrollBox:SetPoint("RIGHT", content, "RIGHT", -26, 0)
    moduleScrollBox:SetPoint("BOTTOM", content, "BOTTOM", 0, 44)

    local scrollBar = CreateFrame("EventFrame", nil, content, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", moduleScrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", moduleScrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(UI.ModuleRow.Height)
    view:SetPadding(0, 0, 0, 0, UI.ModuleRow.Padding)
    view:SetElementInitializer("Frame", function(row, elementData)
        if not row.text then
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetPoint("RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
        end
        row.text:SetText(elementData.name)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(moduleScrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    -- Save action
    saveButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    saveButton:SetSize(150, 22)
    saveButton:SetPoint("BOTTOMRIGHT", -10, 12)
    saveButton:SetText(L["Save to profile…"])
    saveButton:SetScript("OnClick", RequestSave)

    return self
end

function CharacterDetails:SetCharacter(elementData)
    currentEntry = elementData

    if not elementData then
        content:Hide()
        emptyLabel:Show()
        return
    end

    emptyLabel:Hide()
    content:Show()

    -- Header identity
    local classInfo = elementData.ClassID and C_CreatureInfo.GetClassInfo(elementData.ClassID)
    local classColor = classInfo and C_ClassColor.GetClassColor(classInfo.classFile)
    titleText:SetText(classColor and classColor:WrapTextInColorCode(elementData.Key) or elementData.Key)

    local className = classInfo and classInfo.className or L["Unknown"]
    local lastSeen = elementData.LastSeen and date("%b %d, %Y %H:%M", elementData.LastSeen) or L["Unknown"]
    infoText:SetText(L["X • Y"]:format(className, lastSeen))

    -- Captured module list
    local names = CurrentModuleNames()
    local dataProvider = CreateDataProvider()
    for _, name in ipairs(names) do
        dataProvider:Insert({ name = name })
    end
    moduleScrollBox:SetDataProvider(dataProvider)

    saveButton:SetEnabled(#names > 0)
end

function CharacterDetails:OnSaved(callback)
    onSaved = callback
end
