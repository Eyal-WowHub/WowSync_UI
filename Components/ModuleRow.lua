local _, addon = ...

local L = addon.L

--[[
    ModuleRow object (row renderer).

    Row sub-contract for the pooled checkbox rows in ModuleList. Builds a
    checkbox with a label and an optional warning fontstring, and updates its
    checked/enabled state and texts. The row frames are owned by ModuleList;
    this renderer is stateless.

    addon:GetObject("ModuleRow"):Build(parent) -> checkbox frame
    addon:GetObject("ModuleRow"):Update(checkbox, name, canApply, reason)
]]

local ModuleRow = addon:NewObject("ModuleRow")

function ModuleRow:Build(parent)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)

    cb.warning = cb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cb.warning:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)

    return cb
end

function ModuleRow:Update(cb, name, canApply, reason)
    cb:SetChecked(canApply)
    cb:SetEnabled(canApply)
    cb.label:SetText(name)

    if not canApply then
        cb.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        cb.warning:Show()
    else
        cb.warning:Hide()
    end
end
