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

-- Characters of the content hash shown in the selector label.
local HASH_PREFIX = 7

local Verbs = Mixin({}, SelectableRow.Verbs)

-- The user-facing selector for an imported snapshot: a short hash and index.
local function SelectorText(snapshot)
    return ("%s#%d"):format(snapshot.Hash:sub(1, HASH_PREFIX), snapshot.Index or 0)
end

function Verbs:Constructor(config)
    self._ctx = config.ctx

    self:Background()

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

    -- Right-aligned import time, bottom corner.
    self.importedText = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.importedText:SetPoint("BOTTOMRIGHT", -8, 6)
    self.importedText:SetJustifyH("RIGHT")
    self.importedText:SetWordWrap(false)

    -- Note, fills the bottom line up to the import time.
    self.noteText = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.noteText:SetPoint("BOTTOMLEFT", ROW_INSET, 6)
    self.noteText:SetPoint("RIGHT", self.importedText, "LEFT", -6, 0)
    self.noteText:SetJustifyH("LEFT")
    self.noteText:SetWordWrap(false)

    self:WireHover("snapshot")
    self:SetScript("OnMouseDown", function(row)
        if row.snapshot then
            row._ctx.Select(row.snapshot)
        end
    end)
    self:SetScript("OnMouseUp", function(row, button)
        if button == "RightButton" and row.snapshot and row._ctx.OpenMenu then
            row._ctx.Select(row.snapshot)
            row._ctx.OpenMenu(row.snapshot, row)
        end
    end)
end

function Verbs:Render(snapshot)
    self.snapshot = snapshot

    self.subjectText:SetText(SnapshotRow:FormatSubject(snapshot.Timestamp))
    self.selectorText:SetText(SelectorText(snapshot))
    self.noteText:SetText(snapshot.Notes or "")
    self.importedText:SetText(snapshot.ImportedAt and L["Imported X"]:format(date("%d %b %Y", snapshot.ImportedAt)) or "")

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
