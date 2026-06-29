local _, addon = ...

--[[
    DragTracker object.

    Drives an OnUpdate drag loop on a region. While the mouse is held the onUpdate
    callback runs every frame; the drag ends on mouse-up or when the region hides.
    A drag begins only when enabled() returns true (omit to always allow). The
    geometry is the caller's: the callbacks read the cursor and move things.

    addon:GetObject("DragTracker"):Attach(region, {
        enabled  = function() -> boolean,   -- optional gate, checked on mouse-down
        onStart  = function(),              -- optional, once when the drag begins
        onUpdate = function(),              -- each frame while dragging
        onStop   = function(),              -- once when the drag ends
    })
]]

local DragTracker = addon:NewObject("DragTracker")

local C = LibStub("Contracts-1.0")

function DragTracker:Attach(region, opts)
    C:IsTable(region, 2)
    C:IsTable(opts, 3)

    C:Ensures(opts.enabled == nil or type(opts.enabled) == "function", "Attach: 'opts.enabled' must be a function")
    C:Ensures(opts.onStart == nil or type(opts.onStart) == "function", "Attach: 'opts.onStart' must be a function")
    C:Ensures(opts.onUpdate == nil or type(opts.onUpdate) == "function", "Attach: 'opts.onUpdate' must be a function")
    C:Ensures(opts.onStop == nil or type(opts.onStop) == "function", "Attach: 'opts.onStop' must be a function")

    local dragging = false

    local function StopDragging()
        if not dragging then return end
        dragging = false
        region:SetScript("OnUpdate", nil)
        if opts.onStop then
            opts.onStop()
        end
    end

    region:SetScript("OnMouseDown", function()
        if opts.enabled and not opts.enabled() then return end
        dragging = true
        if opts.onStart then
            opts.onStart()
        end
        if opts.onUpdate then
            region:SetScript("OnUpdate", opts.onUpdate)
        end
    end)
    region:SetScript("OnMouseUp", StopDragging)
    region:SetScript("OnHide", StopDragging)
end
