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
}
