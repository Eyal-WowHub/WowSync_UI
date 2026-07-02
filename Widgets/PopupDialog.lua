local _, addon = ...

--[[
    PopupDialog widget (the shared confirm/prompt popup).

    Confirm/prompt popups dressed in the same flat Settings chrome as every other
    window (built on Dialog, so they inherit the title bar, close button,
    Esc-to-close, drag, and stacking beside the main window). Frames are pooled:
    a caller describes a popup for a single showing and drives it through Show,
    which reuses a free frame or grows the pool, so several popups can be open at
    once without any frame being rebuilt.

        addon:GetObject("PopupDialog"):Show({
            title   = L["Delete snapshot"],       -- title bar text
            message = L["Delete this snapshot?"], -- optional wrapped body
            input   = {                           -- optional text field
                multiline    = false,             -- single line, or a scrolling box
                text         = "current value",
                maxLetters   = 64,
                instructions = L["Note (optional):"],  -- placeholder (multiline)
            },
            buttons = {                           -- 1-3 buttons, right to left
                { text = ACCEPT, onClick = function(text) ... end },
                { text = CANCEL },                -- no handler: just closes
                { text = L["Preview changes"], keepOpen = true, onClick = fn },
            },
        })

    Each button closes the popup on click unless keepOpen is set. A button's
    onClick receives the trimmed input text when the popup has an input field.
    Enter in a single-line input triggers the first (primary) button. The popup
    auto-closes if combat begins, and never shows while already in combat.
]]

local PopupDialog = addon:NewObject("PopupDialog")
local Dialog = addon:GetObject("Dialog")
local Button = addon:GetObject("Button")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Inset from the popup edges to its content.
local PADDING = 16

-- Where the content stack starts, clearing the title bar.
local CONTENT_TOP = 44

-- Gap above an input that follows a message, and above the button row.
local ITEM_GAP = 12
local BUTTON_TOP_GAP = 16

-- Button row metrics, matching the other dialogs' action buttons.
local BUTTON_WIDTH = 110
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 8
local BUTTON_BOTTOM = 12

-- Input heights: a single line, or a taller scrolling box.
local SINGLE_INPUT_HEIGHT = 20
local MULTI_INPUT_HEIGHT = 120

-- The most buttons a popup can carry (confirm + cancel + a side action).
local MAX_BUTTONS = 3

-- Pool of popup frames, capped by MAX_POOL. A Show reuses a hidden one, grows
-- the pool up to the cap, or (once capped) reuses the oldest. Raise MAX_POOL to
-- let several popups stack at once, like WoW's own StaticPopups.
local MAX_POOL = 1

local pool = {}

-- The trimmed text of the active input, or nil when the popup has no input.
local function ActiveInputText(dialog)
    if dialog._activeInput == "single" then
        return strtrim(dialog._singleBox:GetText())
    elseif dialog._activeInput == "multi" then
        return strtrim(dialog._multiBox:GetText())
    end
    return nil
end

-- Build one pooled popup: the Dialog chrome plus a body message, a single-line
-- and a multi-line input (both hidden until a showing needs one), and a row of
-- buttons. Everything is positioned per showing in Show. index makes the frame
-- (and its scroll) names unique so each carries its own Esc registration.
local function BuildDialog(index)
    local dialog = Dialog:Build({
        name = "WowSyncPopupDialog" .. index,
        width = UI.Preview.Width,
        onHide = function(self)
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            -- Drop the showing's button handlers so a closed popup holds no
            -- stale callback. Guarded: the Dialog Constructor hides the frame
            -- once during Build, before these buttons exist.
            if self._buttons then
                for i = 1, MAX_BUTTONS do
                    self._buttons[i]:SetScript("OnClick", nil)
                end
            end
        end,
    })

    -- Content sits in a frame above the flat-panel chrome: child frames of the
    -- dialog draw over its own layers, so a body FontString placed straight on
    -- the dialog would hide behind the fill. Everything below parents here.
    local content = CreateFrame("Frame", nil, dialog)
    content:SetPoint("TOPLEFT")
    content:SetPoint("BOTTOMRIGHT")
    content:SetFrameLevel(dialog:GetFrameLevel() + 2)
    dialog._content = content

    -- Body message, left-justified and wrapped to the content width.
    local message = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    message:SetJustifyH("LEFT")
    message:SetJustifyV("TOP")
    message:SetSpacing(4)
    message:SetPoint("TOPLEFT", PADDING, -CONTENT_TOP)
    message:SetWidth(UI.Preview.Width - 2 * PADDING)
    dialog._message = message

    -- Single-line input.
    local singleBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    singleBox:SetHeight(SINGLE_INPUT_HEIGHT)
    singleBox:SetAutoFocus(false)
    singleBox:SetScript("OnEnterPressed", function()
        local primary = dialog._buttons[1]
        if primary:IsShown() and primary:IsEnabled() then
            primary:Click()
        end
    end)
    singleBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog._singleBox = singleBox

    -- Multi-line, scrolling input.
    local scroll = CreateFrame("ScrollFrame", "WowSyncPopupScroll" .. index, content, "InputScrollFrameTemplate")
    scroll:SetScript("OnSizeChanged", function(self, width)
        self.EditBox:SetWidth(width - 18)
    end)
    local multiBox = scroll.EditBox
    multiBox:SetAutoFocus(false)
    multiBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog._multiScroll = scroll
    dialog._multiBox = multiBox

    -- Button pool, positioned right-to-left per showing.
    dialog._buttons = {}
    for i = 1, MAX_BUTTONS do
        dialog._buttons[i] = Button:Build({
            parent = content,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
        })
    end

    -- Combat closes the popup; the window is locked in combat, so a pending
    -- confirm is dropped rather than queued.
    dialog:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self:Hide()
        end
    end)
    dialog:HookScript("OnShow", function(self)
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    end)

    return dialog
