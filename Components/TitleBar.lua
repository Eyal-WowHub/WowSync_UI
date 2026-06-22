local _, addon = ...

--[[
    TitleBar object.

    Fills an injected region with a title label and a close button.

    addon:GetObject("TitleBar"):Build(region, { title = string, onClose = function })
        -> self { SetTitle(text) }
]]

local TitleBar = addon:NewObject("TitleBar")

local titleText

function TitleBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetText(opts.title or "")

    local closeButton = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    closeButton:SetPoint("RIGHT", 2, 0)
    closeButton:SetScript("OnClick", function()
        if opts.onClose then
            opts.onClose()
        end
    end)

    return self
end

function TitleBar:SetTitle(text)
    titleText:SetText(text)
end
