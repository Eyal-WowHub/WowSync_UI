local addon = LibStub("Addon-1.0"):New(...)

-- All UI is built from Addon-1.0 objects (see Components/). MainFrame is the
-- composition root: it builds the panels and wires them together on first
-- Toggle(). This file only registers the addon and exposes the slash entry.
function WowSyncUI_Toggle()
    addon:GetObject("MainFrame"):Toggle()
end
