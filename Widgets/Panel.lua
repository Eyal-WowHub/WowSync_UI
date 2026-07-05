local _, addon = ...

--[[
    Panel object (the base window every WowSync_UI window is built from).

    A Panel IS a top-level frame dressed in WoW's flat "Settings panel" chrome
    (a dark fill inside a nine-slice border). It owns the window and offers opt-in
    features -- a title bar, a lock toggle, moving, resizing, Esc-to-close -- that
    a concrete window turns on in its Constructor. Instead of taking callbacks,
    the features report through events on the Panel object, so consumers subscribe
    by importing it and registering a handler:

        local Panel = addon:GetObject("Panel")
        Panel:RegisterEvent("WOWSYNC_UI_PANEL_RESIZED", function(_, _, panel, w, h) ... end)

    Every event carries the firing panel frame as its first payload so a handler
    can tell which window fired it. Events:
        WOWSYNC_UI_PANEL_CLOSE(panel)                  -- close button pressed
        WOWSYNC_UI_PANEL_LOCK_CHANGED(panel, locked)   -- lock toggled
        WOWSYNC_UI_PANEL_MOVED(panel)                  -- drag finished
        WOWSYNC_UI_PANEL_RESIZED(panel, width, height) -- resize finished
        WOWSYNC_UI_PANEL_RESIZE_RESET(panel)           -- resize reset (double-click)

    Build a window by handing Panel your concrete methods; its Constructor runs
    with the chrome already in place and the feature methods available on self:

        addon:GetObject("Panel"):Build({
            name = "WowSyncExampleWindow",  -- global frame name (Esc, _G lookup)
            width = number, height = number,
            methods = ConcreteMethods,      -- mixed onto the frame; its Constructor runs
        })

    Feature methods (called from the concrete Constructor):
        self:EnableTitleBar({ title })
        self:EnableLockButton({ locked })     -- requires EnableTitleBar
        self:EnableMoving()
        self:EnableResizing({ minWidth, minHeight, maxWidth, maxHeight })
        self:EnableCloseOnEscape()
        self:SetTitle(text) / self:SetLocked(locked)

    Each Enable* is idempotent: a second call is a no-op.
]]

local Panel = addon:NewObject("Panel")

local C = LibStub("Contracts-1.0")

local TitleBar = addon:GetObject("TitleBar")

-- Insets that seat the flat fill inside the nine-slice border, matching WoW's
-- Settings frame (built from the same layout): the top clears the header strip,
-- the other edges tuck under the border art.
local FILL_INSET_LEFT = 7
local FILL_INSET_TOP = 18
local FILL_INSET_RIGHT = 3
local FILL_INSET_BOTTOM = 3

-- The nine-slice layout WoW's own Settings panel is built from.
local NINE_SLICE_LAYOUT = "ButtonFrameTemplateNoPortrait"

-- Panel events, prefixed to match the addon's WOWSYNC_UI_* namespace.
local EVENT_CLOSE = "WOWSYNC_UI_PANEL_CLOSE"
local EVENT_LOCK_CHANGED = "WOWSYNC_UI_PANEL_LOCK_CHANGED"
local EVENT_MOVED = "WOWSYNC_UI_PANEL_MOVED"
local EVENT_RESIZED = "WOWSYNC_UI_PANEL_RESIZED"
local EVENT_RESIZE_RESET = "WOWSYNC_UI_PANEL_RESIZE_RESET"

local Methods = {}

-- Lay the flat fill and nine-slice border onto a fresh panel frame and seed its
-- base state, before the concrete window's Constructor adds its content on top.
local function ApplyChrome(frame)
    frame._locked = false

    local baseLevel = frame:GetFrameLevel()

    local background = CreateFrame("Frame", nil, frame, "FlatPanelBackgroundTemplate")
    background:SetPoint("TOPLEFT", FILL_INSET_LEFT, -FILL_INSET_TOP)
    background:SetPoint("BOTTOMRIGHT", -FILL_INSET_RIGHT, FILL_INSET_BOTTOM)
    background:SetFrameLevel(baseLevel)
    frame.Bg = background

    local border = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    border:SetFrameLevel(baseLevel + 1)
    NineSliceUtil.ApplyLayoutByName(border, NINE_SLICE_LAYOUT)
    frame.NineSlice = border
end

-- Set the title bar text; a no-op when the panel has no title bar.
function Methods:SetTitle(text)
    if self._titleBar then
        self._titleBar:SetTitle(text or "")
    end
end

-- Reflect a locked state on the panel: update the lock icon, hide the resize
-- grip, and suppress moving/resizing. Does not fire an event -- it is how a
-- toggle and the initial state are applied, not how a change is announced.
function Methods:SetLocked(locked)
    locked = locked and true or false
    self._locked = locked
    if self._titleBar then
        self._titleBar:SetLocked(locked)
    end
    if self._resizeGrip then
        self._resizeGrip:SetLocked(locked)
    end
