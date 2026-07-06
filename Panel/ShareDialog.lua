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

local C = addon.C
local L = addon.L

local Dialog = addon:GetObject("Dialog")

-- Roomy enough to show a multi-line share string without the box scrolling on a
-- typical export.
local DIALOG_WIDTH = 760
local DIALOG_HEIGHT = 560

local Methods = {}

-- One-time build of the dialog body onto the adopted Dialog shell.
function Methods:Constructor(config)
    -- Which profile and snapshot this string came from, so the user knows what
    -- they're handing out.
    local subjectLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subjectLabel:SetPoint("TOPLEFT", 14, -38)
    self._subjectLabel = subjectLabel

    local hint = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 14, -58)
    hint:SetText(L["Press Ctrl+C to copy this string, then share it."])

    -- Read-only, pre-selected share string. Edits revert and the box re-selects,
    -- so the export can be copied but not altered.
    local scroll = CreateFrame("ScrollFrame", nil, self, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -80)
    scroll:SetPoint("BOTTOMRIGHT", -14, 14)

    local copyBox = scroll.EditBox
    copyBox:SetFontObject(ChatFontNormal)
    copyBox:SetMaxLetters(0)
    copyBox:SetWidth(scroll:GetWidth() - 18)
    scroll.CharCount:Hide()
    scroll:SetScript("OnSizeChanged", function(frame, width)
        frame.EditBox:SetWidth(width - 18)
    end)
    copyBox:SetScript("OnEscapePressed", function() self:Hide() end)
    copyBox:SetScript("OnTextChanged", function(box)
        if box:GetText() ~= self._shareText then
            box:SetText(self._shareText)
        end
        box:HighlightText()
    end)
    self._copyBox = copyBox
end

-- Fill the dialog with a share string, show it, and pre-select it for copying.
function Methods:Open(opts)
    self._shareText = opts.text
    self._subjectLabel:SetText(opts.subject or "")
    self._copyBox:SetText(opts.text)
    self:Show()
    self._copyBox:SetFocus()
    self._copyBox:HighlightText()
end

-- Build the dialog on first use, adopting the shared Dialog shell so the body
-- lives directly on the dialog frame.
local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncShareDialog",
            title = L["Share snapshot"],
            width = DIALOG_WIDTH,
            height = DIALOG_HEIGHT,
        }),
        methods = Methods,
    })
end

function ShareDialog:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.text) == "string", "Show: 'opts.text' must be a string")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function ShareDialog:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
