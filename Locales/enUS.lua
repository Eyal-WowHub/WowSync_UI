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
L["Revert"] = "Revert"
L["Rename"] = "Rename"
L["Delete"] = "Delete"

-- Profile detail header
L["X • Y • Z"] = "%s  •  %s  •  %s"
L["Last applied: X (Y)"] = "Last applied: %s (%s)"

-- Print feedback
L["Profile 'X' saved."] = "Profile '%s' saved."
L["No modules selected."] = "No modules selected."
L["Nothing to apply."] = "Nothing to apply."
L["X: applied"] = "%s: applied"
L["X (Y)"] = "%s (%s)"
L["X: skipped - Y"] = "%s: skipped - %s"
L["Applied X modules"] = "Applied %d modules"
L["Applied X, skipped Y (see chat)"] = "Applied %d, skipped %d (see chat)"
L["cannot apply"] = "cannot apply"
L["Reverted changes from profile 'X':"] = "Reverted changes from profile '%s':"
L["  X: reverted"] = "  %s: reverted"
L["Rename failed — name may already exist."] = "Rename failed — name may already exist."
L["unknown"] = "unknown"
L["Unknown"] = "Unknown"

-- Confirmation popups
L["Revert all changes made by profile 'X'?"] = "Revert all changes made by profile '%s'?"
L["Delete profile 'X'?"] = "Delete profile '%s'?"
L["Rename profile 'X' to:"] = "Rename profile '%s' to:"
