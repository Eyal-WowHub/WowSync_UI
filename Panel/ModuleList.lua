local _, addon = ...

--[[
    ModuleList object.

    Fills an injected region with a vertical list of module checkboxes for a
    profile. Rows are pooled and reused across profile selections (no frame
    churn). Composes ModuleRow for each row.

    addon:GetObject("ModuleList"):Build(region, {
        onChanged = fn,                 -- called when a row's check/mode changes
        onPreviewModule = fn(name, mode),  -- clicking a change badge opens its preview
    })
        -> module-list frame {
            SetSnapshot(snapshot, preview, mode),   -- (re)build rows; preview adds counts
            GetSelected() -> { [name] = true },
            GetStrategy() -> moduleSet, overrides,  -- chosen modules + per-module mode
            SetAllChecked(checked),
        }
]]

local ModuleList = addon:NewObject("ModuleList")

local C = LibStub("Contracts-1.0")

local UI = addon.UI

local ModuleRow = addon:GetObject("ModuleRow")

local ModuleRegistry = WowSync:Import("ModuleRegistry")
local SnapshotManager = WowSync:Import("SnapshotManager")

-- Placement of the per-row Merge/Exact toggle: inset from the list's right edge,
-- and a vertical nudge to centre the button in the row.
local MODE_BUTTON_INSET = 2
local MODE_BUTTON_VOFFSET = 3

local Methods = {}

-- The Merge/Exact support a module declares, as two booleans.
local function SupportedModes(name)
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode
    local modes = SnapshotManager:GetModuleApplyMode(name)
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

-- Per-module change figure for a row in its current mode. Removals only count
-- when the row applies in Exact and the module supports it, so the preview
-- never overstates the change.
local function ComputeCounts(moduleDiff, rowMode, canExact)
    if not moduleDiff then return nil end
    local showRemovals = (rowMode == "exact") and canExact
    return {
        added = #(moduleDiff.added or {}),
        changed = #(moduleDiff.changed or {}),
        removed = showRemovals and #(moduleDiff.removed or {}) or 0,
    }
end

-- Flip a togglable row between Merge and Exact, refreshing its counts and toggle
-- label and notifying the list owner so dependent UI can update.
local function ToggleRowMode(panel, checkbox)
    local state = checkbox._mode
    if not state or not state.canToggle then return end

    state.mode = (state.mode == "exact") and "merge" or "exact"
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
    checkbox.modeButton:SetScript("OnClick", function()
        ToggleRowMode(panel, checkbox)
    end)
    if panel._onPreviewModule then
        checkbox:SetPreview(function()
            if checkbox._mode then
                panel._onPreviewModule(checkbox._mode.name, checkbox._mode.mode)
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
        checkbox.modeButton:Hide()
        checkbox.inUse = false
    end
    wipe(panel._checkboxes)
end

function Methods:Constructor(config)
    self._checkboxes = {}   -- moduleName -> active checkbox
    self._pool = {}
    self._contentHeight = 0
    self._onChanged = config.onChanged
    self._onPreviewModule = config.onPreviewModule
end

function ModuleList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onChanged == nil or type(opts.onChanged) == "function", "Build: 'opts.onChanged' must be a function")
    C:Ensures(opts.onPreviewModule == nil or type(opts.onPreviewModule) == "function", "Build: 'opts.onPreviewModule' must be a function")

    return addon:NewWidget({
        parent = region,
        anchor = function(self)
            self:SetAllPoints(region)
        end,
        onChanged = opts.onChanged,
        onPreviewModule = opts.onPreviewModule,
    }, {
        frameType = "Frame",
        methods = Methods,
    })
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

    local yOffset = 0
    for _, name in ipairs(moduleNames) do
        local module = ModuleRegistry:Get(name)
        if module then
            local canApply, reason = module:CanApply(sourceMetadata)
            local canMerge, canExact = SupportedModes(name)
            local rowMode = ResolveInitialMode(canMerge, canExact, defaultMode)
            local canToggle = canMerge and canExact

            local moduleDiff = moduleDiffs and moduleDiffs[name]
            local counts = ComputeCounts(moduleDiff, rowMode, canExact)

            local checkbox = Acquire(panel)
            checkbox._mode = {
                name = name,
                mode = rowMode,
                canToggle = canToggle,
                canExact = canExact,
                diff = moduleDiff,
            }
            checkbox:ClearAllPoints()
            checkbox:SetPoint("TOPLEFT", 0, -yOffset)
            checkbox:Update(name, canApply, reason, counts, {
                mode = rowMode,
                canToggle = canToggle,
                visible = canApply,
            })

            checkbox.modeButton:ClearAllPoints()
            checkbox.modeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT",
                -MODE_BUTTON_INSET, -yOffset - MODE_BUTTON_VOFFSET)

            checkbox:Show()

            panel._checkboxes[name] = checkbox
            yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
        end
    end

    panel._contentHeight = yOffset
end

-- The total stacked height of the rows from the last SetSnapshot, so an owner
-- can size itself to seat every module row.
function Methods:GetContentHeight()
    return self._contentHeight or 0
end

function Methods:GetSelected()
    local selected = {}
    for name, checkbox in pairs(self._checkboxes) do
        if checkbox:GetChecked() then
            selected[name] = true
        end
    end
    return selected
end

-- The chosen modules and their per-module apply mode, ready for use as
-- strategy.overrides. Only checked rows are included.
function Methods:GetStrategy()
    local moduleSet, overrides = {}, {}
    for name, checkbox in pairs(self._checkboxes) do
        if checkbox:GetChecked() then
            moduleSet[name] = true
            local state = checkbox._mode
            if state then
                overrides[name] = state.mode
            end
        end
    end
    return moduleSet, overrides
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
