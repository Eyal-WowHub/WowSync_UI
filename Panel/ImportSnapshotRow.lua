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
local UI = addon.UI

-- Left inset of a snapshot row's content.
local ROW_INSET = 10

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

    -- Right-aligned selector, top corner.
    self.selectorText = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.selectorText:SetPoint("TOPRIGHT", -8, -6)
    self.selectorText:SetJustifyH("RIGHT")
    self.selectorText:SetWordWrap(false)

    -- Capture subject, fills the top line up to the selector.
    self.subjectText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.subjectText:SetPoint("TOPLEFT", ROW_INSET, -6)
    self.subjectText:SetPoint("RIGHT", self.selectorText, "LEFT", -6, 0)
    self.subjectText:SetJustifyH("LEFT")
    self.subjectText:SetWordWrap(false)

    -- The note is always shown when present: a one-line preview while collapsed,
    -- the full note while expanded. Two font strings keep their wrapping and
    -- height distinct; the layout in Render picks one and hides the other.
    self.notePreview = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.notePreview:SetJustifyH("LEFT")
    self.notePreview:SetWordWrap(false)
    self.notePreview:SetTextColor(UI.Note.Color:GetRGB())
    self.notePreview:Hide()

    -- The expanded note wraps and auto-sizes to its content (no fixed-height
    -- box), so the gap below it matches the collapsed preview's exactly.
    self.detailNote = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailNote:SetJustifyH("LEFT")
    self.detailNote:SetJustifyV("TOP")
    self.detailNote:SetWordWrap(true)
    self.detailNote:SetTextColor(UI.Note.Color:GetRGB())
    self.detailNote:Hide()

    -- Section header: "Shared modules:" collapsed, "Changes vs current setup:"
    -- expanded.
    self.listHeader = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.listHeader:SetJustifyH("LEFT")
    self.listHeader:SetTextColor(UI.Note.HeaderColor:GetRGB())
    self.listHeader:Hide()

    -- Right-aligned import time, sharing the header's line.
    self.importedText = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.importedText:SetJustifyH("RIGHT")
    self.importedText:SetWordWrap(false)
    self.importedText:Hide()

    -- The vertical list beneath the header: exported module names collapsed,
    -- per-module change lines expanded.
    self.listBody = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.listBody:SetJustifyH("LEFT")
    self.listBody:SetJustifyV("TOP")
    self.listBody:SetWordWrap(true)
    self.listBody:Hide()

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

function Verbs:Render(snapshot)
    self.snapshot = snapshot

    self.subjectText:SetText(SnapshotRow:FormatSubject(snapshot.Timestamp))
    self.selectorText:SetText(SelectorText(snapshot))

    local expanded = self._ctx.IsExpanded(snapshot)
    local note = snapshot.Notes
    local hasNote = note ~= nil and note ~= ""

    -- Note (always shown when present), then the section header below it.
    local anchorAbove = self.subjectText
    if hasNote then
        local noteFS = expanded and self.detailNote or self.notePreview
        local hiddenFS = expanded and self.notePreview or self.detailNote
        hiddenFS:Hide()
        noteFS:ClearAllPoints()
        noteFS:SetPoint("TOPLEFT", self.subjectText, "BOTTOMLEFT", 0, -NOTE_GAP)
        noteFS:SetPoint("RIGHT", self, "RIGHT", -8, 0)
        noteFS:SetText(note)
        noteFS:Show()
        anchorAbove = noteFS
    else
        self.notePreview:Hide()
        self.detailNote:Hide()
    end

    self.listHeader:ClearAllPoints()
    if anchorAbove == self.subjectText then
        self.listHeader:SetPoint("TOPLEFT", self.subjectText, "BOTTOMLEFT", 0, -NOTE_GAP)
    else
        self.listHeader:SetPoint("TOPLEFT", anchorAbove, "BOTTOMLEFT", 0, -SECTION_GAP)
    end
    self.listHeader:SetText(expanded and L["Changes vs current setup:"] or L["Shared modules:"])
    self.listHeader:Show()

    -- The import time shares the header's line, right-aligned. Both font strings
    -- span the line and justify to opposite sides, so their short texts never
    -- collide.
    self.importedText:ClearAllPoints()
    self.importedText:SetPoint("TOPLEFT", self.listHeader, "TOPLEFT", 0, 0)
    self.importedText:SetPoint("RIGHT", self, "RIGHT", -8, 0)
    self.importedText:SetText(ImportedLabel(snapshot))
    self.importedText:Show()

    self.listBody:ClearAllPoints()
    self.listBody:SetPoint("TOPLEFT", self.listHeader, "BOTTOMLEFT", 0, -HEADER_GAP)
    self.listBody:SetPoint("RIGHT", self, "RIGHT", -8, 0)
    self.listBody:SetText(expanded and ChangeLines(self._ctx.GetDetail()) or table.concat(ModuleNames(snapshot), "\n"))
    self.listBody:Show()

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
