local _, addon = ...

--[[
    Button widget (shared push button).

    Wraps the UIPanelButtonTemplate boilerplate every action button repeats:
    create the button, size it, anchor it, set its label, its initial enabled
    state, and its click handler. It owns no behaviour beyond construction;
    extra visuals (spinners, tooltips) and later state changes stay with the
    caller, which drives the returned button frame.

    local button = addon:GetObject("Button"):Build({
        parent = frame,                          -- frame the button lives in
        anchor = function(button) ... end,       -- optional, positions the button
        width = 80, height = 24,                 -- optional size (set together)
        text = L["Apply"],                        -- optional label
        enabled = false,                          -- optional initial state
        onClick = function() ... end,             -- optional click handler
    })
]]

local Button = addon:NewObject("Button")

local C = LibStub("Contracts-1.0")

function Button:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")

    local button = CreateFrame("Button", nil, config.parent, "UIPanelButtonTemplate")

    if config.width and config.height then
        button:SetSize(config.width, config.height)
    end

    if config.anchor then
        C:Ensures(type(config.anchor) == "function", "Build: 'config.anchor' must be a function")
        config.anchor(button)
    end

    if config.text then
        button:SetText(config.text)
    end

    if config.enabled ~= nil then
        button:SetEnabled(config.enabled)
    end

    if config.onClick then
        C:Ensures(type(config.onClick) == "function", "Build: 'config.onClick' must be a function")
        button:SetScript("OnClick", config.onClick)
    end

    return button
end
