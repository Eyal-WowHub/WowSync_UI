local _, addon = ...

--[[
    ActionBar object.

    Fills an injected region with the profile action buttons: Apply, Undo, Save,
    Delete. Each button invokes the matching callback. Buttons can be
    enabled/disabled, and Save animates a spinner while a save is in flight and a
    brief confirmation flourish after it stores.

    addon:GetObject("ActionBar"):Build(region, {
        onApply, onUndo, onSave, onDelete,  -- functions
    })
        -> self {
            SetApplyEnabled(enabled),
            SetUndoEnabled(enabled),
            SetSaveEnabled(enabled),
            SetDeleteEnabled(enabled),
            BeginSaving(),
            EndSaving(storedSnapshot),
        }
]]

local ActionBar = addon:NewObject("ActionBar")

local C = LibStub("Contracts-1.0")
local L = addon.L

local SnapshotManager = WowSync:GetSnapshotManager()

local applyButton
local undoButton
local saveButton
local deleteButton

-- Keep the spinner up at least this long so a fast save is still perceptible,
-- then let the confirmation flourish linger for this long before restoring.
local SAVE_SPINNER_MIN_SECONDS = 0.5
local SAVED_FLOURISH_SECONDS = 0.9

local savingStartedAt = nil

function ActionBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onApply == nil or type(opts.onApply) == "function", "Build: 'opts.onApply' must be a function")
    C:Ensures(opts.onUndo == nil or type(opts.onUndo) == "function", "Build: 'opts.onUndo' must be a function")
    C:Ensures(opts.onSave == nil or type(opts.onSave) == "function", "Build: 'opts.onSave' must be a function")
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

    -- Save, bottom-right beside Delete.
    saveButton = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    saveButton:SetPoint("BOTTOMRIGHT", deleteButton, "BOTTOMLEFT", -6, 0)
    saveButton:SetSize(80, 24)
    saveButton:SetText(L["Save"])

    -- A loading spinner shown over the button while a save is in flight. Scaled
    -- down from the 142px shared template art.
    local spinner = CreateFrame("Frame", nil, saveButton, "SpinnerTemplate")
    spinner:SetSize(18, 18)
    spinner:SetPoint("CENTER")
    spinner:Hide()
    saveButton.spinner = spinner

    -- A brief "Saved" confirmation that rises and fades after a successful save.
    local savedText = saveButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    savedText:SetPoint("CENTER")
    savedText:SetText(L["Saved"])
    savedText:SetTextColor(0.3, 1, 0.3)
    savedText:Hide()
    saveButton.savedText = savedText

    local flourish = savedText:CreateAnimationGroup()
    local fade = flourish:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.2)
    fade:SetDuration(SAVED_FLOURISH_SECONDS - 0.2)
    local rise = flourish:CreateAnimation("Translation")
    rise:SetOffset(0, 14)
    rise:SetDuration(SAVED_FLOURISH_SECONDS)
    flourish:SetScript("OnPlay", function() savedText:Show() end)
    flourish:SetScript("OnStop", function() savedText:Hide() end)
    flourish:SetScript("OnFinished", function() savedText:Hide() end)
    saveButton.flourish = flourish

    applyButton:SetScript("OnClick", function()
        if opts.onApply then opts.onApply() end
    end)
    undoButton:SetScript("OnClick", function()
        if opts.onUndo then opts.onUndo() end
    end)
    saveButton:SetScript("OnClick", function()
        if not saveButton:IsEnabled() then return end
        if opts.onSave then opts.onSave() end
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

function ActionBar:SetSaveEnabled(enabled)
    saveButton:SetEnabled(enabled)
end

function ActionBar:SetDeleteEnabled(enabled)
    deleteButton:SetEnabled(enabled)
end

-- Enter the saving state: hide the label, spin, and lock the button until the
-- save finishes.
function ActionBar:BeginSaving()
    savingStartedAt = GetTime()
    saveButton.flourish:Stop()
    saveButton:SetEnabled(false)
    saveButton:SetText("")
    saveButton.spinner:Show()
end

-- Leave the saving state once the spinner has shown for its minimum time, then
-- play the confirmation flourish (only for a save that actually stored) and
-- restore the button.
function ActionBar:EndSaving(storedSnapshot)
    local startedAt = savingStartedAt
    local elapsed = GetTime() - (startedAt or 0)
    local remaining = math.max(0, SAVE_SPINNER_MIN_SECONDS - elapsed)

    C_Timer.After(remaining, function()
        -- A newer save began while this one was waiting out its minimum spin
        -- time; let that cycle own the button instead of restoring it here.
        if savingStartedAt ~= startedAt then
            return
        end
        saveButton.spinner:Hide()
        saveButton:SetText(L["Save"])
        ActionBar:SetSaveEnabled(SnapshotManager:HasCapturedGameData())
        if storedSnapshot then
            saveButton.flourish:Restart()
        end
    end)
end
