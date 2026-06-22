local _, addon = ...

local L = addon.L

--[[
    RevertBanner object.

    The empty-state revert affordance: a centered-bottom Revert button plus an
    info line describing the last applied profile. Shown only when no profile is
    selected but a revert point exists.

    addon:GetObject("RevertBanner"):Build(region, { onRevert = function })
        -> self { SetState(hasRevert, info) }
            info = { ProfileName, Timestamp } (when hasRevert)
]]

local RevertBanner = addon:NewObject("RevertBanner")

local button, info

function RevertBanner:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    button:SetPoint("BOTTOM", 0, 10)
    button:SetSize(120, 24)
    button:SetText(L["Revert"])
    button:Hide()

    info = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("BOTTOM", button, "TOP", 0, 4)
    info:Hide()

    button:SetScript("OnClick", function()
        if opts.onRevert then
            opts.onRevert()
        end
    end)

    return self
end

function RevertBanner:SetState(hasRevert, revertInfo)
    if hasRevert and revertInfo then
        info:SetText(L["Last applied: X (Y)"]:format(
            revertInfo.ProfileName or L["Unknown"],
            date("%H:%M", revertInfo.Timestamp)
        ))
        info:Show()
        button:Show()
    else
        info:Hide()
        button:Hide()
    end
end
