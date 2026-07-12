local _, addon = ...

--[[
    ModuleList object.

    The shared, reusable list of selectable modules: an injected region filled with
    a vertical stack of module checkboxes. Both the apply preview and the
    save/share dialog use it, so module selection lives in one place. The Plugin
    umbrella expands into a per-plugin header followed by its submodule checkboxes
    (mirroring the diff preview), and the selection is returned as a nested
    moduleSet. Rows are pooled and reused across rebuilds (no frame churn).

    addon:GetObject("ModuleList"):Build(region, {
        onChanged = fn,                    -- a row's check/mode changed
        onPreviewModule = fn(module, mode, plugin, subModule),  -- badge opens its diff
    })
        -> module-list frame {
            SetSnapshot(snapshot, preview, mode),  -- apply rows: badge + Merge/Exact toggle
            SetModuleNames(moduleNames),           -- plain rows: checkbox only (save/share)
            GetSelected() -> moduleSet,            -- nested { [name]=true | { [plugin]={ [sub]=true } } }
            GetStrategy() -> moduleSet, overrides, -- adds per-module apply modes
            HasSelection() -> boolean,             -- any row checked (no allocation)
            SetAllChecked(checked),
            AreAllSelectableChecked() -> boolean,
            GetContentHeight() -> number,
        }
]]

local ModuleList = addon:NewObject("ModuleList")

local C = addon.C
local UI = addon.UI

local ModuleRow = addon:GetObject("ModuleRow")

local ModuleRegistry = WowSync:Import("ModuleRegistry")
local Module = WowSync:Import("Module")
local PluginManager = WowSync:Import("PluginManager")

-- The umbrella module whose row expands into per-plugin headers and submodule
-- checkboxes, so plugins are selectable the way they read in the diff preview.
local PLUGIN_MODULE = "Plugin"

-- Placement of the per-row Merge/Exact switch: inset from the list's right edge,
-- and a vertical nudge to centre it in the row.
local MODE_SWITCH_INSET = 2
local MODE_SWITCH_VOFFSET = 3

-- Left inset of a submodule row, so it reads as nested beneath its plugin header.
local SUBMODULE_INDENT = 16
-- A plugin header renders like GameDiffPreview's: the plugin name alone in a
-- large blue heading. Its height, left inset, and tint match that surface.
local HEADER_HEIGHT = 34
local HEADER_INSET = 6
local HEADER_COLOR = CreateColor(0.25, 0.65, 0.97)

-- Right-edge gutter kept free for the scrollbar, so rows and their Merge/Exact
-- switches never sit beneath it.
local SCROLLBAR_RESERVE = 20

local Methods = {}

-- The Merge/Exact support a module declares, as two booleans.
local function SupportedModes(name)
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode
    local module = Module:FromRegisteredModule(name)
    local modes = module and module:ApplyMode()
    return applyModes and applyModes.CanMerge(modes), applyModes and applyModes.CanExact(modes)
end

-- The mode a row starts in: the requested default when the module supports it,
-- otherwise its only supported mode.
local function ResolveInitialMode(canMerge, canExact, defaultMode)
    if canMerge and canExact then
        return defaultMode
    elseif canExact then
        return "exact"
    end
    return "merge"
end

-- Per-row change figure from a diff (with added/changed/removed lists) in the
-- row's current mode. Removals only count in Exact when the module supports it,
-- so the preview never overstates the change.
local function ComputeCounts(diff, rowMode, canExact)
    if not diff then return nil end
    local showRemovals = (rowMode == "exact") and canExact
    return {
        added = #(diff.added or {}),
        changed = #(diff.changed or {}),
        removed = showRemovals and #(diff.removed or {}) or 0,
    }
end

-- Set a togglable row to the chosen mode, refreshing its counts and switch and
-- notifying the list owner so dependent UI can update.
local function SelectRowMode(panel, checkbox, mode)
    local state = checkbox._mode
    if not state or not state.canToggle or state.mode == mode then return end

    state.mode = mode
    checkbox:RenderCounts(ComputeCounts(state.diff, state.mode, state.canExact))
    checkbox:RenderMode({
        mode = state.mode,
        canToggle = true,
        visible = true,
    })
    if panel._onChanged then panel._onChanged() end
end

