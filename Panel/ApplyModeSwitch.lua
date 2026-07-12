local _, addon = ...

--[[
    ApplyModeSwitch object (the Merge/Exact radio pair).

    A composite of two native radio buttons -- Merge and Exact -- for a module
    row's apply mode, drawn with WoW's dropdown radial art. The selected mode's
    radio is filled; clicking the other selects it, and the two stay mutually
    exclusive. A module that supports only one mode shows both radios with the
    supported one selected and both disabled, so the fixed mode is visible but
    cannot be changed.

    addon:GetObject("ApplyModeSwitch"):Build({
        parent = frame,                    -- required, frame the switch lives in
        width = 116, height = 18,          -- optional size
        onSelect = function(mode) ... end, -- optional, "merge" | "exact" on click
    }) -> Frame {
        radios,                            -- the two radio buttons (hit areas)
        SetOnSelect(fn),
        Configure({ mode, canToggle }),    -- reflect current mode / available modes
    }
]]

local ApplyModeSwitch = addon:NewObject("ApplyModeSwitch")

local C = addon.C
local L = addon.L

-- Fallback size when the caller does not supply one.
local DEFAULT_WIDTH = 116
local DEFAULT_HEIGHT = 18

-- Dimmed alpha for a disabled (single-mode) radio, so a fixed mode reads as
-- present but not changeable.
local DISABLED_ALPHA = 0.55

-- Title and body text for a mode's tooltip.
local function ModeText(mode)
    if mode == "exact" then
        return L["Exact"], L["Exact mode tooltip"]
    end
    return L["Merge"], L["Merge mode tooltip"]
end

-- Draw a radio's tooltip: the mode's name and description, then a footer keyed
-- to the radio's state -- an invitation to select it, a note that the module is
-- locked to this mode, or nothing when it is already the selected one.
local function ShowRadioTooltip(radio)
    local title, body = ModeText(radio.mode)
    GameTooltip:SetOwner(radio, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0, 1, true)
    GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true)

    local footer
    if not radio:IsEnabled() then
        footer = L["This module only supports X mode."]:format(title)
    elseif not radio:GetChecked() then
        footer = L["Click to apply this module in X mode."]:format(title)
    end
    if footer then
        GameTooltip:AddLine(" ", 1, 1, 1, true)
        GameTooltip:AddLine(footer, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- One labelled radio button carrying its mode. Radios reflect the current
-- selection rather than toggle freely, so a click first re-asserts the known
-- state, then asks the switch to change to this mode.
local function CreateRadio(switch, mode, label)
    local radio = CreateFrame("CheckButton", nil, switch, "UIRadialButtonTemplate")
    radio.mode = mode
    radio.text:SetFontObject("GameFontHighlightSmall")
    radio.text:SetText(label)
    radio:SetMotionScriptsWhileDisabled(true)

    radio:SetScript("OnClick", function(self)
        self:SetChecked(self.mode == switch._selected)
        if self.mode ~= switch._selected and switch._onSelect then
            switch._onSelect(self.mode)
        end
    end)
    radio:SetScript("OnEnter", ShowRadioTooltip)
    radio:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return radio
end

local Methods = {}

-- Store the selection handler, called with the chosen mode when an enabled radio
-- is clicked.
function Methods:SetOnSelect(callback)
    self._onSelect = callback
end

-- Reflect the row's mode state: modeInfo.mode is the selected mode, and
-- modeInfo.canToggle whether both modes are on offer (both radios enabled) or the
-- module supports only its current one (both radios shown but disabled).
function Methods:Configure(modeInfo)
    self._selected = modeInfo.mode
    for _, radio in ipairs(self.radios) do
        radio:SetChecked(radio.mode == modeInfo.mode)
        radio:SetEnabled(modeInfo.canToggle)
        radio:SetAlpha(modeInfo.canToggle and 1 or DISABLED_ALPHA)
    end

    local owner = GameTooltip:GetOwner()
    if owner and owner.mode and owner:IsMouseOver() then
        ShowRadioTooltip(owner)
    end
end

-- Build the two radios side by side, each filling half the width so a click on
-- its label (not just the dial) selects the mode. Seeded as a two-mode switch;
-- the owner drives it with Configure.
function Methods:Constructor(config)
    self._onSelect = config.onSelect

    local half = config.width / 2
    local merge = CreateRadio(self, "merge", L["Merge"])
    local exact = CreateRadio(self, "exact", L["Exact"])
    merge:SetPoint("LEFT", self, "LEFT", 0, 0)
    exact:SetPoint("LEFT", self, "LEFT", half, 0)

    -- Extend each radio's hit area across its half so the label is clickable, not
    -- just the dial.
    local dialWidth = merge:GetWidth()
    merge:SetHitRectInsets(0, -(half - dialWidth), 0, 0)
    exact:SetHitRectInsets(0, -(half - dialWidth), 0, 0)

    self.radios = { merge, exact }
end

function ApplyModeSwitch:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")
    C:Ensures(config.onSelect == nil or type(config.onSelect) == "function", "Build: 'config.onSelect' must be a function")

    return addon:NewWidget({
        parent = config.parent,
        anchor = config.anchor,
        width = config.width or DEFAULT_WIDTH,
        height = config.height or DEFAULT_HEIGHT,
        onSelect = config.onSelect,
    }, {
        frameType = "Frame",
        methods = Methods,
    })
end
