local _, addon = ...

--[[
    ImportSnapshotRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportSnapshotList.
    Renders one imported snapshot: its capture subject and selector on top, the
    export note below (always shown when present -- a one-line preview while
    collapsed, the full note while expanded), then a titled list. Collapsed, the
    list is the shared modules under a "Shared modules:" header; expanded,
    it is the per-module change summary against the current setup. The
    list-level selection and expansion state is reached through an injected
    context.

    ctx = {
        GetSelected() -> snapshot or nil,
        IsExpanded(snapshot) -> bool,
        GetDetail() -> detail or nil,   -- valid only for the expanded row
        Select(snapshot),
        OpenMenu(snapshot, anchor),     -- right-click actions for the row
    }

    addon:GetObject("ImportSnapshotRow"):Build(row, ctx)   -- adopts the pooled frame
        -> import-snapshot-row frame { Render(snapshot) }
]]

local ImportSnapshotRow = addon:NewObject("ImportSnapshotRow")
local SnapshotRow = addon:GetObject("SnapshotRow")
local SelectableRow = addon:GetObject("SelectableRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Left inset of a snapshot row's content.
local ROW_INSET = 10

-- Exposed so ImportSnapshotList can derive the content wrap width from the same
-- inset the row anchors its content at, keeping measured height and layout in
-- step.
ImportSnapshotRow.ContentInset = ROW_INSET

-- Characters of the content hash shown in the selector label.
local HASH_PREFIX = 7

local Verbs = Mixin({}, SelectableRow.Verbs)

-- The user-facing selector for an imported snapshot: a short hash and index.
local function SelectorText(snapshot)
    return ("%s#%d"):format(snapshot.Hash:sub(1, HASH_PREFIX), snapshot.Index or 0)
end

-- Gap from the subject down to the note (or the section header when there is
-- no note).
local NOTE_GAP = 2

-- Gap below the note block -- a blank line's worth so the note reads as its own
-- block above the list. Both states size the note to its content, so the same
-- gap looks identical whether collapsed or expanded.
local SECTION_GAP = 14

-- Gap between the section header and the list beneath it.
local HEADER_GAP = 2

-- The sorted module names the imported snapshot carries.
local function ModuleNames(snapshot)
    local names = {}
    for name in pairs(snapshot.Modules or {}) do
        tinsert(names, name)
    end
    table.sort(names)
    return names
end

-- The right-aligned "Imported <date>" label, or "" when the time is unknown.
local function ImportedLabel(snapshot)
    if not snapshot.ImportedAt then return "" end
    return L["Imported X"]:format(date("%d %b %Y", snapshot.ImportedAt))
end

-- The change-summary text for an expanded row: one line per changed module, or
-- a single "matches" line when nothing differs.
local function ChangeLines(detail)
    local lines = {}
    if detail and #detail.modules > 0 then
        for _, change in ipairs(detail.modules) do
            tinsert(lines, L["X: +A ~C -R"]:format(
                change.name, change.added, change.changed, change.removed))
        end
    else
        tinsert(lines, L["Matches your current setup"])
    end
    return table.concat(lines, "\n")
end

function Verbs:Constructor(config)
    self._ctx = config.ctx

    self:Background()
    self:DecorateSelection()

    -- The stacked text content fills the row to the right of the inset. The
    -- import row carries no timeline chrome, so the content starts at the inset.
    self.content = addon:GetObject("ExpandableContent"):Build({
        parent = self,
        anchor = function(content)
            content:SetPoint("TOPLEFT", self, "TOPLEFT", ROW_INSET, -6)
            content:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -8, -6)
        end,
    })

    self:WireHover("snapshot")
    self:SetScript("OnMouseDown", function(row, button)
        if button == "LeftButton" and row.snapshot then
            row._ctx.Select(row.snapshot)
        end
    end)
    self:SetScript("OnMouseUp", function(row, button)
        if button == "RightButton" and row.snapshot and row._ctx.OpenMenu then
            row._ctx.OpenMenu(row.snapshot, row)
        end
    end)
end

-- Build the ordered content lines for an imported snapshot, shared by Render (to
-- draw them) and ImportSnapshotList (to reserve the row height from the same
-- description). detail supplies the expanded change summary; nil while collapsed.
function ImportSnapshotRow:BuildLines(snapshot, expanded, detail)
    local note = snapshot.Notes
    local hasNote = note ~= nil and note ~= ""

    local lines = {
        -- Subject + selector on the top line.
        {
            left = SnapshotRow:FormatSubject(snapshot.Timestamp),
            right = SelectorText(snapshot),
            leftStyle = "Subject",
            rightStyle = "Label",
        },
    }

    -- Note, always shown when present: a one-line preview while collapsed, the
    -- full wrapped note while expanded. Its position is the same either way, so
    -- toggling does not move it.
    if hasNote then
        lines[#lines + 1] = {
            left = note,
            leftStyle = "Note",
            wrap = expanded,
            gap = NOTE_GAP,
        }
    end

    -- Section header, sharing its line with the right-aligned import time.
    lines[#lines + 1] = {
        left = expanded and L["Changes vs current setup:"] or L["Shared modules:"],
        right = ImportedLabel(snapshot),
        leftStyle = "Header",
        rightStyle = "Label",
        gap = hasNote and SECTION_GAP or NOTE_GAP,
    }

    -- The list body: exported module names collapsed, change lines expanded.
    lines[#lines + 1] = {
        left = expanded and ChangeLines(detail)
            or table.concat(ModuleNames(snapshot), "\n"),
        leftStyle = "Body",
        wrap = true,
        gap = HEADER_GAP,
    }

    return lines
end

function Verbs:Render(snapshot)
    self.snapshot = snapshot

    local expanded = self._ctx.IsExpanded(snapshot)
    local detail = expanded and self._ctx.GetDetail() or nil
    self.content:SetLines(ImportSnapshotRow:BuildLines(snapshot, expanded, detail))

    self:Paint(snapshot == self._ctx.GetSelected())
end

function ImportSnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.GetSelected) == "function", "Build: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "Build: 'ctx.Select' must be a function")

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        verbs = Verbs,
    })
end
