local _, addon = ...

local UI = addon.UI

--[[
    ModuleList object.

    Fills an injected region with a vertical list of module checkboxes for a
    profile. Rows are pooled and reused across profile selections (no frame
    churn). Composes ModuleRow for each row.

    addon:GetObject("ModuleList"):Build(region, { profileManager = pm })
        -> self {
            SetProfile(profile),     -- (re)build rows from profile.Modules
            GetSelected() -> { [name] = true },
            SetAllChecked(checked),
        }
]]

local ModuleList = addon:NewObject("ModuleList")
local ModuleRow = addon:GetObject("ModuleRow")

local pm
local root
local checkboxes = {}   -- name -> active checkbox
local pool = {}

local function Acquire()
    for _, cb in ipairs(pool) do
        if not cb.inUse then
            cb.inUse = true
            return cb
        end
    end

    local cb = ModuleRow:Build(root)
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
    opts = opts or {}
    pm = opts.profileManager or WowSync:GetProfileManager()

    root = CreateFrame("Frame", nil, region)
    root:SetAllPoints(region)

    return self
end

function ModuleList:SetProfile(profile)
    ReleaseAll()

    -- Sort module names for consistent ordering
    local names = {}
    for name in pm:IterableModules() do
        if profile.Modules[name] then
            tinsert(names, name)
        end
    end
    table.sort(names)

    local yOffset = 0
    for _, name in ipairs(names) do
        local module = pm:GetModule(name)
        local canApply, reason = module:CanApply(profile.Meta)

        local cb = Acquire()
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 0, -yOffset)
        ModuleRow:Update(cb, name, canApply, reason)
        cb:Show()

        checkboxes[name] = cb
        yOffset = yOffset + UI.ModuleRowHeight + UI.ModuleRowPadding
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
