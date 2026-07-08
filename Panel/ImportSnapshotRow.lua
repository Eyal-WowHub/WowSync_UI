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
        DuplicateOf(snapshot) -> older snapshot or nil,   -- the original this repeats
        OriginContainer(snapshot) -> name or nil,   -- container that imported this hash first
        GetDetail() -> detail or nil,   -- valid only for the expanded row
        Select(snapshot),
        OpenMenu(snapshot, anchor),     -- right-click actions for the row
    }

    addon:GetObject("ImportSnapshotRow"):Build(row, ctx)   -- adopts the pooled frame
        -> import-snapshot-row frame { Render(snapshot) }
]]

local ImportSnapshotRow = addon:NewObject("ImportSnapshotRow")

local C = addon.C
local L = addon.L

local SelectableRow = addon:GetObject("SelectableRow")
local SnapshotRow = addon:GetObject("SnapshotRow")

local HashColors = addon.HashColors

local ChangeBadge = WowSync:Import("ChangeBadge")

-- Left inset of a snapshot row's content, clearing the timeline gutter the
-- TimelineSpan draws its rail and node in (matching the profile rows).
local ROW_INSET = 30

-- Exposed so ImportSnapshotList can derive the content wrap width from the same
-- inset the row anchors its content at, keeping measured height and layout in
-- step.
ImportSnapshotRow.ContentInset = ROW_INSET

-- Fallback timeline node colour for the rare snapshot with no hash to colour from.
local NODE_NEUTRAL = CreateColor(0.85, 0.85, 0.85, 1)

-- Warm accent for a pinned snapshot's node and its "(pinned)" subject tag,
-- matching the profile timeline so a pin reads the same in both views.
local NODE_PINNED = CreateColor(0.95, 0.6, 0.2, 1)

-- Imported snapshots always read white; unlike the profile timeline they carry
-- no "differs from the live setup" colouring.
local SUBJECT_COLOR = CreateColor(1, 1, 1, 1)

local Methods = Mixin({}, SelectableRow.Methods)

-- The user-facing selector for an imported snapshot: its full hash and index. The
-- hash is tinted with a stable per-hash color, so every snapshot carries its
-- hash's colour and any duplicates (same hash) read as one colored group.
local function SelectorText(snapshot)
    local hash = HashColors.WrapHashInColorCode(snapshot.Hash) .. "#" .. snapshot.Hash .. "|r"
    return ("%s#%d"):format(hash, snapshot.Index or 0)
end

-- A compact back-reference to the snapshot a duplicate repeats: its index, which
-- the original's selector shows (the hash is identical for both).
local function DuplicateRef(original)
    return ("#%d"):format(original.Index or 0)
end

-- Gap from the subject down to the note.
local NOTE_GAP = 2

-- Gap above the section header -- a blank line's worth that always separates the
-- header/note block above from the module list below, whether or not a note is
-- present.
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
            tinsert(lines, ChangeBadge.FormatDiffString(change, change.name))
        end
    else
        tinsert(lines, L["Matches your current setup"])
    end
    return table.concat(lines, "\n")
end

function Methods:Constructor(config)
    self._ctx = config.ctx

    self:Background()

    -- The timeline chrome (rail + node) fills the row's left gutter; it takes no
    -- mouse, so clicks and hover fall through to the row. The node's colour is
    -- set per render from the snapshot's hash.
    self.timeline = addon:GetObject("TimelineSpan"):Build({
        parent = self,
        anchor = function(span)
            span:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            span:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end,
    })

    -- The stacked text content fills the row to the right of the inset, past the
    -- timeline gutter the rail and node sit in.
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
-- original is the older in-container snapshot this one repeats, or nil.
-- originName is the container that first imported this hash, or nil; when set it
-- means this container is not the owner, so the copy points at that container.
function ImportSnapshotRow:BuildLines(snapshot, expanded, detail, original, originName)
    local note = snapshot.Notes
    local hasNote = note ~= nil and note ~= ""

    -- The selector doubles as a soft duplicate flag. A cross-container copy points
    -- at the container that imported it first; otherwise an in-container repeat
    -- points at the earlier "#N" copy. Either way the original stays unflagged.
    local selector = SelectorText(snapshot)
    if originName then
        selector = selector .. "  " .. L["(duplicate of X)"]:format(originName)
    elseif original then
        selector = selector .. "  " .. L["(duplicate of X)"]:format(DuplicateRef(original))
    end

    -- The subject carries the disclosure marker and capture date, plus a warm
    -- "(pinned)" tag when pinned so it reads the same as the profile timeline.
    local subject = SnapshotRow:ExpandMarker(expanded) .. SnapshotRow:FormatSubject(snapshot.Timestamp)
    if snapshot.Pinned then
        subject = subject .. "  " .. NODE_PINNED:WrapTextInColorCode(L["(pinned)"])
    end

    local lines = {
        -- Subject + selector on the top line. A leading disclosure marker shows
        -- whether the row is collapsed or expanded -- the only cue to its state.
        {
            left = subject,
            right = selector,
            leftStyle = "Subject",
            rightStyle = "Label",
            leftColor = SUBJECT_COLOR,
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
        gap = SECTION_GAP,
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

function Methods:Render(snapshot)
    self.snapshot = snapshot

    local expanded = self._ctx.IsExpanded(snapshot)
    local detail = expanded and self._ctx.GetDetail() or nil
    local original = self._ctx.DuplicateOf and self._ctx.DuplicateOf(snapshot)
    local originName = self._ctx.OriginContainer and self._ctx.OriginContainer(snapshot)
    self.content:SetLines(ImportSnapshotRow:BuildLines(snapshot, expanded, detail, original, originName))

    -- The node carries the snapshot's hash colour, so duplicates read as one
    -- coloured group down the timeline just as their selectors do. A pinned
    -- snapshot takes the warm accent instead, matching the profile timeline.
    local nodeColor
    if snapshot.Pinned then
        nodeColor = NODE_PINNED
    elseif snapshot.Hash then
        nodeColor = CreateColor(HashColors.GetRGB(snapshot.Hash))
    else
        nodeColor = NODE_NEUTRAL
    end
    self.timeline:SetNodeColor(nodeColor)

    self:Paint(snapshot == self._ctx.GetSelected())
end

function ImportSnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.GetSelected) == "function", "Build: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "Build: 'ctx.Select' must be a function")

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        methods = Methods,
    })
end
