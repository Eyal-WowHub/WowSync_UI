local _, addon = ...
local L = {}
addon.L = L

-- Buttons and labels
L["Profiles"] = "Profiles"
L["Save"] = "Save"
L["Select a profile"] = "Select a profile"
L["Modules to apply:"] = "Modules to apply:"
L["Select All"] = "Select All"
L["Deselect All"] = "Deselect All"
L["Apply"] = "Apply"
L["Undo"] = "Undo"
L["Rename"] = "Rename"
L["Delete"] = "Delete"

-- Profile detail header
L["X • Y • Z"] = "%s  •  %s  •  %s"
L["Last applied: X"] = "Last applied: %s"

-- Snapshot timeline
L["(latest)"] = "(latest)"
L["(pinned)"] = "(pinned)"
L["Changes vs current setup:"] = "Changes vs current setup:"
L["Matches your current setup"] = "Matches your current setup"
L["X: +A ~C -R"] = "%s:  |cff5fcf5f+%d|r |cffd9c84a~%d|r |cffd96b6b-%d|r"

-- Print feedback
L["Profile 'X' saved."] = "Profile '%s' saved."
L["Profile 'X': nothing changed."] = "Profile '%s': nothing changed."
L["No modules selected."] = "No modules selected."
L["Nothing to apply."] = "Nothing to apply."
L["X: applied"] = "%s: applied"
L["X (Y)"] = "%s (%s)"
L["X: skipped - Y"] = "%s: skipped - %s"
L["Applied X modules"] = "Applied %d modules"
L["Applied X, skipped Y (see chat)"] = "Applied %d, skipped %d (see chat)"
L["cannot apply"] = "cannot apply"
L["Undid the last apply (X)."] = "Undid the last apply (%s)."
L["  X: restored"] = "  %s: restored"
L["Rename failed — name may already exist."] = "Rename failed — name may already exist."
L["unknown"] = "unknown"
L["Unknown"] = "Unknown"

-- Confirmation popups
L["Undo the last apply (X)?"] = "Undo the last apply (%s)?"
L["Delete profile 'X'?"] = "Delete profile '%s'?"
L["Rename profile 'X' to:"] = "Rename profile '%s' to:"