-- A pooled checkbox for a module row. A freshly built one has its action
-- closures wired once here -- the change hook, the Merge/Exact toggle, and the
-- optional name link -- each reading the row's live state (panel, the module on
-- checkbox._mode) at click time, so one binding serves every module the row is
-- later reused for.
local function Acquire(panel)
    for _, checkbox in ipairs(panel._pool) do
        if not checkbox.inUse then
            checkbox.inUse = true
            return checkbox
        end
    end

    local checkbox = ModuleRow:Build(panel)
    checkbox:HookScript("OnClick", function()
        if panel._onChanged then panel._onChanged() end
    end)
    checkbox.modeSwitch:SetOnSelect(function(mode)
        SelectRowMode(panel, checkbox, mode)
    end)
    if panel._onPreviewModule then
        checkbox:SetPreview(function()
            local target = checkbox._target
            if target then
                panel._onPreviewModule(target.module, checkbox._mode and checkbox._mode.mode, target.plugin, target.subModule)
            end
        end)
    else
        checkbox:SetPreview(nil)
    end
    checkbox.inUse = true
    tinsert(panel._pool, checkbox)
    return checkbox
end

local function ReleaseAll(panel)
    for _, checkbox in pairs(panel._checkboxes) do
        checkbox:Hide()
        checkbox.modeSwitch:Hide()
        checkbox.inUse = false
    end
    wipe(panel._checkboxes)

    for i = 1, panel._headerCount do
        panel._headers[i]:Hide()
    end
    panel._headerCount = 0
end

-- A pooled plugin-header label (non-interactive), reused across rebuilds. The
-- name is centred within the header's full height so it sits with even spacing
-- above and below, matching GameDiffPreview's plugin headers.
local function AcquireHeader(panel)
    panel._headerCount = panel._headerCount + 1
    local header = panel._headers[panel._headerCount]
    if not header then
        header = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        header:SetJustifyH("LEFT")
        header:SetJustifyV("MIDDLE")
        header:SetHeight(HEADER_HEIGHT)
        header:SetTextColor(HEADER_COLOR:GetRGB())
        panel._headers[panel._headerCount] = header
    end
    header:Show()
    return header
end

-- Place a plugin header at yOffset and return the advanced offset.
local function AddHeader(panel, label, yOffset)
    local header = AcquireHeader(panel)
    header:SetText(label)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", HEADER_INSET, -yOffset)
    return yOffset + HEADER_HEIGHT
end

-- Place one selectable checkbox row for `target` (keyed by `key`) at the given
-- indent, and return the advanced offset. rowSpec = { label, canApply, reason,
-- counts, modeInfo }; modeInfo (apply rows only) = { mode, canToggle, canExact, diff }.
local function AddRow(panel, key, target, rowSpec, indent, yOffset)
    local checkbox = Acquire(panel)
    checkbox._target = target
    checkbox._mode = rowSpec.modeInfo

    checkbox:ClearAllPoints()
    checkbox:SetPoint("TOPLEFT", indent, -yOffset)
    checkbox:Update(rowSpec.label, rowSpec.canApply, rowSpec.reason, rowSpec.counts, rowSpec.modeInfo and {
        mode = rowSpec.modeInfo.mode,
        canToggle = rowSpec.modeInfo.canToggle,
        visible = rowSpec.canApply,
    } or { visible = false })

    if rowSpec.modeInfo then
        checkbox.modeSwitch:ClearAllPoints()
        checkbox.modeSwitch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MODE_SWITCH_INSET, -yOffset - MODE_SWITCH_VOFFSET)
    end

    checkbox:Show()
    panel._checkboxes[key] = checkbox

    return yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
end

-- Per-submodule diff lookup from the Plugin module's diff:
-- lookup[plugin][subModule] = the submodule diff entry (only changed ones exist).
local function SubModuleDiffLookup(pluginDiff)
    local lookup = {}
    if pluginDiff and pluginDiff.plugins then
        for _, plugin in ipairs(pluginDiff.plugins) do
            local byName = {}
            for _, subModule in ipairs(plugin.subModules) do
                byName[subModule.name] = subModule
            end
            lookup[plugin.name] = byName
        end
    end
    return lookup
end

