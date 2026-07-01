local _, addon = ...

--[[
    PopupDialogs object.

    Reusable confirmation/prompt popups. The StaticPopupDialogs are registered
    once at load; callers pass their own callbacks through the popup `data`
    payload, so this service is fully decoupled from any single consumer.

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
local Button = addon:GetObject("Button")

local L = addon.L
local UI = addon.UI

-- The edit-note prompt is a custom modal (not a StaticPopup) so it can offer a
-- large, multi-line, scrolling edit box. Built lazily on first use.
local editNoteFrame
local editNoteOnAccept

-- The rename prompt is a custom modal (not a StaticPopup) so it centres on the
-- screen and matches the styling of the other WowSync dialogs. Built lazily.
local renameFrame
local renameDialog
local renameBox
local renameOnAccept
local MAX_RENAME_LETTERS = 64

StaticPopupDialogs["WOWSYNC_UNDO"] = {
    text = L["Undo the last apply (X)?"],
    button1 = YES,
    button2 = NO,
    button3 = L["Preview changes"],
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
    end,
    OnAlt = function(self, popupData)
        if popupData and popupData.onPreview then
            popupData.onPreview()
        end
    end,
    -- Previewing opens the diff viewer alongside; keep the confirm open so the
    -- choice isn't lost.
    noCloseOnAlt = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_UNDO_MULTI"] = {
    text = L["Undo the last X changes, back to Y?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
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
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
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
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_DELETE_SNAPSHOT_CASCADE"] = {
    text = L["Delete this snapshot (X)? Its Y duplicate(s) will be removed too."],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
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
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
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
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WOWSYNC_SAVE_AT_LIMIT"] = {
    text = L["You've reached the snapshot limit (X). Saving will remove the oldest snapshot, from Y. Save anyway?"],
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function PopupDialogs:ConfirmUndo(subject, onConfirm, onPreview)
    StaticPopup_Show("WOWSYNC_UNDO", subject, nil, { onConfirm = onConfirm, onPreview = onPreview })
end

function PopupDialogs:ConfirmUndoSteps(count, subject, onConfirm)
    StaticPopup_Show("WOWSYNC_UNDO_MULTI", count, subject, { onConfirm = onConfirm })
end

function PopupDialogs:ConfirmDelete(profileName, onConfirm)
    StaticPopup_Show("WOWSYNC_DELETE_PROFILE", profileName, nil, { onConfirm = onConfirm })
end

function PopupDialogs:ConfirmDeleteSnapshot(subject, onConfirm, dependentCount)
    if dependentCount and dependentCount > 0 then
        StaticPopup_Show("WOWSYNC_DELETE_SNAPSHOT_CASCADE", subject, dependentCount, { onConfirm = onConfirm })
    else
        StaticPopup_Show("WOWSYNC_DELETE_SNAPSHOT", subject, nil, { onConfirm = onConfirm })
    end
end

-- Lazily builds the multi-line note editor and returns it. The owning callback
-- is held in the module-level editNoteOnAccept so the buttons stay decoupled
-- from any single caller.
local function BuildEditNoteDialog()
    if editNoteFrame then return editNoteFrame end

    local frame = CreateFrame("Frame", "WowSyncEditNoteDialog", UIParent, "BackdropTemplate")
    frame:SetSize(420, 240)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(UI.Backdrop.Main))
    frame:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))
    frame:EnableMouse(true)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L["Set the snapshot note:"])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Multi-line, scrolling input with a remaining-character counter.
    local scroll = CreateFrame("ScrollFrame", "WowSyncEditNoteScroll", frame, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -40)
    scroll:SetPoint("TOPRIGHT", -16, -40)
    scroll:SetPoint("BOTTOM", frame, "BOTTOM", 0, 46)

    local editBox = scroll.EditBox
    editBox:SetMaxLetters(255)
    editBox:SetWidth(scroll:GetWidth() - 18)
    InputScrollFrame_SetInstructions(scroll, L["Note (optional):"])
    -- Keep the inner edit box width in step with the (anchored) scroll frame so
    -- text wraps correctly after the frame resolves its size.
    scroll:SetScript("OnSizeChanged", function(self, width)
        self.EditBox:SetWidth(width - 18)
    end)
    frame.editBox = editBox

    local accept = Button:Build({
        parent = frame,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        text = ACCEPT,
        onClick = function()
            local text = strtrim(editBox:GetText())
            -- Capture the callback before hiding: the OnHide script clears
            -- editNoteOnAccept, so reading it after frame:Hide() would be nil.
            local onAccept = editNoteOnAccept
            frame:Hide()
            if onAccept then
                onAccept(text)
            end
        end,
    })

    local cancel = Button:Build({
        parent = frame,
        anchor = function(button)
            button:SetPoint("RIGHT", accept, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = CANCEL,
        onClick = function() frame:Hide() end,
    })

    frame:SetScript("OnHide", function() editNoteOnAccept = nil end)

    -- ESC closes the dialog (after first clearing edit-box focus).
    tinsert(UISpecialFrames, "WowSyncEditNoteDialog")

    editNoteFrame = frame
    frame:Hide()
    return frame
end

function PopupDialogs:PromptEditNote(currentText, onAccept)
    local frame = BuildEditNoteDialog()
    editNoteOnAccept = onAccept

    local editBox = frame.editBox
    editBox:SetText(currentText or "")
    editBox:SetCursorPosition(editBox:GetNumLetters())

    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

StaticPopupDialogs["WOWSYNC_DELETE_IMPORT"] = {
    text = L["Delete import 'X' and all its snapshots?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, popupData)
        if popupData and popupData.onConfirm then
            popupData.onConfirm()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function PopupDialogs:ConfirmApply(mode, onConfirm)
    local popup = (mode == "exact") and "WOWSYNC_APPLY_EXACT" or "WOWSYNC_APPLY_MERGE"
    StaticPopup_Show(popup, nil, nil, { onConfirm = onConfirm })
end

function PopupDialogs:ConfirmSaveAtLimit(limit, oldestSubject, onConfirm)
    StaticPopup_Show("WOWSYNC_SAVE_AT_LIMIT", limit, oldestSubject, { onConfirm = onConfirm })
end

function PopupDialogs:ConfirmDeleteImport(name, onConfirm)
    StaticPopup_Show("WOWSYNC_DELETE_IMPORT", name, nil, { onConfirm = onConfirm })
end

-- Lazily builds the centred, single-line rename modal so it matches the styling
-- and position of the other WowSync dialogs.
local function BuildRenameDialog()
    if renameFrame then return end

    renameDialog = addon:GetObject("Dialog"):Build({
        name = "WowSyncRenameDialog",
        title = L["Rename this import:"],
        width = UI.Preview.Width,
        height = 130,
        onHide = function() renameOnAccept = nil end,
    })
    renameFrame = renameDialog

    renameBox = CreateFrame("EditBox", nil, renameFrame, "InputBoxTemplate")
    renameBox:SetPoint("TOPLEFT", 16, -44)
    renameBox:SetPoint("RIGHT", renameFrame, "RIGHT", -16, 0)
    renameBox:SetHeight(20)
    renameBox:SetAutoFocus(false)
    renameBox:SetMaxLetters(MAX_RENAME_LETTERS)

    local function Accept()
        local text = strtrim(renameBox:GetText())
        local onAccept = renameOnAccept
        renameDialog:Hide()
        if onAccept and text ~= "" then
            onAccept(text)
        end
    end

    renameBox:SetScript("OnEnterPressed", Accept)
    renameBox:SetScript("OnEscapePressed", function() renameDialog:Hide() end)

    local accept = Button:Build({
        parent = renameFrame,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        text = ACCEPT,
        onClick = Accept,
    })

    local cancel = Button:Build({
        parent = renameFrame,
        anchor = function(button)
            button:SetPoint("RIGHT", accept, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = CANCEL,
        onClick = function() renameDialog:Hide() end,
    })
end

function PopupDialogs:PromptRename(currentName, onAccept)
    BuildRenameDialog()
    renameOnAccept = onAccept

    renameBox:SetText(currentName or "")
    renameBox:HighlightText()

    renameDialog:Show()
    renameBox:SetFocus()
end
