local _, addon = ...

--[[
    ImportSnapshotRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportSnapshotList.
    Renders one imported snapshot: its capture subject and selector on top, its
    note and import time below. The list-level selection state is reached through
    an injected context.

    ctx = {
        GetSelected() -> snapshot or nil,
        Select(snapshot),
    }

    addon:GetObject("ImportSnapshotRow"):Build(row, ctx)
    addon:GetObject("ImportSnapshotRow"):Update(row, snapshot, ctx)
]]

local ImportSnapshotRow = addon:NewObject("ImportSnapshotRow")
local SnapshotRow = addon:GetObject("SnapshotRow")
local SelectableRow = addon:GetObject("SelectableRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Left inset of a snapshot row's content.
local ROW_INSET = 10

-- Characters of the content hash shown in the selector label.
local HASH_PREFIX = 7

-- The user-facing selector for an imported snapshot: a short hash and index.
local function SelectorText(snapshot)
    return ("%s#%d"):format(snapshot.Hash:sub(1, HASH_PREFIX), snapshot.Index or 0)
end

function ImportSnapshotRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.GetSelected) == "function", "Build: 'ctx.GetSelected' must be a function")
    C:Ensures(type(ctx.Select) == "function", "Build: 'ctx.Select' must be a function")

    SelectableRow:Background(row)

    -- Right-aligned selector, top corner.
    row.selectorText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.selectorText:SetPoint("TOPRIGHT", -8, -6)
    row.selectorText:SetJustifyH("RIGHT")
    row.selectorText:SetWordWrap(false)

    -- Capture subject, fills the top line up to the selector.
    row.subjectText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.subjectText:SetPoint("TOPLEFT", ROW_INSET, -6)
    row.subjectText:SetPoint("RIGHT", row.selectorText, "LEFT", -6, 0)
    row.subjectText:SetJustifyH("LEFT")
    row.subjectText:SetWordWrap(false)

    -- Right-aligned import time, bottom corner.
    row.importedText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.importedText:SetPoint("BOTTOMRIGHT", -8, 6)
    row.importedText:SetJustifyH("RIGHT")
    row.importedText:SetWordWrap(false)

    -- Note, fills the bottom line up to the import time.
    row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.noteText:SetPoint("BOTTOMLEFT", ROW_INSET, 6)
    row.noteText:SetPoint("RIGHT", row.importedText, "LEFT", -6, 0)
    row.noteText:SetJustifyH("LEFT")
    row.noteText:SetWordWrap(false)

    SelectableRow:WireHover(row, "snapshot", ctx)
    row:SetScript("OnMouseDown", function(self)
        if self.snapshot then
            ctx.Select(self.snapshot)
        end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.snapshot and ctx.OpenMenu then
            ctx.Select(self.snapshot)
            ctx.OpenMenu(self.snapshot, self)
        end
    end)
end

function ImportSnapshotRow:Update(row, snapshot, ctx)
    C:IsTable(row, 2)
    C:IsTable(snapshot, 3)
    C:IsTable(ctx, 4)

    row.snapshot = snapshot

    row.subjectText:SetText(SnapshotRow:FormatSubject(snapshot.Timestamp))
    row.selectorText:SetText(SelectorText(snapshot))
    row.noteText:SetText(snapshot.Notes or "")
    row.importedText:SetText(snapshot.ImportedAt and L["Imported X"]:format(date("%d %b %Y", snapshot.ImportedAt)) or "")

    SelectableRow:Paint(row, snapshot == ctx.GetSelected())
end
