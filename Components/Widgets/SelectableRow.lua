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

-- Install hover highlighting. A row with no key (e.g. a group header) is inert,
-- and the hover never overrides the current selection.
function Verbs:WireHover(keyField)
    self:EnableMouse(true)
    self:SetScript("OnEnter", function(row)
        local key = row[keyField]
        if key == nil then return end
        if key ~= row._ctx.GetSelected() then
            row.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    self:SetScript("OnLeave", function(row)
        local key = row[keyField]
        if key == nil then return end
        if key ~= row._ctx.GetSelected() then
            row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
end

-- Paint the row for its current selection state.
function Verbs:Paint(isSelected)
    if isSelected then
        self.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end

SelectableRow.Verbs = Verbs
