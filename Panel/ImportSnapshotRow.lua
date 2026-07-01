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

-- Rows sit on a dark, near-transparent background (and a translucent blue when
-- selected), so a per-hash hue must clear this perceived-luminance floor to stay
-- readable; darker hues are lifted toward white until they do.
local HASH_MIN_LUMINANCE = 0.5

-- Saturation/value for the generated hues: vivid enough to tell groups apart,
-- not so neon they clash with the rest of the row text.
local HASH_SATURATION = 0.55
local HASH_VALUE = 1.0

local floor = math.floor
local abs = math.abs

local Verbs = Mixin({}, SelectableRow.Verbs)

-- Standard HSV->RGB (h in degrees, s/v in [0,1]); components come back in [0,1].
local function HSVToRGB(h, s, v)
    local c = v * s
    local x = c * (1 - abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

-- Rec. 601 perceived luminance, the yardstick for the contrast floor.
local function Luminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

-- A stable, high-contrast color escape for a content hash, so an imported
-- snapshot and every duplicate of it share one hue (they share the hash, so the
-- derivation matches). The hue is folded from the hash bytes; any hue too dark
-- for the background is blended toward white until it clears the floor.
local function ColorForHash(hash)
    local seed = 0
    for i = 1, #hash do
        seed = (seed * 31 + hash:byte(i)) % 360
    end
    local r, g, b = HSVToRGB(seed, HASH_SATURATION, HASH_VALUE)
    local lum = Luminance(r, g, b)
    if lum < HASH_MIN_LUMINANCE then
        local t = (HASH_MIN_LUMINANCE - lum) / (1 - lum)
        r = r + (1 - r) * t
        g = g + (1 - g) * t
        b = b + (1 - b) * t
    end
    return ("|cff%02x%02x%02x"):format(
        floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- The user-facing selector for an imported snapshot: a short hash and index. The
-- hash prefix is tinted with a stable per-hash color, so every snapshot carries
-- its hash's hue and any duplicates (same hash) read as one colored group.
local function SelectorText(snapshot)
    local hash = ColorForHash(snapshot.Hash) .. snapshot.Hash:sub(1, HASH_PREFIX) .. "|r"
    return ("%s#%d"):format(hash, snapshot.Index or 0)
end

-- A compact back-reference to the snapshot a duplicate repeats: its index, which
-- the original's selector shows (the hash prefix is identical for both).
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

    local lines = {
        -- Subject + selector on the top line. A leading disclosure marker shows
        -- whether the row is collapsed or expanded -- the only cue to its state.
        {
            left = SnapshotRow:ExpandMarker(expanded) .. SnapshotRow:FormatSubject(snapshot.Timestamp),
            right = selector,
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

function Verbs:Render(snapshot)
    self.snapshot = snapshot

    local expanded = self._ctx.IsExpanded(snapshot)
    local detail = expanded and self._ctx.GetDetail() or nil
    local original = self._ctx.DuplicateOf and self._ctx.DuplicateOf(snapshot)
    local originName = self._ctx.OriginContainer and self._ctx.OriginContainer(snapshot)
    self.content:SetLines(ImportSnapshotRow:BuildLines(snapshot, expanded, detail, original, originName))

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
