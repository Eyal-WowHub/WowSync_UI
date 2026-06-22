local _, addon = ...

local UI = addon.UI

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

local function FormatDate(timestamp)
    if not timestamp then return "" end
    return date("%b %d, %Y", timestamp)
end

local ProfileRow = addon:NewObject("ProfileRow")

function ProfileRow:Build(row, ctx)
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
        if self.profileName ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.RowHoverColor:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.profileName ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self)
        ctx.Select(self.profileName)
    end)
end

function ProfileRow:Update(row, elementData, ctx)
    local profileName = elementData.name

    row.profileName = profileName

    -- Class icon and class-colored name
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
        row.nameText:SetText(classColor and classColor:WrapTextInColorCode(profileName) or profileName)
    else
        row.classIcon:SetTexture(nil)
        row.nameText:SetText(profileName)
    end

    -- Info line
    row.infoText:SetText((elementData.character or "") .. "  " .. FormatDate(elementData.timestamp))

    -- Selection highlight
    if profileName == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.RowSelectedColor:GetRGBA())
    else
        row.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
    end
end
