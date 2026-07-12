local _, addon = ...

--[[
    ModuleRow widget (checkbox row).

    A module checkbox row for ModuleList, built on the Checkbox widget: the box
    and its label come from Checkbox (clicking either toggles the module, and the
    row lights a Settings-style hover). ModuleRow adds the module's warning, a
    per-module change badge that opens the module's filtered diff, and an optional
    Merge/Exact switch. The row IS the CheckButton; ModuleList pools and positions it.

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

local ChangesBadge = addon:GetObject("ChangesBadge")
local Checkbox = addon:GetObject("Checkbox")
local ApplyModeSwitch = addon:GetObject("ApplyModeSwitch")

-- Size of the per-row Merge/Exact switch shown on apply rows.
local MODE_SWITCH_WIDTH = 116
local MODE_SWITCH_HEIGHT = 18

local Methods = {}

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

    -- Optional per-row Merge/Exact switch, used by the apply preview. The list
    -- owner positions it at the row's right edge and wires its selection; rows
    -- without a choice to make (or that aren't apply rows) leave it hidden.
    self.modeSwitch = ApplyModeSwitch:Build({
        parent = config.parent,
        width = MODE_SWITCH_WIDTH,
        height = MODE_SWITCH_HEIGHT,
    })
    self.modeSwitch:Hide()
    self:AddHoverRegion(self.modeSwitch)
    for _, radio in ipairs(self.modeSwitch.radios) do
        self:AddHoverRegion(radio)
    end
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
        self.modeSwitch:Hide()
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

-- Render the Merge/Exact switch for an apply row: a two-segment switch when the
-- module supports both modes, a single fixed pill when it supports one, and
-- hidden when no mode control is offered.
function Methods:RenderMode(modeInfo)
    if not (modeInfo and modeInfo.visible) then
        self.modeSwitch:Hide()
        return
    end

    self.modeSwitch:Configure({
        mode = modeInfo.mode,
        canToggle = modeInfo.canToggle == true,
    })
    self.modeSwitch:Show()
end
