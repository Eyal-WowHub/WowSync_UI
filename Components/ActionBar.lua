local _, addon = ...

--[[
    ActionBar object.

    Fills an injected region with the profile action buttons: Apply, Undo,
    Delete. Each button invokes the matching callback. The Undo button can be
    enabled/disabled to reflect whether an undo point exists.

    addon:GetObject("ActionBar"):Build(region, {
        onApply, onUndo, onDelete,  -- functions
    })
        -> self {
            SetApplyEnabled(enabled),
            SetUndoEnabled(enabled),
            SetDeleteEnabled(enabled),
        }
]]

local ActionBar = addon:NewObject("ActionBar")

local C = LibStub("Contracts-1.0")
local L = addon.L

local applyButton
local undoButton
local deleteButton

function ActionBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onApply == nil or type(opts.onApply) == "function", "Build: 'opts.onApply' must be a function")
    C:Ensures(opts.onUndo == nil or type(opts.onUndo) == "function", "Build: 'opts.onUndo' must be a function")
    C:Ensures(opts.onDelete == nil or type(opts.onDelete) == "function", "Build: 'opts.onDelete' must be a function")

    local root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    applyButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    applyButton:SetPoint("BOTTOMLEFT", 0, 0)
    applyButton:SetSize(80, 24)
    applyButton:SetText(L["Apply"])

    undoButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    undoButton:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
    undoButton:SetSize(80, 24)
    undoButton:SetText(L["Undo"])

    deleteButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    deleteButton:SetPoint("BOTTOMRIGHT", 0, 0)
    deleteButton:SetSize(80, 24)
    deleteButton:SetText(L["Delete"])

    applyButton:SetScript("OnClick", function()
        if opts.onApply then opts.onApply() end
    end)
    undoButton:SetScript("OnClick", function()
        if opts.onUndo then opts.onUndo() end
    end)
    deleteButton:SetScript("OnClick", function()
        if opts.onDelete then opts.onDelete() end
    end)

    return self
end

function ActionBar:SetApplyEnabled(enabled)
    applyButton:SetEnabled(enabled)
end

function ActionBar:SetUndoEnabled(enabled)
    undoButton:SetEnabled(enabled)
end

function ActionBar:SetDeleteEnabled(enabled)
    deleteButton:SetEnabled(enabled)
end
