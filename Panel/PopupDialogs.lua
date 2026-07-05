local _, addon = ...

--[[
    PopupDialogs object.

    The confirm/prompt popups the UI raises, each a thin description handed to the
    shared PopupDialog widget so every one wears the same flat Settings chrome
    (no WoW default popup). Callers pass their own callbacks; this service owns no
    state of its own.

    addon:GetObject("PopupDialogs"):ConfirmUndo(subject, onConfirm, onPreview)
    addon:GetObject("PopupDialogs"):ConfirmUndoSteps(count, subject, onConfirm)
    addon:GetObject("PopupDialogs"):ConfirmDelete(profileName, onConfirm)
    addon:GetObject("PopupDialogs"):ConfirmDeleteSnapshot(subject, onConfirm, dependentCount)
    addon:GetObject("PopupDialogs"):PromptEditNote(currentText, onAccept)  -- onAccept(trimmedText)
    addon:GetObject("PopupDialogs"):ConfirmApply(mode, onConfirm)  -- mode = "merge"|"exact"
    addon:GetObject("PopupDialogs"):ConfirmSaveAtLimit(limit, oldestSubject, onConfirm)
    addon:GetObject("PopupDialogs"):ConfirmDeleteImport(name, onConfirm)
    addon:GetObject("PopupDialogs"):PromptRename(currentName, onAccept)  -- onAccept(trimmedName)
]]

local PopupDialogs = addon:NewObject("PopupDialogs")

local L = addon.L

local PopupDialog = addon:GetObject("PopupDialog")

-- Longest name a renamed import may carry.
local MAX_RENAME_LETTERS = 64

-- Longest note a snapshot may carry.
local MAX_NOTE_LETTERS = 255

function PopupDialogs:ConfirmUndo(subject, onConfirm, onPreview)
    PopupDialog:Show({
        title = L["Undo"],
        message = L["Undo the last apply (X)?"]:format(subject or ""),
        buttons = {
            { text = YES, onClick = onConfirm },
            { text = NO },
            -- Previewing opens the diff viewer alongside; keep the confirm open
            -- so the choice isn't lost.
            { text = L["Preview changes"], keepOpen = true, onClick = onPreview },
        },
    })
end

function PopupDialogs:ConfirmUndoSteps(count, subject, onConfirm)
    PopupDialog:Show({
        title = L["Undo"],
        message = L["Undo the last X changes, back to Y?"]:format(count, subject or ""),
        buttons = {
            { text = YES, onClick = onConfirm },
            { text = NO },
        },
    })
end

function PopupDialogs:ConfirmDelete(profileName, onConfirm)
    PopupDialog:Show({
        title = L["Delete profile"],
        message = L["Delete profile 'X'?"]:format(profileName or ""),
        buttons = {
            { text = YES, onClick = onConfirm },
            { text = NO },
        },
    })
end

function PopupDialogs:ConfirmDeleteSnapshot(subject, onConfirm, dependentCount)
    local message
    if dependentCount and dependentCount > 0 then
        message = L["Delete this snapshot (X)? Its Y duplicate(s) will be removed too."]:format(subject or "", dependentCount)
    else
        message = L["Delete this snapshot (X)?"]:format(subject or "")
    end

    PopupDialog:Show({
        title = L["Delete snapshot"],
        message = message,
        buttons = {
            { text = YES, onClick = onConfirm },
            { text = NO },
        },
    })
end

-- Empty text is allowed: it clears the note.
function PopupDialogs:PromptEditNote(currentText, onAccept)
    PopupDialog:Show({
        title = L["Set the snapshot note:"],
        input = {
            multiline = true,
            text = currentText or "",
            maxLetters = MAX_NOTE_LETTERS,
            instructions = L["Note (optional):"],
        },
        buttons = {
            { text = ACCEPT, onClick = function(text)
                if onAccept then onAccept(text) end
            end },
            { text = CANCEL },
        },
    })
end

function PopupDialogs:ConfirmApply(mode, onConfirm)
    local message = (mode == "exact")
        and L["Apply the selected modules in Exact mode?\n\nThey will be made to match this snapshot exactly — entries that aren't in it (such as extra macros, keybindings, chat tabs, or addons) will be removed. You can Undo afterward."]
        or L["Apply the selected modules from this snapshot?\n\nNew and changed entries will be added or updated. Nothing will be removed."]

    PopupDialog:Show({
        title = L["Apply snapshot"],
        message = message,
        buttons = {
            { text = ACCEPT, onClick = onConfirm },
            { text = CANCEL },
        },
    })
end

function PopupDialogs:ConfirmSaveAtLimit(limit, oldestSubject, onConfirm)
    PopupDialog:Show({
        title = L["Save snapshot"],
        message = L["You've reached the snapshot limit (X). Saving will remove the oldest snapshot, from Y. Save anyway?"]:format(limit, oldestSubject or ""),
        buttons = {
            { text = ACCEPT, onClick = onConfirm },
            { text = CANCEL },
        },
    })
end

function PopupDialogs:ConfirmDeleteImport(name, onConfirm)
    PopupDialog:Show({
        title = L["Delete import"],
        message = L["Delete import 'X' and all its snapshots?"]:format(name or ""),
        buttons = {
            { text = YES, onClick = onConfirm },
            { text = NO },
        },
    })
end

-- A blank name is ignored, leaving the import's name unchanged.
function PopupDialogs:PromptRename(currentName, onAccept)
    PopupDialog:Show({
        title = L["Rename this import:"],
        input = {
            multiline = false,
            text = currentName or "",
            maxLetters = MAX_RENAME_LETTERS,
        },
        buttons = {
            { text = ACCEPT, onClick = function(text)
                if onAccept and text ~= "" then onAccept(text) end
            end },
            { text = CANCEL },
        },
    })
end
