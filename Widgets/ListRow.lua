local _, addon = ...

--[[
    ListRow methods (reusable grouped-list row).

    The shared frame skeleton for a selectable, class-grouped list row plus the
    common hover/selection behaviour, mixed into a row widget's methods. A row
    renders in one of two modes: a group header (a label spanning the row) or an
    item (class icon, class-colored title, and an info line). The row reaches the
    list selection through self._ctx and carries its identifier on self.id so the
    shared handlers and the list agree on what is selected.

    These methods build on SelectableRow's, mixed in here so a consumer only needs
    to mix ListRow.Methods:

    local Methods = Mixin({}, addon:GetObject("ListRow").Methods)
        self:BuildSkeleton()            -- one-time child regions
        self:WireSelection([onActivate])-- selection + optional double-click
        self:RenderHeader(text)         -- per-update: group header
        self:RenderItem({ id, classID, title, info })  -- per-update: item
]]

local ListRow = addon:NewObject("ListRow")

local SelectableRow = addon:GetObject("SelectableRow")

-- Left inset of a group header and the deeper inset of the item rows grouped
-- beneath it, so the list reads as an indented tree.
local HEADER_INSET = 8
local ITEM_INSET = 16

-- Two clicks closer than this on the same row count as a double-click.
local DOUBLE_CLICK_WINDOW = 0.4

-- ListRow methods build on the shared selectable-row behaviour, mixed in so a row
-- frame carries the background/hover/paint as its own methods.
local Methods = Mixin({}, SelectableRow.Methods)

-- Build the shared child regions once. The list reuses pooled row frames, so a
-- row is built a single time and only re-rendered afterwards.
function Methods:BuildSkeleton()
    self:Background()

    -- Group header, shown in place of the item widgets. Bottom-anchored so the
    -- empty space above the text separates each group consistently.
    self.header = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.header:SetPoint("BOTTOMLEFT", HEADER_INSET, 5)
    self.header:SetPoint("RIGHT", -6, 0)
    self.header:SetJustifyH("LEFT")
    self.header:SetWordWrap(false)
    self.header:Hide()

    self.headerLine = self:CreateTexture(nil, "ARTWORK")
    self.headerLine:SetColorTexture(1, 1, 1, 0.08)
    self.headerLine:SetHeight(1)
    self.headerLine:SetPoint("BOTTOMLEFT", HEADER_INSET, 2)
    self.headerLine:SetPoint("BOTTOMRIGHT", -6, 2)
    self.headerLine:Hide()

    self.classIcon = self:CreateTexture(nil, "ARTWORK")
    self.classIcon:SetPoint("LEFT", ITEM_INSET, 0)
    self.classIcon:SetSize(28, 28)

    self.nameText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.nameText:SetPoint("TOPLEFT", self.classIcon, "TOPRIGHT", 6, -2)
    self.nameText:SetPoint("RIGHT", -6, 0)
    self.nameText:SetJustifyH("LEFT")
    self.nameText:SetWordWrap(false)

    self.infoText = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.infoText:SetPoint("BOTTOMLEFT", self.classIcon, "BOTTOMRIGHT", 6, 2)
    self.infoText:SetPoint("RIGHT", -6, 0)
    self.infoText:SetJustifyH("LEFT")
    self.infoText:SetWordWrap(false)
end

-- Wire the shared hover and selection behaviour. A header row clears self.id so
-- the handlers no-op over it. When onActivate is given, a double-click on the
-- same row invokes onActivate(row) (used for inline rename). A right-click
-- selects the row and, when the row context provides OpenMenu, opens the
-- per-row context menu anchored to the row.
function Methods:WireSelection(onActivate)
    self:WireHover("id")
    self:SetScript("OnMouseDown", function(row, button)
        if not row.id then return end
        row._ctx.Select(row.id)

        if button == "RightButton" then
            if row._ctx.OpenMenu then
                row._ctx.OpenMenu(row.id, row)
            end
            return
        end

        if not onActivate then return end
        local now = GetTime()
        if row.lastClick and (now - row.lastClick) < DOUBLE_CLICK_WINDOW then
            row.lastClick = nil
            onActivate(row)
        else
            row.lastClick = now
        end
    end)
end

-- Render the row as a group header: a label spanning the row, no selection.
function Methods:RenderHeader(text)
    self.id = nil
    self.classIcon:Hide()
    self.nameText:Hide()
    self.infoText:Hide()
    self.bg:SetColorTexture(0, 0, 0, 0)
    self.header:SetText(text or "")
    self.header:Show()
    self.headerLine:Show()
end

-- Render the row as a selectable item: class icon, class-colored title, and an
-- info line, carrying the current selection highlight.
function Methods:RenderItem(data)
    self.header:Hide()
    self.headerLine:Hide()
    self.classIcon:Show()
    self.nameText:Show()
    self.infoText:Show()

    self.id = data.id

    local title = data.title or ""
    local classInfo = data.classID and C_CreatureInfo.GetClassInfo(data.classID)
    if classInfo then
        local coords = CLASS_ICON_TCOORDS[classInfo.classFile]
        if coords then
            self.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
            self.classIcon:SetTexCoord(unpack(coords))
        else
            self.classIcon:SetTexture(nil)
        end

        local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
        self.nameText:SetText(classColor and classColor:WrapTextInColorCode(title) or title)
    else
        self.classIcon:SetTexture(nil)
        self.nameText:SetText(title)
    end

    self.infoText:SetText(data.info or "")

    self:Paint(data.id == self._ctx.GetSelected())
end

-- Class-colored class name for a header, or "" when the class is unknown.
function Methods:ClassHeaderText(classID)
    local classInfo = classID and C_CreatureInfo.GetClassInfo(classID)
    if not classInfo then return "" end
    local className = classInfo.className or ""
    local classColor = C_ClassColor.GetClassColor(classInfo.classFile)
    return classColor and classColor:WrapTextInColorCode(className) or className
end

ListRow.Methods = Methods
