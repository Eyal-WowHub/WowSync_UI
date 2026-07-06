local _, addon = ...

--[[
    LockButton object.

    A small padlock toggle for window chrome. Anchored to the left of a sibling
    region (typically the close button) and reports each toggle through
    onToggle(locked). The icon shows the *current* state: a closed padlock when
    locked, an open padlock when unlocked.

    addon:GetObject("LockButton"):Build(parent, anchorTo, {
        onToggle = function(locked),
        locked = boolean,
    }) -> Button { SetLocked(locked) }
]]

local LockButton = addon:NewObject("LockButton")

local C = addon.C
local L = addon.L

local Methods = {}

-- Repaint the padlock for the current locked/hover state: a bright, fully
-- coloured lock when locked; a dim, desaturated one when unlocked.
function Methods:UpdateAppearance()
    self.icon:SetDesaturated(not self._isLocked)
    if self._isLocked then
        self.icon:SetVertexColor(1, 1, 1)
        self.icon:SetAlpha(self._isHovered and 1 or 0.95)
    else
        self.icon:SetVertexColor(0.85, 0.85, 0.85)
        self.icon:SetAlpha(self._isHovered and 0.9 or 0.55)
    end
end

-- Reflect the locked state in the icon.
function Methods:SetLocked(locked)
    self._isLocked = locked and true or false
    self:UpdateAppearance()
end

function Methods:Constructor(config)
    self._isLocked = false
    self._isHovered = false

    self:SetSize(20, 20)
    self:SetPoint("RIGHT", config.anchorTo, "LEFT", -2, 0)

    -- A clean, centred padlock that fills its texture (unlike the legacy
    -- LockButton-* art, which is a dark item-overlay square). State is conveyed
    -- by brightness rather than swapping textures.
    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("CENTER")
    self.icon:SetSize(16, 16)
    self.icon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")

    self:SetScript("OnClick", function(self)
        if config.onToggle then
            config.onToggle(not self._isLocked)
        end
    end)
    self:SetScript("OnEnter", function(self)
        self._isHovered = true
        self:UpdateAppearance()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self._isLocked and L["Unlock window"] or L["Lock window"])
        GameTooltip:Show()
    end)
    self:SetScript("OnLeave", function(self)
        self._isHovered = false
        self:UpdateAppearance()
        GameTooltip:Hide()
    end)

    self:SetLocked(config.locked)
end

function LockButton:Build(parent, anchorTo, opts)
    C:IsTable(parent, 2)
    C:IsTable(anchorTo, 3)

    opts = opts or {}

    C:Ensures(opts.onToggle == nil or type(opts.onToggle) == "function", "Build: 'opts.onToggle' must be a function")

    return addon:NewWidget({
        parent = parent,
        anchorTo = anchorTo,
        onToggle = opts.onToggle,
        locked = opts.locked,
    }, {
        frameType = "Button",
        methods = Methods,
    })
end
