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

local C = addon.C
local L = addon.L

local SelectableRow = addon:GetObject("SelectableRow")

local ChangeBadge = WowSync:Import("ChangeBadge")

local Methods = Mixin({}, SelectableRow.Methods)

-- The shared subject format, mirroring the backend's Time:ToShortDisplay.
local function FormatSubject(timestamp)
    if not timestamp then return "" end
    return date("%d %b %Y %H:%M", timestamp)
end

-- Left inset of the row's text content, clearing the timeline gutter the
-- TimelineSpan draws its rail and node in.
local CONTENT_INSET = 30

-- Exposed so SnapshotList can derive the content wrap width from the same inset
-- the row anchors its content at, keeping measured height and layout in step.
SnapshotRow.ContentInset = CONTENT_INSET

-- Node accent colours, shared by the node dot and the matching text (the head's
-- subject and the pinned marker) so a snapshot reads the same in both places.
local TIMELINE_NODE_COLOR = CreateColor(0.85, 0.85, 0.85, 1)
local TIMELINE_NODE_LATEST_COLOR = CreateColor(0.25, 0.65, 0.95, 1)

-- Pinned snapshots get a warm accent so they stand out from the history.
local TIMELINE_NODE_PINNED_COLOR = CreateColor(0.95, 0.6, 0.2, 1)

-- The head row's collapsed hint, in a calm green so it reads as guidance.
local HEAD_HINT_COLOR = CreateColor(0.4, 0.85, 0.4, 1)

-- A snapshot that differs from the live setup reads red; an in-sync one reads
-- white. Both override the Subject style's gold default so only the live head
-- keeps an accent.
local CHANGES_TEXT_COLOR = CreateColor(0.85, 0.42, 0.42, 1)
local IN_SYNC_TEXT_COLOR = CreateColor(1, 1, 1, 1)

-- Vertical gaps between the stacked content lines, mirroring the reserved
-- height SnapshotList computes for a row (and the import rows' spacing).
local NOTE_GAP = 2     -- subject -> note
local SECTION_GAP = 14 -- (note or subject) -> header (a blank line's worth)
local HEADER_GAP = 2   -- header -> change list

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

-- Exposed so siblings (e.g. the context menu and its dialogs) can label a
-- snapshot with the same subject the row shows.
function SnapshotRow:FormatSubject(timestamp)
    return FormatSubject(timestamp)
end

-- Disclosure markers drawn as fixed-size textures rather than "+"/"-" glyphs:
-- a texture keeps its own single colour (independent of the subject's) and a
-- constant width, so toggling a row never shifts the subject sideways the way
-- the differently-sized "+"/"-" characters did.
local MARKER_COLLAPSED = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t "
local MARKER_EXPANDED = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "

-- Exposed so the import rows render the identical open/closed marker.
function SnapshotRow:ExpandMarker(expanded)
    return expanded and MARKER_EXPANDED or MARKER_COLLAPSED
end

-- The subject colour for a saved row: red when it differs from the live setup,
-- white when it matches -- both overriding the Subject style's gold. Exposed so
-- the import rows colour the same way.
function SnapshotRow:ChangesColor(hasChanges)
    return hasChanges and CHANGES_TEXT_COLOR or IN_SYNC_TEXT_COLOR
end

function Methods:Constructor(config)
    self._ctx = config.ctx

    self:Background()

    -- The timeline chrome (rail + node) fills the row's left gutter; the text
    -- content sits to its right. Both are siblings of the row -- import rows
    -- reuse the same content widget but carry no timeline.
    self.timeline = addon:GetObject("TimelineSpan"):Build({
        parent = self,
        anchor = function(span)
            span:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            span:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end,
    })

    self.content = addon:GetObject("ExpandableContent"):Build({
        parent = self,
        anchor = function(content)
            content:SetPoint("TOPLEFT", self, "TOPLEFT", CONTENT_INSET, -6)
            content:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -8, -6)
        end,
    })

    self:WireHover("snapshot")
    self:SetScript("OnMouseDown", function(row, button)
        if button == "RightButton" then
            row._ctx.OpenMenu(row.snapshot, row)
        else
            row._ctx.Select(row.snapshot)
        end
    end)
end

-- Build the ordered content lines for a snapshot, shared by Render (to draw
-- them) and SnapshotList (to reserve the row height from the same description).
-- detail supplies the expanded change summary; nil while collapsed. hasChanges
-- tags a collapsed saved row that differs from the live setup.
function SnapshotRow:BuildLines(snapshot, isHead, expanded, detail, hasChanges)
    -- Subject: the head reads "Current" in the brand accent; a saved snapshot
    -- shows its capture date, with an inline pinned marker in the warm accent.
    local subject
    if isHead then
        subject = L["Current"]
    else
        subject = FormatSubject(snapshot:GetTimestamp())
        if snapshot:IsPinned() then
            subject = subject .. "  " .. TIMELINE_NODE_PINNED_COLOR:WrapTextInColorCode(L["(pinned)"])
        end
    end

    -- A leading disclosure marker shows whether the row is collapsed or
    -- expanded -- the only cue to its state.
    subject = SnapshotRow:ExpandMarker(expanded) .. subject

    -- The subject reads blue for the live head, red when the snapshot differs
    -- from the live setup, and the default white when it is in sync.
    local lines = {
        {
            left = subject,
            leftStyle = "Subject",
            leftColor = isHead and TIMELINE_NODE_LATEST_COLOR or SnapshotRow:ChangesColor(hasChanges),
        },
    }

    if expanded then
        -- The inline detail: the full note (when present), a section header,
        -- then the per-module change summary.
        if detail and detail.hasNote then
            lines[#lines + 1] = {
                left = detail.note,
                leftStyle = "Note",
                wrap = true,
                gap = NOTE_GAP,
            }
        end
        lines[#lines + 1] = {
            left = L["Changes vs current setup:"],
            leftStyle = "Header",
            gap = SECTION_GAP,
        }
        lines[#lines + 1] = {
            left = ChangeLines(detail),
            leftStyle = "Body",
            wrap = true,
            gap = HEADER_GAP,
        }
    elseif isHead then
        -- The head carries no saved note; a green hint describes the live setup.
        lines[#lines + 1] = {
            left = L["Your live setup — Save to keep it as a snapshot."],
            leftStyle = "Note",
            gap = NOTE_GAP,
            leftColor = HEAD_HINT_COLOR,
        }
    else
        local note = snapshot:GetNotes()
        if note ~= "" then
            lines[#lines + 1] = {
                left = note,
                leftStyle = "Note",
                gap = NOTE_GAP,
            }
        end
    end

    return lines
end

function Methods:Render(elementData)
    local snapshot = elementData.snapshot
    self.snapshot = snapshot

    local isHead = elementData.isHead
    local expanded = self._ctx.IsExpanded(snapshot)
    local hasChanges = (not isHead) and self._ctx.HasChanges(snapshot) or false
    self.content:SetLines(
        SnapshotRow:BuildLines(snapshot, isHead, expanded, expanded and self._ctx.GetDetail() or nil, hasChanges))

    -- The head node carries the brand accent; pinned nodes take the warm
    -- accent; the rest stay neutral.
    local nodeColor
    if isHead then
        nodeColor = TIMELINE_NODE_LATEST_COLOR
    elseif snapshot:IsPinned() then
        nodeColor = TIMELINE_NODE_PINNED_COLOR
    else
        nodeColor = TIMELINE_NODE_COLOR
    end
    self.timeline:SetNodeColor(nodeColor)

    self:Paint(snapshot == self._ctx.GetSelected())
end

function SnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        methods = Methods,
    })
end
