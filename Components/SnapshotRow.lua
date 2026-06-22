local _, addon = ...

local UI = addon.UI
local L = addon.L

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

    elementData = { snapshot = <snapshot>, isLatest = bool, isOldest = bool }

    ctx = {
        GetSelected() -> hash or nil,
        IsExpanded(hash) -> bool,
        GetDetail() -> detail or nil,   -- valid only for the expanded row
        Select(hash),
        OpenMenu(hash, anchor),         -- right-click actions for the row
    }

    addon:GetObject("SnapshotRow"):Build(row, ctx)
    addon:GetObject("SnapshotRow"):Update(row, elementData, ctx)
]]

-- The shared subject format, mirroring the backend's Time:ToShortDisplay.
local function FormatSubject(timestamp)
    if not timestamp then return "" end
    return date("%d %b %Y %H:%M", timestamp)
end

local SnapshotRow = addon:NewObject("SnapshotRow")

-- Exposed so siblings (e.g. the context menu and its dialogs) can label a
-- snapshot with the same subject the row shows.
function SnapshotRow:FormatSubject(timestamp)
    return FormatSubject(timestamp)
end

function SnapshotRow:Build(row, ctx)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)

    -- Timeline rail: a vertical line down the row with a node dot on it.
    row.rail = row:CreateTexture(nil, "ARTWORK")
    row.rail:SetColorTexture(UI.TimelineRailColor:GetRGBA())
    row.rail:SetWidth(2)
    row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", UI.TimelineRailX, 0)
    row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", UI.TimelineRailX, 0)

    row.node = row:CreateTexture(nil, "OVERLAY")
    row.node:SetTexture("Interface\\COMMON\\Indicator-Gray")
    row.node:SetSize(14, 14)
    row.node:SetPoint("CENTER", row, "TOPLEFT", UI.TimelineRailX + 1, -UI.SnapshotNodeY)

    local textLeft = UI.TimelineRailX + 16

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
    local detailTop = -(UI.SnapshotSubjectZone + UI.SnapshotDetailTopPad)

    row.detailNote = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailNote:SetPoint("RIGHT", -8, 0)
    row.detailNote:SetJustifyH("LEFT")
    row.detailNote:SetJustifyV("TOP")
    row.detailNote:SetHeight(UI.SnapshotDetailNoteHeight)
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
        if self.snapshotHash ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.RowHoverColor:GetRGBA())
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.snapshotHash ~= ctx.GetSelected() then
            self.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
        end
    end)
    row:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ctx.OpenMenu(self.snapshotHash, self)
        else
            ctx.Select(self.snapshotHash)
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

    if snapshot.Body and snapshot.Body ~= "" then
        row.noteText:SetText(snapshot.Body)
        row.noteText:Show()
    else
        row.noteText:Hide()
    end
end

function SnapshotRow:Update(row, elementData, ctx)
    local snapshot = elementData.snapshot
    row.snapshotHash = snapshot.Hash

    row.subjectText:SetText(FormatSubject(snapshot.Timestamp))

    -- Latest / pinned tags
    local tags = {}
    if elementData.isLatest then
        tinsert(tags, L["(latest)"])
    end
    if snapshot.Pinned then
        tinsert(tags, L["(pinned)"])
    end
    row.tagText:SetText(table.concat(tags, " "))

    if ctx.IsExpanded(row.snapshotHash) then
        ExpandRow(row, ctx.GetDetail())
    else
        CollapseRow(row, snapshot)
    end

    -- The latest node carries the brand accent; older nodes stay neutral.
    if elementData.isLatest then
        row.node:SetVertexColor(UI.TimelineNodeLatestColor:GetRGB())
    else
        row.node:SetVertexColor(UI.TimelineNodeColor:GetRGB())
    end

    -- Selection highlight
    if row.snapshotHash == ctx.GetSelected() then
        row.bg:SetColorTexture(UI.RowSelectedColor:GetRGBA())
    else
        row.bg:SetColorTexture(UI.RowNormalColor:GetRGBA())
    end
end
