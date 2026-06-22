local _, addon = ...

local L = addon.L

--[[
    SaveBar object.

    Fills an injected region with a name edit box and a Save button. Submitting
    (button click or Enter) invokes the onSave callback with the trimmed name
    and clears the box.

    addon:GetObject("SaveBar"):Build(region, { onSave = function(name) })
        -> self
]]

local SaveBar = addon:NewObject("SaveBar")

function SaveBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    local saveBox = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    saveBox:SetPoint("LEFT", 0, 0)
    saveBox:SetPoint("RIGHT", -60, 0)
    saveBox:SetHeight(22)
    saveBox:SetAutoFocus(false)
    saveBox:SetMaxLetters(50)

    local saveButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    saveButton:SetPoint("LEFT", saveBox, "RIGHT", 4, 0)
    saveButton:SetSize(56, 22)
    saveButton:SetText(L["Save"])

    local function Submit()
        local name = strtrim(saveBox:GetText())
        if name ~= "" then
            if opts.onSave then
                opts.onSave(name)
            end
            saveBox:SetText("")
            saveBox:ClearFocus()
        end
    end

    saveButton:SetScript("OnClick", Submit)
    saveBox:SetScript("OnEnterPressed", Submit)

    return self
end
