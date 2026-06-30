local _, addon = ...

--[[
    ProfileRow widget (row renderer).

    Row sub-contract for the pooled scroll-list elements in ProfileList. Maps a
    character (or realm header) onto the shared ListRow verbs, which own the
    frame skeleton and the selection behaviour. The list selection is reached
    through the context the row stores on self._ctx.

    ctx = {
        GetSelected() -> profileName or nil,
        Select(profileName),
    }

    addon:GetObject("ProfileRow"):Build(row, ctx)   -- adopts the pooled frame
        -> profile-row frame { Render(elementData) }
]]

local ProfileRow = addon:NewObject("ProfileRow")
local ListRow = addon:GetObject("ListRow")

local C = LibStub("Contracts-1.0")
local L = addon.L

local Verbs = Mixin({}, ListRow.Verbs)

local function FormatDate(timestamp)
    if not timestamp then return "" end
    return date("%b %d, %Y", timestamp)
end

function Verbs:Constructor(config)
    self._ctx = config.ctx
    self:BuildSkeleton()
    self:WireSelection()
end

function Verbs:Render(elementData)
    -- Realm header: just the realm name, with no selection behaviour.
    if elementData.kind == "realm" then
        self:RenderHeader(elementData.realm or "")
        return
    end

    -- Info line: when the character was last seen (its setup last captured).
    local info = elementData.timestamp
        and L["Last seen: X"]:format(FormatDate(elementData.timestamp))
        or ""

    self:RenderItem({
        id = elementData.id,
        classID = elementData.classID,
        title = elementData.character or "",
        info = info,
    })
end

function ProfileRow:Build(row, ctx)
    C:IsTable(row, 2)
    C:IsTable(ctx, 3)

    return addon:NewWidget({ ctx = ctx }, {
        frame = row,
        verbs = Verbs,
    })
end
