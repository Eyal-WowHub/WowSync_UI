local _, addon = ...

--[[
    ScrollList widget (shared scroll-box plumbing).

    Wraps the boilerplate every WowScrollBoxList in the addon repeats: it creates
    the scroll box and its MinimalScrollBar, wires a linear view with the given
    extent and padding, installs a build-once/update element initializer, and
    hides the scrollbar when the content fits. It owns no selection, chrome, or
    data; the caller anchors it, supplies the row build/update, and drives it
    through the returned scroll box (SetDataProvider, ForEachFrame, ...).

    local scrollBox = addon:GetObject("ScrollList"):Build({
        parent = root,                          -- frame the scroll box lives in
        anchor = function(scrollBox) ... end,   -- positions the scroll box
        elementType = "Frame",                  -- optional, default "Frame"
        extent = number or function(_, data),   -- fixed height or per-element calc
        padding = UI.List.ItemPadding,           -- optional gap between rows
        build = function(row) end,               -- one-time child creation
        update = function(row, data) end,        -- per-render content
    })
]]

local ScrollList = addon:NewObject("ScrollList")

local C = LibStub("Contracts-1.0")

function ScrollList:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")
    C:Ensures(type(config.anchor) == "function", "Build: 'config.anchor' must be a function")
    C:Ensures(config.extent ~= nil, "Build: 'config.extent' is required")
    C:Ensures(type(config.build) == "function", "Build: 'config.build' must be a function")
    C:Ensures(type(config.update) == "function", "Build: 'config.update' must be a function")

    local scrollBox = CreateFrame("Frame", nil, config.parent, "WowScrollBoxList")
    config.anchor(scrollBox)

    local scrollBar = CreateFrame("EventFrame", nil, config.parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    if type(config.extent) == "function" then
        view:SetElementExtentCalculator(config.extent)
    else
        view:SetElementExtent(config.extent)
    end
    view:SetPadding(0, 0, 0, 0, config.padding or 0)

    local build, update = config.build, config.update
    view:SetElementInitializer(config.elementType or "Frame", function(row, data)
        if not row.initialized then
            build(row)
            row.initialized = true
        end
        update(row, data)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Only show the scrollbar when the list actually overflows.
    scrollBar:SetHideIfUnscrollable(true)

    return scrollBox
end
