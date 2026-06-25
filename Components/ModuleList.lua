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
        checkbox.inUse = false
    end
    wipe(checkboxes)
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
    local exact = (mode == "exact")
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode

    -- The snapshot's modules, in a stable order, intersected with what is
    -- currently registered (a snapshot may carry a module no longer installed).
    local moduleNames = snapshot and SnapshotView:GetModuleNames(snapshot) or {}

    local yOffset = 0
    for _, name in ipairs(moduleNames) do
        local module = ModuleRegistry:Get(name)
        if module then
            local canApply, reason = module:CanApply(sourceMetadata)

            local counts
            local moduleDiff = moduleDiffs and moduleDiffs[name]
            if moduleDiff then
                -- Merge never removes, and Exact removes only for modules whose apply
                -- mode supports it; surface a removal figure only when the apply will
                -- actually act on it, so the preview never overstates the change.
                local showRemovals = exact and applyModes
                    and applyModes.CanExact(SnapshotManager:GetModuleApplyMode(name))
                counts = {
                    added = #(moduleDiff.added or {}),
                    changed = #(moduleDiff.changed or {}),
                    removed = showRemovals and #(moduleDiff.removed or {}) or 0,
                }
            end

            local checkbox = Acquire()
            checkbox:ClearAllPoints()
            checkbox:SetPoint("TOPLEFT", 0, -yOffset)
            ModuleRow:Update(checkbox, name, canApply, reason, counts)
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
