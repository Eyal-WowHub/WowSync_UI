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

    Each diff entry may be a plain label string or a table { label, icon }, so the
    window renders today's text labels and gains icons once the diff is enriched.

    addon:GetObject("GameDiffPreview"):Show({
        title        = string,                 -- window title (optional)
        preview      = { perModule = {...} },  -- from SnapshotView:Preview
        mode         = "exact" | "merge",      -- gates the Removed section
        moduleFilter = name | nil,             -- nil shows every module
    })
]]

local GameDiffPreview = addon:NewObject("GameDiffPreview")
local Dialog = addon:GetObject("Dialog")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local SnapshotManager = WowSync:GetSnapshotManager()

-- Row heights per element kind; the list mixes module headers, section
-- subheaders, and entry rows in one virtualised stream.
local MODULE_HEADER_HEIGHT = 24
local SECTION_HEADER_HEIGHT = 18
local ITEM_HEIGHT = 20
local EMPTY_HEIGHT = 28

-- Left inset of each element kind, and the entry icon size. Entries indent past
-- the icon column so labels line up whether or not an entry carries an icon.
local MODULE_INSET = 6
local SECTION_INSET = 16
local ITEM_INSET = 20
local ICON_SIZE = 16

-- Tints for the three change kinds (added green, updated gold, removed red),
-- matching the +A ~C -R colours used elsewhere.
local ADDED_COLOR = CreateColor(0.37, 0.81, 0.37)
local CHANGED_COLOR = CreateColor(0.85, 0.78, 0.29)
local REMOVED_COLOR = CreateColor(0.85, 0.42, 0.42)
local MODULE_HEADER_COLOR = CreateColor(0.95, 0.95, 0.95)

-- The change kinds in display order; "removed" is shown only in Exact mode.
local SECTIONS = {
    { key = "added", color = ADDED_COLOR, label = L["Added (X)"] },
    { key = "changed", color = CHANGED_COLOR, label = L["Updated (X)"] },
    { key = "removed", color = REMOVED_COLOR, label = L["Removed (X)"] },
}

local dialog, frame, scrollBox
local currentPreview, currentMode, moduleFilter

-- The label and optional icon of a diff entry, which may be a bare string or a
-- { label, icon } table.
local function NormalizeEntry(entry)
    if type(entry) == "table" then
        return entry.label or "", entry.icon
    end
    return entry, nil
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
    local modes = SnapshotManager:GetModuleApplyMode(name)
    return applyModes and applyModes.CanExact(modes) or false
end

-- Flatten the preview into the list's element stream: a header per changed
-- module, then a subheader and one row per entry for each non-empty section.
local function Populate(dataProvider, preview, filterName, mode)
    local exactMode = (mode == "exact")
    local anyShown = false

    for _, name in ipairs(ModuleNamesIn(preview)) do
        if not filterName or filterName == name then
            local moduleDiff = preview.perModule[name]
            -- Removals are real only when this module applies in Exact, so a
            -- merge-only module never shows a Removed section.
            local showRemoved = exactMode and ModuleSupportsExact(name)
            if HasVisibleChanges(moduleDiff, showRemoved) then
                anyShown = true
                dataProvider:Insert({ kind = "module", name = name })

                for _, section in ipairs(SECTIONS) do
                    if section.key ~= "removed" or showRemoved then
                        local entries = moduleDiff[section.key] or {}
                        if #entries > 0 then
                            dataProvider:Insert({ kind = "section", section = section, count = #entries })
                            for _, entry in ipairs(entries) do
                                local label, icon = NormalizeEntry(entry)
                                dataProvider:Insert({ kind = "item", label = label, icon = icon })
                            end
                        end
                    end
                end
            end
        end
    end

    if not anyShown then
        dataProvider:Insert({ kind = "empty" })
    end
end

-- Create the reusable widgets a pooled row needs for any element kind.
local function BuildRow(row)
    local separator = row:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(unpack(UI.Backdrop.Separator))
    separator:SetHeight(1)
    separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", MODULE_INSET, 0)
    separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
    separator:Hide()
    row.separator = separator

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    row.icon = icon

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.text = text
end

-- Render a pooled row for its element kind.
local function UpdateRow(row, data)
    row.icon:Hide()
    row.separator:Hide()
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    if data.kind == "module" then
        row.text:SetFontObject("GameFontNormal")
        row.text:SetText(data.name)
        row.text:SetTextColor(MODULE_HEADER_COLOR:GetRGB())
        row.text:SetPoint("LEFT", row, "LEFT", MODULE_INSET, 0)
        row.separator:Show()
    elseif data.kind == "section" then
        row.text:SetFontObject("GameFontNormalSmall")
        row.text:SetText(data.section.label:format(data.count))
        row.text:SetTextColor(data.section.color:GetRGB())
        row.text:SetPoint("LEFT", row, "LEFT", SECTION_INSET, 0)
    elseif data.kind == "item" then
        row.text:SetFontObject("GameFontHighlightSmall")
        row.text:SetText(data.label)
        row.text:SetTextColor(1, 1, 1)
        if data.icon then
            row.icon:SetTexture(data.icon)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", ITEM_INSET, 0)
            row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        else
            row.text:SetPoint("LEFT", row, "LEFT", ITEM_INSET + ICON_SIZE + 4, 0)
        end
    else
        row.text:SetFontObject("GameFontDisableSmall")
        row.text:SetText(L["No changes to preview."])
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row.text:SetPoint("LEFT", row, "LEFT", SECTION_INSET, 0)
    end
end

-- Rebuild the element stream from the current preview, filter, and mode.
local function Rebuild()
    local dataProvider = CreateDataProvider()
    Populate(dataProvider, currentPreview, moduleFilter, currentMode)
    scrollBox:SetDataProvider(dataProvider)
end

local function Build()
    if frame then return end

    dialog = Dialog:Build({
        name = "WowSyncGameDiffPreview",
        title = L["Preview changes"],
        width = UI.Preview.Width,
        height = UI.Preview.Height,
    })
    frame = dialog:GetFrame()

    scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 14, -40)
    scrollBox:SetPoint("BOTTOMRIGHT", -28, 14)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, data)
        if data.kind == "module" then
            return MODULE_HEADER_HEIGHT
        elseif data.kind == "section" then
            return SECTION_HEADER_HEIGHT
        elseif data.kind == "empty" then
            return EMPTY_HEIGHT
        end
        return ITEM_HEIGHT
    end)
    view:SetPadding(0, 0, 0, 0, UI.List.ItemPadding)
    view:SetElementInitializer("Frame", function(row, data)
        if not row.initialized then
            BuildRow(row)
            row.initialized = true
        end
        UpdateRow(row, data)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    scrollBar:SetHideIfUnscrollable(true)
end

function GameDiffPreview:Show(opts)
    C:IsTable(opts, 2)
    C:Ensures(type(opts.preview) == "table", "Show: 'opts.preview' must be a table")

    Build()

    currentPreview = opts.preview
    currentMode = opts.mode or "exact"
    moduleFilter = opts.moduleFilter

    dialog:SetTitle(opts.title or L["Preview changes"])
    Rebuild()

    dialog:Show()
end

function GameDiffPreview:Hide()
    if dialog then
        dialog:Hide()
    end
end
