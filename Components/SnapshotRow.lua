local _, addon = ...

local UI = addon.UI
local L = addon.L

--[[
    SnapshotRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in SnapshotList. The
    scroll box owns the row frames; this module only builds their children once
    and updates their content. Renders a single snapshot on the timeline: a rail
    node, the subject (formatted date), latest/pinned tags, and an optional note
    preview. The list-level selection state is reached through an injected
    context.

    elementData = { snapshot = <snapshot>, isLatest = bool, isOldest = bool }

    ctx = {
        GetSelected() -> hash or nil,
        Select(hash),
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
    row.node:SetPoint("CENTER", row, "LEFT", UI.TimelineRailX + 1, 0)

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
    row:SetScript("OnMouseDown", function(self)
        ctx.Select(self.snapshotHash)
    end)
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

    -- Optional body note preview
    if snapshot.Body and snapshot.Body ~= "" then
        row.noteText:SetText(snapshot.Body)
        row.noteText:Show()
    else
        row.noteText:Hide()
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
