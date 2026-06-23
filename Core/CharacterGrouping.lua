local _, addon = ...

--[[
    CharacterGrouping (ordering policy).

    Single source of truth for how the other-character list is ordered and
    grouped at the UI level. Storage stays flat ("Name - Realm" keys); this
    helper only decides presentation, so any surface that lists characters
    (the side list, a future dropdown, ...) shares the same ordering.

    Group(characters) takes the flat array returned by
    ProfileManager:GetOtherCharacters() -- entries of the form
        { Key = "Name - Realm", ClassID = number?, LastSeen = number? }
    and returns:

        sections -> array of {
            Realm       = "Argent Dawn",
            IsOwnRealm  = boolean,            -- matches the logged-in realm
            Characters  = { entry, ... },     -- alphabetical by name
        }
        grouped  -> boolean (true when more than one realm is present)

    Ordering: the logged-in character's own realm is pinned first, remaining
    realms are alphabetical, and characters within a realm are alphabetical by
    name. Each entry is annotated in place with parsed Name and Realm fields so
    renderers can show a stripped name without re-parsing the key.

    addon.CharacterGrouping:Group(characters) -> sections, grouped
]]

local CharacterGrouping = {}
addon.CharacterGrouping = CharacterGrouping

-- Keys are "Name - Realm". Character names never contain " - ", so a lazy
-- match on the first separator splits the name from a realm that may itself
-- contain hyphens (e.g. "Azjol-Nerub").
local function SplitKey(key)
    local name, realm = key:match("^(.-) %- (.+)$")
    if not name then
        return key, ""
    end
    return name, realm
end

function CharacterGrouping:Group(characters)
    local ownRealm = GetRealmName()

    local byRealm = {}
    local order = {}

    for _, entry in ipairs(characters) do
        local name, realm = SplitKey(entry.Key)
        entry.Name = name
        entry.Realm = realm

        local section = byRealm[realm]
        if not section then
            section = {
                Realm = realm,
                IsOwnRealm = (realm == ownRealm),
                Characters = {},
            }
            byRealm[realm] = section
            order[#order + 1] = section
        end

        section.Characters[#section.Characters + 1] = entry
    end

    -- Characters within a realm: alphabetical by name.
    for _, section in ipairs(order) do
        table.sort(section.Characters, function(a, b)
            return a.Name:lower() < b.Name:lower()
        end)
    end

    -- Sections: own realm first, then alphabetical by realm.
    table.sort(order, function(a, b)
        if a.IsOwnRealm ~= b.IsOwnRealm then
            return a.IsOwnRealm
        end
        return a.Realm:lower() < b.Realm:lower()
    end)

    return order, (#order > 1)
end
