local _, addon = ...

--[[
    ProfileRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ProfileList. The
    scroll box owns the row frames; this module only builds their children once
    and updates their content. The list-level selection state is reached through
    an injected context.

    ctx = {
        GetSelected() -> profileName or nil,
        Select(profileName),
    }

    addon:GetObject("ProfileRow"):Build(row, ctx)
    addon:GetObject("ProfileRow"):Update(row, elementData, ctx)
]]

local ProfileRow = addon:NewObject("ProfileRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

-- Left inset of a realm header and the deeper inset of the character rows
-- grouped beneath it, so the list reads as an indented tree.
local HEADER_INSET = 8
local CHARACTER_INSET = 16

local function FormatDate(timestamp)
    if not timestamp then return "" end
    return date("%b %d, %Y", timestamp)
end

function ProfileRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.GetSelected) == "function", "Build: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "Build: 'ctx.Select' must be a function")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Realm group header, shown in place of the character widgets. Bottom-anchored
    -- so the empty space above the text separates each group consistently.
    row.realmHeader = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.realmHeader:SetPoint("BOTTOMLEFT", HEADER_INSET, 5)
    row.realmHeader:SetPoint("RIGHT", -6, 0)
    row.realmHeader:SetJustifyH("LEFT")
    row.realmHeader:SetWordWrap(false)
    row.realmHeader:Hide()

    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetColorTexture(1, 1, 1, 0.08)
    row.headerLine:SetHeight(1)
    row.headerLine:SetPoint("BOTTOMLEFT", HEADER_INSET, 2)
    row.headerLine:SetPoint("BOTTOMRIGHT", -6, 2)
    row.headerLine:Hide()

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetPoint("LEFT", CHARACTER_INSET, 0)
    row.classIcon:SetSize(28, 28)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 6, -2)
    row.nameText:SetPoint("RIGHT", -6, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.infoText:SetPoint("BOTTOMLEFT", row.classIcon, "BOTTOMRIGHT", 6, 2)
    row.infoText:SetPoint("RIGHT", -6, 0)
    row.infoText:SetJustifyH("LEFT")
    row.infoText:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.profileName then return end
        if self.profileName ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.profileName then return end
        if self.profileName ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self)
        if not self.profileName then return end
        ctx.Select(self.profileName)
    end)
end

function ProfileRow:Update(row, elementData, ctx)
    C:IsTable(row, 2)
    C:IsTable(elementData, 3)
    C:IsTable(ctx, 4)

    -- Realm header: just the realm name, with no selection behaviour.
    if elementData.kind == "realm" then
        row.profileName = nil
        row.classIcon:Hide()
        row.nameText:Hide()
        row.infoText:Hide()
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.realmHeader:SetText(elementData.realm or "")
        row.realmHeader:Show()
        row.headerLine:Show()
        return
    end

    row.realmHeader:Hide()
    row.headerLine:Hide()
    row.classIcon:Show()
    row.nameText:Show()
    row.infoText:Show()

    local profileName = elementData.id
    local character = elementData.character or ""

    row.profileName = profileName

    -- Class icon and class-colored character name
    local classInfo = elementData.classID and C_CreatureInfo.GetClassInfo(elementData.classID)
    if classInfo then
        local coords = CLASS_ICON_TCOORDS[classInfo.classFile]
        if coords then
            row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexture(nil)
        end

        local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
        row.nameText:SetText(classColor and classColor:WrapTextInColorCode(character) or character)
    else
        row.classIcon:SetTexture(nil)
        row.nameText:SetText(character)
    end

    -- Info line: when the character was last seen (its setup last captured).
    if elementData.timestamp then
        row.infoText:SetText(L["Last seen: X"]:format(FormatDate(elementData.timestamp)))
    else
        row.infoText:SetText("")
    end

    -- Selection highlight
    if profileName == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end
