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

    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)

    cb.warning = cb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cb.warning:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)

    -- Per-module change counts, shown after the name for applicable rows.
    -- Anchored to the label (not the list) so it tracks the row vertically;
    -- mutually exclusive with the warning, so they share the same slot.
    cb.counts = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.counts:SetPoint("LEFT", cb.label, "RIGHT", 8, 0)

    return cb
end

function ModuleRow:Update(cb, name, canApply, reason, counts)
    C:IsTable(cb, 2)
    C:IsString(name, 3)

    cb:SetChecked(canApply)
    cb:SetEnabled(canApply)
    cb.label:SetText(name)

    if not canApply then
        cb.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        cb.warning:Show()
        cb.counts:Hide()
        return
    end

    cb.warning:Hide()

    local added = counts and counts.added or 0
    local changed = counts and counts.changed or 0
    local removed = counts and counts.removed or 0

    if added > 0 or changed > 0 or removed > 0 then
        if removed > 0 then
            cb.counts:SetText(L["+A ~C -R"]:format(added, changed, removed))
        else
            cb.counts:SetText(L["+A ~C"]:format(added, changed))
        end
        cb.counts:Show()
    else
        cb.counts:Hide()
    end
end
