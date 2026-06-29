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
        preview      = { perModule = {...} },  -- from SnapshotView:Preview
        mode         = "exact" | "merge",      -- gates the Removed section
        moduleFilter = name | nil,             -- nil shows every module
    })
]]

local GameDiffPreview = addon:NewObject("GameDiffPreview")
local Dialog = addon:GetObject("Dialog")
local ScrollList = addon:GetObject("ScrollList")

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
local ICON_TEXT_GAP = 4
local TEXT_RIGHT_INSET = 6

-- Scroll region insets, used both to place the list and to derive the wrap
-- width available to an entry's description line.
local SCROLLBOX_LEFT_INSET = 14
local SCROLLBOX_RIGHT_INSET = 28
local ROW_WIDTH = UI.Preview.Width - SCROLLBOX_LEFT_INSET - SCROLLBOX_RIGHT_INSET

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

-- The change kinds in display order; "removed" is shown only in Exact mode.
local SECTIONS = {
    { key = "added", color = ADDED_COLOR, label = L["Added (X)"] },
    { key = "changed", color = CHANGED_COLOR, label = L["Updated (X)"] },
    { key = "removed", color = REMOVED_COLOR, label = L["Removed (X)"] },
}

local dialog, frame, scrollBox, measureText
local currentPreview, currentMode, moduleFilter

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
    local modes = SnapshotManager:GetModuleApplyMode(name)
    return applyModes and applyModes.CanExact(modes) or false
end

-- The pixel height an entry row needs: a single centred line when it has no
-- description, or a top-aligned label plus its wrapped description otherwise.
local function ItemHeight(item)
    if not item.description or item.description == "" then
        return ITEM_HEIGHT
    end
    local iconOffset = item.icon and (ICON_SIZE + ICON_TEXT_GAP) or 0
    measureText:SetWidth(ROW_WIDTH - (ITEM_INSET + iconOffset) - TEXT_RIGHT_INSET)
    measureText:SetText(item.description)
    local descHeight = math.ceil(measureText:GetStringHeight())
    return ITEM_TOP_PAD + LABEL_HEIGHT + DESC_GAP + descHeight + ITEM_BOTTOM_PAD
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
                local moduleIcon = SnapshotManager:GetModuleDefaultIcon(name)
                dataProvider:Insert({ kind = "module", name = name })

                for _, section in ipairs(SECTIONS) do
                    if section.key ~= "removed" or showRemoved then
                        local entries = moduleDiff[section.key] or {}
                        if #entries > 0 then
                            dataProvider:Insert({ kind = "section", section = section, count = #entries })
                            for _, entry in ipairs(entries) do
                                local label, icon, description = NormalizeEntry(entry)
                                local item = {
                                    kind = "item",
                                    label = label,
                                    icon = icon or moduleIcon,
                                    description = description,
                                }
                                item.height = ItemHeight(item)
                                dataProvider:Insert(item)
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

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.6, 0.6, 0.6)
    desc:Hide()
    row.desc = desc
end

-- Render a pooled row for its element kind.
local function UpdateRow(row, data)
    row.icon:Hide()
    row.separator:Hide()
    row.desc:Hide()
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", row, "RIGHT", -TEXT_RIGHT_INSET, 0)

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

        local iconOffset = data.icon and (ICON_SIZE + ICON_TEXT_GAP) or 0
        local hasDesc = data.description and data.description ~= ""

        if hasDesc then
            -- Top-align the label (and icon) so the wrapped description can sit
            -- beneath them instead of fighting the row's vertical centring.
            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", ITEM_INSET + iconOffset, -ITEM_TOP_PAD)
            row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TEXT_RIGHT_INSET, -ITEM_TOP_PAD)

            if data.icon then
                row.icon:SetTexture(data.icon)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", ITEM_INSET, -ITEM_TOP_PAD)
                row.icon:Show()
            end

            row.desc:ClearAllPoints()
            row.desc:SetPoint("TOPLEFT", row, "TOPLEFT", ITEM_INSET + iconOffset, -(ITEM_TOP_PAD + LABEL_HEIGHT + DESC_GAP))
            row.desc:SetPoint("RIGHT", row, "RIGHT", -TEXT_RIGHT_INSET, 0)
            row.desc:SetText(data.description)
            row.desc:Show()
        elseif data.icon then
            row.icon:SetTexture(data.icon)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", ITEM_INSET, 0)
            row.icon:Show()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", ICON_TEXT_GAP, 0)
        else
            row.text:SetPoint("LEFT", row, "LEFT", ITEM_INSET, 0)
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
    frame = dialog

    -- Hidden font string used to measure wrapped description heights up front,
    -- so the virtualised list can size each entry row before it is shown.
    measureText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    measureText:Hide()
    measureText:SetWordWrap(true)
    measureText:SetJustifyH("LEFT")

    scrollBox = ScrollList:Build({
        parent = frame,
        anchor = function(sb)
            sb:SetPoint("TOPLEFT", SCROLLBOX_LEFT_INSET, -40)
            sb:SetPoint("BOTTOMRIGHT", -SCROLLBOX_RIGHT_INSET, 14)
        end,
        extent = function(_, data)
            if data.kind == "module" then
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
        update = UpdateRow,
    })
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
