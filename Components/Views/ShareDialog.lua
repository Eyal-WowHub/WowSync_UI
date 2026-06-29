local _, addon = ...

--[[
    ShareDialog object.

    A modal window that shows a read-only, pre-selected share string for copying.
    The user exports a snapshot, the string fills a scrolling box already
    highlighted, and Ctrl+C copies it. Editing is suppressed so the export stays
    intact; closing dismisses the dialog.

    addon:GetObject("ShareDialog"):Show({ text = string })
    addon:GetObject("ShareDialog"):Hide()
]]

local ShareDialog = addon:NewObject("ShareDialog")
local Dialog = addon:GetObject("Dialog")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Roomy enough to show a multi-line share string without the box scrolling on a
-- typical export.
local DIALOG_WIDTH = 760
local DIALOG_HEIGHT = 560

local dialog, frame
local copyBox, subjectLabel

local function Build()
    if frame then return end

    dialog = Dialog:Build({
        name = "WowSyncShareDialog",
        title = L["Share snapshot"],
        width = DIALOG_WIDTH,
        height = DIALOG_HEIGHT,
    })
    frame = dialog:GetFrame()

    -- Which profile and snapshot this string came from, so the user knows what
    -- they're handing out.
    subjectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subjectLabel:SetPoint("TOPLEFT", 14, -38)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 14, -58)
    hint:SetText(L["Press Ctrl+C to copy this string, then share it."])

    -- Read-only, pre-selected share string. Edits revert and the box re-selects,
    -- so the export can be copied but not altered.
    local scroll = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -80)
    scroll:SetPoint("BOTTOMRIGHT", -14, 14)

    copyBox = scroll.EditBox
    copyBox:SetFontObject(ChatFontNormal)
    copyBox:SetMaxLetters(0)
    copyBox:SetWidth(scroll:GetWidth() - 18)
    scroll.CharCount:Hide()
    scroll:SetScript("OnSizeChanged", function(self, width)
        self.EditBox:SetWidth(width - 18)
    end)
    copyBox:SetScript("OnEscapePressed", function() ShareDialog:Hide() end)
    copyBox:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= frame.shareText then
            self:SetText(frame.shareText)
        end
        self:HighlightText()
    end)
end

function ShareDialog:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.text) == "string", "Show: 'opts.text' must be a string")

    Build()
    frame.shareText = opts.text
    subjectLabel:SetText(opts.subject or "")
    copyBox:SetText(opts.text)
    dialog:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end

function ShareDialog:Hide()
    if dialog then
        dialog:Hide()
    end
end
