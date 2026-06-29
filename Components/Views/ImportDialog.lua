local _, addon = ...

--[[
    ImportDialog object.

    A modal window for importing a shared snapshot string into a new, named
    container. Collects a container name and the pasted string, hands them to
    the core, and reports any failure inline; on success it closes and notifies
    the caller with the new container's id.

    addon:GetObject("ImportDialog"):Show({
        onImported = function(importID, result) end,  -- after a successful import
    })
]]

local ImportDialog = addon:NewObject("ImportDialog")
local Dialog = addon:GetObject("Dialog")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local dialog, frame
local nameBox, pasteBox, statusLabel
local onImported

-- Longest a container name may be; the core trims it and enforces uniqueness.
local MAX_NAME_LETTERS = 64

-- Height of the dialog; taller than the shared default to fit the paste box.
local DIALOG_HEIGHT = 300

-- Player-facing message for a core reason code, with a generic fallback.
local function ReasonText(reason)
    if reason == "invalid-name" then
        return L["Enter a name for this import."]
    elseif reason == "duplicate-name" then
        return L["An import with that name already exists."]
    elseif reason == "invalid-class" then
        return L["This shared string is for an unknown class."]
    elseif reason == "invalid-input" or reason == "bad-format" then
        return L["That doesn't appear to be a shared string."]
    end
    return L["Could not import that string."]
end

-- Read the fields, run the import, and either report a failure inline or close
-- and notify the caller.
local function AttemptImport()
    statusLabel:SetText("")

    local name = strtrim(nameBox:GetText())
    local text = strtrim(pasteBox:GetText())

    if text == "" then
        statusLabel:SetText(L["Paste a shared string to import."])
        return
    end

    local result, reason = ImportManager:ImportString(text, { name = name })
    if not result then
        statusLabel:SetText(ReasonText(reason))
        return
    end

    local importedName = result.Name or name
    local callback = onImported

    ImportDialog:Hide()
    WowSync:Print(L["Imported 'X'."]:format(importedName))
    if callback then
        callback(result.ImportID, result)
    end
end

local function Build()
    if frame then return end

    dialog = Dialog:Build({
        name = "WowSyncImportDialog",
        title = L["Import snapshot"],
        width = UI.Preview.Width,
        height = DIALOG_HEIGHT,
    })
    frame = dialog:GetFrame()

    -- Name for the new container.
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameLabel:SetPoint("TOPLEFT", 14, -44)
    nameLabel:SetText(L["Name:"])

    nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 2, -6)
    nameBox:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    nameBox:SetHeight(20)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(MAX_NAME_LETTERS)

    -- Pasted share string.
    local pasteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pasteLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -2, -14)
    pasteLabel:SetText(L["Paste the shared string:"])

    local scroll = CreateFrame("ScrollFrame", "WowSyncImportPasteScroll", frame, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", pasteLabel, "BOTTOMLEFT", 2, -6)
    scroll:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    scroll:SetPoint("BOTTOM", frame, "BOTTOM", 0, 72)

    pasteBox = scroll.EditBox
    pasteBox:SetMaxLetters(0)
    pasteBox:SetWidth(scroll:GetWidth() - 18)
    InputScrollFrame_SetInstructions(scroll, L["Paste the shared string:"])
    -- No character counter: share strings are long and a remaining-letters
    -- readout is meaningless with no limit.
    if scroll.CharCount then
        scroll.CharCount:Hide()
    end
    -- Keep the inner edit box width in step with the (anchored) scroll frame so
    -- text wraps correctly after the frame resolves its size.
    scroll:SetScript("OnSizeChanged", function(self, width)
        self.EditBox:SetWidth(width - 18)
    end)

    -- Inline failure feedback, full-width above the buttons.
    statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", 16, 44)
    statusLabel:SetPoint("BOTTOMRIGHT", -16, 44)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetTextColor(1, 0.3, 0.3)

    local importButton = Button:Build({
        parent = frame,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        text = L["Import"],
        onClick = AttemptImport,
    })

    local cancelButton = Button:Build({
        parent = frame,
        anchor = function(button)
            button:SetPoint("RIGHT", importButton, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = CANCEL,
        onClick = function() ImportDialog:Hide() end,
    })

    -- Enter in the name box jumps to the paste box; the paste box is multi-line,
    -- so Enter there inserts a newline rather than confirming.
    nameBox:SetScript("OnEnterPressed", function() pasteBox:SetFocus() end)
end

function ImportDialog:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(opts.onImported == nil or type(opts.onImported) == "function", "Show: 'opts.onImported' must be a function")

    Build()

    onImported = opts.onImported

    nameBox:SetText("")
    pasteBox:SetText("")
    statusLabel:SetText("")

    dialog:Show()
    nameBox:SetFocus()
end

function ImportDialog:Hide()
    if dialog then
        dialog:Hide()
    end
end
