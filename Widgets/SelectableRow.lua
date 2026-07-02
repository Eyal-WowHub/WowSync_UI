local _, addon = ...

--[[
    SelectableRow methods (shared selectable-row behaviour).

    The selection visuals every pooled, single-select scroll-list row repeats:
    a transparent background texture, hover highlighting that yields to the
    current selection, and the selected/normal paint. These are mixed into a
    row widget's methods, so a row frame carries them as its own methods.

    A row identifies itself through a field named by the keyField passed to
    WireHover (e.g. "id" or "snapshot"); the list selection is read through
    self._ctx.GetSelected, stored on the row by its Constructor.

    local Methods = Mixin({}, addon:GetObject("SelectableRow").Methods)
        self:Background()           -- create self.bg
        self:WireHover(keyField)    -- hover highlight via self._ctx
        self:Paint(isSelected)      -- selected/normal paint
]]

local SelectableRow = addon:NewObject("SelectableRow")

local UI = addon.UI

local Methods = {}

-- Create the row's background texture, transparent until painted.
function Methods:Background()
    self.bg = self:CreateTexture(nil, "BACKGROUND")
    self.bg:SetAllPoints()
    self.bg:SetColorTexture(0, 0, 0, 0)
    return self.bg
end

-- Install hover highlighting. A row with no key (e.g. a group header) is inert,
-- and the hover never overrides the current selection.
function Methods:WireHover(keyField)
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

-- Re-derive the hover highlight from the current pointer and selection state.
-- Rows with child widgets (e.g. inline buttons) call this after the pointer
-- crosses into a child, because the row's own OnLeave fires and clears the
-- highlight even while the cursor is still within the row's bounds. keyField is
-- the same identifier field passed to WireHover.
function Methods:ApplyHoverState(keyField)
    local key = self[keyField]
    if key == nil then return end
    if key == self._ctx.GetSelected() then return end

    if self:IsMouseOver() then
        self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
    else
        self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end

-- Paint the row for its current selection state.
function Methods:Paint(isSelected)
    if isSelected then
        self.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end

SelectableRow.Methods = Methods
