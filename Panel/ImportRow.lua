local _, addon = ...

--[[
    ImportRow widget (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportList. Maps an
    imported container (or class header) onto the shared ListRow methods, adding an
    inline rename box on top. The list selection is reached through the context
    the row stores on self._ctx.

    ctx = {
        GetSelected() -> importID or nil,
        Select(importID),
        Rename(importID, name) -> handled,
        MoveUp(importID),       -- move the container up within its class group
        MoveDown(importID),     -- move the container down within its class group
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

local Methods = Mixin({}, ListRow.Methods)

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

-- Build the two stacked reorder arrows on the row's right edge. They are hidden
-- until the row is hovered or selected, and only ever shown for a container
-- whose class group holds more than one member (see UpdateReorder).
local function BuildReorderArrows(row)
    row.moveUp = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
    row.moveUp:SetPoint("BOTTOMRIGHT", row, "RIGHT", -6, 1)
    row.moveUp:Hide()
    row.moveUp:SetScript("OnClick", function()
        if row.id and row._ctx.MoveUp then
            row._ctx.MoveUp(row.id)
        end
    end)

    row.moveDown = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
    row.moveDown:SetPoint("TOPRIGHT", row, "RIGHT", -6, -1)
    row.moveDown:Hide()
    row.moveDown:SetScript("OnClick", function()
        if row.id and row._ctx.MoveDown then
            row._ctx.MoveDown(row.id)
        end
    end)

    -- Leaving an arrow keeps the reveal active while the cursor is still over the
    -- row, so moving between the two arrows (or arrow and row) does not flicker.
    local function OnArrowEnter()
        row._hovering = true
        row:UpdateReorder()
        row:ApplyHoverState("id")
    end
    local function OnArrowLeave()
        if not row:IsMouseOver() then
            row._hovering = false
        end
        row:UpdateReorder()
        row:ApplyHoverState("id")
    end
    row.moveUp:HookScript("OnEnter", OnArrowEnter)
    row.moveDown:HookScript("OnEnter", OnArrowEnter)
    row.moveUp:SetScript("OnLeave", OnArrowLeave)
    row.moveDown:SetScript("OnLeave", OnArrowLeave)
end

function Methods:Constructor(config)
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

    -- Reorder arrows and the hover tracking that reveals them.
    self._hovering = false
    BuildReorderArrows(self)
    self:HookScript("OnEnter", function(row)
        row._hovering = true
        row:UpdateReorder()
    end)
    self:HookScript("OnLeave", function(row)
        if not row:IsMouseOver() then
            row._hovering = false
        end
        row:UpdateReorder()
        row:ApplyHoverState("id")
    end)
end

-- Reveal the reorder arrows when the row is a reorderable container that is
-- hovered or selected, disabling whichever arrow sits at a group boundary so the
-- row's width stays stable.
function Methods:UpdateReorder()
    local reveal = self._canReorder
        and (self._hovering or (self.id ~= nil and self.id == self._ctx.GetSelected()))
    self.moveUp:SetShown(reveal)
    self.moveDown:SetShown(reveal)
    if reveal then
        self.moveUp:SetEnabled(self._canMoveUp)
        self.moveDown:SetEnabled(self._canMoveDown)
    end
end

-- Hide the reorder arrows outright, used for class headers.
function Methods:HideReorder()
    self._canReorder = false
    self.moveUp:Hide()
    self.moveDown:Hide()
end

-- Paint the selection state and refresh the reorder arrows, which follow the
-- selection as well as hover.
function Methods:Paint(isSelected)
    ListRow.Methods.Paint(self, isSelected)
    self:UpdateReorder()
end

function Methods:Render(elementData)
    -- Class header: just the class name, with no selection behaviour.
    if elementData.kind == "class" then
        self.renameBox:Hide()
        self:HideReorder()
        self:RenderHeader(self:ClassHeaderText(elementData.classID))
        return
    end

    self.name = elementData.name or ""
    self.renameBox:Hide()
    self.lastClick = nil
    self._canReorder = elementData.canReorder == true
    self._canMoveUp = elementData.canMoveUp == true
    self._canMoveDown = elementData.canMoveDown == true

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
        methods = Methods,
    })
end