-- Expand the Plugin umbrella into a per-plugin header (the plugin's name) plus a
-- checkbox per submodule, for every installed plugin. pluginDiff (apply rows
-- only) supplies per-submodule counts; nil for plain lists. Returns the advanced
-- offset.
local function AddPluginRows(panel, pluginDiff, defaultMode, yOffset)
    local diffLookup = SubModuleDiffLookup(pluginDiff)
    for _, entry in ipairs(PluginManager:GetSubModuleLayout()) do
        yOffset = AddHeader(panel, entry.plugin, yOffset)
        for _, subName in ipairs(entry.subModules) do
            local subDiff = diffLookup[entry.plugin] and diffLookup[entry.plugin][subName]
            yOffset = AddRow(panel, PLUGIN_MODULE .. "\0" .. entry.plugin .. "\0" .. subName, {
                module = PLUGIN_MODULE,
                plugin = entry.plugin,
                subModule = subName,
            }, {
                label = subName,
                canApply = true,
                counts = subDiff and ComputeCounts(subDiff, defaultMode, subDiff.canExact) or nil,
            }, SUBMODULE_INDENT, yOffset)
        end
    end
    return yOffset
end

-- Size the scroll child to the laid-out rows (height from the rows, width from
-- the viewport minus the scrollbar gutter) and reset it to the top, so a long
-- list scrolls within the fixed viewport instead of growing the dialog. The
-- width also tracks the viewport via OnSizeChanged for the first-layout pass,
-- when GetWidth() is not yet reliable.
local function ApplyContentSize(panel)
    local scrollFrame = panel._scrollFrame
    local width = scrollFrame:GetWidth()
    if width and width > 0 then
        panel:SetWidth(math.max(width - SCROLLBAR_RESERVE, 1))
    end
    panel:SetHeight(math.max(panel._contentHeight, 1))
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()
end

function Methods:Constructor(config)
    self._checkboxes = {}   -- selection key -> active checkbox
    self._pool = {}
    self._headers = {}      -- pooled plugin-header labels
    self._headerCount = 0
    self._contentHeight = 0
    self._onChanged = config.onChanged
    self._onPreviewModule = config.onPreviewModule
end

function ModuleList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onChanged == nil or type(opts.onChanged) == "function", "Build: 'opts.onChanged' must be a function")
    C:Ensures(opts.onPreviewModule == nil or type(opts.onPreviewModule) == "function", "Build: 'opts.onPreviewModule' must be a function")

    -- A scroll viewport over the pooled rows, driven by the same MinimalScrollBar
    -- the diff preview uses so both surfaces scroll identically. The bar sits
    -- inside the region's right edge; the list keeps rendering into one content
    -- frame (its widget), which becomes the scroll child, so a long module set
    -- scrolls rather than growing the dialog past the screen.
    local scrollFrame = CreateFrame("ScrollFrame", nil, region)
    scrollFrame:SetAllPoints(region)
    scrollFrame:EnableMouseWheel(true)

    local scrollBar = CreateFrame("EventFrame", nil, region, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 2)

    local content = addon:NewWidget({
        parent = scrollFrame,
        anchor = function(self)
            self:SetPoint("TOPLEFT")
        end,
        onChanged = opts.onChanged,
        onPreviewModule = opts.onPreviewModule,
    }, {
        frameType = "Frame",
        methods = Methods,
    })

    content:SetSize(1, 1)
    content._scrollFrame = scrollFrame
    scrollFrame:SetScrollChild(content)
    scrollBar:SetFrameLevel(content:GetFrameLevel() + 10)

    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
    scrollBar:SetHideIfUnscrollable(true)

    -- Keep the scroll child as wide as the viewport (minus the scrollbar gutter)
    -- whenever the region resolves or resizes, so rows fill the width even on the
    -- first layout pass, before GetWidth() is reliable.
    scrollFrame:SetScript("OnSizeChanged", function(frame, width)
        content:SetWidth(math.max(width - SCROLLBAR_RESERVE, 1))
        frame:UpdateScrollChildRect()
    end)

    return content
end

