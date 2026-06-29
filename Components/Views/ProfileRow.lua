local _, addon = ...

--[[
    ProfileRow object (row renderer).

    Row sub-contract for the pooled scroll-list elements in ProfileList. Maps a
    character (or realm header) onto the shared ListRow widget, which owns the
    frame skeleton and the selection behaviour. The list-level selection state is
    reached through an injected context.

    ctx = {
        GetSelected() -> profileName or nil,
        Select(profileName),
    }

    addon:GetObject("ProfileRow"):Build(row, ctx)
    addon:GetObject("ProfileRow"):Update(row, elementData, ctx)
]]

local ProfileRow = addon:NewObject("ProfileRow")
local ListRow = addon:GetObject("ListRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

local function FormatDate(timestamp)
    if not timestamp then return "" end
    return date("%b %d, %Y", timestamp)
end

function ProfileRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    ListRow:BuildSkeleton(row)
    ListRow:WireSelection(row, ctx)
end

function ProfileRow:Update(row, elementData, ctx)
    C:IsTable(row, 2)
    C:IsTable(elementData, 3)
    C:IsTable(ctx, 4)

    -- Realm header: just the realm name, with no selection behaviour.
    if elementData.kind == "realm" then
        ListRow:RenderHeader(row, elementData.realm or "")
        return
    end

    -- Info line: when the character was last seen (its setup last captured).
    local info = elementData.timestamp
        and L["Last seen: X"]:format(FormatDate(elementData.timestamp))
        or ""

    ListRow:RenderItem(row, {
        id = elementData.id,
        classID = elementData.classID,
        title = elementData.character or "",
        info = info,
    }, ctx)
end
