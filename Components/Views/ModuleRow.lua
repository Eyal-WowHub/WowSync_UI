local _, addon = ...

--[[
    ModuleRow widget (checkbox row).

    A module checkbox row for ModuleList: a checkbox with a label, an optional
    warning, a per-module change count, and an optional Merge/Exact toggle. The
    row IS the CheckButton; ModuleList pools and positions it.

    addon:GetObject("ModuleRow"):Build(parent)   -- creates the checkbox widget
        -> checkbox frame {
            SetNameLink(onClick),
            Update(name, canApply, reason, counts, modeInfo),
            RenderCounts(counts),
            RenderMode(modeInfo),
        }
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

local Verbs = {}

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

function Verbs:Constructor(config)
    self:SetSize(24, 24)

    self.label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.label:SetPoint("LEFT", self, "RIGHT", 2, 0)

    -- An invisible button matching the name's bounds that turns it into a link:
    -- hovering tints the name blue. The list owner opts a row in (and wires the
    -- click) through SetNameLink; rows left out stay plain text.
    self.nameLink = CreateFrame("Button", nil, self)
    self.nameLink:SetAllPoints(self.label)
    self.nameLink:SetScript("OnEnter", function()
        self.label:SetTextColor(unpack(LINK_HOVER_COLOR))
    end)
    self.nameLink:SetScript("OnLeave", function()
        self.label:SetTextColor(unpack(LINK_COLOR))
    end)
    self.nameLink:Hide()

    self.warning = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.warning:SetPoint("LEFT", self.label, "RIGHT", 6, 0)

    -- Per-module change counts, shown after the name for applicable rows.
    -- Anchored to the label (not the list) so it tracks the row vertically;
    -- mutually exclusive with the warning, so they share the same slot.
    self.counts = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.counts:SetPoint("LEFT", self.label, "RIGHT", 8, 0)

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
end

function ModuleRow:Build(parent)
    C:IsTable(parent, 2)

    return addon:NewWidget({ parent = parent }, {
        frameType = "CheckButton",
        template = "UICheckButtonTemplate",
        verbs = Verbs,
    })
end

-- Turn the module name into a clickable link with the given click handler, or
-- restore it to plain text when no handler is given.
function Verbs:SetNameLink(onClick)
    self.label:SetTextColor(unpack(LINK_COLOR))
    if onClick then
        self.nameLink:SetScript("OnClick", onClick)
        self.nameLink:Show()
    else
        self.nameLink:SetScript("OnClick", nil)
        self.nameLink:Hide()
    end
end

function Verbs:Update(moduleName, canApply, reason, counts, modeInfo)
    C:IsString(moduleName, 2)

    self:SetChecked(canApply)
    self:SetEnabled(canApply)
    self.label:SetText(moduleName)

    if not canApply then
        self.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        self.warning:Show()
        self.counts:Hide()
        self.modeButton:Hide()
        return
    end

    self.warning:Hide()
    self:RenderCounts(counts)
    self:RenderMode(modeInfo)
end

-- Render the per-module change figure after the module name; hidden when the
-- module has no pending change.
function Verbs:RenderCounts(counts)
    local added = counts and counts.added or 0
    local changed = counts and counts.changed or 0
    local removed = counts and counts.removed or 0

    if added > 0 or changed > 0 or removed > 0 then
        if removed > 0 then
            self.counts:SetText(L["+A ~C -R"]:format(added, changed, removed))
        else
            self.counts:SetText(L["+A ~C"]:format(added, changed))
        end
        self.counts:Show()
    else
        self.counts:Hide()
    end
end

-- Render the Merge/Exact toggle for an apply row; disabled (but shown) for
-- modules that support a single mode, and hidden when no toggle is offered.
function Verbs:RenderMode(modeInfo)
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
