local _, addon = ...

--[[
    ModuleRow widget (checkbox row).

    A module checkbox row for ModuleList, built on the Checkbox widget: the box
    and its label come from Checkbox (clicking either toggles the module, and the
    row lights a Settings-style hover). ModuleRow adds the module's warning, a
    per-module change badge that opens the module's filtered diff, and an optional
    Merge/Exact toggle. The row IS the CheckButton; ModuleList pools and positions it.

    addon:GetObject("ModuleRow"):Build(parent)   -- creates the checkbox widget
        -> checkbox frame {
            SetPreview(onClick),
            Update(name, canApply, reason, counts, modeInfo),
            RenderCounts(counts),
            RenderMode(modeInfo),
        }
]]

local ModuleRow = addon:NewObject("ModuleRow")

local C = addon.C
local L = addon.L

local Button = addon:GetObject("Button")
local ChangesBadge = addon:GetObject("ChangesBadge")
local Checkbox = addon:GetObject("Checkbox")

-- Size of the per-row Merge/Exact toggle shown on apply rows.
local MODE_BUTTON_WIDTH = 58
local MODE_BUTTON_HEIGHT = 18

local Methods = {}

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

function Methods:Constructor(config)
    self:SetSize(24, 24)

    self.warning = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.warning:SetPoint("LEFT", self.label, "RIGHT", 6, 0)

    -- Per-module change badge, shown after the name for applicable rows. Anchored
    -- to the label (not the list) so it tracks the row vertically; mutually
    -- exclusive with the warning, so they share the same slot. The list owner
    -- wires its click through SetPreview to open the module's filtered diff.
    self.badge = ChangesBadge:Build({
        parent = self,
        anchor = function(badge)
            badge:SetPoint("LEFT", self.label, "RIGHT", 8, 0)
        end,
    })
    self:AddHoverRegion(self.badge)

    -- Optional per-row Merge/Exact toggle, used by the apply preview. The list
    -- owner positions it at the row's right edge; rows without a choice to make
    -- (or that aren't apply rows) leave it hidden.
    self.modeButton = Button:Build({
        parent = config.parent,
        width = MODE_BUTTON_WIDTH,
        height = MODE_BUTTON_HEIGHT,
    })
    self.modeButton:SetScript("OnEnter", ShowModeTooltip)
    self.modeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.modeButton:Hide()
    self:AddHoverRegion(self.modeButton)
end

function ModuleRow:Build(parent)
    C:IsTable(parent, 2)

    return Checkbox:Build({
        parent = parent,
        methods = Methods,
    })
end

-- Wire the change badge to open this module's filtered diff, or clear it. When
-- set, the badge shows as a blue-on-hover link wherever the counts are shown.
function Methods:SetPreview(onClick)
    self.badge:SetPreview(onClick)
end

function Methods:Update(moduleName, canApply, reason, counts, modeInfo)
    C:IsString(moduleName, 2)

    self:SetChecked(canApply)
    self:SetEnabled(canApply)
    self.label:SetText(moduleName)

    if not canApply then
        self.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        self.warning:Show()
        self.badge:SetCounts(nil)
        self.modeButton:Hide()
        return
    end

    self.warning:Hide()
    self:RenderCounts(counts)
    self:RenderMode(modeInfo)
end

-- Render the per-module change figure after the module name; hidden when the
-- module has no pending change.
function Methods:RenderCounts(counts)
    self.badge:SetCounts(counts)
end

-- Render the Merge/Exact toggle for an apply row; disabled (but shown) for
-- modules that support a single mode, and hidden when no toggle is offered.
function Methods:RenderMode(modeInfo)
    if not (modeInfo and modeInfo.visible) then
        self.modeButton._tooltip = nil
        self.modeButton:Hide()
        return
    end

    local title, body = ModeTooltip(modeInfo.mode)
    self.modeButton._tooltip = {
        title = title,
        body = body,
        footer = (modeInfo.canToggle == true)
            and L["Click to change between Exact and Merge modes."]
            or L["This module only supports X mode."]:format(title),
    }

    self.modeButton:SetText(title)
    self.modeButton:SetEnabled(modeInfo.canToggle == true)
    self.modeButton:Show()

    -- Toggling is click-driven, so refresh the tooltip in place when it is
    -- already showing for this button.
    if GameTooltip:GetOwner() == self.modeButton then
        ShowModeTooltip(self.modeButton)
    end
end
