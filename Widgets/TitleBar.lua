local _, addon = ...

--[[
    TitleBar object.

    Fills an injected region with a title, a close button, and an optional lock
    toggle. The window's nine-slice chrome draws the header itself, so the bar
    only carries the title text and the controls. The lock toggle (a composed
    LockButton) is hidden by default and revealed with ShowLock(); it sits
    immediately left of the close button and reports each change through
    onToggleLock(locked) so the owner can enable or disable window moving,
    resizing, and the splitter.

    addon:GetObject("TitleBar"):Build(region, {
        title = string,
        onClose = function,
        onToggleLock = function(locked),
        locked = boolean,
    }) -> self { SetTitle(text), SetLocked(locked), ShowLock() }
]]

local TitleBar = addon:NewObject("TitleBar")

local C = addon.C

local LockButton = addon:GetObject("LockButton")

-- The title bar's natural height; owners size the slot they build it into to
-- this so the title and controls sit the same in the window and in dialogs.
TitleBar.HEIGHT = 24

local Methods = {}

function Methods:SetTitle(text)
    self._title:SetText(text)
end

-- Reflect the locked state in the composed lock toggle.
function Methods:SetLocked(locked)
    if self._lockButton then
        self._lockButton:SetLocked(locked)
    end
end

-- Reveal the lock toggle, which is hidden by default (dialogs have no lock).
function Methods:ShowLock()
    self._lockButton:Show()
end

-- Build the title, close button, and the composed lock toggle (hidden until
-- ShowLock). The bar IS this frame; SetTitle/SetLocked drive it afterwards.
function Methods:Constructor(config)
    -- Vertically centred, matching the lock and close buttons (which anchor to the
    -- bar's vertical centre) so the three sit on one line.
    self._title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self._title:SetPoint("CENTER", 10, 0)
    self._title:SetText(config.title or "")

    local closeButton = CreateFrame("Button", nil, self, "UIPanelCloseButton")
    closeButton:SetSize(20, 20)
    closeButton:SetPoint("RIGHT", -1, 0)
    closeButton:SetScript("OnClick", function()
        if config.onClose then
            config.onClose()
        end
    end)

    self._lockButton = LockButton:Build(self, closeButton, {
        onToggle = config.onToggleLock,
        locked = config.locked,
    })
    self._lockButton:Hide()
end

function TitleBar:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onClose == nil or type(opts.onClose) == "function", "Build: 'opts.onClose' must be a function")
    C:Ensures(opts.onToggleLock == nil or type(opts.onToggleLock) == "function", "Build: 'opts.onToggleLock' must be a function")

    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
        title = opts.title,
        onClose = opts.onClose,
        onToggleLock = opts.onToggleLock,
        locked = opts.locked,
    }, {
        frameType = "Frame",
        methods = Methods,
    })
end
