local _, addon = ...

--[[
    SelectableRow widget (shared selectable-row behaviour).

    Factors out the selection visuals every pooled, single-select scroll-list row
    repeats: a transparent background texture, hover highlighting that yields to
    the current selection, and the selected/normal paint. Click, double-click,
    and context-menu handling stay with each row, since those interaction models
    differ; this owns only the background and its colour states.

    A row identifies itself through a field named by keyField (e.g. "id" or
    "snapshot"); the list-level selection is read through ctx.GetSelected().

    addon:GetObject("SelectableRow"):Background(row)              -- create row.bg
    addon:GetObject("SelectableRow"):WireHover(row, keyField, ctx)
    addon:GetObject("SelectableRow"):Paint(row, isSelected)
]]

local SelectableRow = addon:NewObject("SelectableRow")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Create the row's background texture, transparent until painted.
function SelectableRow:Background(row)
    C:IsTable(row, 2)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    return row.bg
end

-- Install hover highlighting. A row with no key (e.g. a group header) is inert,
-- and the hover never overrides the current selection.
function SelectableRow:WireHover(row, keyField, ctx)
    C:IsTable(row, 2)
    C:Ensures(type(keyField) == "string", "WireHover: 'keyField' must be a string")
    C:IsTable(ctx, 4)
    C:Ensures(type(ctx.GetSelected) == "function", "WireHover: 'ctx.GetSelected' must be a function")

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local key = self[keyField]
        if key == nil then return end
        if key ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        local key = self[keyField]
        if key == nil then return end
        if key ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
end

-- Paint the row for its current selection state.
function SelectableRow:Paint(row, isSelected)
    C:IsTable(row, 2)

    if isSelected then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end
