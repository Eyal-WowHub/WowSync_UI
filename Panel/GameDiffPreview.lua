local _, addon = ...

--[[
    GameDiffPreview object.

    A standalone, movable window that lists the actual entries a snapshot diff
    would add, update, or remove against the live setup -- macros, keybindings,
    action slots, talents, CVars, addons, and so on -- grouped by module. It is a
    pure viewer: callers hand it a ready preview and it renders, owning none of
    the apply/undo logic.

    The list is pooled and virtualised, so a large diff renders lazily as the
    user scrolls. A module filter narrows the view to one module, or shows them
    all. Removed entries appear only when the mode is Exact, mirroring what an
    apply in that mode would actually delete.

    Each diff entry may be a plain label string or a table
    { label, icon, description }; the icon and one-line description are optional.

    addon:GetObject("GameDiffPreview"):Show({
        title        = string,                 -- window title (optional)
        preview      = { perModule = {...} },  -- from SnapshotManager:Preview
        mode         = "exact" | "merge",      -- gates the Removed section
        moduleFilter = name | nil,             -- nil shows every module
        pluginFilter = name | nil,             -- narrow the Plugin umbrella to one plugin
        subModuleFilter = name | nil,          -- narrow that plugin to one submodule
    })
]]

local GameDiffPreview = addon:NewObject("GameDiffPreview")

local C = addon.C
local L = addon.L
local UI = addon.UI

local Dialog = addon:GetObject("Dialog")
local ScrollList = addon:GetObject("ScrollList")
local Button = addon:GetObject("Button")
local SnapshotRow = addon:GetObject("SnapshotRow")

local Module = WowSync:Import("Module")

-- Row heights per element kind; the list mixes module headers, section
-- subheaders, and entry rows in one virtualised stream.
local PLUGIN_HEADER_HEIGHT = 34
local MODULE_HEADER_HEIGHT = 24
local SECTION_HEADER_HEIGHT = 18
local ITEM_HEIGHT = 20
local EMPTY_HEIGHT = 28

-- Left inset of each element kind, and the entry icon size. Entries indent past
-- the icon column so labels line up whether or not an entry carries an icon.
local PLUGIN_INSET = 6
local MODULE_INSET = 6
local SECTION_INSET = 16
local ITEM_INSET = 20
local ICON_SIZE = 16
local ICON_TEXT_GAP = 4
local TEXT_RIGHT_INSET = 6

-- Extra left shift applied to a plugin's submodule headers, sections, and
-- entries so they read as nested beneath their plugin's section header.
local SUBMODULE_INDENT = 12

-- Scroll region insets, used both to place the list and to derive the wrap
-- width available to an entry's description line.
local SCROLLBOX_LEFT_INSET = 14
local SCROLLBOX_RIGHT_INSET = 28
local ROW_WIDTH = UI.Preview.Width - SCROLLBOX_LEFT_INSET - SCROLLBOX_RIGHT_INSET

-- The list starts below a slim toolbar whose two buttons collapse or expand
-- every section at once, anchored to the top-right of the window.
local SCROLLBOX_TOP_INSET = -58
local TOOLBAR_TOP = -30
local TOOLBAR_BUTTON_WIDTH = 96
local TOOLBAR_BUTTON_HEIGHT = 22
local TOOLBAR_RIGHT_INSET = 14
local TOOLBAR_BUTTON_GAP = 6

-- Vertical layout of an entry row that carries a description: the label sits at
-- the top, the wrapped grey description follows beneath it.
local ITEM_TOP_PAD = 3
local LABEL_HEIGHT = 14
local DESC_GAP = 2
local ITEM_BOTTOM_PAD = 4

-- Tints for the three change kinds (added green, updated gold, removed red),
-- matching the +A ~C -R colours used elsewhere.
local ADDED_COLOR = CreateColor(0.37, 0.81, 0.37)
local CHANGED_COLOR = CreateColor(0.85, 0.78, 0.29)
local REMOVED_COLOR = CreateColor(0.85, 0.42, 0.42)
local MODULE_HEADER_COLOR = CreateColor(0.95, 0.95, 0.95)
local PLUGIN_HEADER_COLOR = CreateColor(0.25, 0.65, 0.97)

