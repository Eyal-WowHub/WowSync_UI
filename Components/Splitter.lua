local _, addon = ...

--[[
    Splitter object.

    A thin draggable handle that lives in the gap between a pane's two panels.
    Dragging it reports the raw left-panel ratio (0..1 of the pane width, taken
    straight from the cursor) through onResize(ratio) on every frame of the drag,
    and onCommit() once on release so the owner can persist. Clamping is the
    owner's job; the handle only maps the cursor to a fraction of the pane.

    A pane is any frame ("view") containing a left slot frame; the handle anchors
    to the right edge of that slot and spans the pane's height.

    addon:GetObject("Splitter"):Build(pane, {
        onResize = function(ratio),
        onCommit = function(),
    }) -> Button { SetLocked(locked) }

    where pane = { view = Frame, leftSlot = Frame }.
]]

local Splitter = addon:NewObject("Splitter")
local DragTracker = addon:GetObject("DragTracker")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

-- Idle and hover colours of the handle's centre line { r, g, b, a }.
local SPLITTER_COLOR = { 0.35, 0.35, 0.35, 0.7 }
local SPLITTER_HOVER_COLOR = { 0.25, 0.65, 0.95, 0.9 }

-- Thickness of the handle's centre line.
local LINE_THICKNESS = 2

-- Frame levels the handle sits above its pane so it stays clickable.
local HANDLE_FRAME_LEVEL_OFFSET = 5

function Splitter:Build(pane, opts)
    C:IsTable(pane, 2)

    C:Ensures(type(pane.view) == "table", "Build: 'pane.view' must be a frame")
    C:Ensures(type(pane.leftSlot) == "table", "Build: 'pane.leftSlot' must be a frame")

    opts = opts or {}

    C:Ensures(opts.onResize == nil or type(opts.onResize) == "function", "Build: 'opts.onResize' must be a function")
    C:Ensures(opts.onCommit == nil or type(opts.onCommit) == "function", "Build: 'opts.onCommit' must be a function")

    local view = pane.view
    local locked = false

    local handle = CreateFrame("Button", nil, view)
    handle:SetWidth(UI.Splitter.Width)
    handle:SetPoint("TOPLEFT", pane.leftSlot, "TOPRIGHT", 0, 0)
    handle:SetPoint("BOTTOMLEFT", pane.leftSlot, "BOTTOMRIGHT", 0, 0)
    handle:SetFrameLevel(view:GetFrameLevel() + HANDLE_FRAME_LEVEL_OFFSET)
    handle:EnableMouse(true)

    handle.line = handle:CreateTexture(nil, "OVERLAY")
    handle.line:SetPoint("TOP")
    handle.line:SetPoint("BOTTOM")
    handle.line:SetWidth(LINE_THICKNESS)
    handle.line:SetColorTexture(unpack(SPLITTER_COLOR))

    handle:SetScript("OnEnter", function(self)
        if not locked then
            self.line:SetColorTexture(unpack(SPLITTER_HOVER_COLOR))
        end
    end)
    handle:SetScript("OnLeave", function(self)
        self.line:SetColorTexture(unpack(SPLITTER_COLOR))
    end)

    DragTracker:Attach(handle, {
        enabled = function() return not locked end,
        onUpdate = function()
            local viewWidth = view:GetWidth()
            local viewLeft = view:GetLeft()
            if viewLeft and viewWidth and viewWidth > 0 then
                local cursorX = GetCursorPosition() / view:GetEffectiveScale()
                if opts.onResize then
                    opts.onResize((cursorX - viewLeft) / viewWidth)
                end
            end
        end,
        onStop = function()
            if opts.onCommit then
                opts.onCommit()
            end
        end,
    })

    -- When locked the handle ignores the mouse and drops back to its idle colour.
    function handle:SetLocked(value)
        locked = value and true or false
        self:EnableMouse(not locked)
        self.line:SetColorTexture(unpack(SPLITTER_COLOR))
    end

    return handle
end
