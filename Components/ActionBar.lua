local _, addon = ...

local L = addon.L

--[[
    ActionBar object.

    Fills an injected region with the profile action buttons: Apply, Undo,
    Rename, Delete. Each button invokes the matching callback. The Undo button
    can be enabled/disabled to reflect whether an undo point exists.

    addon:GetObject("ActionBar"):Build(region, {
        onApply, onUndo, onRename, onDelete,  -- functions
    })
        -> self { SetUndoEnabled(enabled) }
]]

local ActionBar = addon:NewObject("ActionBar")

local undoButton

function ActionBar:Build(region, opts)
    opts = opts or {}

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    local applyButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    applyButton:SetPoint("BOTTOMLEFT", 0, 0)
    applyButton:SetSize(80, 24)
    applyButton:SetText(L["Apply"])

    undoButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    undoButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    undoButton:SetSize(80, 24)
    undoButton:SetText(L["Undo"])

    local renameButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    renameButton:SetPoint("LEFT", undoButton, "RIGHT", 6, 0)
    renameButton:SetSize(80, 24)
    renameButton:SetText(L["Rename"])

    local deleteButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    deleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
    deleteButton:SetSize(80, 24)
    deleteButton:SetText(L["Delete"])

    applyButton:SetScript("OnClick", function()
        if opts.onApply then opts.onApply() end
    end)
    undoButton:SetScript("OnClick", function()
        if opts.onUndo then opts.onUndo() end
    end)
    renameButton:SetScript("OnClick", function()
        if opts.onRename then opts.onRename() end
    end)
    deleteButton:SetScript("OnClick", function()
        if opts.onDelete then opts.onDelete() end
    end)

    return self
end

function ActionBar:SetUndoEnabled(enabled)
    undoButton:SetEnabled(enabled)
end
