local _, addon = ...

--[[
    ExpandableContent widget (a stacked, two-column text block).

    The content half of a snapshot row: an ordered stack of lines, each with an
    optional left text and an optional right label, each text drawn in a named
    style (font + colour) from UI.LineStyles. A left cell may wrap into a
    multi-line block; right cells are short labels. Lines stack top-to-bottom,
    each below the previous by its own gap, so a caller describes *what* to show
    and this owns *how* it is laid out -- the shared vocabulary both the profile
    and import rows render through.

    The cells are pooled: created once, re-fonted and re-anchored on every
    SetLines so the widget fits the scroll box's frame reuse. It enables no
    mouse, so clicks and hover fall through to the owning row.

    local content = addon:GetObject("ExpandableContent"):Build({
        parent = row,
        anchor = function(c) c:SetPoint(...) end,
    })

    content:SetLines({
        { left = subject, right = selector, leftStyle = "Subject", rightStyle = "Label" },
        { left = note, leftStyle = "Note", wrap = true, gap = 2 },
        { left = header, right = imported, leftStyle = "Header", rightStyle = "Label", gap = 14 },
        { left = body, leftStyle = "Body", wrap = true, gap = 2 },
    })

    -- Reserve the row height from the same lines (before the frame exists):
    -- local h = addon:GetObject("ExpandableContent"):Measure(lines, width)
]]

local ExpandableContent = addon:NewObject("ExpandableContent")

local C = LibStub("Contracts-1.0")

-- Horizontal gap between a wrapping/own-line left cell and a right label that
-- shares its line, so their texts never touch.
local COLUMN_GAP = 6

local Verbs = {}

-- Apply a named style (font object + colour) to a font string. SetFontObject
-- resets the colour to the font's default, so the colour is set after.
local function ApplyStyle(fontString, styleName)
    local style = addon.UI.LineStyles[styleName] or addon.UI.LineStyles.Body
    fontString:SetFontObject(style.font)
    fontString:SetTextColor(style.color:GetRGBA())
end

-- Start with an empty cell pool; SetLines grows it on demand and the scroll box
-- reuses the frame (and its pool) across renders.
function Verbs:Constructor()
    self._cells = {}
end

-- Create (or fetch) the pooled cell at index i: a left text and a right label,
-- both top-aligned.
function Verbs:CellAt(i)
    local cell = self._cells[i]
    if cell then return cell end

    -- The template gives each cell a real font up front (the client resolves the
    -- name against loaded fonts); ApplyStyle then swaps in the line's own style.
    cell = {
        left = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        right = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
    }
    cell.left:SetJustifyH("LEFT")
    cell.left:SetJustifyV("TOP")
    cell.right:SetJustifyH("RIGHT")
    cell.right:SetWordWrap(false)
    self._cells[i] = cell
    return cell
end

-- Lay out and populate the stack from an ordered list of line descriptors. Each
-- line: { left, right, leftStyle, rightStyle, gap, wrap, leftColor, rightColor }.
-- A right label leans on its left cell's edge; a labelled left cell is short and
-- never wraps. leftColor/rightColor override the style's colour for this render
-- (e.g. a head row's accent), leaving the shared style otherwise intact.
function Verbs:SetLines(lines)
    local previousLeft

    for i, line in ipairs(lines) do
        local cell = self:CellAt(i)
        local hasRight = line.right ~= nil and line.right ~= ""

        cell.left:ClearAllPoints()
        cell.right:ClearAllPoints()

        ApplyStyle(cell.left, line.leftStyle)
        if line.leftColor then
            cell.left:SetTextColor(line.leftColor:GetRGBA())
        end
        cell.left:SetWordWrap(line.wrap and true or false)
        cell.left:SetText(line.left or "")

        if previousLeft then
            cell.left:SetPoint("TOPLEFT", previousLeft, "BOTTOMLEFT", 0, -(line.gap or 0))
        else
            cell.left:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        end

        -- The dependency runs one way only -- a right label leans on the left
        -- cell, never the reverse -- so the two never form an anchor cycle.
        -- Lines that carry a right label are short and never wrap, so the left
        -- cell sizes to its own text and leaves room for the label; wrapping
        -- lines have no label and stretch to the full width instead.
        if hasRight then
            ApplyStyle(cell.right, line.rightStyle)
            if line.rightColor then
                cell.right:SetTextColor(line.rightColor:GetRGBA())
            end
            cell.right:SetText(line.right)
            cell.right:Show()
            cell.right:SetPoint("TOP", cell.left, "TOP", 0, 0)
            cell.right:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            cell.right:SetPoint("LEFT", cell.left, "RIGHT", COLUMN_GAP, 0)
        else
            cell.right:Hide()
            cell.left:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end

        cell.left:Show()
        previousLeft = cell.left
    end

    -- Hide any cells left over from a previous, longer render.
    for i = #lines + 1, #self._cells do
        self._cells[i].left:Hide()
        self._cells[i].right:Hide()
    end
end

-- Measure the stacked height these lines will render at, for the given content
-- width, mirroring SetLines exactly: each line's own text height (wrap-aware)
-- plus its gap above the previous. Lets a caller reserve the right row height
-- from the same line list it renders, so the layout is described in one place.
local measureProbe
function ExpandableContent:Measure(lines, width)
    if not measureProbe then
        measureProbe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measureProbe:SetJustifyH("LEFT")
        measureProbe:Hide()
    end

    -- A non-positive width (before the scroll box is sized) can't drive wrapping,
    -- so measure those lines as a single line -- the same fallback the note
    -- preview used, and a transient the scroll box corrects on its next pass.
    local wrapOK = width and width > 0

    local total = 0
    for i, line in ipairs(lines) do
        if i > 1 then
            total = total + (line.gap or 0)
        end

        local style = addon.UI.LineStyles[line.leftStyle] or addon.UI.LineStyles.Body
        measureProbe:SetFontObject(style.font)
        measureProbe:SetWordWrap((line.wrap and wrapOK) and true or false)
        measureProbe:SetWidth(wrapOK and width or 10000)
        measureProbe:SetText(line.left or "")

        local h = measureProbe:GetStringHeight()
        total = total + ((h and h > 0) and math.ceil(h) or 0)
    end

    return total
end

function ExpandableContent:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")
    C:Ensures(type(config.anchor) == "function", "Build: 'config.anchor' must be a function")

    return addon:NewWidget(config, {
        frameType = "Frame",
        verbs = Verbs,
    })
end