end

-- Add the title bar (title + close). The close button fires WOWSYNC_UI_PANEL_CLOSE
-- and hides the window; the lock toggle (revealed by EnableLockButton) applies the
-- new state and fires WOWSYNC_UI_PANEL_LOCK_CHANGED.
function Methods:EnableTitleBar(opts)
    if self._titleBar then return end
    opts = opts or {}
    local frame = self

    local titleSlot = CreateFrame("Frame", nil, frame)
    titleSlot:SetPoint("TOPLEFT", 0, 0)
    titleSlot:SetPoint("TOPRIGHT", 0, 0)
    titleSlot:SetHeight(TitleBar.HEIGHT)

    self._titleBar = TitleBar:Build(titleSlot, {
        title = opts.title,
        onClose = function()
            Panel:TriggerEvent(EVENT_CLOSE, frame)
            frame:Hide()
        end,
        onToggleLock = function(locked)
            frame:SetLocked(locked)
            Panel:TriggerEvent(EVENT_LOCK_CHANGED, frame, locked)
        end,
        locked = opts.locked,
    })
end

-- Reveal the title bar's lock toggle and apply the initial locked state. Requires
-- EnableTitleBar.
function Methods:EnableLockButton(opts)
    if self._lockEnabled then return end
    self._lockEnabled = true
    opts = opts or {}
    if self._titleBar then
        self._titleBar:ShowLock()
    end
    self:SetLocked(opts.locked)
end

-- Make the panel draggable (suppressed while locked). Fires WOWSYNC_UI_PANEL_MOVED
-- once a drag ends.
function Methods:EnableMoving()
    if self._movable then return end
    self._movable = true
    local frame = self
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if not frame._locked then
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        Panel:TriggerEvent(EVENT_MOVED, frame)
    end)
end

-- Make the panel resizable via a bottom-right grip (hidden while locked). Fires
-- WOWSYNC_UI_PANEL_RESIZED after a resize and WOWSYNC_UI_PANEL_RESIZE_RESET on a
-- double-click reset. The owner decides the reset size and persistence.
function Methods:EnableResizing(opts)
    if self._resizeGrip then return end
    opts = opts or {}
    local frame = self
    -- Resolved lazily: ResizeGrip loads after Panel in the load order.
    local ResizeGrip = addon:GetObject("ResizeGrip")

    frame:SetResizable(true)
    if opts.minWidth then
        frame:SetResizeBounds(opts.minWidth, opts.minHeight, opts.maxWidth, opts.maxHeight)
    end

    self._resizeGrip = ResizeGrip:Build(frame, {
        onResizeStop = function(width, height)
            Panel:TriggerEvent(EVENT_RESIZED, frame, width, height)
        end,
        onReset = function()
            Panel:TriggerEvent(EVENT_RESIZE_RESET, frame)
        end,
    })
    self._resizeGrip:SetLocked(frame._locked)
end

-- Register the panel with UISpecialFrames so Esc closes it. Requires the panel to
-- have been built with a name.
function Methods:EnableCloseOnEscape()
    if self._escapeEnabled then return end
    local name = self:GetName()
    C:Ensures(name ~= nil, "EnableCloseOnEscape: the panel must be built with a name")
    self._escapeEnabled = true
    tinsert(UISpecialFrames, name)
end

-- The base feature methods merged with a window type's own methods, cached by
-- that method table so each type merges once rather than once per window built.
local mergedMethods = setmetatable({}, { __mode = "k" })

local function ResolveMethods(concreteMethods)
    if not concreteMethods then
        return Methods
    end

    local merged = mergedMethods[concreteMethods]
    if not merged then
        merged = {}
        for key, value in pairs(Methods) do
            merged[key] = value
        end
        -- The window type's methods win over the base features on a name clash.
        for key, value in pairs(concreteMethods) do
            merged[key] = value
        end
        mergedMethods[concreteMethods] = merged
    end
    return merged
end

-- Build a window: create the frame (parented to UIParent by default), dress it in
-- chrome, mix the base features and the concrete window's methods onto it, and run
-- the concrete Constructor with everything in place. Returns the frame.
function Panel:Build(config)
    C:IsTable(config, 2)

    -- Create the frame here rather than letting NewWidget default the parent, so
    -- the caller's config table is never mutated.
    local frame = CreateFrame("Frame", config.name, config.parent or UIParent, config.template)

    return addon:NewWidget(config, {
        frame = frame,
        methods = ResolveMethods(config.methods),
        onReady = ApplyChrome,
    })
end
