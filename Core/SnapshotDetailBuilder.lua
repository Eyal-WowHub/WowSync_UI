local _, addon = ...
local SnapshotDetailBuilder = {}
addon.SnapshotDetailBuilder = SnapshotDetailBuilder

--[[
    SnapshotDetailBuilder — folds a snapshot's note and per-module diff preview
    into the small, render-ready table the timelines show beneath an expanded
    row. The profile timeline (SnapshotList) and the imports timeline
    (ImportSnapshotList) share it so their change summaries read the same; each
    list only supplies the note and preview from its own source.

        SnapshotDetailBuilder.Build(note, preview)
            -> { hasNote, note, modules = { { name, added, changed, removed }, … } }
]]

local SnapshotManager = WowSync:GetSnapshotManager()

-- Whether a module deletes entries on apply (Exact-capable). Merge-only modules
-- never remove, so their removals are not counted in the change summary.
local function ModuleSupportsExact(name)
    local applyModes = WowSync.Models and WowSync.Models.SnapshotApplyMode
    local modes = SnapshotManager:GetModuleApplyMode(name)
    return applyModes and applyModes.CanExact(modes) or false
end

-- Build the render-ready detail payload from a note and per-module preview.
function SnapshotDetailBuilder.Build(note, preview)
    local detail = { hasNote = false, note = nil, modules = {} }

    if note and note ~= "" then
        detail.hasNote = true
        detail.note = note
    end

    if not (preview and preview.perModule) then
        return detail
    end

    local moduleNames = {}
    for name in pairs(preview.perModule) do
        tinsert(moduleNames, name)
    end
    table.sort(moduleNames)

    for _, name in ipairs(moduleNames) do
        local moduleDiff = preview.perModule[name]
        local added = #(moduleDiff.added or {})
        local changed = #(moduleDiff.changed or {})
        local removed = ModuleSupportsExact(name) and #(moduleDiff.removed or {}) or 0
        if added + changed + removed > 0 then
            tinsert(detail.modules, {
                name = name,
                added = added,
                changed = changed,
                removed = removed,
            })
        end
    end

    return detail
end
