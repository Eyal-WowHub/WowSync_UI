local _, addon = ...

--[[
    ListRow widget (reusable grouped-list row).

    Builds the shared frame skeleton for a selectable, class-grouped list row and
    wires the common hover/selection behaviour. A row renders in one of two modes:
    a group header (a label spanning the row) or an item (class icon, class-colored
    title, and an info line). The owning list reaches its selection state through an
    injected context, and a row carries its identifier on row.id so the shared
    handlers and the list agree on what is selected.

    ctx = {
        GetSelected() -> id or nil,
        Select(id),
    }

    -- One-time skeleton + behaviour (pooled rows are built once):
    addon:GetObject("ListRow"):BuildSkeleton(row)
    addon:GetObject("ListRow"):WireSelection(row, ctx[, onActivate])

    -- Per-update rendering (mutually exclusive):
    addon:GetObject("ListRow"):RenderHeader(row, text)
    addon:GetObject("ListRow"):RenderItem(row, { id, classID, title, info }, ctx)
]]

local ListRow = addon:NewObject("ListRow")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Left inset of a group header and the deeper inset of the item rows grouped
-- beneath it, so the list reads as an indented tree.
local HEADER_INSET = 8
local ITEM_INSET = 16

-- Two clicks closer than this on the same row count as a double-click.
local DOUBLE_CLICK_WINDOW = 0.4

-- Build the shared child regions once. The list reuses pooled row frames, so a
-- row is built a single time and only re-rendered afterwards.
function ListRow:BuildSkeleton(row)
    C:IsTable(row, 2)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Group header, shown in place of the item widgets. Bottom-anchored so the
    -- empty space above the text separates each group consistently.
    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.header:SetPoint("BOTTOMLEFT", HEADER_INSET, 5)
    row.header:SetPoint("RIGHT", -6, 0)
    row.header:SetJustifyH("LEFT")
    row.header:SetWordWrap(false)
    row.header:Hide()

    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetColorTexture(1, 1, 1, 0.08)
    row.headerLine:SetHeight(1)
    row.headerLine:SetPoint("BOTTOMLEFT", HEADER_INSET, 2)
    row.headerLine:SetPoint("BOTTOMRIGHT", -6, 2)
    row.headerLine:Hide()

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetPoint("LEFT", ITEM_INSET, 0)
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
end

-- Wire the shared hover and selection behaviour. A header row clears row.id so
-- the handlers no-op over it. When onActivate is given, a double-click on the
-- same row invokes onActivate(row) (used for inline rename).
function ListRow:WireSelection(row, ctx, onActivate)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)
    C:Ensures(type(ctx.GetSelected) == "function", "WireSelection: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "WireSelection: 'ctx.Select' must be a function")

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        if self.id ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.id then return end
        if self.id ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self)
        if not self.id then return end
        ctx.Select(self.id)

        if not onActivate then return end
        local now = GetTime()
        if self.lastClick and (now - self.lastClick) < DOUBLE_CLICK_WINDOW then
            self.lastClick = nil
            onActivate(self)
        else
            self.lastClick = now
        end
    end)
end

-- Render the row as a group header: a label spanning the row, no selection.
function ListRow:RenderHeader(row, text)
    C:IsTable(row, 2)

    row.id = nil
    row.classIcon:Hide()
    row.nameText:Hide()
    row.infoText:Hide()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row.header:SetText(text or "")
    row.header:Show()
    row.headerLine:Show()
end

-- Render the row as a selectable item: class icon, class-colored title, and an
-- info line, carrying the current selection highlight.
function ListRow:RenderItem(row, data, ctx)
    C:IsTable(row, 2)
    C:IsTable(data, 3)
    C:IsTable(ctx, 4)

    row.header:Hide()
    row.headerLine:Hide()
    row.classIcon:Show()
    row.nameText:Show()
    row.infoText:Show()

    row.id = data.id

    local title = data.title or ""
    local classInfo = data.classID and C_CreatureInfo.GetClassInfo(data.classID)
    if classInfo then
        local coords = CLASS_ICON_TCOORDS[classInfo.classFile]
        if coords then
            row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
            row.classIcon:SetTexCoord(unpack(coords))
        else
            row.classIcon:SetTexture(nil)
        end

        local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
        row.nameText:SetText(classColor and classColor:WrapTextInColorCode(title) or title)
    else
        row.classIcon:SetTexture(nil)
        row.nameText:SetText(title)
    end

    row.infoText:SetText(data.info or "")

    if data.id == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end

-- Class-colored class name for a header, or "" when the class is unknown.
function ListRow:ClassHeaderText(classID)
    local classInfo = classID and C_CreatureInfo.GetClassInfo(classID)
    if not classInfo then return "" end
    local className = classInfo.className or ""
    local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
    return classColor and classColor:WrapTextInColorCode(className) or className
end
