local addon = LibStub("Addon-1.0"):New(...)

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
