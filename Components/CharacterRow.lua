local _, addon = ...

--[[
    CharacterRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in CharacterList. The
    scroll box owns the row frames; this module only builds their children once
    and updates their content. The list-level selection state is reached through
    an injected context.

    elementData = { Key = "Name-Realm", ClassID = number?, LastSeen = number? }

    ctx = {
        GetSelected() -> charKey or nil,
        Select(elementData),
    }

    addon:GetObject("CharacterRow"):Build(row, ctx)
    addon:GetObject("CharacterRow"):Update(row, elementData, ctx)
]]

local CharacterRow = addon:NewObject("CharacterRow")

local L = addon.L
local UI = addon.UI

local function FormatLastSeen(timestamp)
    if not timestamp then return "" end
    return L["Last seen: X"]:format(date("%b %d, %Y", timestamp))
end

function CharacterRow:Build(row, ctx)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetPoint("LEFT", 6, 0)
    row.classIcon:SetSize(28, 28)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 6, -2)
    row.nameText:SetPoint("RIGHT", -6, 0)
    row.nameText:SetJustifyH("LEFT")

    row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.infoText:SetPoint("BOTTOMLEFT", row.classIcon, "BOTTOMRIGHT", 6, 2)
    row.infoText:SetPoint("RIGHT", -6, 0)
    row.infoText:SetJustifyH("LEFT")

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.charKey ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.charKey ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self)
        ctx.Select(self.elementData)
    end)
end

-- Toggle the character visuals so a pooled frame can be reused as an inert
-- realm header (CharacterList hides these and shows its own header label).
function CharacterRow:SetShown(row, shown)
    row.bg:SetShown(shown)
    row.classIcon:SetShown(shown)
    row.nameText:SetShown(shown)
    row.infoText:SetShown(shown)
end

function CharacterRow:Update(row, elementData, ctx)
    local charKey = elementData.Key
    -- The realm is conveyed by the section header (or is implicit for a single
    -- own-realm list), so the row shows just the character name when available.
    local displayName = elementData.Name or charKey

    row.charKey = charKey
    row.elementData = elementData

    -- Class icon and class-colored name
    local classInfo = elementData.ClassID and C_CreatureInfo.GetClassInfo(elementData.ClassID)
    if classInfo then
        local coords = CLASS_ICON_TCOORDS[classInfo.classFile]
        if coords then
            row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexture(nil)
        end

        local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
        row.nameText:SetText(classColor and classColor:WrapTextInColorCode(displayName) or displayName)
    else
        row.classIcon:SetTexture(nil)
        row.nameText:SetText(displayName)
    end

    -- Info line
    row.infoText:SetText(FormatLastSeen(elementData.LastSeen))

    -- Selection highlight
    if charKey == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end
