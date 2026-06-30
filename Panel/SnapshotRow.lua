local _, addon = ...

--[[
    SnapshotRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in SnapshotList. The
    scroll box owns the row frames; this module only builds their children once
    and updates their content. Renders a single snapshot on the timeline: a rail
    node, the subject (formatted date), latest/pinned tags, and an optional note
    preview. When the row is expanded it also shows an inline detail panel: the
    full note plus a per-module change summary against the current setup. The
    list-level selection and expansion state is reached through an injected
    context.

    elementData = { snapshot = <handle>, isHead = bool }

    ctx = {
        GetSelected() -> snapshot or nil,
        IsExpanded(snapshot) -> bool,
        GetDetail() -> detail or nil,   -- valid only for the expanded row
        Select(snapshot),
        OpenMenu(snapshot, anchor),     -- right-click actions for the row
    }

    addon:GetObject("SnapshotRow"):Build(row, ctx)   -- adopts the pooled frame
        -> snapshot-row frame { Render(elementData) }
]]

local SnapshotRow = addon:NewObject("SnapshotRow")
local SelectableRow = addon:GetObject("SelectableRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local SnapshotView = WowSync:GetSnapshotView()

local Verbs = Mixin({}, SelectableRow.Verbs)

-- The shared subject format, mirroring the backend's Time:ToShortDisplay.
local function FormatSubject(timestamp)
    if not timestamp then return "" end
    return date("%d %b %Y %H:%M", timestamp)
end

-- X position of the timeline rail within a row.
local TIMELINE_RAIL_X = 14

-- Y offset of a node dot's centre below the row top, aligning it with the subject.
local SNAPSHOT_NODE_Y = 16

-- Thickness of the timeline rail and diameter of a node dot.
local RAIL_THICKNESS = 2
local NODE_SIZE = 14

-- Horizontal nudge centring a node dot on the rail.
local NODE_RAIL_NUDGE = 1

-- Gap from the rail to the start of the row text.
local TEXT_INDENT = 16

-- Timeline rail and node colours.
local TIMELINE_RAIL_COLOR = CreateColor(0.35, 0.35, 0.35, 0.8)
local TIMELINE_NODE_COLOR = CreateColor(0.85, 0.85, 0.85, 1)
local TIMELINE_NODE_LATEST_COLOR = CreateColor(0.25, 0.65, 0.95, 1)

-- Pinned snapshots get a warm accent so they stand out from the history.
local TIMELINE_NODE_PINNED_COLOR = CreateColor(0.95, 0.6, 0.2, 1)

-- The head row's collapsed hint, in a calm green so it reads as guidance.
local HEAD_HINT_COLOR = CreateColor(0.4, 0.85, 0.4, 1)

-- Exposed so siblings (e.g. the context menu and its dialogs) can label a
-- snapshot with the same subject the row shows.
function SnapshotRow:FormatSubject(timestamp)
    return FormatSubject(timestamp)
end

function Verbs:Constructor(config)
    self._ctx = config.ctx

    self:Background()
    self:DecorateSelection()

    -- Timeline rail: a vertical line down the row with a node dot on it.
    self.rail = self:CreateTexture(nil, "ARTWORK")
    self.rail:SetColorTexture(TIMELINE_RAIL_COLOR:GetRGBA())
    self.rail:SetWidth(RAIL_THICKNESS)
    self.rail:SetPoint("TOPLEFT", self, "TOPLEFT", TIMELINE_RAIL_X, 0)
    self.rail:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", TIMELINE_RAIL_X, 0)

    self.node = self:CreateTexture(nil, "OVERLAY")
    self.node:SetTexture("Interface\\COMMON\\Indicator-Gray")
    self.node:SetSize(NODE_SIZE, NODE_SIZE)
    self.node:SetPoint("CENTER", self, "TOPLEFT", TIMELINE_RAIL_X + NODE_RAIL_NUDGE, -SNAPSHOT_NODE_Y)

    local textLeft = TIMELINE_RAIL_X + TEXT_INDENT

    self.subjectText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.subjectText:SetPoint("TOPLEFT", textLeft, -6)
    self.subjectText:SetJustifyH("LEFT")

    self.tagText = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.tagText:SetPoint("LEFT", self.subjectText, "RIGHT", 6, 0)
    self.tagText:SetJustifyH("LEFT")

    self.noteText = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.noteText:SetPoint("TOPLEFT", self.subjectText, "BOTTOMLEFT", 0, -2)
    self.noteText:SetPoint("RIGHT", -8, 0)
    self.noteText:SetJustifyH("LEFT")
    self.noteText:SetWordWrap(false)

    -- Inline detail panel (shown only while expanded). Anchored below the
    -- subject zone; the scroll box sizes the row tall enough to hold it.
    local detailTop = -(UI.SnapshotDetail.SubjectZone + UI.SnapshotDetail.TopPad)

    self.detailNote = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailNote:SetPoint("RIGHT", -8, 0)
    self.detailNote:SetJustifyH("LEFT")
    self.detailNote:SetJustifyV("TOP")
    self.detailNote:SetHeight(UI.SnapshotDetail.NoteHeight)
    self.detailNote:SetWordWrap(true)
    self.detailNote:SetTextColor(UI.Note.Color:GetRGB())
    self.detailNote:Hide()

    self.detailHeader = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.detailHeader:SetJustifyH("LEFT")
    self.detailHeader:SetTextColor(UI.Note.HeaderColor:GetRGB())
    self.detailHeader:Hide()

    self.detailChanges = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailChanges:SetPoint("RIGHT", -8, 0)
    self.detailChanges:SetJustifyH("LEFT")
    self.detailChanges:SetJustifyV("TOP")
    self.detailChanges:SetWordWrap(true)
    self.detailChanges:Hide()

    -- Stash anchors used by Render's dynamic detail layout.
    self.textLeft = textLeft
    self.detailTop = detailTop

    self:WireHover("snapshot")
    self:SetScript("OnMouseDown", function(row, button)
        if button == "RightButton" then
            row._ctx.OpenMenu(row.snapshot, row)
        else
            row._ctx.Select(row.snapshot)
        end
    end)
end

-- Lay out and populate the inline detail panel for an expanded row: the full
-- note (when present) followed by the per-module change summary.
local function ExpandRow(row, detail)
    row.noteText:Hide()

    if detail and detail.hasNote then
        row.detailNote:ClearAllPoints()
        row.detailNote:SetPoint("TOPLEFT", row.subjectText, "BOTTOMLEFT", 0, -2)
        row.detailNote:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.detailNote:SetText(detail.note)
        row.detailNote:Show()

        row.detailHeader:ClearAllPoints()
        row.detailHeader:SetPoint("TOPLEFT", row.detailNote, "BOTTOMLEFT", 0, -2)
    else
        row.detailNote:Hide()

        row.detailHeader:ClearAllPoints()
        row.detailHeader:SetPoint("TOPLEFT", row.subjectText, "BOTTOMLEFT", 0, -2)
    end

    row.detailHeader:SetText(L["Changes vs current setup:"])
    row.detailHeader:Show()

    local lines = {}
    if detail and #detail.modules > 0 then
        for _, change in ipairs(detail.modules) do
            tinsert(lines, L["X: +A ~C -R"]:format(
                change.name, change.added, change.changed, change.removed))
        end
    else
        tinsert(lines, L["Matches your current setup"])
    end

    row.detailChanges:ClearAllPoints()
    row.detailChanges:SetPoint("TOPLEFT", row.detailHeader, "BOTTOMLEFT", 0, -2)
    row.detailChanges:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.detailChanges:SetText(table.concat(lines, "\n"))
    row.detailChanges:Show()
end

-- Restore the compact look: subject, tags, and a one-line note preview; the
-- inline detail panel is hidden.
local function CollapseRow(row, snapshot, isHead)
    row.detailNote:Hide()
    row.detailHeader:Hide()
    row.detailChanges:Hide()

    -- The head carries no saved note; show a hint describing the live setup so
    -- the row still guides the user when collapsed.
    if isHead then
        row.noteText:SetText(L["Your live setup — Save to keep it as a snapshot."])
        row.noteText:SetTextColor(HEAD_HINT_COLOR:GetRGB())
        row.noteText:Show()
        return
    end

    local note = SnapshotView:GetNotes(snapshot)
    if note ~= "" then
        row.noteText:SetText(note)
        row.noteText:SetTextColor(UI.Note.Color:GetRGB())
        row.noteText:Show()
    else
        row.noteText:Hide()
    end
end

function Verbs:Render(elementData)
    local snapshot = elementData.snapshot
    self.snapshot = snapshot

    -- The current head reads "Current" in the brand accent; saved snapshots show
    -- their capture date in the normal colour. Rows are pooled, so both the
    -- text and its colour are set explicitly on every update.
    if elementData.isHead then
        self.subjectText:SetText(L["Current"])
        self.subjectText:SetTextColor(TIMELINE_NODE_LATEST_COLOR:GetRGB())
    else
        self.subjectText:SetText(FormatSubject(SnapshotView:GetTimestamp(snapshot)))
        self.subjectText:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end

    -- Tag: a saved snapshot may show a pinned marker in the warm accent; the
    -- head and ordinary snapshots carry no tag.
    if SnapshotView:IsPinned(snapshot) then
        self.tagText:SetText(L["(pinned)"])
        self.tagText:SetTextColor(TIMELINE_NODE_PINNED_COLOR:GetRGB())
    else
        self.tagText:SetText("")
    end

    if self._ctx.IsExpanded(self.snapshot) then
        ExpandRow(self, self._ctx.GetDetail())
    else
        CollapseRow(self, snapshot, elementData.isHead)
    end

    -- The head node carries the brand accent; pinned nodes take the warm
    -- accent; the rest stay neutral.
    if elementData.isHead then
        self.node:SetVertexColor(TIMELINE_NODE_LATEST_COLOR:GetRGB())
    elseif SnapshotView:IsPinned(snapshot) then
        self.node:SetVertexColor(TIMELINE_NODE_PINNED_COLOR:GetRGB())
    else
        self.node:SetVertexColor(TIMELINE_NODE_COLOR:GetRGB())
    end

    -- Selection highlight
    self:Paint(self.snapshot == self._ctx.GetSelected())
end

function SnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        verbs = Verbs,
    })
end
