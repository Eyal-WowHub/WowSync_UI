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
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Size of the per-row Merge/Exact toggle shown on apply rows.
local MODE_BUTTON_WIDTH = 58
local MODE_BUTTON_HEIGHT = 18

-- Module-name link colours: the resting white and the blue-ish hover that
-- signals the name opens that module's filtered change preview.
local LINK_COLOR = { 1, 1, 1 }
local LINK_HOVER_COLOR = { 0.4, 0.7, 1 }

-- Title/body text for the mode toggle tooltip, per mode.
local function ModeTooltip(mode)
    if mode == "exact" then
        return L["Exact"], L["Exact mode tooltip"]
    end
    return L["Merge"], L["Merge mode tooltip"]
end

-- Draw the mode button's tooltip from the text stashed on it.
local function ShowModeTooltip(button)
    local tooltip = button._tooltip
    if not tooltip then return end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltip.title, 1, 0.82, 0, 1, true)
    GameTooltip:AddLine(tooltip.body, 0.9, 0.9, 0.9, true)
    if tooltip.footer then
        GameTooltip:AddLine(" ", 1, 1, 1, true)
        GameTooltip:AddLine(tooltip.footer, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function ModuleRow:Build(parent)
    C:IsTable(parent, 2)

    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)

    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)

    -- An invisible button matching the name's bounds that turns it into a link:
    -- hovering tints the name blue. The list owner opts a row in (and wires the
    -- click) through SetNameLink; rows left out stay plain text.
    checkbox.nameLink = CreateFrame("Button", nil, checkbox)
    checkbox.nameLink:SetAllPoints(checkbox.label)
    checkbox.nameLink:SetScript("OnEnter", function()
        checkbox.label:SetTextColor(unpack(LINK_HOVER_COLOR))
    end)
    checkbox.nameLink:SetScript("OnLeave", function()
        checkbox.label:SetTextColor(unpack(LINK_COLOR))
    end)
    checkbox.nameLink:Hide()

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
    checkbox.modeButton = Button:Build({
        parent = parent,
        width = MODE_BUTTON_WIDTH,
        height = MODE_BUTTON_HEIGHT,
    })
    checkbox.modeButton:SetScript("OnEnter", ShowModeTooltip)
    checkbox.modeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    checkbox.modeButton:Hide()

    return checkbox
end

-- Turn the module name into a clickable link with the given click handler, or
-- restore it to plain text when no handler is given.
function ModuleRow:SetNameLink(checkbox, onClick)
    checkbox.label:SetTextColor(unpack(LINK_COLOR))
    if onClick then
        checkbox.nameLink:SetScript("OnClick", onClick)
        checkbox.nameLink:Show()
    else
        checkbox.nameLink:SetScript("OnClick", nil)
        checkbox.nameLink:Hide()
    end
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
        checkbox.modeButton._tooltip = nil
        checkbox.modeButton:Hide()
        return
    end

    local title, body = ModeTooltip(modeInfo.mode)
    checkbox.modeButton._tooltip = {
        title = title,
        body = body,
        footer = (modeInfo.canToggle == true)
            and L["Click to change between Exact and Merge modes."]
            or L["This module only supports X mode."]:format(title),
    }

    checkbox.modeButton:SetText(title)
    checkbox.modeButton:SetEnabled(modeInfo.canToggle == true)
    checkbox.modeButton:Show()

    -- Toggling is click-driven, so refresh the tooltip in place when it is
    -- already showing for this button.
    if GameTooltip:GetOwner() == checkbox.modeButton then
        ShowModeTooltip(checkbox.modeButton)
    end
end
