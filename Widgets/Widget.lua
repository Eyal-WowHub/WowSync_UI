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
        onReady   = function(frame) end,      -- optional: runs after layout, before Constructor
    })

    config carries the common layout keys ApplyLayout consumes -- parent, anchor,
    width, height, shown -- plus whatever else the widget's Constructor reads.
]]

-- The base methods mixed onto every widget frame. Deliberately a plain table and
-- NOT an addon:NewObject: NewWidget Mixin-copies these keys straight onto each
-- frame, so an Addon-1.0 object here would copy its per-object state (a shared
-- __ObjectContext) and event/name methods onto -- and over -- every frame too.
-- We also considered making Widget a proper object (base methods in a private
-- Methods table, Mixin'd instead of the object itself) -- see below. Kept the
-- plain table: it's simpler, and object-ness buys Widget nothing today (no
-- events, lifecycle, or storage).
--[[
    local Widget = addon:NewObject("Widget")
    local Methods = {}
    function Methods:SetShownIf(...) ... end
    function Widget:New(config, def) ... Mixin(frame, Methods, def.methods or {}) ... end
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

    -- A hook to finish the frame after mixin and layout but before its Constructor,
    -- so a builder (e.g. Panel) can lay chrome behind the content the Constructor
    -- then adds.
    if def.onReady then
        def.onReady(frame, config)
    end

    if frame.Constructor then
        frame:Constructor(config)
    end

    return frame
end
