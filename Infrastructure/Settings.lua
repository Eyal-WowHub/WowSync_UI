local _, addon = ...

local UI = addon.UI

--[[
    Settings object.

    Persistent, typed access to the user-adjustable window layout state (size,
    position, splitter ratio, lock). Storage is backed by AceDB-3.0 (shared with
    the parent WowSync addon, reachable through the global LibStub since WowSync
    is a required dependency and loads first). Profiles are per-character: the
    default profile is the current character, so each character keeps its own
    window layout.

    Each piece of state has its own accessor so callers work in domain terms
    instead of poking the raw profile table, and so layout defaults live in one
    place. The database is created lazily on first access.

    addon.Settings:GetWindowSize()   -> width, height
    addon.Settings:SetWindowSize(width, height)
    addon.Settings:GetWindowAnchor() -> point, relativePoint, x, y | nil
    addon.Settings:SetWindowAnchor(point, relativePoint, x, y)
    addon.Settings:GetSplitRatio()   -> ratio | nil
    addon.Settings:SetSplitRatio(ratio)
    addon.Settings:IsLocked()        -> boolean
    addon.Settings:SetLocked(locked)
]]

-- AceDB fills these in via a metatable until the user overrides them. Keys that
-- should stay nil until first set (anchor, splitRatio) are intentionally absent.
local DEFAULTS = {
    profile = {
        frameWidth = UI.Window.Width,
        frameHeight = UI.Window.Height,
        locked = false,
    },
}

local Settings = {}
addon.Settings = Settings

local database

-- The active per-character profile table. Created on first access; safe to call
-- after the addon loads because its saved variable is loaded by then.
local function Profile()
    if not database then
        -- The third argument (true) selects the current character as the default
        -- profile, giving each character its own layout out of the box.
        database = LibStub("AceDB-3.0"):New("WowSyncUIDB", DEFAULTS, true)
    end
    return database.profile
end

-- Window size; AceDB supplies the default frame size before the first resize.
function Settings:GetWindowSize()
    local profile = Profile()
    return profile.frameWidth, profile.frameHeight
end

function Settings:SetWindowSize(width, height)
    local profile = Profile()
    profile.frameWidth = width
    profile.frameHeight = height
end

-- Window anchor; returns nil until the window has been moved, so the caller can
-- centre it on first open instead of restoring a position.
function Settings:GetWindowAnchor()
    local anchor = Profile().anchor
    if not anchor then
        return nil
    end
    return anchor.point, anchor.relativePoint, anchor.x, anchor.y
end

function Settings:SetWindowAnchor(point, relativePoint, x, y)
    Profile().anchor = { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- Splitter ratio (left panel fraction of the content width); nil until the user
-- drags the splitter, letting the caller supply its own layout-derived default.
function Settings:GetSplitRatio()
    return Profile().splitRatio
end

function Settings:SetSplitRatio(ratio)
    Profile().splitRatio = ratio
end

-- Lock state: when locked the window cannot be moved, resized, or split.
function Settings:IsLocked()
    return Profile().locked == true
end

function Settings:SetLocked(locked)
    Profile().locked = locked and true or false
end
