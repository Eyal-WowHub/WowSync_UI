local _, addon = ...

addon.UI = {
    -- Dimensions
    FrameWidth = 800,
    FrameHeight = 600,
    LeftPanelWidth = 220,
    -- Window sizing. These are *preferences*: the layout engine treats the panel
    -- minimums (MinLeftPanelWidth + SplitterWidth + MinRightPanelWidth) as the one
    -- hard constraint and clamps everything else into a valid range, so editing any
    -- value here can never invert the resize bounds or starve a panel. If FrameWidth
    -- is below the panel minimums, the window opens at that derived minimum instead.
    MaxFrameWidth = 1600,
    MaxFrameHeight = 1100,
    MinLeftPanelWidth = 200,
    MinRightPanelWidth = 600,
    -- Slack reserved between the two panel minimums so the splitter always has room
    -- to move, even at the smallest allowed window. The minimum window width carries
    -- both panel minimums plus this band; widening the window adds more travel.
    MinSplitTravel = 120,
    SplitterWidth = 6,
    ResizeGripSize = 16,
    TitleBarHeight = 28,
    TabStripHeight = 24,
    ListItemHeight = 44,
    ListItemPadding = 2,
    RealmHeaderHeight = 20,
    ModuleRowHeight = 24,
    ModuleRowPadding = 2,
    PreviewWidth = 380,
    PreviewHeight = 360,
    SnapshotRowHeight = 40,
    SnapshotRowPadding = 2,
    TimelineRailX = 14,
    SnapshotNodeY = 16,           -- node center, below the row top (aligns with subject)
    SnapshotSubjectZone = 24,     -- top zone holding subject + tags when a row is expanded
    SnapshotDetailTopPad = 2,
    SnapshotDetailNoteHeight = 28,
    SnapshotDetailLineHeight = 15,
    SnapshotDetailBottomPad = 8,
    UndoRowHeight = 34,
    UndoRowPadding = 2,

    -- Brand accent (used for the window title)
    AccentHex = "ff40a5f7",

    -- Backdrop colors { r, g, b, a }
    MainBackdropColor = { 0.08, 0.08, 0.08, 0.92 },
    MainBorderColor = { 0.5, 0.5, 0.5, 1 },
    PanelBackdropColor = { 0.05, 0.05, 0.05, 0.8 },
    PanelBorderColor = { 0.4, 0.4, 0.4, 0.8 },
    SeparatorColor = { 0.4, 0.4, 0.4, 0.6 },

    -- Splitter handle between the left and right panels { r, g, b, a }
    SplitterColor = { 0.35, 0.35, 0.35, 0.7 },
    SplitterHoverColor = { 0.25, 0.65, 0.95, 0.9 },

    -- Profile row highlight colors
    RowSelectedColor = CreateColor(0.2, 0.4, 0.6, 0.6),
    RowHoverColor = CreateColor(0.3, 0.3, 0.3, 0.4),
    RowNormalColor = CreateColor(0, 0, 0, 0),

    -- Active tab underline accent
    TabUnderlineColor = CreateColor(0.25, 0.65, 0.95, 1),

    -- Realm header label in the grouped character list
    RealmHeaderColor = CreateColor(0.55, 0.7, 0.95, 1),

    -- Snapshot timeline colors
    TimelineRailColor = CreateColor(0.35, 0.35, 0.35, 0.8),
    TimelineNodeColor = CreateColor(0.6, 0.6, 0.6, 1),
    TimelineNodeLatestColor = CreateColor(0.25, 0.65, 0.95, 1),

    -- Status text colors { r, g, b, a }
    SuccessTextColor = { 0.3, 0.85, 0.3, 1 },
    WarningTextColor = { 0.95, 0.75, 0.2, 1 },
}
