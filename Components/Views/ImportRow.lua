local _, addon = ...

--[[
    ImportRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ImportList. Maps an
    imported container (or class header) onto the shared ListRow widget, adding an
    inline rename box on top. The list-level selection state is reached through an
    injected context.

    ctx = {
        GetSelected() -> importID or nil,
        Select(importID),
        Rename(importID, name) -> handled,
    }

    addon:GetObject("ImportRow"):Build(row, ctx)
    addon:GetObject("ImportRow"):Update(row, elementData, ctx)
]]

local ImportRow = addon:NewObject("ImportRow")
local ListRow = addon:GetObject("ListRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

-- Cap on an inline-renamed container name, matching the rename dialog.
local MAX_RENAME_LETTERS = 64

-- One-line snapshot-count label for a container's info line.
local function SnapshotCountText(count)
    if count == 1 then
        return L["1 snapshot"]
    end
    return L["X snapshots"]:format(count or 0)
end

-- Open the inline rename box over the name, seeded with the current name.
local function BeginRename(row)
    row.renameBox:SetText(row.name or "")
    row.renameBox:Show()
    row.renameBox:SetFocus()
    row.renameBox:HighlightText()
end

function ImportRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    C:Ensures(type(ctx.Rename) == "function", "Build: 'ctx.Rename' must be a function")

    ListRow:BuildSkeleton(row)

    -- Inline rename box, overlaid on the name and shown only while editing.
    row.renameBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.renameBox:SetAutoFocus(false)
    row.renameBox:SetMaxLetters(MAX_RENAME_LETTERS)
    row.renameBox:SetPoint("TOPLEFT", row.nameText, "TOPLEFT", 0, 4)
    row.renameBox:SetPoint("BOTTOMRIGHT", row.nameText, "BOTTOMRIGHT", 0, -4)
    row.renameBox:Hide()
    row.renameBox:SetScript("OnEscapePressed", function(self) self:Hide() end)
    row.renameBox:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    row.renameBox:SetScript("OnEnterPressed", function(self)
        local importID = row.id
        local name = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        self:Hide()
        if importID and name ~= "" then
            ctx.Rename(importID, name)
        end
    end)

    -- A double-click on a container row opens its inline rename.
    ListRow:WireSelection(row, ctx, BeginRename)
end

function ImportRow:Update(row, elementData, ctx)
    C:IsTable(row, 2)
    C:IsTable(elementData, 3)
    C:IsTable(ctx, 4)

    -- Class header: just the class name, with no selection behaviour.
    if elementData.kind == "class" then
        row.renameBox:Hide()
        ListRow:RenderHeader(row, ListRow:ClassHeaderText(elementData.classID))
        return
    end

    row.name = elementData.name or ""
    row.renameBox:Hide()
    row.lastClick = nil

    ListRow:RenderItem(row, {
        id = elementData.id,
        classID = elementData.classID,
        title = row.name,
        info = SnapshotCountText(elementData.snapshotCount),
    }, ctx)
end
