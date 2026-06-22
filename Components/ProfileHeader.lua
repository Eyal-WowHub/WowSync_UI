local _, addon = ...

local L = addon.L

--[[
    ProfileHeader object.

    Fills an injected region with the selected profile's name and a summary
    line (class, last character, last updated).

    addon:GetObject("ProfileHeader"):Build(region)
        -> self { SetProfile(profileName, meta) }
]]

local ProfileHeader = addon:NewObject("ProfileHeader")

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

function ProfileHeader:SetProfile(profileName, meta)
    local classInfo = C_CreatureInfo.GetClassInfo(meta.ClassID)
    local className = classInfo and classInfo.className or L["Unknown"]
    titleText:SetText(profileName)
    infoText:SetText(L["X • Y • Z"]:format(
        className,
        meta.LastCharacter,
        date("%b %d, %Y %H:%M", meta.LastUpdated or 0)
    ))
end
