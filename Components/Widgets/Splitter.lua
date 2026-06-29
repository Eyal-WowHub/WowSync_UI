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

-- Trim taken off each end of the centre line so it stops short of the pane edges
-- rather than running the full height.
local LINE_END_INSET = 4

-- Frame levels the handle sits above its pane so it stays clickable.
local HANDLE_FRAME_LEVEL_OFFSET = 5

local Verbs = {}

-- When locked the handle ignores the mouse and drops back to its idle colour.
function Verbs:SetLocked(value)
    self._locked = value and true or false
    self:EnableMouse(not self._locked)
    self.line:SetColorTexture(unpack(SPLITTER_COLOR))
end

-- Build the drag handle in the gap to the right of the pane's left slot and wire
-- the cursor-to-ratio drag. The handle IS this frame.
function Verbs:Constructor(config)
    local view = config.view
    self._locked = false

    self:SetWidth(UI.Splitter.Width)
    self:SetPoint("TOPLEFT", config.leftSlot, "TOPRIGHT", 0, 0)
    self:SetPoint("BOTTOMLEFT", config.leftSlot, "BOTTOMRIGHT", 0, 0)
    self:SetFrameLevel(view:GetFrameLevel() + HANDLE_FRAME_LEVEL_OFFSET)
    self:EnableMouse(true)

    self.line = self:CreateTexture(nil, "OVERLAY")
    self.line:SetPoint("TOP", 0, -LINE_END_INSET)
    self.line:SetPoint("BOTTOM", 0, LINE_END_INSET)
    self.line:SetWidth(LINE_THICKNESS)
    self.line:SetColorTexture(unpack(SPLITTER_COLOR))

    self:SetScript("OnEnter", function(self)
        if not self._locked then
            self.line:SetColorTexture(unpack(SPLITTER_HOVER_COLOR))
        end
    end)
    self:SetScript("OnLeave", function(self)
        self.line:SetColorTexture(unpack(SPLITTER_COLOR))
    end)

    local handle = self
    DragTracker:Attach(handle, {
        enabled = function() return not handle._locked end,
        onUpdate = function()
            local viewWidth = view:GetWidth()
            local viewLeft = view:GetLeft()
            if viewLeft and viewWidth and viewWidth > 0 then
                local cursorX = GetCursorPosition() / view:GetEffectiveScale()
                if config.onResize then
                    config.onResize((cursorX - viewLeft) / viewWidth)
                end
            end
        end,
        onStop = function()
            if config.onCommit then
                config.onCommit()
            end
        end,
    })
end

function Splitter:Build(pane, opts)
    C:IsTable(pane, 2)

    C:Ensures(type(pane.view) == "table", "Build: 'pane.view' must be a frame")
    C:Ensures(type(pane.leftSlot) == "table", "Build: 'pane.leftSlot' must be a frame")

    opts = opts or {}

    C:Ensures(opts.onResize == nil or type(opts.onResize) == "function", "Build: 'opts.onResize' must be a function")
    C:Ensures(opts.onCommit == nil or type(opts.onCommit) == "function", "Build: 'opts.onCommit' must be a function")

    return addon:NewWidget({
        parent = pane.view,
        view = pane.view,
        leftSlot = pane.leftSlot,
        onResize = opts.onResize,
        onCommit = opts.onCommit,
    }, {
        frameType = "Button",
        verbs = Verbs,
    })
end