end

-- Reuse a hidden pooled popup, grow the pool up to MAX_POOL when all are in use,
-- or reuse the oldest once the cap is reached.
local function AcquireDialog()
    for _, dialog in ipairs(pool) do
        if not dialog:IsShown() then
            return dialog
        end
    end
    if #pool < MAX_POOL then
        local dialog = BuildDialog(#pool + 1)
        tinsert(pool, dialog)
        return dialog
    end
    return pool[1]
end

-- Configure the button row from the showing's specs, right-aligned with the
-- primary (first) button on the right; unused pool buttons are hidden.
local function LayoutButtons(dialog, buttons)
    local previous
    for index = 1, MAX_BUTTONS do
        local spec = buttons and buttons[index]
        local button = dialog._buttons[index]
        if spec then
            button:SetLabel(spec.text)
            button:ClearAllPoints()
            if previous then
                button:SetPoint("RIGHT", previous, "LEFT", -BUTTON_GAP, 0)
            else
                button:SetPoint("BOTTOMRIGHT", -PADDING + 2, BUTTON_BOTTOM)
            end
            button:SetScript("OnClick", function()
                local text = ActiveInputText(dialog)
                if not spec.keepOpen then
                    dialog:Hide()
                end
                if spec.onClick then
                    spec.onClick(text)
                end
            end)
            button:Show()
            previous = button
        else
            button:SetScript("OnClick", nil)
            button:Hide()
        end
    end
end

-- Show the popup for one interaction, laying out the body, optional input, and
-- buttons and sizing the frame to fit. No-op while in combat.
function PopupDialog:Show(config)
    C:IsTable(config, 2)

    if InCombatLockdown() then
        return
    end

    local dialog = AcquireDialog()
    dialog:SetTitle(config.title or "")

    -- Stack the content from the top, tracking the running bottom offset so the
    -- frame can be sized to exactly fit it.
    local bottom = -CONTENT_TOP

    local hasMessage = config.message ~= nil and config.message ~= ""
    if hasMessage then
        dialog._message:SetText(config.message)
        dialog._message:Show()
        bottom = bottom - dialog._message:GetStringHeight()
    else
        dialog._message:Hide()
    end

    dialog._activeInput = nil
    dialog._singleBox:Hide()
    dialog._multiScroll:Hide()

    local input = config.input
    if input then
        if hasMessage then
            bottom = bottom - ITEM_GAP
        end

        if input.multiline then
            local scroll = dialog._multiScroll
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", PADDING, bottom)
            scroll:SetPoint("TOPRIGHT", -PADDING, bottom)
            scroll:SetHeight(MULTI_INPUT_HEIGHT)
            scroll:Show()

            local box = dialog._multiBox
            box:SetMaxLetters(input.maxLetters or 255)
            InputScrollFrame_SetInstructions(scroll, input.instructions or "")
            box:SetText(input.text or "")

            dialog._activeInput = "multi"
            bottom = bottom - MULTI_INPUT_HEIGHT
        else
            local box = dialog._singleBox
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", PADDING, bottom)
            box:SetPoint("RIGHT", dialog._content, "RIGHT", -PADDING, 0)
            box:SetMaxLetters(input.maxLetters or 64)
            box:SetText(input.text or "")
            box:Show()

            dialog._activeInput = "single"
            bottom = bottom - SINGLE_INPUT_HEIGHT
        end
    end

    LayoutButtons(dialog, config.buttons)

    dialog:SetHeight(-bottom + BUTTON_TOP_GAP + BUTTON_HEIGHT + BUTTON_BOTTOM)
    dialog:Show()

    if dialog._activeInput == "single" then
        dialog._singleBox:SetFocus()
        dialog._singleBox:HighlightText()
    elseif dialog._activeInput == "multi" then
        dialog._multiBox:SetFocus()
        dialog._multiBox:HighlightText()
    end
end
