local _, addon = ...

local NOTES_COLOR = CreateColor(0.62, 0.80, 1.00, 1)            -- a user-written note, soft blue
local NOTES_HEADER_COLOR = CreateColor(0.52, 0.62, 0.78, 1)     -- a detail section header

-- Constants kept here for one of two reasons: they are shared by more than one
-- component, or they are preferences the user may safely adjust. Values that are
-- internal to a single component live as named locals in that component's file.
-- Grouped by concept.
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

    -- Frame backdrop fills, borders, and divider lines { r, g, b, a }.
    Backdrop = {
        Main = { 0.08, 0.08, 0.08, 0.92 },
        MainBorder = { 0.22, 0.22, 0.24, 1 },
        Panel = { 0.05, 0.05, 0.05, 0.8 },
        PanelBorder = { 0.4, 0.4, 0.4, 0.8 },
        Separator = { 0.4, 0.4, 0.4, 0.6 },
    },

    -- Background states shared by every selectable list/tab row.
    Row = {
        Selected = CreateColor(0.2, 0.4, 0.6, 0.6),
        Hover = CreateColor(0.3, 0.3, 0.3, 0.4),
        Normal = CreateColor(0, 0, 0, 0),

        -- Decorated selection, opted into by the snapshot rows: a bright left
        -- accent bar, a gentle left-to-right gradient fill, and thin edge lines
        -- so a selected row reads as a panel opening rather than a flat block.
        Accent = CreateColor(0.30, 0.62, 0.95, 1),
        AccentWidth = 3,
        SelectedGradientLeft = CreateColor(0.30, 0.54, 0.80, 0.82),
        SelectedGradientRight = CreateColor(0.30, 0.54, 0.80, 0.32),
        SelectedEdge = CreateColor(0.35, 0.62, 0.95, 0.55),

        -- Hover echoes the selected gradient in the same hue but dimmer,
        -- so pointing at an unselected row previews the selection look.
        HoverGradientLeft = CreateColor(0.30, 0.54, 0.80, 0.55),
        HoverGradientRight = CreateColor(0.30, 0.54, 0.80, 0.18),
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
