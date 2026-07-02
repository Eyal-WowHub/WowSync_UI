local _, addon = ...

--[[
    SectionHeader object.

    Creates a Settings-style section label on a parent frame: a large white
    heading (GameFontHighlightLarge, left-justified), matching the section headers
    in WoW's own Options window. The caller anchors -- and, if it changes, retitles
    -- the returned font string.

    local header = addon:GetObject("SectionHeader"):Create(parent, L["Profiles"])
    header:SetPoint("TOPLEFT", 10, -8)
    header:SetText(newText)
]]

local SectionHeader = addon:NewObject("SectionHeader")

local C = LibStub("Contracts-1.0")

-- WoW's Settings section headers use the large highlight (white) font.
local SECTION_HEADER_FONT = "GameFontHighlightLarge"

function SectionHeader:Create(parent, text)
    C:IsTable(parent, 2)

    local header = parent:CreateFontString(nil, "OVERLAY", SECTION_HEADER_FONT)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    header:SetText(text or "")
    return header
end
