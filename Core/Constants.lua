local _, addon = ...

local NOTES_COLOR = CreateColor(0.62, 0.80, 1.00, 1)            -- a user-written note, soft blue
local NOTES_HEADER_COLOR = CreateColor(0.52, 0.62, 0.78, 1)     -- a detail section header

-- Shared and user-tunable UI constants, grouped by concept.
addon.UI = {
    -- Default window size, used to seed the saved layout and as the centred
    -- starting size. A user-tunable preference; the layout engine clamps it into
    -- a valid range, so changing it cannot break the window.
    Window = {
        Width = 800,
        Height = 600,
    },

    -- Width of the handle dividing the left and right panels, and the matching gap
    -- left for it in the layout.
    Splitter = {
        Width = 6,
    },

    -- Row metrics for the profile and character lists.
    List = {
        ItemHeight = 44,
        ItemPadding = 2,
    },

    -- Row metrics for the module checklists (module list, character details,
    -- and the save dialog).
    ModuleRow = {
        Height = 24,
        Padding = 2,
    },

    -- Default size for the preview dialogs.
    Preview = {
        Width = 380,
        Height = 360,
    },

    -- Frame backdrop fills, borders, and divider lines { r, g, b, a }. Tuned to
    -- WoW's flat Settings panel so inner panels sit under the NineSlice chrome
    -- without a colour seam.
    Backdrop = {
        Main = { 0.05, 0.05, 0.06, 0.92 },
        MainBorder = { 0.22, 0.22, 0.24, 1 },
        Panel = { 0.05, 0.05, 0.06, 0.8 },
        PanelBorder = { 0.4, 0.4, 0.4, 0.8 },
        Separator = { 0.4, 0.4, 0.4, 0.6 },
    },

    -- Flat selection states shared by every selectable list/tab row, matching
    -- WoW's Settings list: a white a=0.1 hover and a subtle blue selection fill.
    Row = {
        Selected = CreateColor(0.20, 0.40, 0.62, 0.5),
        Hover = CreateColor(1, 1, 1, 0.1),
        Normal = CreateColor(0, 0, 0, 0),
    },

    -- Snapshot annotation colours, shared by the profile and import rows so a
    -- note and a section header read the same wherever they appear.
    Note = {
        Color = NOTES_COLOR,
        HeaderColor = NOTES_HEADER_COLOR,
    },

    -- Named text styles (font object + colour) for the stacked row content. A row
    -- describes a line with a style name; ExpandableContent applies it. The note
    -- styles reuse the file-local note colours so they stay in sync with Note above.
    LineStyles = {
        Subject = { font = GameFontNormal, color = NORMAL_FONT_COLOR },           -- the row's title line
        Label = { font = GameFontDisableSmall, color = DISABLED_FONT_COLOR },     -- a short right-aligned label
        Note = { font = GameFontHighlightSmall, color = NOTES_COLOR },            -- a user-written note
        Header = { font = GameFontDisableSmall, color = NOTES_HEADER_COLOR },     -- a detail section header
        Body = { font = GameFontHighlightSmall, color = HIGHLIGHT_FONT_COLOR },   -- a list or change summary
    }
}
