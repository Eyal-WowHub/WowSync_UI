local _, addon = ...

local L = addon.L

--[[
    UndoBanner object.

    The empty-state undo affordance: a centered-bottom Undo button plus an
    info line describing the last apply. Shown only when no profile is selected
    but an undo point exists.

    addon:GetObject("UndoBanner"):Build(region, { onUndo = function })
        -> self { SetState(hasUndo, info) }
            info = { Subject, Timestamp, ModuleNames } (when hasUndo)
]]

local UndoBanner = addon:NewObject("UndoBanner")

local button, info

function UndoBanner:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    button:SetPoint("BOTTOM", 0, 10)
    button:SetSize(120, 24)
    button:SetText(L["Undo"])
    button:Hide()

    info = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("BOTTOM", button, "TOP", 0, 4)
    info:Hide()

    button:SetScript("OnClick", function()
        if opts.onUndo then
            opts.onUndo()
        end
    end)

    return self
end

function UndoBanner:SetState(hasUndo, undoInfo)
    if hasUndo and undoInfo then
        info:SetText(L["Last applied: X"]:format(undoInfo.Subject or L["Unknown"]))
        info:Show()
        button:Show()
    else
        info:Hide()
        button:Hide()
    end
end
