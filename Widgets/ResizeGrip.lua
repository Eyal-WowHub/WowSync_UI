local _, addon = ...

--[[
    ResizeGrip object.

    A corner grab handle that resizes its target frame. Anchored to the frame's
    bottom-right; dragging it sizes the frame (the frame must be resizable and
    have its bounds configured by the owner). Reports the final size through
    onResizeStop(width, height) so the owner can persist and re-lay out.
    Double-clicking the grip fires onReset() so the owner can restore defaults.

    addon:GetObject("ResizeGrip"):Build(frame, {
        onResizeStop = function(width, height),
        onReset = function(),
    }) -> Button { SetLocked(locked) }
]]

local ResizeGrip = addon:NewObject("ResizeGrip")

local C = addon.C

local DragTracker = addon:GetObject("DragTracker")

-- Size of the square grab handle.
local RESIZE_GRIP_SIZE = 16

-- Inset of the grip from the frame's bottom-right corner, just clearing the
-- window's 1px border so the handle sits snug in the corner.
local GRIP_INSET = 1

-- Frame levels the grip sits above its frame so it stays clickable.
local GRIP_FRAME_LEVEL_OFFSET = 10

-- A click that ends without the frame changing size, shortly after a previous
-- such click, is treated as a double-click (reset) rather than a resize.
local DOUBLE_CLICK_SECONDS = 0.3

-- Pixels of size change below which a drag counts as a click rather than a resize.
local RESIZE_EPSILON = 1

local Methods = {}

-- When locked the grip hides and stops responding to the mouse.
function Methods:SetLocked(value)
    self._locked = value and true or false
    self:SetShown(not self._locked)
end

-- Build the corner grab handle and wire cursor-tracked resizing with a
-- double-click reset. The grip IS this frame; config.target is the frame it
-- resizes (also its parent).
function Methods:Constructor(config)
    local frame = config.target
    self._locked = false

    self:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    self:SetPoint("BOTTOMRIGHT", -GRIP_INSET, GRIP_INSET)
    self:SetFrameLevel(frame:GetFrameLevel() + GRIP_FRAME_LEVEL_OFFSET)
    self:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    self:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    self:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local grip = self

    -- Click-tracking state: the time of the last non-resizing click and the frame
    -- size when the current drag began, used to tell a resize from a double-click.
    local lastClickTime = 0
    local widthAtDown, heightAtDown = 0, 0

    -- Resize state captured when the drag begins, shared with the per-frame update.
    local left, top, grabX, grabY
    local minWidth, minHeight, maxWidth, maxHeight

    -- Resize by tracking the cursor's absolute position each frame rather than
    -- StartSizing, which stops following once the cursor outruns the corner at a
    -- size bound and never re-syncs. The top-left corner is pinned so only the
    -- bottom-right moves; width/height are recomputed from the cursor and clamped
    -- to the frame's resize bounds, so crossing back over the corner re-syncs at
    -- once. A grab offset keeps the corner from jumping under the cursor.
    DragTracker:Attach(grip, {
        enabled = function() return not grip._locked end,
        onStart = function()
            widthAtDown, heightAtDown = frame:GetWidth(), frame:GetHeight()
            left, top = frame:GetLeft(), frame:GetTop()
            if not left or not top then return end

            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

            minWidth, minHeight, maxWidth, maxHeight = frame:GetResizeBounds()
            local cursorX, cursorY = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            grabX = cursorX / scale - frame:GetRight()
            grabY = cursorY / scale - frame:GetBottom()
        end,
        onUpdate = function()
            if not left or not top then return end
            local scale = frame:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            local right = cursorX / scale - grabX
            local bottom = cursorY / scale - grabY
            frame:SetSize(
                Clamp(right - left, minWidth, maxWidth),
                Clamp(top - bottom, minHeight, maxHeight))
        end,
        onStop = function()
            local width, height = frame:GetWidth(), frame:GetHeight()
            if math.abs(width - widthAtDown) > RESIZE_EPSILON or math.abs(height - heightAtDown) > RESIZE_EPSILON then
                -- An actual resize: persist it and clear any pending double-click
                -- so a quick click afterwards isn't mistaken for a reset.
                lastClickTime = 0
                if config.onResizeStop then
                    config.onResizeStop(width, height)
                end
                return
            end
            -- A click that didn't resize: a second such click in quick succession
            -- is a double-click, which resets.
            local now = GetTime()
            if (now - lastClickTime) <= DOUBLE_CLICK_SECONDS then
                lastClickTime = 0
                if config.onReset then
                    config.onReset()
                end
                return
            end
            lastClickTime = now
        end,
    })
end

function ResizeGrip:Build(frame, opts)
    C:IsTable(frame, 2)

    opts = opts or {}

    C:Ensures(opts.onResizeStop == nil or type(opts.onResizeStop) == "function", "Build: 'opts.onResizeStop' must be a function")
    C:Ensures(opts.onReset == nil or type(opts.onReset) == "function", "Build: 'opts.onReset' must be a function")

    return addon:NewWidget({
        parent = frame,
        target = frame,
        onResizeStop = opts.onResizeStop,
        onReset = opts.onReset,
    }, {
        frameType = "Button",
        methods = Methods,
    })
end
