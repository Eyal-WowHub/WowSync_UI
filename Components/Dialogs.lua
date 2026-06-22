local _, addon = ...

local L = addon.L

--[[
    Dialogs object.

    Reusable confirmation/prompt popups. The StaticPopupDialogs are registered
    once at load; callers pass their own callbacks through the popup `data`
    payload, so this service is fully decoupled from any single consumer.

    addon:GetObject("Dialogs"):ConfirmUndo(subject, onConfirm)
    addon:GetObject("Dialogs"):ConfirmDelete(profileName, onConfirm)
    addon:GetObject("Dialogs"):PromptRename(currentName, onAccept)  -- onAccept(trimmedText)
    addon:GetObject("Dialogs"):ConfirmDeleteSnapshot(subject, onConfirm)
    addon:GetObject("Dialogs"):PromptEditNote(currentText, onAccept)  -- onAccept(trimmedText)
    addon:GetObject("Dialogs"):ConfirmApply(mode, onConfirm)  -- mode = "merge"|"exact"
]]

local Dialogs = addon:NewObject("Dialogs")

StaticPopupDialogs["WOWSYNC_UNDO"] = {
    text = L["Undo the last apply (X)?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if data and data.onConfirm then
            data.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_DELETE_PROFILE"] = {
    text = L["Delete profile 'X'?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if data and data.onConfirm then
            data.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_RENAME_PROFILE"] = {
    text = L["Rename profile 'X' to:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self, data)
        if data and data.onAccept then
            data.onAccept(strtrim(self.editBox:GetText()))
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if strtrim(self:GetText()) ~= "" then
            parent.button1:Click()
        end
    end,
    OnShow = function(self, data)
        self.editBox:SetText(data and data.currentName or "")
        self.editBox:HighlightText()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_DELETE_SNAPSHOT"] = {
    text = L["Delete this snapshot (X)?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if data and data.onConfirm then
            data.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_EDIT_NOTE"] = {
    text = L["Set the snapshot note:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self, data)
        if data and data.onAccept then
            data.onAccept(strtrim(self.editBox:GetText()))
        end
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    OnShow = function(self, data)
        self.editBox:SetText(data and data.currentText or "")
        self.editBox:HighlightText()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_APPLY_MERGE"] = {
    text = L["Apply the selected modules from this snapshot?\n\nNew and changed entries will be added or updated. Nothing will be removed."],
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        if data and data.onConfirm then
            data.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_APPLY_EXACT"] = {
    text = L["Apply the selected modules in Exact mode?\n\nThey will be made to match this snapshot exactly — entries that aren't in it (such as extra macros, keybindings, chat tabs, or addons) will be removed. You can Undo afterward."],
    button1 = ACCEPT,
    button2 = CANCEL,
    showAlert = true,
    OnAccept = function(self, data)
        if data and data.onConfirm then
            data.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Dialogs:ConfirmUndo(subject, onConfirm)
    StaticPopup_Show("WOWSYNC_UNDO", subject, nil, { onConfirm = onConfirm })
end

function Dialogs:ConfirmDelete(profileName, onConfirm)
    StaticPopup_Show("WOWSYNC_DELETE_PROFILE", profileName, nil, { onConfirm = onConfirm })
end

function Dialogs:PromptRename(currentName, onAccept)
    StaticPopup_Show("WOWSYNC_RENAME_PROFILE", currentName, nil, {
        currentName = currentName,
        onAccept = onAccept,
    })
end

function Dialogs:ConfirmDeleteSnapshot(subject, onConfirm)
    StaticPopup_Show("WOWSYNC_DELETE_SNAPSHOT", subject, nil, { onConfirm = onConfirm })
end

function Dialogs:PromptEditNote(currentText, onAccept)
    StaticPopup_Show("WOWSYNC_EDIT_NOTE", nil, nil, {
        currentText = currentText,
        onAccept = onAccept,
    })
end

function Dialogs:ConfirmApply(mode, onConfirm)
    local popup = (mode == "exact") and "WOWSYNC_APPLY_EXACT" or "WOWSYNC_APPLY_MERGE"
    StaticPopup_Show(popup, nil, nil, { onConfirm = onConfirm })
end
