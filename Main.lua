local addon = LibStub("Addon-1.0"):New(...)

-- Expose the UI addon table so the dev-only WowSync_TestSuite can reach the
-- dialogs it drives in its UI smoke tests -- but only in a developer build, gated
-- on the core addon's dev-mode flag so it never ships in a release.
if WowSync.DevMode then
    _G.WowSync_UI = addon
end

-- The contract checker shared by every WowSync_UI file, resolved from the core
-- addon so both run in the same mode.
addon.C = WowSync:Import("Contracts")

-- WowSync loads this addon on demand and fires WOWSYNC_UI_TOGGLED to
-- open or toggle the window.
WowSync:RegisterEvent("WOWSYNC_UI_TOGGLED", function()
    addon:GetObject("MainFrame"):Toggle()
end)

-- WowSync routes /ws import and /ws export here to open the matching share
-- dialog; action is "import" or "export".
WowSync:RegisterEvent("WOWSYNC_UI_OPEN_SHARE_DIALOG", function(_, _, action)
    addon:GetObject("MainFrame"):OpenShareDialog(action)
end)
