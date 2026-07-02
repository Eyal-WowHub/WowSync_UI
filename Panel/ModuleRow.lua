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
local Button = addon:GetObject("Button")
local Checkbox = addon:GetObject("Checkbox")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Size of the per-row Merge/Exact toggle shown on apply rows.
local MODE_BUTTON_WIDTH = 58
local MODE_BUTTON_HEIGHT = 18

-- Change-badge colours: the resting white and the blue-ish hover that signals
-- the badge opens that module's filtered change preview.
local BADGE_COLOR = { 1, 1, 1 }
local BADGE_HOVER_COLOR = { 0.4, 0.7, 1 }

-- Strip WoW colour escapes (|cAARRGGBB … |r) from a string. The badge's resting
-- text colours each figure green/amber/red inline, which would override a plain
-- SetTextColor, so the hover tint swaps to the stripped text first.
local function StripColorCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

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

    -- Per-module change counts, shown after the name for applicable rows.
    -- Anchored to the label (not the list) so it tracks the row vertically;
    -- mutually exclusive with the warning, so they share the same slot.
    self.counts = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.counts:SetPoint("LEFT", self.label, "RIGHT", 8, 0)
    self.counts:SetTextColor(unpack(BADGE_COLOR))

    -- An invisible button over the change counts that turns the badge into a
    -- link: hovering tints it blue and shows a hint, clicking opens the module's
    -- filtered diff. The list owner wires the click through SetPreview; rows
    -- without a preview keep the badge as plain text.
    self.countsButton = CreateFrame("Button", nil, self)
    self.countsButton:SetAllPoints(self.counts)
    self.countsButton:SetScript("OnEnter", function()
        self.counts:SetText(StripColorCodes(self._countsColored or ""))
        self.counts:SetTextColor(unpack(BADGE_HOVER_COLOR))
        GameTooltip:SetOwner(self.countsButton, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Click here to see the changes"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.countsButton:SetScript("OnLeave", function()
        self.counts:SetTextColor(unpack(BADGE_COLOR))
        self.counts:SetText(self._countsColored or "")
        GameTooltip:Hide()
    end)
    self.countsButton:Hide()
    self:AddHoverRegion(self.countsButton)

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
    self._onPreview = onClick
    self.countsButton:SetScript("OnClick", onClick or nil)
    self.countsButton:SetShown(onClick ~= nil and self.counts:IsShown())
end

function Methods:Update(moduleName, canApply, reason, counts, modeInfo)
    C:IsString(moduleName, 2)

    self:SetChecked(canApply)
    self:SetEnabled(canApply)
    self.label:SetText(moduleName)

    if not canApply then
        self.warning:SetText("(" .. (reason or L["cannot apply"]) .. ")")
        self.warning:Show()
        self.counts:Hide()
        self.countsButton:Hide()
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
    local added = counts and counts.added or 0
    local changed = counts and counts.changed or 0
    local removed = counts and counts.removed or 0

    if added > 0 or changed > 0 or removed > 0 then
        if removed > 0 then
            self._countsColored = L["+A ~C -R"]:format(added, changed, removed)
        else
            self._countsColored = L["+A ~C"]:format(added, changed)
        end
        self.counts:SetText(self._countsColored)
        self.counts:Show()
        self.countsButton:SetShown(self._onPreview ~= nil)
    else
        self.counts:Hide()
        self.countsButton:Hide()
    end
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
