local _, addon = ...

--[[
    SaveBar object.

    Fills an injected region with a name edit box and two buttons. "Save"
    submits a quick full-module save through onSave(name); "Save…" hands the
    name to onSaveAdvanced(name) so the caller can open the save dialog (module
    subset + note). Both clear the box once a non-empty name is submitted.

    addon:GetObject("SaveBar"):Build(region, {
        onSave = function(name) end,
        onSaveAdvanced = function(name) end,
    }) -> self
]]

local SaveBar = addon:NewObject("SaveBar")

local L = addon.L

function SaveBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    local saveBox = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    saveBox:SetPoint("LEFT", 0, 0)
    saveBox:SetHeight(22)
    saveBox:SetAutoFocus(false)
    saveBox:SetMaxLetters(50)

    local moreButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    moreButton:SetPoint("RIGHT", 0, 0)
    moreButton:SetSize(56, 22)
    moreButton:SetText(L["Save…"])

    local saveButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    saveButton:SetPoint("RIGHT", moreButton, "LEFT", -4, 0)
    saveButton:SetSize(56, 22)
    saveButton:SetText(L["Save"])

    saveBox:SetPoint("RIGHT", saveButton, "LEFT", -4, 0)

    -- Read the trimmed name, fire the handler, and clear the box. Returns the
    -- name (or nil when empty so nothing happens).
    local function Take()
        local name = strtrim(saveBox:GetText())
        if name == "" then
            return nil
        end
        saveBox:SetText("")
        saveBox:ClearFocus()
        return name
    end

    local function Submit()
        local name = Take()
        if name and opts.onSave then
            opts.onSave(name)
        end
    end

    saveButton:SetScript("OnClick", Submit)
    saveBox:SetScript("OnEnterPressed", Submit)

    moreButton:SetScript("OnClick", function()
        local name = Take()
        if name and opts.onSaveAdvanced then
            opts.onSaveAdvanced(name)
        end
    end)

    return self
end
