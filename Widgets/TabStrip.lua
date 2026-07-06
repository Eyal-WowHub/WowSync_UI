local _, addon = ...

--[[
    TabStrip object.

    A row of slim tabs that switch a top-level view. Each tab shows an accent
    underline and a highlighted background when active; inactive tabs are dimmed.
    Clicking a tab reports its key through onSelect(key); the owner reflects the
    active tab by calling Select(key), which updates the visuals without firing
    onSelect again.

    addon:GetObject("TabStrip"):Build(parent, {
        height = number,
        tabs = { { key = string, label = string }, ... },
        onSelect = function(key),
    }) -> Frame { Select(key) }
]]

local TabStrip = addon:NewObject("TabStrip")

local C = addon.C
local UI = addon.UI

-- Fallback strip height when the caller does not supply one.
local DEFAULT_HEIGHT = 24

-- Width of each tab and the gap between adjacent tabs.
local TAB_WIDTH = 110
local TAB_GAP = 4

-- Offset of the first tab from the strip's left edge.
local FIRST_TAB_INSET = 2

-- Underline drawn beneath the active tab.
local TAB_UNDERLINE_INSET = 0
local TAB_UNDERLINE_THICKNESS = 2
local TAB_UNDERLINE_COLOR = CreateColor(0.25, 0.65, 0.95, 1)

-- A slim tab button. Active tabs show an accent underline and a highlighted
-- background; inactive tabs are dimmed.
local function CreateTab(parent, label, height, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(TAB_WIDTH, height)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(UI.Row.Normal:GetRGBA())

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(label)

    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetPoint("BOTTOMLEFT", TAB_UNDERLINE_INSET, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -TAB_UNDERLINE_INSET, 0)
    tab.underline:SetHeight(TAB_UNDERLINE_THICKNESS)
    tab.underline:SetColorTexture(TAB_UNDERLINE_COLOR:GetRGBA())
    tab.underline:Hide()

    tab.active = false

    function tab:SetActive(active)
        self.active = active
        self.underline:SetShown(active)
        self.text:SetFontObject(active and "GameFontNormal" or "GameFontDisable")
        self.bg:SetColorTexture((active and UI.Row.Selected or UI.Row.Normal):GetRGBA())
    end

    tab:SetScript("OnEnter", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    tab:SetScript("OnClick", onClick)

    return tab
end

local Methods = {}

-- Reflect the active tab in the visuals without firing onSelect.
function Methods:Select(key)
    for tabKey, tab in pairs(self._tabs) do
        tab:SetActive(tabKey == key)
    end
end

-- Build the row of tabs, anchored left to right, and seed them inactive. The
-- strip IS this frame; the owner calls Select to mark the active tab.
function Methods:Constructor(config)
    local height = config.height
    self:SetHeight(height)

    local tabs = {}
    local previous

    for _, tabDefinition in ipairs(config.tabs) do
        local key = tabDefinition.key
        local tab = CreateTab(self, tabDefinition.label, height, function()
            if config.onSelect then
                config.onSelect(key)
            end
        end)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", TAB_GAP, 0)
        else
            tab:SetPoint("LEFT", FIRST_TAB_INSET, 0)
        end
        tabs[key] = tab
        previous = tab
    end

    self._tabs = tabs
end

function TabStrip:Build(parent, opts)
    C:IsTable(parent, 2)

    opts = opts or {}

    C:Ensures(type(opts.tabs) == "table" and #opts.tabs > 0, "Build: 'opts.tabs' must be a non-empty array")
    C:Ensures(opts.onSelect == nil or type(opts.onSelect) == "function", "Build: 'opts.onSelect' must be a function")

    for _, tabDefinition in ipairs(opts.tabs) do
        C:Ensures(type(tabDefinition.key) == "string", "Build: each tab needs a string 'key'")
        C:Ensures(type(tabDefinition.label) == "string", "Build: each tab needs a string 'label'")
    end

    return addon:NewWidget({
        parent = parent,
        height = opts.height or DEFAULT_HEIGHT,
        tabs = opts.tabs,
        onSelect = opts.onSelect,
    }, {
        frameType = "Frame",
        methods = Methods,
    })
end
