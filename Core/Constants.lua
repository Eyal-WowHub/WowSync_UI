local _, addon = ...

addon.UI = {
    -- Dimensions
    FrameWidth = 640,
    FrameHeight = 440,
    LeftPanelWidth = 220,
    TitleBarHeight = 28,
    ListItemHeight = 44,
    ListItemPadding = 2,
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

    -- Brand accent (used for the window title)
    AccentHex = "ff40a5f7",

    -- Backdrop colors { r, g, b, a }
    MainBackdropColor = { 0.08, 0.08, 0.08, 0.92 },
    MainBorderColor = { 0.5, 0.5, 0.5, 1 },
    PanelBackdropColor = { 0.05, 0.05, 0.05, 0.8 },
    PanelBorderColor = { 0.4, 0.4, 0.4, 0.8 },
    SeparatorColor = { 0.4, 0.4, 0.4, 0.6 },

    -- Profile row highlight colors
    RowSelectedColor = CreateColor(0.2, 0.4, 0.6, 0.6),
    RowHoverColor = CreateColor(0.3, 0.3, 0.3, 0.4),
    RowNormalColor = CreateColor(0, 0, 0, 0),

    -- Snapshot timeline colors
    TimelineRailColor = CreateColor(0.35, 0.35, 0.35, 0.8),
    TimelineNodeColor = CreateColor(0.6, 0.6, 0.6, 1),
    TimelineNodeLatestColor = CreateColor(0.25, 0.65, 0.95, 1),

    -- Status text colors { r, g, b, a }
    SuccessTextColor = { 0.3, 0.85, 0.3, 1 },
    WarningTextColor = { 0.95, 0.75, 0.2, 1 },
}
