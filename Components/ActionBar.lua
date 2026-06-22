local _, addon = ...

local L = addon.L

--[[
    ActionBar object.

    Fills an injected region with the profile action buttons: Apply, Revert,
    Rename, Delete. Each button invokes the matching callback. The Revert button
    can be enabled/disabled to reflect whether a revert point exists.

    addon:GetObject("ActionBar"):Build(region, {
        onApply, onRevert, onRename, onDelete,  -- functions
    })
        -> self { SetRevertEnabled(enabled) }
]]

local ActionBar = addon:NewObject("ActionBar")

local revertButton

function ActionBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    local applyButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    applyButton:SetPoint("BOTTOMLEFT", 0, 0)
    applyButton:SetSize(80, 24)
    applyButton:SetText(L["Apply"])

    revertButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    revertButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    revertButton:SetSize(80, 24)
    revertButton:SetText(L["Revert"])

    local renameButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    renameButton:SetPoint("LEFT", revertButton, "RIGHT", 6, 0)
    renameButton:SetSize(80, 24)
    renameButton:SetText(L["Rename"])

    local deleteButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    deleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
    deleteButton:SetSize(80, 24)
    deleteButton:SetText(L["Delete"])

    applyButton:SetScript("OnClick", function()
        if opts.onApply then opts.onApply() end
    end)
    revertButton:SetScript("OnClick", function()
        if opts.onRevert then opts.onRevert() end
    end)
    renameButton:SetScript("OnClick", function()
        if opts.onRename then opts.onRename() end
    end)
    deleteButton:SetScript("OnClick", function()
        if opts.onDelete then opts.onDelete() end
    end)

    return self
end

function ActionBar:SetRevertEnabled(enabled)
    revertButton:SetEnabled(enabled)
end
