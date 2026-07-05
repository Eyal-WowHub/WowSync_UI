local _, addon = ...

--[[
    ChangesBadge widget (the interactive per-module change figure).

    A ChangesBadge IS a Button that renders a module's pending change figure
    (formatted by the addon's diff formatter) and doubles as a link: give it a preview
    handler and hovering tints it blue and shows a hint while clicking opens that
    module's filtered diff. Without a handler it stays plain, non-interactive
    text, and it hides itself when there is no change.

        local badge = addon:GetObject("ChangesBadge"):Build({
            parent = frame,
            anchor = function(badge) badge:SetPoint("LEFT", label, "RIGHT", 8, 0) end,
        })
        badge:SetCounts({ added = 1, changed = 2, removed = 0 })  -- render, or hide
        badge:SetPreview(onClick)                                 -- wire / clear the link
]]

local ChangesBadge = addon:NewObject("ChangesBadge")

local C = LibStub("Contracts-1.0")

local L = addon.L

local ChangeBadge = WowSync:Import("ChangeBadge")

-- The badge's resting white and the blue-ish hover that signals it opens the
-- module's filtered change preview.
local BADGE_COLOR = { 1, 1, 1 }
local BADGE_HOVER_COLOR = { 0.4, 0.7, 1 }

-- Strip WoW colour escapes (|cAARRGGBB … |r) from a string. The resting text
-- colours each figure green/amber/red inline, which would override a plain
-- SetTextColor, so the hover tint swaps to the stripped text first.
local function StripColorCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local Methods = {}

-- Render the change figure, sizing the badge to fit its text; hides the badge
-- when the module has no pending change.
function Methods:SetCounts(counts)
    local text = ChangeBadge.FormatDiffString(counts)
    if text == "" then
        self._colored = nil
        self:Hide()
        return
    end

    self._colored = text
    self.text:SetText(text)
    self.text:SetTextColor(unpack(BADGE_COLOR))
    self:SetSize(self.text:GetStringWidth(), self.text:GetStringHeight())
    self:Show()
end

-- Wire the badge to open a module's filtered diff, or clear it. With a handler
-- the badge acts as a blue-on-hover link; without one it is plain text.
function Methods:SetPreview(onClick)
    self._onPreview = onClick
    self:SetScript("OnClick", onClick or nil)
end

function Methods:Constructor()
    self.text = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.text:SetPoint("LEFT")
    self.text:SetTextColor(unpack(BADGE_COLOR))

    self:SetScript("OnEnter", function()
        if not self._onPreview then return end
        self.text:SetText(StripColorCodes(self._colored or ""))
        self.text:SetTextColor(unpack(BADGE_HOVER_COLOR))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Click here to see the changes"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self:SetScript("OnLeave", function()
        if not self._onPreview then return end
        self.text:SetTextColor(unpack(BADGE_COLOR))
        self.text:SetText(self._colored or "")
        GameTooltip:Hide()
    end)

    self:Hide()
end

function ChangesBadge:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")

    return addon:NewWidget(config, {
        frameType = "Button",
        methods = Methods,
    })
end
