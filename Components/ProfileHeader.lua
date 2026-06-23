local _, addon = ...

--[[
    ProfileHeader object.

    Fills an injected region with the selected profile's name and a summary
    line (class, last character, last updated).

    addon:GetObject("ProfileHeader"):Build(region)
        -> self { SetProfile(profileName, snapshot) }
]]

local ProfileHeader = addon:NewObject("ProfileHeader")

local L = addon.L

local titleText, infoText

function ProfileHeader:Build(region)
    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 0, 0)

    infoText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)

    return self
end

function ProfileHeader:SetProfile(profileName, snapshot)
    local source = snapshot and snapshot.Source
    local classInfo = source and source.ClassID and C_CreatureInfo.GetClassInfo(source.ClassID)
    local className = classInfo and classInfo.className or L["Unknown"]
    titleText:SetText(profileName)
    infoText:SetText(L["X • Y • Z"]:format(
        className,
        (source and source.Character) or L["Unknown"],
        date("%b %d, %Y %H:%M", (snapshot and snapshot.Timestamp) or 0)
    ))
end
