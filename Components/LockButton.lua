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

local C = LibStub("Contracts-1.0")
local L = addon.L

function LockButton:Build(parent, anchorTo, opts)
    C:IsTable(parent, 2)
    C:IsTable(anchorTo, 3)

    opts = opts or {}

    C:Ensures(opts.onToggle == nil or type(opts.onToggle) == "function", "Build: 'opts.onToggle' must be a function")

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    button:SetPoint("RIGHT", anchorTo, "LEFT", -2, 0)

    -- A clean, centred padlock that fills its texture (unlike the legacy
    -- LockButton-* art, which is a dark item-overlay square). State is conveyed
    -- by brightness rather than swapping textures: a bright, fully-coloured lock
    -- when locked; a dim, desaturated one when unlocked.
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(16, 16)
    button.icon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")

    local isLocked = false
    local isHovered = false

    local function UpdateAppearance()
        button.icon:SetDesaturated(not isLocked)
        if isLocked then
            button.icon:SetVertexColor(1, 1, 1)
            button.icon:SetAlpha(isHovered and 1 or 0.95)
        else
            button.icon:SetVertexColor(0.85, 0.85, 0.85)
            button.icon:SetAlpha(isHovered and 0.9 or 0.55)
        end
    end

    -- Reflect the locked state in the icon.
    function button:SetLocked(locked)
        isLocked = locked and true or false
        UpdateAppearance()
    end

    button:SetScript("OnClick", function()
        if opts.onToggle then
            opts.onToggle(not isLocked)
        end
    end)
    button:SetScript("OnEnter", function(self)
        isHovered = true
        UpdateAppearance()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(isLocked and L["Unlock window"] or L["Lock window"])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        isHovered = false
        UpdateAppearance()
        GameTooltip:Hide()
    end)

    button:SetLocked(opts.locked)

    return button
end
