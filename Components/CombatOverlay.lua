local _, addon = ...

--[[
    CombatOverlay object.

    A modal scrim over the window, shown while the player is in combat, since
    saving and applying snapshots are only allowed out of combat. It dims the
    area it covers, swallows mouse input so nothing underneath can be clicked,
    and centres a card with the combat icon and a short explanation. Parented to
    the window so it tracks its position and size, and toggled by the player's
    combat state.

    addon:GetObject("CombatOverlay"):Build(parent, { topInset = number })
]]

local CombatOverlay = addon:NewObject("CombatOverlay")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

-- The in-combat icon Blizzard shows on the player frame (crossed swords).
local COMBAT_ICON_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon"

-- Notice card geometry and the icon size on it.
local CARD_WIDTH = 300
local CARD_HEIGHT = 116
local ICON_SIZE = 40

-- Opacity of the scrim that dims the window behind the card.
local SCRIM_ALPHA = 0.72

-- Frame-level bump that lifts the overlay above every panel beneath it.
local OVERLAY_LEVEL_BUMP = 100

local overlay

function CombatOverlay:Build(parent, opts)
    C:IsTable(parent, 2)

    opts = opts or {}
    local topInset = opts.topInset or 0

    -- Cover everything below the title bar so the window can still be moved and
    -- closed, but its contents cannot be acted on.
    overlay = CreateFrame("Frame", nil, parent)
    overlay:SetPoint("TOPLEFT", 0, -topInset)
    overlay:SetPoint("BOTTOMRIGHT", 0, 0)
    overlay:SetFrameLevel(parent:GetFrameLevel() + OVERLAY_LEVEL_BUMP)
    overlay:EnableMouse(true)

    -- Dim the window behind the card.
    local scrim = overlay:CreateTexture(nil, "BACKGROUND")
    scrim:SetAllPoints()
    scrim:SetColorTexture(0, 0, 0, SCRIM_ALPHA)

    -- Centred notice card.
    local card = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    card:SetPoint("CENTER")
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(unpack(UI.Backdrop.Main))
    card:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(COMBAT_ICON_ATLAS)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOP", 0, -14)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
    title:SetText(L["In combat"])

    local body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOP", title, "BOTTOM", 0, -6)
    body:SetPoint("LEFT", card, "LEFT", 12, 0)
    body:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    body:SetJustifyH("CENTER")
    body:SetText(L["Saving and applying are paused until you leave combat."])

    -- Track combat directly so the scrim stays correct even while the window is
    -- hidden (events still fire) and the moment it next opens.
    overlay:RegisterEvent("PLAYER_REGEN_DISABLED")
    overlay:RegisterEvent("PLAYER_REGEN_ENABLED")
    overlay:SetScript("OnEvent", function(self, event)
        self:SetShown(event == "PLAYER_REGEN_DISABLED")
    end)

    overlay:SetShown(InCombatLockdown())

    return self
end
