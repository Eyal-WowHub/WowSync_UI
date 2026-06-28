local _, addon = ...

--[[
    ModuleRow object (row renderer).

    Row sub-contract for the pooled checkbox rows in ModuleList. Builds a
    checkbox with a label and an optional warning fontstring, and updates its
    checked/enabled state and texts. The row frames are owned by ModuleList;
    this renderer is stateless.

    addon:GetObject("ModuleRow"):Build(parent) -> checkbox frame
    addon:GetObject("ModuleRow"):Update(checkbox, name, canApply, reason, counts, modeInfo)
]]

local ModuleRow = addon:NewObject("ModuleRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Size of the per-row Merge/Exact toggle shown on apply rows.
local MODE_BUTTON_WIDTH = 58
local MODE_BUTTON_HEIGHT = 18

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

    -- Optional per-row Merge/Exact toggle, used by the apply preview. The list
    -- owner positions it at the row's right edge; rows without a choice to make
    -- (or that aren't apply rows) leave it hidden.
    checkbox.modeButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    checkbox.modeButton:SetSize(MODE_BUTTON_WIDTH, MODE_BUTTON_HEIGHT)
    checkbox.modeButton:Hide()

    return checkbox
end

function ModuleRow:Update(checkbox, moduleName, canApply, reason, counts, modeInfo)
    C:IsTable(checkbox, 2)
    C:IsString(moduleName, 3)

    checkbox:SetChecked(canApply)
    checkbox:SetEnabled(canApply)
    checkbox.label:SetText(moduleName)

    if not canApply then
        checkbox.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        checkbox.warning:Show()
        checkbox.counts:Hide()
        checkbox.modeButton:Hide()
        return
    end

    checkbox.warning:Hide()
    self:RenderCounts(checkbox, counts)
    self:RenderMode(checkbox, modeInfo)
end

-- Render the per-module change figure after the module name; hidden when the
-- module has no pending change.
function ModuleRow:RenderCounts(checkbox, counts)
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

-- Render the Merge/Exact toggle for an apply row; disabled (but shown) for
-- modules that support a single mode, and hidden when no toggle is offered.
function ModuleRow:RenderMode(checkbox, modeInfo)
    if not (modeInfo and modeInfo.visible) then
        checkbox.modeButton:Hide()
        return
    end

    checkbox.modeButton:SetText(modeInfo.mode == "exact" and L["Exact"] or L["Merge"])
    checkbox.modeButton:SetEnabled(modeInfo.canToggle == true)
    checkbox.modeButton:Show()
end
