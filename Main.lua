local addon = LibStub("Addon-1.0"):New(...)

-- Expose a narrow, dev-only import surface so the WowSync_TestSuite can reach the
-- shared widgets it builds its explorer from, without handing out the whole addon
-- table. Gated on the core dev-mode flag so it never ships in a release.
if WowSync.DevMode then
    WowSync_UI = {}

    local Exports = {
        Button = true,
        ScrollList = true,
        Splitter = true,
        Panel = true,
    }

    function WowSync_UI:Import(name)
        return WowSync:ImportFrom(addon, Exports, name)
    end
end

-- The contract checker shared by every WowSync_UI file, resolved from the core
-- addon so both run in the same mode.
addon.C = WowSync:Import("Contracts")

-- WowSync loads this addon on demand and fires WOWSYNC_UI_TOGGLED to
-- open or toggle the window.
WowSync:RegisterEvent("WOWSYNC_UI_TOGGLED", function()
    addon:GetObject("MainFrame"):Toggle()
end)