-- The change kinds in display order; "removed" is shown only in Exact mode.
local SECTIONS = {
    { key = "added", color = ADDED_COLOR, label = L["Added (X)"] },
    { key = "changed", color = CHANGED_COLOR, label = L["Updated (X)"] },
    { key = "removed", color = REMOVED_COLOR, label = L["Removed (X)"] },
}

local Methods = {}

-- Forward declaration: the header click handlers and the toolbar both rebuild
-- the list, while Rebuild itself is defined once the render helpers exist.
local Rebuild

-- The label, optional icon, and optional description of a diff entry, which may
-- be a bare string or a { label, icon, description } table.
local function NormalizeEntry(entry)
    if type(entry) == "table" then
        return entry.label or "", entry.icon, entry.description
    end
    return entry, nil, nil
end

-- The module names present in a preview, sorted for a stable list order.
local function ModuleNamesIn(preview)
    local names = {}
    if preview and preview.perModule then
        for name in pairs(preview.perModule) do
            tinsert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- True when a module has any entry the current mode would show.
local function HasVisibleChanges(moduleDiff, showRemoved)
    if not moduleDiff then return false end
    local count = #(moduleDiff.added or {}) + #(moduleDiff.changed or {})
    if showRemoved then
        count = count + #(moduleDiff.removed or {})
    end
    return count > 0
end

-- Whether a module deletes entries on apply (Exact-capable). Merge-only modules
-- never remove, so their removals are not previewed even in Exact mode.
local function ModuleSupportsExact(name)
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode
    local module = Module:FromRegisteredModule(name)
    local modes = module and module:ApplyMode()
    return applyModes and applyModes.CanExact(modes) or false
end

-- The pixel height an entry row needs: a single centred line when it has no
-- description, or a top-aligned label plus its wrapped description otherwise.
local function ItemHeight(panel, item)
    if not item.description or item.description == "" then
        return ITEM_HEIGHT
    end
    local iconOffset = item.icon and (ICON_SIZE + ICON_TEXT_GAP) or 0
    local measureText = panel._measureText
    measureText:SetWidth(ROW_WIDTH - (ITEM_INSET + (item.indent or 0) + iconOffset) - TEXT_RIGHT_INSET)
    measureText:SetText(item.description)
    local descHeight = math.ceil(measureText:GetStringHeight())
    return ITEM_TOP_PAD + LABEL_HEIGHT + DESC_GAP + descHeight + ITEM_BOTTOM_PAD
end

