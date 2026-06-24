local _, addon = ...

--[[
    ModuleList object.

    Fills an injected region with a vertical list of module checkboxes for a
    profile. Rows are pooled and reused across profile selections (no frame
    churn). Composes ModuleRow for each row.

    addon:GetObject("ModuleList"):Build(region, { profileManager = pm })
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

local pm
local sv
local root
local checkboxes = {}   -- name -> active checkbox
local pool = {}
local onChanged

local function Acquire()
    for _, cb in ipairs(pool) do
        if not cb.inUse then
            cb.inUse = true
            return cb
        end
    end

    local cb = ModuleRow:Build(root)
    cb:HookScript("OnClick", function()
        if onChanged then onChanged() end
    end)
    cb.inUse = true
    tinsert(pool, cb)
    return cb
end

local function ReleaseAll()
    for _, cb in pairs(checkboxes) do
        cb:Hide()
        cb.inUse = false
    end
    wipe(checkboxes)
end

function ModuleList:Build(region, opts)
    C:IsTable(region, 2)

    opts = opts or {}

    C:Ensures(opts.onChanged == nil or type(opts.onChanged) == "function", "Build: 'opts.onChanged' must be a function")

    pm = opts.profileManager or WowSync:GetProfileManager()
    sv = WowSync:GetSnapshotView()
    onChanged = opts.onChanged

    root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    return self
end

function ModuleList:SetSnapshot(snapshot, preview, mode)
    ReleaseAll()

    local meta = { ClassID = snapshot and sv:GetCharacterInfo(snapshot).ClassID }
    local perModule = preview and preview.perModule
    local exact = (mode == "exact")
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode

    -- The snapshot's modules, in a stable order, intersected with what is
    -- currently registered (a snapshot may carry a module no longer installed).
    local names = snapshot and sv:GetModuleNames(snapshot) or {}

    local yOffset = 0
    for _, name in ipairs(names) do
        local module = pm:GetModule(name)
        if module then
            local canApply, reason = module:CanApply(meta)

            local counts
            local moduleDiff = perModule and perModule[name]
            if moduleDiff then
                -- Merge never removes, and Exact removes only for modules whose apply
                -- mode supports it; surface a removal figure only when the apply will
                -- actually act on it, so the preview never overstates the change.
                local showRemovals = exact and applyModes
                    and applyModes.CanExact(pm:GetModuleSnapshotApplyMode(name))
                counts = {
                    added = #(moduleDiff.added or {}),
                    changed = #(moduleDiff.changed or {}),
                    removed = showRemovals and #(moduleDiff.removed or {}) or 0,
                }
            end

            local cb = Acquire()
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", 0, -yOffset)
            ModuleRow:Update(cb, name, canApply, reason, counts)
            cb:Show()

            checkboxes[name] = cb
            yOffset = yOffset + UI.ModuleRow.Height + UI.ModuleRow.Padding
        end
    end
end

function ModuleList:GetSelected()
    local selected = {}
    for name, cb in pairs(checkboxes) do
        if cb:GetChecked() then
            selected[name] = true
        end
    end
    return selected
end

function ModuleList:SetAllChecked(checked)
    for _, cb in pairs(checkboxes) do
        if cb:IsEnabled() then
            cb:SetChecked(checked)
        end
    end
end

-- True only when there is at least one selectable row and every selectable
-- row is currently checked.
function ModuleList:AreAllSelectableChecked()
    local hasSelectable = false
    for _, cb in pairs(checkboxes) do
        if cb:IsEnabled() then
            hasSelectable = true
            if not cb:GetChecked() then
                return false
            end
        end
    end
    return hasSelectable
end
