local _, addon = ...

--[[
    Button widget (shared push button).

    A UIPanelButtonTemplate button that follows the widget model: build it
    through addon:GetObject("Button"):Build(config) and drive it through its
    verbs. Beyond the label/enabled/click basics it owns the "busy" spinner and
    the one-shot confirmation flash that action buttons reuse.

    local button = addon:GetObject("Button"):Build({
        parent = frame,                    -- required, frame the button lives in
        anchor = function(button) ... end, -- optional, positions the button
        width = 80, height = 24,           -- optional size (set together)
        text = L["Apply"],                  -- optional label
        enabled = false,                    -- optional initial state
        onClick = function() ... end,       -- optional click handler
    })

    button:SetLabel(text)
    button:SetBusy(isBusy)   -- spinner + lock while an action is in flight
    button:Flash(text)       -- brief rising/fading confirmation
]]

local Button = addon:NewObject("Button")

local C = LibStub("Contracts-1.0")

-- How long the confirmation flash rises and fades.
local FLASH_SECONDS = 0.9

local verbs = {}

function verbs:SetLabel(text)
    self:SetText(text or "")
end

-- Enter/leave the busy state: a centered spinner replaces the label and the
-- button locks. Leaving restores the label but not the enabled state -- "not
-- busy" does not imply "enabled", so the caller restores that.
function verbs:SetBusy(isBusy)
    if isBusy then
        if not self._spinner then
            local spinner = CreateFrame("Frame", nil, self, "SpinnerTemplate")
            spinner:SetSize(18, 18)
            spinner:SetPoint("CENTER")
            spinner:Hide()
            self._spinner = spinner
        end
        if self._flash then self._flash:Stop() end
        self._label = self:GetText()
        self:SetEnabled(false)
        self:SetText("")
        self._spinner:Show()
    elseif self._spinner then
        self._spinner:Hide()
        self:SetText(self._label or "")
    end
end

-- Play a one-shot confirmation that rises and fades over the button.
function verbs:Flash(text)
    if not self._flash then
        local label = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetTextColor(0.3, 1, 0.3)
        label:Hide()
        self._flashText = label

        local flash = label:CreateAnimationGroup()
        local fade = flash:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.2)
        fade:SetDuration(FLASH_SECONDS - 0.2)
        local rise = flash:CreateAnimation("Translation")
        rise:SetOffset(0, 14)
        rise:SetDuration(FLASH_SECONDS)
        flash:SetScript("OnPlay", function() label:Show() end)
        flash:SetScript("OnStop", function() label:Hide() end)
        flash:SetScript("OnFinished", function() label:Hide() end)
        self._flash = flash
    end

    self._flashText:SetText(text or "")
    self._flash:Restart()
end

function verbs:Init(config)
    if config.text then self:SetLabel(config.text) end
    if config.enabled ~= nil then self:SetEnabled(config.enabled) end
    if config.onClick then
        C:Ensures(type(config.onClick) == "function", "Build: 'config.onClick' must be a function")
        self:SetScript("OnClick", config.onClick)
    end
end

function Button:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")
    C:Ensures(config.anchor == nil or type(config.anchor) == "function", "Build: 'config.anchor' must be a function")

    return addon:NewWidget(config, {
        frameType = "Button",
        template = "UIPanelButtonTemplate",
        verbs = verbs,
    })
end
