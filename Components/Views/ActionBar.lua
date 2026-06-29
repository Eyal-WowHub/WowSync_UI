local _, addon = ...

--[[
    ActionBar object.

    Fills an injected region with the profile action buttons: Apply, Undo, Save.
    Each button invokes the matching callback. Buttons can be enabled/disabled,
    and Save animates a spinner while a save is in flight and a brief
    confirmation flourish after it stores.

    addon:GetObject("ActionBar"):Build(region, {
        onApply, onUndo, onSave,  -- functions
    })
        -> action-bar frame {
            SetApplyEnabled(enabled),
            SetUndoEnabled(enabled),
            SetSaveEnabled(enabled),
            BeginSaving(),
            EndSaving(storedSnapshot),
        }
]]

local ActionBar = addon:NewObject("ActionBar")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L

local SnapshotManager = WowSync:GetSnapshotManager()

-- Keep the spinner up at least this long so a fast save is still perceptible.
local SAVE_SPINNER_MIN_SECONDS = 0.5

local Verbs = {}

function Verbs:Constructor(config)
    local applyButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMLEFT", 0, 0)
        end,
        width = 80,
        height = 24,
        text = L["Apply"],
    })

    local undoButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("LEFT", applyButton, "RIGHT", 6, 0)
        end,
        width = 80,
        height = 24,
        text = L["Undo"],
    })

    -- Save, bottom-right.
    local saveButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", 0, 0)
        end,
        width = 80,
        height = 24,
        text = L["Save"],
    })

    applyButton:SetScript("OnClick", function()
        if config.onApply then config.onApply() end
    end)
    undoButton:SetScript("OnClick", function()
        if config.onUndo then config.onUndo() end
    end)
    saveButton:SetScript("OnClick", function()
        if not saveButton:IsEnabled() then return end
        if config.onSave then config.onSave() end
    end)

    self._applyButton = applyButton
    self._undoButton = undoButton
    self._saveButton = saveButton
    self._savingStartedAt = nil
end

function Verbs:SetApplyEnabled(enabled)
    self._applyButton:SetEnabled(enabled)
end

function Verbs:SetUndoEnabled(enabled)
    self._undoButton:SetEnabled(enabled)
end

function Verbs:SetSaveEnabled(enabled)
    self._saveButton:SetEnabled(enabled)
end

-- Enter the saving state: hide the label, spin, and lock the button until the
-- save finishes.
function Verbs:BeginSaving()
    self._savingStartedAt = GetTime()
    self._saveButton:SetBusy(true)
end

-- Leave the saving state once the spinner has shown for its minimum time, then
-- play the confirmation flourish (only for a save that actually stored) and
-- restore the button.
function Verbs:EndSaving(storedSnapshot)
    local bar = self
    local startedAt = self._savingStartedAt
    local elapsed = GetTime() - (startedAt or 0)
    local remaining = math.max(0, SAVE_SPINNER_MIN_SECONDS - elapsed)

    C_Timer.After(remaining, function()
        -- A newer save began while this one was waiting out its minimum spin
        -- time; let that cycle own the button instead of restoring it here.
        if bar._savingStartedAt ~= startedAt then
            return
        end
        bar._saveButton:SetBusy(false)
        bar:SetSaveEnabled(SnapshotManager:HasCapturedGameData())
        if storedSnapshot then
            bar._saveButton:Flash(L["Saved"])
        end
    end)
end

function ActionBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onApply == nil or type(opts.onApply) == "function", "Build: 'opts.onApply' must be a function")
    C:Ensures(opts.onUndo == nil or type(opts.onUndo) == "function", "Build: 'opts.onUndo' must be a function")
    C:Ensures(opts.onSave == nil or type(opts.onSave) == "function", "Build: 'opts.onSave' must be a function")

    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
        onApply = opts.onApply,
        onUndo = opts.onUndo,
        onSave = opts.onSave,
    }, {
        frameType = "Frame",
        verbs = Verbs,
    })
end
