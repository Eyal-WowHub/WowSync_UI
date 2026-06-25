local _, addon = ...

--[[
    ModuleRow object (row renderer).

    Row sub-contract for the pooled checkbox rows in ModuleList. Builds a
    checkbox with a label and an optional warning fontstring, and updates its
    checked/enabled state and texts. The row frames are owned by ModuleList;
    this renderer is stateless.

    addon:GetObject("ModuleRow"):Build(parent) -> checkbox frame
    addon:GetObject("ModuleRow"):Update(checkbox, name, canApply, reason, counts)
]]

local ModuleRow = addon:NewObject("ModuleRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

function ModuleRow:Build(parent)
    C:IsTable(parent, 2)

    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)

    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)

    checkbox.warning = checkbox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    checkbox.warning:SetPoint("LEFT", checkbox.label, "RIGHT", 6, 0)

    -- Per-module change counts, shown after the name for applicable rows.
    -- Anchored to the label (not the list) so it tracks the row vertically;
    -- mutually exclusive with the warning, so they share the same slot.
    checkbox.counts = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkbox.counts:SetPoint("LEFT", checkbox.label, "RIGHT", 8, 0)

    return checkbox
end

function ModuleRow:Update(checkbox, moduleName, canApply, reason, counts)
    C:IsTable(checkbox, 2)
    C:IsString(moduleName, 3)

    checkbox:SetChecked(canApply)
    checkbox:SetEnabled(canApply)
    checkbox.label:SetText(moduleName)

    if not canApply then
        checkbox.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        checkbox.warning:Show()
        checkbox.counts:Hide()
        return
    end

    checkbox.warning:Hide()

    local added = counts and counts.added or 0
    local changed = counts and counts.changed or 0
    local removed = counts and counts.removed or 0

    if added > 0 or changed > 0 or removed > 0 then
        if removed > 0 then
            checkbox.counts:SetText(L["+A ~C -R"]:format(added, changed, removed))
        else
            checkbox.counts:SetText(L["+A ~C"]:format(added, changed))
        end
        checkbox.counts:Show()
    else
        checkbox.counts:Hide()
    end
end
