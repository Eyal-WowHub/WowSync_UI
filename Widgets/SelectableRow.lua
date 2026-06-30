local _, addon = ...

--[[
    SelectableRow verbs (shared selectable-row behaviour).

    The selection visuals every pooled, single-select scroll-list row repeats:
    a transparent background texture, hover highlighting that yields to the
    current selection, and the selected/normal paint. These are mixed into a
    row widget's verbs, so a row frame carries them as its own methods.

    A row identifies itself through a field named by the keyField passed to
    WireHover (e.g. "id" or "snapshot"); the list selection is read through
    self._ctx.GetSelected, stored on the row by its Constructor.

    local Verbs = Mixin({}, addon:GetObject("SelectableRow").Verbs)
        self:Background()           -- create self.bg
        self:DecorateSelection()    -- optional: accent bar + gradient + edges
        self:WireHover(keyField)    -- hover highlight via self._ctx
        self:Paint(isSelected)      -- selected/normal paint
]]

local SelectableRow = addon:NewObject("SelectableRow")

local UI = addon.UI

local Verbs = {}

-- Create the row's background texture, transparent until painted.
function Verbs:Background()
    self.bg = self:CreateTexture(nil, "BACKGROUND")
    self.bg:SetAllPoints()
    self.bg:SetColorTexture(0, 0, 0, 0)
    return self.bg
end

-- Opt a row into the richer selection look: a bright left accent bar, a gentle
-- left-to-right gradient fill, and thin top/bottom edge lines, all revealed only
-- while the row is selected. Plain rows skip this and keep the flat fill.
function Verbs:DecorateSelection()
    self._decorated = true

    self.selFill = self:CreateTexture(nil, "BACKGROUND", nil, 2)
    self.selFill:SetAllPoints()
    self.selFill:SetColorTexture(1, 1, 1, 1)
    self.selFill:SetGradient("HORIZONTAL", UI.Row.SelectedGradientLeft, UI.Row.SelectedGradientRight)
    self.selFill:Hide()

    -- A darker echo of the selected gradient, shown only while hovering an
    -- unselected row.
    self.hoverFill = self:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.hoverFill:SetAllPoints()
    self.hoverFill:SetColorTexture(1, 1, 1, 1)
    self.hoverFill:SetGradient("HORIZONTAL", UI.Row.HoverGradientLeft, UI.Row.HoverGradientRight)
    self.hoverFill:Hide()

    self.accent = self:CreateTexture(nil, "ARTWORK")
    self.accent:SetPoint("TOPLEFT", 0, 0)
    self.accent:SetPoint("BOTTOMLEFT", 0, 0)
    self.accent:SetWidth(UI.Row.AccentWidth)
    self.accent:SetColorTexture(UI.Row.Accent:GetRGBA())
    self.accent:Hide()

    self.topLine = self:CreateTexture(nil, "ARTWORK")
    self.topLine:SetPoint("TOPLEFT", 0, 0)
    self.topLine:SetPoint("TOPRIGHT", 0, 0)
    self.topLine:SetHeight(1)
    self.topLine:SetColorTexture(UI.Row.SelectedEdge:GetRGBA())
    self.topLine:Hide()

    self.bottomLine = self:CreateTexture(nil, "ARTWORK")
    self.bottomLine:SetPoint("BOTTOMLEFT", 0, 0)
    self.bottomLine:SetPoint("BOTTOMRIGHT", 0, 0)
    self.bottomLine:SetHeight(1)
    self.bottomLine:SetColorTexture(UI.Row.SelectedEdge:GetRGBA())
    self.bottomLine:Hide()
end

-- Install hover highlighting. A row with no key (e.g. a group header) is inert,
-- and the hover never overrides the current selection.
function Verbs:WireHover(keyField)
    self:EnableMouse(true)
    self:SetScript("OnEnter", function(row)
        local key = row[keyField]
        if key == nil then return end
        if key ~= row._ctx.GetSelected() then
            if row._decorated then
                row.hoverFill:Show()
                row.accent:Show()
            else
                row.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
            end
        end
    end)
    self:SetScript("OnLeave", function(row)
        local key = row[keyField]
        if key == nil then return end
        if key ~= row._ctx.GetSelected() then
            if row._decorated then
                row.hoverFill:Hide()
                row.accent:Hide()
            else
                row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
            end
        end
    end)
end

-- Paint the row for its current selection state.
function Verbs:Paint(isSelected)
    if self._decorated then
        -- The gradient fill and edge decorations carry the selection; the base
        -- texture stays clear so hover can still tint an unselected row.
        self.selFill:SetShown(isSelected)
        self.accent:SetShown(isSelected)
        self.topLine:SetShown(isSelected)
        self.bottomLine:SetShown(isSelected)
        if isSelected then
            self.hoverFill:Hide()
        end
        self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        return
    end

    if isSelected then
        self.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end

SelectableRow.Verbs = Verbs
