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

    addon:GetObject("SnapshotRow"):Build(row, ctx)
    addon:GetObject("SnapshotRow"):Update(row, elementData, ctx)
]]

local SnapshotRow = addon:NewObject("SnapshotRow")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local sv

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

-- Exposed so siblings (e.g. the context menu and its dialogs) can label a
-- snapshot with the same subject the row shows.
function SnapshotRow:FormatSubject(timestamp)
    return FormatSubject(timestamp)
end

function SnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Timeline rail: a vertical line down the row with a node dot on it.
    row.rail = row:CreateTexture(nil, "ARTWORK")
    row.rail:SetColorTexture(TIMELINE_RAIL_COLOR:GetRGBA())
    row.rail:SetWidth(RAIL_THICKNESS)
    row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", TIMELINE_RAIL_X, 0)
    row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TIMELINE_RAIL_X, 0)

    row.node = row:CreateTexture(nil, "OVERLAY")
    row.node:SetTexture("Interface\\COMMON\\Indicator-Gray")
    row.node:SetSize(NODE_SIZE, NODE_SIZE)
    row.node:SetPoint("CENTER", row, "TOPLEFT", TIMELINE_RAIL_X + NODE_RAIL_NUDGE, -SNAPSHOT_NODE_Y)

    local textLeft = TIMELINE_RAIL_X + TEXT_INDENT

    row.subjectText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.subjectText:SetPoint("TOPLEFT", textLeft, -6)
    row.subjectText:SetJustifyH("LEFT")

    row.tagText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.tagText:SetPoint("LEFT", row.subjectText, "RIGHT", 6, 0)
    row.tagText:SetJustifyH("LEFT")

    row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.noteText:SetPoint("TOPLEFT", row.subjectText, "BOTTOMLEFT", 0, -2)
    row.noteText:SetPoint("RIGHT", -8, 0)
    row.noteText:SetJustifyH("LEFT")
    row.noteText:SetWordWrap(false)

    -- Inline detail panel (shown only while expanded). Anchored below the
    -- subject zone; the scroll box sizes the row tall enough to hold it.
    local detailTop = -(UI.SnapshotDetail.SubjectZone + UI.SnapshotDetail.TopPad)

    row.detailNote = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailNote:SetPoint("RIGHT", -8, 0)
    row.detailNote:SetJustifyH("LEFT")
    row.detailNote:SetJustifyV("TOP")
    row.detailNote:SetHeight(UI.SnapshotDetail.NoteHeight)
    row.detailNote:SetWordWrap(true)
    row.detailNote:Hide()

    row.detailHeader = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detailHeader:SetJustifyH("LEFT")
    row.detailHeader:Hide()

    row.detailChanges = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailChanges:SetPoint("RIGHT", -8, 0)
    row.detailChanges:SetJustifyH("LEFT")
    row.detailChanges:SetJustifyV("TOP")
    row.detailChanges:SetWordWrap(false)
    row.detailChanges:Hide()

    -- Stash anchors used by Update's dynamic detail layout.
    row.textLeft = textLeft
    row.detailTop = detailTop

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.snapshot ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.snapshot ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ctx.OpenMenu(self.snapshot, self)
        else
            ctx.Select(self.snapshot)
        end
    end)
end

-- Lay out and populate the inline detail panel for an expanded row: the full
-- note (when present) followed by the per-module change summary.
local function ExpandRow(row, detail)
    row.noteText:Hide()

    if detail and detail.hasNote then
        row.detailNote:ClearAllPoints()
        row.detailNote:SetPoint("TOPLEFT", row, "TOPLEFT", row.textLeft, row.detailTop)
        row.detailNote:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.detailNote:SetText(detail.note)
        row.detailNote:Show()

        row.detailHeader:ClearAllPoints()
        row.detailHeader:SetPoint("TOPLEFT", row.detailNote, "BOTTOMLEFT", 0, -2)
    else
        row.detailNote:Hide()

        row.detailHeader:ClearAllPoints()
        row.detailHeader:SetPoint("TOPLEFT", row, "TOPLEFT", row.textLeft, row.detailTop)
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
local function CollapseRow(row, snapshot)
    row.detailNote:Hide()
    row.detailHeader:Hide()
    row.detailChanges:Hide()

    local note = sv:GetNotes(snapshot)
    if note ~= "" then
        row.noteText:SetText(note)
        row.noteText:Show()
    else
        row.noteText:Hide()
    end
end

function SnapshotRow:Update(row, elementData, ctx)
    C:IsTable(row, 2)
    C:IsTable(elementData, 3)
    C:IsTable(ctx, 4)

    sv = sv or WowSync:GetSnapshotView()

    local snapshot = elementData.snapshot
    row.snapshot = snapshot

    -- The current head reads "Current" in the brand accent; saved snapshots show
    -- their capture date in the normal colour. Rows are pooled, so both the
    -- text and its colour are set explicitly on every update.
    if elementData.isHead then
        row.subjectText:SetText(L["Current"])
        row.subjectText:SetTextColor(TIMELINE_NODE_LATEST_COLOR:GetRGB())
    else
        row.subjectText:SetText(FormatSubject(sv:GetTimestamp(snapshot)))
        row.subjectText:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end

    -- Tag: a saved snapshot may show a pinned marker in the warm accent; the
    -- head and ordinary snapshots carry no tag.
    if sv:IsPinned(snapshot) then
        row.tagText:SetText(L["(pinned)"])
        row.tagText:SetTextColor(TIMELINE_NODE_PINNED_COLOR:GetRGB())
    else
        row.tagText:SetText("")
    end

    if ctx.IsExpanded(row.snapshot) then
        ExpandRow(row, ctx.GetDetail())
    else
        CollapseRow(row, snapshot)
    end

    -- The head node carries the brand accent; pinned nodes take the warm
    -- accent; the rest stay neutral.
    if elementData.isHead then
        row.node:SetVertexColor(TIMELINE_NODE_LATEST_COLOR:GetRGB())
    elseif sv:IsPinned(snapshot) then
        row.node:SetVertexColor(TIMELINE_NODE_PINNED_COLOR:GetRGB())
    else
        row.node:SetVertexColor(TIMELINE_NODE_COLOR:GetRGB())
    end

    -- Selection highlight
    if row.snapshot == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.Row.Selected:GetRGBA())
    else
        row.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
    end
end
