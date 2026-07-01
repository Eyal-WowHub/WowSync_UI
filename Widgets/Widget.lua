local _, addon = ...

--[[
    Widget core (the single widget model).

    Every widget IS a frame. A widget defines its class as a `methods` table and
    an optional Constructor(config) method; addon:NewWidget creates or adopts a
    frame, mixes the shared base methods and the widget's methods onto it, applies the
    common layout, then runs Constructor. Frames cannot inherit through a metatable (theirs is
    reserved for the C widget dispatch), so methods are copied on with Mixin -- once,
    here, never at the call sites.

    local frame = addon:NewWidget(config, {
        frameType = "Button",                 -- optional, default "Frame"
        template  = "UIPanelButtonTemplate",  -- optional
        name      = "GlobalFrameName",        -- optional: global name (ESC, _G lookup)
        frame     = existingFrame,            -- optional: adopt instead of create
        methods   = ButtonMethods,            -- optional: the widget's class
    })

    config carries the common layout keys ApplyLayout consumes -- parent, anchor,
    width, height, shown -- plus whatever else the widget's Constructor reads.
]]

local Widget = {}

function Widget:SetShownIf(condition)
    self:SetShown(condition and true or false)
end

-- Apply the common layout keys every widget repeats, in the original order:
-- size, then anchor, then initial visibility.
function Widget:ApplyLayout(config)
    if config.width and config.height then
        self:SetSize(config.width, config.height)
    end
    if config.anchor then
        config.anchor(self)
    end
    if config.shown ~= nil then
        self:SetShownIf(config.shown)
    end
end

-- The single entry point every widget's Build funnels through. Creates the frame
-- (or adopts def.frame), mixes the base + the widget's methods onto it, lays it out,
-- and runs the optional Constructor hook.
function addon:NewWidget(config, def)
    local frame = def.frame or CreateFrame(def.frameType or "Frame", def.name, config.parent, def.template)

    Mixin(frame, Widget, def.methods or {})
    frame:ApplyLayout(config)

    if frame.Constructor then
        frame:Constructor(config)
    end

    return frame
end