function Methods:SetSnapshot(snapshot, preview, mode)
    local panel = self

    ReleaseAll(panel)

    local sourceMetadata = { ClassID = snapshot and snapshot:GetCharacterInfo().ClassID }
    local moduleDiffs = preview and preview.perModule
    local defaultMode = (mode == "exact") and "exact" or "merge"

    -- The snapshot's modules, in a stable order, intersected with what is
    -- currently registered (a snapshot may carry a module no longer installed).
    local moduleNames = snapshot and snapshot:GetModuleNames() or {}

    -- Registered built-in modules from the snapshot, split so the ones offering a
    -- Merge/Exact choice list before the single-mode ones (a clearer read), each
    -- group keeping the snapshot's stable order. The Plugin umbrella is separate.
    local dualMode, singleMode = {}, {}
    local hasPlugin = false
    for _, name in ipairs(moduleNames) do
        if name == PLUGIN_MODULE then
            hasPlugin = true
        elseif ModuleRegistry:Get(name) then
            local canMerge, canExact = SupportedModes(name)
            if canMerge and canExact then
                dualMode[#dualMode + 1] = name
            else
                singleMode[#singleMode + 1] = name
            end
        end
    end

    local yOffset = 0
    for _, group in ipairs({ dualMode, singleMode }) do
        for _, name in ipairs(group) do
            local module = ModuleRegistry:Get(name)
            local canApply, reason = module:CanApply(sourceMetadata)
            local canMerge, canExact = SupportedModes(name)
            local rowMode = ResolveInitialMode(canMerge, canExact, defaultMode)
            local moduleDiff = moduleDiffs and moduleDiffs[name]

            yOffset = AddRow(panel, name, { module = name }, {
                label = name,
                canApply = canApply,
                reason = reason,
                counts = ComputeCounts(moduleDiff, rowMode, canExact),
                modeInfo = {
                    mode = rowMode,
                    canToggle = canMerge and canExact,
                    canExact = canExact,
                    diff = moduleDiff,
                },
            }, 0, yOffset)
        end
    end

    -- Plugins always render below the built-in modules, as their own group.
    if hasPlugin then
        yOffset = AddPluginRows(panel, moduleDiffs and moduleDiffs[PLUGIN_MODULE], defaultMode, yOffset)
    end

    panel._contentHeight = yOffset
    ApplyContentSize(panel)
end

-- Build plain checkbox rows (no change badge, no Merge/Exact toggle) for the
-- given module names, or every registered module when omitted — used by the
-- save/share dialog. The Plugin umbrella still expands into its submodule rows.
function Methods:SetModuleNames(moduleNames)
    local panel = self

    ReleaseAll(panel)

    local names = {}
    if moduleNames then
        for _, name in ipairs(moduleNames) do
            names[#names + 1] = name
        end
    else
        for name in ModuleRegistry:Iterate() do
            names[#names + 1] = name
        end
    end
    table.sort(names)

    local yOffset = 0
    local hasPlugin = false
    for _, name in ipairs(names) do
        if name == PLUGIN_MODULE then
            hasPlugin = true
        else
            yOffset = AddRow(panel, name, { module = name }, {
                label = name,
                canApply = true,
            }, 0, yOffset)
        end
    end

    -- Plugins always render below the built-in modules, as their own group.
    if hasPlugin then
        yOffset = AddPluginRows(panel, nil, "merge", yOffset)
    end

    panel._contentHeight = yOffset
    ApplyContentSize(panel)
end

-- The total stacked height of the rows from the last SetSnapshot/SetModuleNames,
-- so an owner can size itself to seat every module row.
function Methods:GetContentHeight()
    return self._contentHeight or 0
end

-- Build the current selection as a (possibly nested) moduleSet plus per-module
-- apply-mode overrides. A submodule checkbox contributes a nested entry
-- moduleSet[Plugin][plugin][subModule] = true; a top-level checkbox contributes
-- moduleSet[name] = true and its mode override. Only checked rows count.
local function BuildSelection(panel)
    local moduleSet, overrides = {}, {}
    for _, checkbox in pairs(panel._checkboxes) do
        if checkbox:GetChecked() then
            local target = checkbox._target
            if target.subModule then
                local selection = moduleSet[target.module]
                if type(selection) ~= "table" then
                    selection = {}
                    moduleSet[target.module] = selection
                end
                selection[target.plugin] = selection[target.plugin] or {}
                selection[target.plugin][target.subModule] = true
            else
                moduleSet[target.module] = true
                if checkbox._mode then
                    overrides[target.module] = checkbox._mode.mode
                end
            end
        end
    end
    return moduleSet, overrides
end

-- The chosen selection as a (nested) moduleSet.
function Methods:GetSelected()
    return (BuildSelection(self))
end

-- The chosen selection plus per-module apply modes (strategy.overrides).
function Methods:GetStrategy()
    return BuildSelection(self)
end

-- True when at least one selectable row is checked, without building the
-- selection table -- cheap enough to gate a button on every row toggle.
function Methods:HasSelection()
    for _, checkbox in pairs(self._checkboxes) do
        if checkbox:GetChecked() then
            return true
        end
    end
    return false
end

function Methods:SetAllChecked(checked)
    for _, checkbox in pairs(self._checkboxes) do
        if checkbox:IsEnabled() then
            checkbox:SetChecked(checked)
        end
    end
end

-- True only when there is at least one selectable row and every selectable
-- row is currently checked.
function Methods:AreAllSelectableChecked()
    local hasSelectable = false
    for _, checkbox in pairs(self._checkboxes) do
        if checkbox:IsEnabled() then
            hasSelectable = true
            if not checkbox:GetChecked() then
                return false
            end
        end
    end
    return hasSelectable
end
