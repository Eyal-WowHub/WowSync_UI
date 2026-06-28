local _, addon = ...

--[[
    ImportRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportList. Renders
    either a class group header or an imported container (class icon, name, and
    snapshot count). The list-level selection state is reached through an
    injected context.

    ctx = {
        GetSelected() -> importID or nil,
        Select(importID),
    }

    addon:GetObject("ImportRow"):Build(row, ctx)
    addon:GetObject("ImportRow"):Update(row, elementData, ctx)
]]

local ImportRow = addon:NewObject("ImportRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

-- Left inset of a class header and the deeper inset of the container rows
-- grouped beneath it, so the list reads as an indented tree.
local HEADER_INSET = 8
local CONTAINER_INSET = 16

-- One-line snapshot-count label for a container's info line.
local function SnapshotCountText(count)
    if count == 1 then
        return L["1 snapshot"]
    end
    return L["X snapshots"]:format(count or 0)
end

function ImportRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.GetSelected) == "function", "Build: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "Build: 'ctx.Select' must be a function")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Class group header, shown in place of the container widgets. Bottom-anchored
    -- so the empty space above the text separates each group consistently.
    row.classHeader = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.classHeader:SetPoint("BOTTOMLEFT", HEADER_INSET, 5)
    row.classHeader:SetPoint("RIGHT", -6, 0)
    row.classHeader:SetJustifyH("LEFT")
    row.classHeader:SetWordWrap(false)
    row.classHeader:Hide()

    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetColorTexture(1, 1, 1, 0.08)
    row.headerLine:SetHeight(1)
    row.headerLine:SetPoint("BOTTOMLEFT", HEADER_INSET, 2)
    row.headerLine:SetPoint("BOTTOMRIGHT", -6, 2)
    row.headerLine:Hide()

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetPoint("LEFT", CONTAINER_INSET, 0)
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
        if not self.importID then return end
        if self.importID ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.importID then return end
        if self.importID ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self)
        if not self.importID then return end
        ctx.Select(self.importID)
    end)
end

function ImportRow:Update(row, elementData, ctx)
    C:IsTable(row, 2)
    C:IsTable(elementData, 3)
    C:IsTable(ctx, 4)

    -- Class header: just the class name, with no selection behaviour.
    if elementData.kind == "class" then
        row.importID = nil
        row.classIcon:Hide()
        row.nameText:Hide()
        row.infoText:Hide()
        row.bg:SetColorTexture(0, 0, 0, 0)

        local classInfo = elementData.classID and C_CreatureInfo.GetClassInfo(elementData.classID)
        local className = classInfo and classInfo.className or ""
        local classColor = classInfo and C_ClassColor.GetClassColor(classInfo.classFile)
        row.classHeader:SetText(classColor and classColor:WrapTextInColorCode(className) or className)
        row.classHeader:Show()
        row.headerLine:Show()
        return
    end

    row.classHeader:Hide()
    row.headerLine:Hide()
    row.classIcon:Show()
    row.nameText:Show()
    row.infoText:Show()

    local importID = elementData.id
    local name = elementData.name or ""

    row.importID = importID

    -- Class icon and class-colored container name.
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
        row.nameText:SetText(classColor and classColor:WrapTextInColorCode(name) or name)
    else
        row.classIcon:SetTexture(nil)
        row.nameText:SetText(name)
    end

    -- Info line: how many snapshots the container holds.
    row.infoText:SetText(SnapshotCountText(elementData.snapshotCount))

    -- Selection highlight
    if importID == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end
