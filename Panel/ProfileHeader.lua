local _, addon = ...

--[[
    ProfileHeader object.

    Fills an injected region with the selected character's class-colored name and
    a summary line (class and the latest snapshot's date). Per-snapshot notes are
    shown in the timeline below, not here.

    addon:GetObject("ProfileHeader"):Build(region)
        -> profile-header frame { SetProfile(character, snapshot) }
]]

local ProfileHeader = addon:NewObject("ProfileHeader")

local C = LibStub("Contracts-1.0")
local L = addon.L

local SnapshotView = WowSync:GetSnapshotView()

local Verbs = {}

function Verbs:Constructor(config)
    self._titleText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self._titleText:SetPoint("TOPLEFT", 0, 0)

    self._infoText = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self._infoText:SetPoint("TOPLEFT", self._titleText, "BOTTOMLEFT", 0, -4)
end

function Verbs:SetProfile(character, snapshot)
    local characterInfo = snapshot and SnapshotView:GetCharacterInfo(snapshot)
    character = character or (characterInfo and characterInfo.Character) or L["Unknown"]

    local classInfo = characterInfo and characterInfo.ClassID and C_CreatureInfo.GetClassInfo(characterInfo.ClassID)
    local className = classInfo and classInfo.className or L["Unknown"]

    -- Class-color the character name when we know the class.
    if classInfo then
        local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
        self._titleText:SetText(classColor and classColor:WrapTextInColorCode(character) or character)
    else
        self._titleText:SetText(character)
    end

    self._infoText:SetText(L["X • Y"]:format(
        className,
        date("%b %d, %Y %H:%M", (snapshot and SnapshotView:GetTimestamp(snapshot)) or 0)
    ))
end

function ProfileHeader:Build(region)
    C:IsTable(region, 2)

    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
    }, {
        frameType = "Frame",
        verbs = Verbs,
    })
end
