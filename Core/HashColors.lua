local _, addon = ...
local HashColors = {}
addon.HashColors = HashColors

--[[
    HashColors — assigns each content hash a stable, distinct display colour.

    A hash is coloured while at least one snapshot references it and keeps that
    colour for as long as it does; every duplicate (same hash) resolves to the
    same colour, so a shared setup reads as one coloured group wherever it
    appears. A caller reference-counts a hash with Add/Remove so its palette slot
    is freed for reuse once the last copy is gone.

    Colours are drawn from a hue/saturation/brightness palette. When a new hash
    would land on a slot a different hash already holds, it is re-rolled a few
    times to a fresh slot before giving up and sharing, so distinct hashes stay
    visually apart well past the point a plain hash-to-hue mapping would repeat.

        HashColors.Add(hash)      -- claim a reference (assigns a colour on the first)
        HashColors.Remove(hash)   -- release a reference (frees the slot on the last)
        HashColors.GetRGB(hash)   -> r, g, b        colour for display
        HashColors.WrapHashInColorCode(hash) -> "|cffRRGGBB"  escape code for tinting text
]]

local floor = math.floor
local abs = math.abs

-- Rows sit on a dark, near-transparent background, so a colour must clear this
-- perceived-luminance floor to stay readable; darker results are lifted toward
-- white until they do.
local MIN_LUMINANCE = 0.5

-- Saturation and brightness bands the palette draws from alongside hue. Hue
-- alone offers only ~two dozen tints the eye can separate; varying saturation
-- and brightness as well widens the palette by an order of magnitude. Each band
-- stays vivid/bright enough to read on the row without turning neon or muddy.
local SATURATIONS = { 0.50, 0.68, 0.86 }
local VALUES = { 0.80, 0.90, 1.00 }

-- Distinct hues the palette spans; the whole palette is this times the
-- saturation and brightness bands.
local HUES = 360

-- Attempts a colliding hash is given before it gives up and shares the taken
-- colour: one initial pick plus three re-rolls. Four tries drive the collision
-- odds negligible for any realistic number of imports.
local MAX_ATTEMPTS = 4

-- Standard HSV->RGB (h in degrees, s/v in [0,1]); components come back in [0,1].
local function HSVToRGB(h, s, v)
    local c = v * s
    local x = c * (1 - abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

-- Rec. 601 perceived luminance, the yardstick for the contrast floor.
local function Luminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

-- Fold a string into a wide, well-mixed integer, kept within 2^24 so it stays
-- an exact integer.
local function Fold(text)
    local acc = 0
    for i = 1, #text do
        acc = (acc * 33 + text:byte(i)) % 16777216
    end
    return acc
end

-- The palette slot a string maps to: a hue plus a saturation and brightness
-- index, folded into one comparable key so two strings share a slot only when
-- all three channels match.
local function SlotFor(text)
    local acc = Fold(text)
    local hue = acc % HUES
    local satIndex = floor(acc / HUES) % #SATURATIONS
    local valIndex = floor(acc / (HUES * #SATURATIONS)) % #VALUES
    return (hue * #SATURATIONS + satIndex) * #VALUES + valIndex
end

-- The readable RGB for a palette slot, lifting anything below the contrast floor
-- toward white until it clears it.
local function SlotColor(slot)
    local valIndex = slot % #VALUES
    local satIndex = floor(slot / #VALUES) % #SATURATIONS
    local hue = floor(slot / (#VALUES * #SATURATIONS))

    local r, g, b = HSVToRGB(hue, SATURATIONS[satIndex + 1], VALUES[valIndex + 1])
    local lum = Luminance(r, g, b)
    if lum < MIN_LUMINANCE then
        local t = (MIN_LUMINANCE - lum) / (1 - lum)
        r = r + (1 - r) * t
        g = g + (1 - g) * t
        b = b + (1 - b) * t
    end
    return r, g, b
end

-- hash -> { r, g, b, slot, refs }, the colour assigned to a hash, its palette
-- slot, and how many callers currently reference it.
local assigned = {}
-- slot -> true for every palette slot already claimed, so a new hash re-rolls
-- off a slot a different hash already holds.
local claimed = {}

-- Ensure a colour exists for a hash and return its entry, picking the hash's
-- palette slot on first sight and re-rolling to a fresh one on the rare clash
-- with a different hash. Does not touch the reference count.
local function Assign(hash)
    local entry = assigned[hash]
    if entry then
        return entry
    end

    local slot = SlotFor(hash)
    local attempt = 1
    while claimed[slot] and attempt < MAX_ATTEMPTS do
        slot = SlotFor(hash .. ":" .. attempt)
        attempt = attempt + 1
    end
    claimed[slot] = true

    local r, g, b = SlotColor(slot)
    entry = { r = r, g = g, b = b, slot = slot, refs = 0 }
    assigned[hash] = entry
    return entry
end

-- Claim a reference to a hash's colour, assigning one on the first reference.
function HashColors.Add(hash)
    local entry = Assign(hash)
    entry.refs = entry.refs + 1
end

-- Release a reference to a hash's colour, freeing its palette slot for reuse
-- once the last reference is gone. A no-op for a hash that was never added.
function HashColors.Remove(hash)
    local entry = assigned[hash]
    if not entry then
        return
    end

    entry.refs = entry.refs - 1
    if entry.refs <= 0 then
        -- claimed is a plain set, not a count. In the rare case two hashes share
        -- a slot (all attempts collided), freeing it here while the other still
        -- holds it only nudges the future collision chance up a touch -- never a
        -- crash or a mislabel -- so it is not worth a per-slot count.
        claimed[entry.slot] = nil
        assigned[hash] = nil
    end
end

-- The display RGB for a hash, assigning a colour if one is not claimed yet.
function HashColors.GetRGB(hash)
    local entry = Assign(hash)
    return entry.r, entry.g, entry.b
end

-- The escape code that tints text in a hash's colour.
function HashColors.WrapHashInColorCode(hash)
    local r, g, b = HashColors.GetRGB(hash)
    return ("|cff%02x%02x%02x"):format(
        floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end
