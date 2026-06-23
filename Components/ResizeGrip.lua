local _, addon = ...

local UI = addon.UI
local DragTracker = addon:GetObject("DragTracker")

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

function ResizeGrip:Build(frame, opts)
    opts = opts or {}

    local locked = false

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(UI.ResizeGripSize, UI.ResizeGripSize)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    -- A click that ends without the frame changing size, shortly after a previous
    -- such click, is treated as a double-click (reset) rather than a resize.
    local DOUBLE_CLICK_SECONDS = 0.3
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
        enabled = function() return not locked end,
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
            if math.abs(width - widthAtDown) > 1 or math.abs(height - heightAtDown) > 1 then
                -- An actual resize: persist it and clear any pending double-click
                -- so a quick click afterwards isn't mistaken for a reset.
                lastClickTime = 0
                if opts.onResizeStop then
                    opts.onResizeStop(width, height)
                end
                return
            end
            -- A click that didn't resize: a second such click in quick succession
            -- is a double-click, which resets.
            local now = GetTime()
            if (now - lastClickTime) <= DOUBLE_CLICK_SECONDS then
                lastClickTime = 0
                if opts.onReset then
                    opts.onReset()
                end
                return
            end
            lastClickTime = now
        end,
    })

    -- When locked the grip hides and stops responding to the mouse.
    function grip:SetLocked(value)
        locked = value and true or false
        self:SetShown(not locked)
    end

    return grip
end
