local _, addon = ...

--[[
    ImportRow widget (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportList. Maps an
    imported container (or class header) onto the shared ListRow verbs, adding an
    inline rename box on top. The list selection is reached through the context
    the row stores on self._ctx.

    ctx = {
        GetSelected() -> importID or nil,
        Select(importID),
        Rename(importID, name) -> handled,
    }

    addon:GetObject("ImportRow"):Build(row, ctx)    -- adopts the pooled frame
        -> import-row frame { Render(elementData) }
]]

local ImportRow = addon:NewObject("ImportRow")
local ListRow = addon:GetObject("ListRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Cap on an inline-renamed container name, matching the rename dialog.
local MAX_RENAME_LETTERS = 64

local Verbs = Mixin({}, ListRow.Verbs)

-- One-line snapshot-count label for a container's info line.
local function SnapshotCountText(count)
    if count == 1 then
        return L["1 snapshot"]
    end
    return L["X snapshots"]:format(count or 0)
end

-- Open the inline rename box over the name, seeded with the current name. The
-- label is hidden while editing so it does not show through the (transparent)
-- edit box behind the typed text.
local function BeginRename(row)
    row.nameText:Hide()
    row.renameBox:SetText(row.name or "")
    row.renameBox:Show()
    row.renameBox:SetFocus()
    row.renameBox:HighlightText()
end

function Verbs:Constructor(config)
    self._ctx = config.ctx
    self:BuildSkeleton()

    -- Inline rename box, overlaid on the name and shown only while editing.
    self.renameBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
    self.renameBox:SetAutoFocus(false)
    self.renameBox:SetMaxLetters(MAX_RENAME_LETTERS)
    self.renameBox:SetPoint("TOPLEFT", self.nameText, "TOPLEFT", 0, 4)
    self.renameBox:SetPoint("BOTTOMRIGHT", self.nameText, "BOTTOMRIGHT", 0, -4)
    self.renameBox:Hide()
    -- Restore the label whenever the box closes (escape, focus loss, commit, or
    -- the row being recycled) so it is never left hidden.
    self.renameBox:SetScript("OnHide", function() self.nameText:Show() end)
    self.renameBox:SetScript("OnEscapePressed", function(box) box:Hide() end)
    self.renameBox:SetScript("OnEditFocusLost", function(box) box:Hide() end)
    self.renameBox:SetScript("OnEnterPressed", function(box)
        local importID = self.id
        local name = box:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        box:Hide()
        if importID and name ~= "" then
            self._ctx.Rename(importID, name)
        end
    end)

    -- A double-click on a container row opens its inline rename.
    self:WireSelection(BeginRename)
end

function Verbs:Render(elementData)
    -- Class header: just the class name, with no selection behaviour.
    if elementData.kind == "class" then
        self.renameBox:Hide()
        self:RenderHeader(self:ClassHeaderText(elementData.classID))
        return
    end

    self.name = elementData.name or ""
    self.renameBox:Hide()
    self.lastClick = nil

    self:RenderItem({
        id = elementData.id,
        classID = elementData.classID,
        title = self.name,
        info = SnapshotCountText(elementData.snapshotCount),
    })
end

function ImportRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)
    C:Ensures(type(ctx.Rename) == "function", "Build: 'ctx.Rename' must be a function")

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        verbs = Verbs,
    })
end
