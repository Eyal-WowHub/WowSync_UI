local _, addon = ...

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

local C = LibStub("Contracts-1.0")
local L = addon.L

local undoButton

function ActionBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onApply == nil or type(opts.onApply) == "function", "Build: 'opts.onApply' must be a function")
    C:Ensures(opts.onUndo == nil or type(opts.onUndo) == "function", "Build: 'opts.onUndo' must be a function")
    C:Ensures(opts.onRename == nil or type(opts.onRename) == "function", "Build: 'opts.onRename' must be a function")
    C:Ensures(opts.onDelete == nil or type(opts.onDelete) == "function", "Build: 'opts.onDelete' must be a function")

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
