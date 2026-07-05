local _, addon = ...

--[[
    ImportDialog object.

    A modal window for importing a shared snapshot string. In its default mode
    it collects a container name and the pasted string to create a new, named
    container. Passing a targetID switches to "add snapshot" mode: the name is
    fixed to that container (shown read-only) and the pasted snapshot is
    appended to it, provided it is for the same class. Failures are reported
    inline; on success it closes and notifies the caller with the container id.

    addon:GetObject("ImportDialog"):Show({
        onImported = function(importID, result) end,  -- after a successful import
        targetID = importID,        -- optional: append to this container
        targetName = "Name",        -- optional: shown read-only in add mode
    })
]]

local ImportDialog = addon:NewObject("ImportDialog")
local Dialog = addon:GetObject("Dialog")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:Import("ImportManager")
local Console = WowSync:Import("Console")

local Methods = {}

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
    elseif reason == "class-mismatch" then
        return L["That snapshot is from a different class."]
    elseif reason == "not-found" then
        return L["That import no longer exists."]
    end
    return L["Could not import that string."]
end

-- Read the fields, run the import, and either report a failure inline or close
-- and notify the caller.
local function AttemptImport(panel)
    panel._statusLabel:SetText("")

    local name = strtrim(panel._nameBox:GetText())
    local text = strtrim(panel._pasteBox:GetText())

    if text == "" then
        panel._statusLabel:SetText(L["Paste a shared string to import."])
        return
    end

    local targetID = panel._targetID
    local opts = targetID and { targetID = targetID } or { name = name }

    local result, reason = ImportManager:ImportString(text, opts)
    if not result then
        panel._statusLabel:SetText(ReasonText(reason))
        return
    end

    local callback = panel._onImported

    panel:Hide()
    if targetID then
        Console:Print(result.Duplicate and L["Snapshot added but already exists."]
            or L["Snapshot added."])
    else
        Console:Print(L["Imported 'X'."]:format(result.Name or name))
    end
    if callback then
        callback(result.ImportID, result)
    end
end

function Methods:Constructor(config)
    local panel = self

    -- Name for the new container (read-only when adding to an existing one).
    local nameLabel = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameLabel:SetPoint("TOPLEFT", 14, -44)
    nameLabel:SetText(L["Name:"])
    self._nameLabel = nameLabel

    local nameBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 2, -6)
    nameBox:SetPoint("RIGHT", self, "RIGHT", -16, 0)
    nameBox:SetHeight(20)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(MAX_NAME_LETTERS)
    self._nameBox = nameBox

    -- Pasted share string.
    local pasteLabel = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pasteLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -2, -14)
    pasteLabel:SetText(L["Paste the shared string:"])

    local scroll = CreateFrame("ScrollFrame", "WowSyncImportPasteScroll", self, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", pasteLabel, "BOTTOMLEFT", 2, -6)
    scroll:SetPoint("RIGHT", self, "RIGHT", -16, 0)
    scroll:SetPoint("BOTTOM", self, "BOTTOM", 0, 72)

    local pasteBox = scroll.EditBox
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
    scroll:SetScript("OnSizeChanged", function(scrollFrame, width)
        scrollFrame.EditBox:SetWidth(width - 18)
    end)
    self._pasteBox = pasteBox

    -- Inline failure feedback, full-width above the buttons.
    local statusLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("BOTTOMLEFT", 16, 44)
    statusLabel:SetPoint("BOTTOMRIGHT", -16, 44)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetTextColor(1, 0.3, 0.3)
    self._statusLabel = statusLabel

    local importButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("BOTTOMRIGHT", -14, 12)
        end,
        width = 110,
        height = 22,
        text = L["Import"],
        onClick = function() AttemptImport(panel) end,
    })

    local cancelButton = Button:Build({
        parent = self,
        anchor = function(button)
            button:SetPoint("RIGHT", importButton, "LEFT", -8, 0)
        end,
        width = 110,
        height = 22,
        text = CANCEL,
        onClick = function() panel:Hide() end,
    })

    -- Enter in the name box jumps to the paste box; the paste box is multi-line,
    -- so Enter there inserts a newline rather than confirming.
    nameBox:SetScript("OnEnterPressed", function() pasteBox:SetFocus() end)
end

function Methods:Open(opts)
    self._onImported = opts.onImported
    self._targetID = opts.targetID

    self._pasteBox:SetText("")
    self._statusLabel:SetText("")

    if opts.targetID then
        -- Add-snapshot mode: the container is fixed, so the name is shown
        -- read-only and the paste box takes focus.
        self._nameLabel:SetText(L["Add to:"])
        self._nameBox:SetText(opts.targetName or "")
        self._nameBox:Disable()
        self:SetTitle(L["Add snapshot"])
        self:Show()
        self._pasteBox:SetFocus()
    else
        self._nameLabel:SetText(L["Name:"])
        self._nameBox:Enable()
        self._nameBox:SetText("")
        self:SetTitle(L["Import snapshot"])
        self:Show()
        self._nameBox:SetFocus()
    end
end

local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncImportDialog",
            title = L["Import snapshot"],
            width = UI.Preview.Width,
            height = DIALOG_HEIGHT,
        }),
        methods = Methods,
    })
end

function ImportDialog:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(opts.onImported == nil or type(opts.onImported) == "function", "Show: 'opts.onImported' must be a function")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function ImportDialog:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
