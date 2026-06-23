local _, addon = ...

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

    -- Geometry of a snapshot row's expanded detail block, shared by the row that
    -- draws it and the list that measures its height.
    SnapshotDetail = {
        SubjectZone = 24,    -- top zone holding the subject and tags
        TopPad = 2,
        NoteHeight = 28,
    },

    -- Frame backdrop fills, borders, and divider lines { r, g, b, a }.
    Backdrop = {
        Main = { 0.08, 0.08, 0.08, 0.92 },
        MainBorder = { 0.5, 0.5, 0.5, 1 },
        Header = { 0.13, 0.13, 0.15, 0.95 },
        Panel = { 0.05, 0.05, 0.05, 0.8 },
        PanelBorder = { 0.4, 0.4, 0.4, 0.8 },
        Separator = { 0.4, 0.4, 0.4, 0.6 },
    },

    -- Background states shared by every selectable list/tab row.
    Row = {
        Selected = CreateColor(0.2, 0.4, 0.6, 0.6),
        Hover = CreateColor(0.3, 0.3, 0.3, 0.4),
        Normal = CreateColor(0, 0, 0, 0),
    },
}