-- Insert a module's non-empty Added/Updated/Removed sections and their entry
-- rows into the element stream. indent shifts the sections and entries right so
-- a plugin's submodules read as nested beneath their plugin header.
local function InsertModuleEntries(panel, dataProvider, moduleDiff, moduleIcon, showRemoved, indent)
    indent = indent or 0
    for _, section in ipairs(SECTIONS) do
        if section.key ~= "removed" or showRemoved then
            local entries = moduleDiff[section.key] or {}
            if #entries > 0 then
                dataProvider:Insert({ kind = "section", section = section, count = #entries, indent = indent })
                for _, entry in ipairs(entries) do
                    local label, icon, description = NormalizeEntry(entry)
                    local item = {
                        kind = "item",
                        label = label,
                        icon = icon or moduleIcon,
                        description = description,
                        indent = indent,
                    }
                    item.height = ItemHeight(panel, item)
                    dataProvider:Insert(item)
                end
            end
        end
    end
end

-- True when a plugin has at least one submodule (optionally only the filtered
-- one) with changes the mode would show.
local function PluginHasVisible(plugin, exactMode, subModuleFilter)
    for _, subModule in ipairs(plugin.subModules) do
        if not subModuleFilter or subModule.name == subModuleFilter then
            local showRemoved = exactMode and subModule.canExact
            if HasVisibleChanges(subModule, showRemoved) then
                return true
            end
        end
    end
    return false
end

-- Insert one plugin as a collapsible section header named for the plugin; while
-- expanded, each changed submodule follows as its own collapsible module header
-- with entries beneath. Returns whether the plugin header was shown.
local function InsertPlugin(panel, dataProvider, plugin, exactMode, subModuleFilter)
    if not PluginHasVisible(plugin, exactMode, subModuleFilter) then
        return false
    end

    local pluginKey = "plugin:" .. plugin.name
    local expanded = not panel._collapsed[pluginKey]
    dataProvider:Insert({
        kind = "plugin",
        name = plugin.name,
        collapseKey = pluginKey,
        expanded = expanded,
    })

    if expanded then
        for _, subModule in ipairs(plugin.subModules) do
            if not subModuleFilter or subModule.name == subModuleFilter then
                local showRemoved = exactMode and subModule.canExact
                if HasVisibleChanges(subModule, showRemoved) then
                    local subKey = pluginKey .. "/" .. subModule.name
                    local subExpanded = not panel._collapsed[subKey]
                    dataProvider:Insert({
                        kind = "module",
                        name = subModule.name,
                        collapseKey = subKey,
                        expanded = subExpanded,
                        indent = SUBMODULE_INDENT,
                    })
                    if subExpanded then
                        InsertModuleEntries(panel, dataProvider, subModule, nil, showRemoved, SUBMODULE_INDENT)
                    end
                end
            end
        end
    end

    return true
end

-- Flatten the preview into the list's element stream: for each module, a
-- collapsible header then its sections and entries. The Plugin umbrella's diff
-- carries submodules, so it expands into a collapsible section header per
-- plugin with its submodules beneath. Returns whether anything was shown.
local function Populate(panel, dataProvider, preview, filterName, mode, pluginFilter, subModuleFilter)
    local exactMode = (mode == "exact")
    local anyShown = false

    for _, name in ipairs(ModuleNamesIn(preview)) do
        if not filterName or filterName == name then
            local moduleDiff = preview.perModule[name]
            if moduleDiff.plugins then
                for _, plugin in ipairs(moduleDiff.plugins) do
                    if (not pluginFilter or plugin.name == pluginFilter)
                        and InsertPlugin(panel, dataProvider, plugin, exactMode, subModuleFilter) then
                        anyShown = true
                    end
                end
            else
                -- Removals are real only when this module applies in Exact, so a
                -- merge-only module never shows a Removed section.
                local showRemoved = exactMode and ModuleSupportsExact(name)
                if HasVisibleChanges(moduleDiff, showRemoved) then
                    anyShown = true
                    local moduleKey = "module:" .. name
                    local expanded = not panel._collapsed[moduleKey]
                    dataProvider:Insert({
                        kind = "module",
                        name = name,
                        collapseKey = moduleKey,
                        expanded = expanded,
                    })
                    if expanded then
                        local module = Module:FromRegisteredModule(name)
                        local moduleIcon = module and module:DefaultIcon()
                        InsertModuleEntries(panel, dataProvider, moduleDiff, moduleIcon, showRemoved)
                    end
                end
            end
        end
    end

    if not anyShown then
        dataProvider:Insert({ kind = "empty" })
    end

    return anyShown
end

-- Visit every top-level collapsible header key the current preview would show
-- (each plain module and each plugin), in list order. A plugin's submodules
-- collapse independently and are not swept here, so Collapse All folds the view
-- down to just its top-level section headers.
local function ForEachTopHeaderKey(preview, filterName, mode, fn, pluginFilter, subModuleFilter)
    local exactMode = (mode == "exact")
    for _, name in ipairs(ModuleNamesIn(preview)) do
        if not filterName or filterName == name then
            local moduleDiff = preview.perModule[name]
            if moduleDiff.plugins then
                for _, plugin in ipairs(moduleDiff.plugins) do
                    if (not pluginFilter or plugin.name == pluginFilter)
                        and PluginHasVisible(plugin, exactMode, subModuleFilter) then
                        fn("plugin:" .. plugin.name)
                    end
                end
            else
                local showRemoved = exactMode and ModuleSupportsExact(name)
                if HasVisibleChanges(moduleDiff, showRemoved) then
                    fn("module:" .. name)
                end
            end
        end
    end
end

-- Create the reusable widgets a pooled row needs for any element kind.
local function BuildRow(row)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    row.bg = bg

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    row.icon = icon

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.text = text

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.6, 0.6, 0.6)
    desc:Hide()
    row.desc = desc

    -- Header rows toggle their section on click, with hover feedback; the
    -- scripts stay inert on other rows, which carry no collapse key and keep the
    -- mouse disabled. Wiring once here (reading the row's live key) avoids
    -- rebuilding closures on every render.
    row:SetScript("OnEnter", function(self)
        if self._collapseKey then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._collapseKey then
            self.bg:SetColorTexture(0, 0, 0, 0)
        end
    end)
    row:SetScript("OnMouseUp", function(self)
        local key = self._collapseKey
        if not key then return end
        local panel = self._panel
        panel._collapsed[key] = not panel._collapsed[key] or nil
        Rebuild(panel)
    end)
end

-- Render a pooled row for its element kind. Header rows (plugin and module)
-- carry a disclosure marker and toggle their section's collapsed state on click.
local function UpdateRow(row, data, panel)
    row.icon:Hide()
    row.desc:Hide()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row._panel = panel
    row._collapseKey = nil
    row:EnableMouse(false)
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", row, "RIGHT", -TEXT_RIGHT_INSET, 0)

    if data.kind == "plugin" then
        -- A Settings-style section header (large heading) so each plugin reads as
        -- its own block, matching WoW's Options panel.
        row.text:SetFontObject("GameFontHighlightLarge")
        row.text:SetText(SnapshotRow:ExpandMarker(data.expanded) .. data.name)
        row.text:SetTextColor(PLUGIN_HEADER_COLOR:GetRGB())
        row.text:SetPoint("LEFT", row, "LEFT", PLUGIN_INSET, 0)
        row._collapseKey = data.collapseKey
        row:EnableMouse(true)
    elseif data.kind == "module" then
        row.text:SetFontObject("GameFontNormal")
        row.text:SetText(SnapshotRow:ExpandMarker(data.expanded) .. data.name)
        row.text:SetTextColor(MODULE_HEADER_COLOR:GetRGB())
        row.text:SetPoint("LEFT", row, "LEFT", MODULE_INSET + (data.indent or 0), 0)
        row._collapseKey = data.collapseKey
        row:EnableMouse(true)
    elseif data.kind == "section" then
        row.text:SetFontObject("GameFontNormalSmall")
        row.text:SetText(data.section.label:format(data.count))
        row.text:SetTextColor(data.section.color:GetRGB())
        row.text:SetPoint("LEFT", row, "LEFT", SECTION_INSET + (data.indent or 0), 0)
    elseif data.kind == "item" then
        row.text:SetFontObject("GameFontHighlightSmall")
        row.text:SetText(data.label)
        row.text:SetTextColor(1, 1, 1)

        local iconOffset = data.icon and (ICON_SIZE + ICON_TEXT_GAP) or 0
        local itemInset = ITEM_INSET + (data.indent or 0)
        local hasDesc = data.description and data.description ~= ""

        if hasDesc then
            -- Top-align the label (and icon) so the wrapped description can sit
            -- beneath them instead of fighting the row's vertical centring.
            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", itemInset + iconOffset, -ITEM_TOP_PAD)
            row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TEXT_RIGHT_INSET, -ITEM_TOP_PAD)

            if data.icon then
                row.icon:SetTexture(data.icon)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", itemInset, -ITEM_TOP_PAD)
                row.icon:Show()
            end

            row.desc:ClearAllPoints()
            row.desc:SetPoint("TOPLEFT", row, "TOPLEFT", itemInset + iconOffset, -(ITEM_TOP_PAD + LABEL_HEIGHT + DESC_GAP))
            row.desc:SetPoint("RIGHT", row, "RIGHT", -TEXT_RIGHT_INSET, 0)
            row.desc:SetText(data.description)
            row.desc:Show()
        elseif data.icon then
            row.icon:SetTexture(data.icon)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", itemInset, 0)
            row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", ICON_TEXT_GAP, 0)
        else
            row.text:SetPoint("LEFT", row, "LEFT", itemInset, 0)
        end
    else
        row.text:SetFontObject("GameFontDisableSmall")
        row.text:SetText(L["No changes to preview."])
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row.text:SetPoint("LEFT", row, "LEFT", SECTION_INSET, 0)
    end
end

-- Rebuild the element stream from the current preview, filter, and mode, and
-- show the Collapse/Expand toolbar only when there is something to collapse.
function Rebuild(panel)
    local dataProvider = CreateDataProvider()
    local anyShown = Populate(panel, dataProvider, panel._currentPreview, panel._moduleFilter, panel._currentMode, panel._pluginFilter, panel._subModuleFilter)
    panel._scrollBox:SetDataProvider(dataProvider)
    panel._collapseAllButton:SetShown(anyShown)
    panel._expandAllButton:SetShown(anyShown)
end

function Methods:Constructor(config)
    self._collapsed = {}

    -- Hidden font string used to measure wrapped description heights up front,
    -- so the virtualised list can size each entry row before it is shown.
    local measureText = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    measureText:Hide()
    measureText:SetWordWrap(true)
    measureText:SetJustifyH("LEFT")
    self._measureText = measureText

    self._scrollBox = ScrollList:Build({
        parent = self,
        anchor = function(sb)
            sb:SetPoint("TOPLEFT", SCROLLBOX_LEFT_INSET, SCROLLBOX_TOP_INSET)
            sb:SetPoint("BOTTOMRIGHT", -SCROLLBOX_RIGHT_INSET, 14)
        end,
        extent = function(_, data)
            if data.kind == "plugin" then
                return PLUGIN_HEADER_HEIGHT
            elseif data.kind == "module" then
                return MODULE_HEADER_HEIGHT
            elseif data.kind == "section" then
                return SECTION_HEADER_HEIGHT
            elseif data.kind == "empty" then
                return EMPTY_HEIGHT
            end
            return data.height or ITEM_HEIGHT
        end,
        padding = UI.List.ItemPadding,
        build = BuildRow,
        update = function(row, data) UpdateRow(row, data, self) end,
    })

    self._collapseAllButton = Button:Build({
        parent = self,
        width = TOOLBAR_BUTTON_WIDTH,
        height = TOOLBAR_BUTTON_HEIGHT,
        text = L["Collapse all"],
        anchor = function(button)
            button:SetPoint("TOPRIGHT", self, "TOPRIGHT",
                -(TOOLBAR_RIGHT_INSET + TOOLBAR_BUTTON_WIDTH + TOOLBAR_BUTTON_GAP), TOOLBAR_TOP)
        end,
        onClick = function() self:CollapseAll() end,
    })

    self._expandAllButton = Button:Build({
        parent = self,
        width = TOOLBAR_BUTTON_WIDTH,
        height = TOOLBAR_BUTTON_HEIGHT,
        text = L["Expand all"],
        anchor = function(button)
            button:SetPoint("TOPRIGHT", self, "TOPRIGHT", -TOOLBAR_RIGHT_INSET, TOOLBAR_TOP)
        end,
        onClick = function() self:ExpandAll() end,
    })
end

-- Collapse every top-level section (each module and plugin) to its header.
function Methods:CollapseAll()
    ForEachTopHeaderKey(self._currentPreview, self._moduleFilter, self._currentMode, function(key)
        self._collapsed[key] = true
    end, self._pluginFilter, self._subModuleFilter)
    Rebuild(self)
end

-- Expand everything, clearing every remembered collapsed section.
function Methods:ExpandAll()
    wipe(self._collapsed)
    Rebuild(self)
end

function Methods:Open(opts)
    self._currentPreview = opts.preview
    self._currentMode = opts.mode or "exact"
    self._moduleFilter = opts.moduleFilter
    self._pluginFilter = opts.pluginFilter
    self._subModuleFilter = opts.subModuleFilter
    wipe(self._collapsed)

    self:SetTitle(opts.title or L["Preview changes"])
    Rebuild(self)

    self:Show()
end

local function BuildWidget()
    return addon:NewWidget({}, {
        frame = Dialog:Build({
            name = "WowSyncGameDiffPreview",
            title = L["Preview changes"],
            width = UI.Preview.Width,
            height = UI.Preview.Height,
        }),
        methods = Methods,
    })
end

function GameDiffPreview:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.preview) == "table", "Show: 'opts.preview' must be a table")

    self._frame = self._frame or BuildWidget()
    self._frame:Open(opts)
end

function GameDiffPreview:Hide()
    if self._frame then
        self._frame:Hide()
    end
end
