local _, addon = ...

--[[
    ModuleList object.

    Fills an injected region with a vertical list of module checkboxes for a
    profile. Rows are pooled and reused across profile selections (no frame
    churn). Composes ModuleRow for each row.

    addon:GetObject("ModuleList"):Build(region, { onChanged = fn })
        -> self {
            SetSnapshot(snapshot, preview, mode),   -- (re)build rows; preview adds counts
            GetSelected() -> { [name] = true },
            GetStrategy() -> moduleSet, overrides,  -- chosen modules + per-module mode
            SetAllChecked(checked),
        }
]]

local ModuleList = addon:NewObject("ModuleList")
local ModuleRow = addon:GetObject("ModuleRow")

local C = LibStub("Contracts-1.0")
local UI = addon.UI

local ModuleRegistry = WowSync:GetModuleRegistry()
local SnapshotManager = WowSync:GetSnapshotManager()
local SnapshotView = WowSync:GetSnapshotView()

-- Placement of the per-row Merge/Exact toggle: inset from the list's right edge,
-- and a vertical nudge to centre the button in the row.
local MODE_BUTTON_INSET = 2
local MODE_BUTTON_VOFFSET = 3

local root
local checkboxes = {}   -- moduleName -> active checkbox
local pool = {}
local onChanged

local function Acquire()
    for _, checkbox in ipairs(pool) do
        if not checkbox.inUse then
            checkbox.inUse = true
            return checkbox
        end
    end

    local checkbox = ModuleRow:Build(root)
    checkbox:HookScript("OnClick", function()
        if onChanged then onChanged() end
    end)
    checkbox.inUse = true
    tinsert(pool, checkbox)
    return checkbox
end

local function ReleaseAll()
    for _, checkbox in pairs(checkboxes) do
        checkbox:Hide()
        checkbox.modeButton:Hide()
        checkbox.inUse = false
    end
    wipe(checkboxes)
end

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
local function ToggleRowMode(checkbox)
    local state = checkbox._mode
    if not state or not state.canToggle then return end

    state.mode = (state.mode == "exact") and "merge" or "exact"
    ModuleRow:RenderCounts(checkbox, ComputeCounts(state.diff, state.mode, state.canExact))
    ModuleRow:RenderMode(checkbox, {
        mode = state.mode,
        canToggle = true,
        visible = true,
    })
    if onChanged then onChanged() end
end

function ModuleList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onChanged == nil or type(opts.onChanged) == "function", "Build: 'opts.onChanged' must be a function")

    onChanged = opts.onChanged

    root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    return self
end

function ModuleList:SetSnapshot(snapshot, preview, mode)
    ReleaseAll()

    local sourceMetadata = { ClassID = snapshot and SnapshotView:GetCharacterInfo(snapshot).ClassID }
    local moduleDiffs = preview and preview.perModule
    local defaultMode = (mode == "exact") and "exact" or "merge"

    -- The snapshot's modules, in a stable order, intersected with what is
    -- currently registered (a snapshot may carry a module no longer installed).
    local moduleNames = snapshot and SnapshotView:GetModuleNames(snapshot) or {}

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

            local checkbox = Acquire()
            checkbox._mode = {
                name = name,
                mode = rowMode,
                canToggle = canToggle,
                canExact = canExact,
                diff = moduleDiff,
            }
            checkbox:ClearAllPoints()
            checkbox:SetPoint("TOPLEFT", 0, -yOffset)
            ModuleRow:Update(checkbox, name, canApply, reason, counts, {
                mode = rowMode,
                canToggle = canToggle,
                visible = canApply,
            })

            checkbox.modeButton:ClearAllPoints()
            checkbox.modeButton:SetPoint("TOPRIGHT", root, "TOPRIGHT",
                -MODE_BUTTON_INSET, -yOffset - MODE_BUTTON_VOFFSET)
            checkbox.modeButton:SetScript("OnClick", function()
                ToggleRowMode(checkbox)
            end)

            checkbox:Show()

            checkboxes[name] = checkbox
            yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
        end
    end
end

function ModuleList:GetSelected()
    local selected = {}
    for name, checkbox in pairs(checkboxes) do
        if checkbox:GetChecked() then
            selected[name] = true
        end
    end
    return selected
end

-- The chosen modules and their per-module apply mode, ready for use as
-- strategy.overrides. Only checked rows are included.
function ModuleList:GetStrategy()
    local moduleSet, overrides = {}, {}
    for name, checkbox in pairs(checkboxes) do
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

function ModuleList:SetAllChecked(checked)
    for _, checkbox in pairs(checkboxes) do
        if checkbox:IsEnabled() then
            checkbox:SetChecked(checked)
        end
    end
end

-- True only when there is at least one selectable row and every selectable
-- row is currently checked.
function ModuleList:AreAllSelectableChecked()
    local hasSelectable = false
    for _, checkbox in pairs(checkboxes) do
        if checkbox:IsEnabled() then
            hasSelectable = true
            if not checkbox:GetChecked() then
                return false
            end
        end
    end
    return hasSelectable
end
