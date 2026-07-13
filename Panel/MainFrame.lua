local _, addon = ...

--[[
    MainFrame widget (the window shell and composition root).

    The top-level movable window: it IS the frame. Owns the backdrop, title bar,
    drag and escape handling, and a tab strip above the Profiles and Imports
    views (each a list + details pair sharing one split ratio). Builds and wires
    those panels in its Constructor, and the single instance is built lazily on
    the first Toggle().

    addon:GetObject("MainFrame"):Toggle()
]]

local MainFrame = addon:NewObject("MainFrame")

local L = addon.L
local Settings = addon.Settings
local UI = addon.UI

local CombatOverlay = addon:GetObject("CombatOverlay")
local ImportList = addon:GetObject("ImportList")
local ImportsTabFrame = addon:GetObject("ImportsTabFrame")
local Panel = addon:GetObject("Panel")
local ProfileList = addon:GetObject("ProfileList")
local ProfilesTabFrame = addon:GetObject("ProfilesTabFrame")
local Splitter = addon:GetObject("Splitter")
local TabStrip = addon:GetObject("TabStrip")
local TitleBar = addon:GetObject("TitleBar")

-- The single window instance, built lazily on the first Toggle.
local instance

-- The left panel may never exceed this share of the pane width, so the right
-- panel always keeps the majority.
local MAX_LEFT_PANEL_RATIO = 0.4

-- Default width of the left panel; the starting split ratio is derived from it.
local LEFT_PANEL_WIDTH = 220

-- Largest size the window may be resized to.
local MAX_FRAME_WIDTH = 1600
local MAX_FRAME_HEIGHT = 1100

-- Smallest width each panel may shrink to.
local MIN_LEFT_PANEL_WIDTH = 200
local MIN_RIGHT_PANEL_WIDTH = 600

-- Slack kept between the two panel minimums so the splitter always has room to
-- move, even at the smallest window.
local MIN_SPLIT_TRAVEL = 120

-- Heights of the title bar and the tab strip beneath it.
local TITLE_BAR_HEIGHT = TitleBar.HEIGHT
local TAB_STRIP_HEIGHT = 24

-- Inset between the frame edge and its content on every side.
local EDGE_INSET = 8

-- Colour escape applied to the window title.
local ACCENT_HEX = "ff40a5f7"

-- Clamp a left-panel width (in pixels) for a pane of the given width: neither
-- panel may drop below its minimum, and the left panel never passes
-- MAX_LEFT_PANEL_RATIO of the pane so the right panel keeps the majority.
local function ClampLeftWidth(leftWidth, viewWidth)
    local maxLeft = math.max(MIN_LEFT_PANEL_WIDTH,
        math.min(viewWidth - UI.Splitter.Width - MIN_RIGHT_PANEL_WIDTH,
            viewWidth * MAX_LEFT_PANEL_RATIO))
    return Clamp(leftWidth, MIN_LEFT_PANEL_WIDTH, maxLeft)
end

local Methods = {}

function Methods:Constructor(config)
    local panel = self

    -- The panes share one left/right split ratio; the lock state lives on the
    -- Panel.
    panel._panes = {}

    -- Resolve a guaranteed-valid set of frame bounds from the constants. The
    -- panel minimums are the only hard constraint; FrameWidth/FrameHeight and the
    -- MaxFrame* caps are treated as preferences and clamped into a feasible range.
    -- This keeps the UI valid for ANY combination of values in Constants.lua:
    -- nothing edited there can invert the resize bounds or starve a panel.
    local contentInset = EDGE_INSET * 2
    -- The minimum width carries both panel minimums plus a reserved band of travel
    -- so the splitter is never pinned even at the smallest window.
    local minFrameWidth = MIN_LEFT_PANEL_WIDTH + UI.Splitter.Width + MIN_RIGHT_PANEL_WIDTH
        + MIN_SPLIT_TRAVEL + contentInset
    local minFrameHeight = UI.Window.Height
    local maxFrameWidth = math.max(MAX_FRAME_WIDTH, minFrameWidth)
    local maxFrameHeight = math.max(MAX_FRAME_HEIGHT, minFrameHeight)
    local defaultFrameWidth = Clamp(UI.Window.Width, minFrameWidth, maxFrameWidth)
    local defaultFrameHeight = Clamp(UI.Window.Height, minFrameHeight, maxFrameHeight)

    local defaultContentWidth = defaultFrameWidth - contentInset
    panel._splitRatio = Settings:GetSplitRatio() or (LEFT_PANEL_WIDTH / defaultContentWidth)

    -- Apply the current split ratio to every view. Re-run whenever the window or
    -- the ratio changes.
    local function Reflow()
        for _, pane in ipairs(panel._panes) do
            local viewWidth = pane.view:GetWidth()
            if viewWidth and viewWidth > 0 then
                pane.leftSlot:SetWidth(ClampLeftWidth(panel._splitRatio * viewWidth, viewWidth))
            end
        end
    end

    -- Register a pane (a view with a left slot) and attach a draggable splitter
    -- to it. The splitter rewrites the shared split ratio and re-lays out every
    -- view; the change is persisted once the drag ends.
    local function AddPane(view, leftSlot)
        local pane = { view = view, leftSlot = leftSlot }
        pane.splitter = Splitter:Build(pane, {
            -- The splitter reports the raw cursor ratio; clamp it here, in the
            -- layout owner, so the stored ratio honours the panel minimums and
            -- the left-panel ceiling.
            onResize = function(ratio)
                local viewWidth = view:GetWidth()
                if viewWidth and viewWidth > 0 then
                    panel._splitRatio = ClampLeftWidth(ratio * viewWidth, viewWidth) / viewWidth
                end
                Reflow()
            end,
            onCommit = function()
                Settings:SetSplitRatio(panel._splitRatio)
            end,
        })
        -- Reflow whenever the view is first laid out (0 -> width), revealed, or
        -- resized with the window. A frame-level handler would miss the initial
        -- layout and the first reveal of the hidden view.
        view:SetScript("OnSizeChanged", Reflow)
        tinsert(panel._panes, pane)
    end

    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")

    -- The chrome is already in place (Panel applied it before this Constructor).
    -- Turn on the window's features; each reports back through Panel events, wired
    -- below. The lock toggle blocks moving, resizing, and the splitters.
    panel:EnableTitleBar({ title = "|c" .. ACCENT_HEX .. "WowSync|r" })
    panel:EnableLockButton({ locked = Settings:IsLocked() })
    panel:EnableMoving()
    panel:EnableResizing({
        minWidth = minFrameWidth, minHeight = minFrameHeight,
        maxWidth = maxFrameWidth, maxHeight = maxFrameHeight,
    })
    panel:EnableCloseOnEscape()

    -- Restore the persisted size and position; the first time the window opens
    -- it falls back to the default size, centred on screen. Clamp to the resolved
    -- bounds in case a saved size predates the current panel minimums.
    local savedWidth, savedHeight = Settings:GetWindowSize()

    panel:SetSize(
        Clamp(savedWidth, minFrameWidth, maxFrameWidth),
        Clamp(savedHeight, minFrameHeight, maxFrameHeight))

    local point, relativePoint, x, y = Settings:GetWindowAnchor()

    if point then
        panel:ClearAllPoints()
        panel:SetPoint(point, UIParent, relativePoint, x, y)
    else
        panel:SetPoint("CENTER")
    end

    -- While the window is open, ask the core to keep the live setup mirrored;
    -- release it on close so on-demand tracking can idle.
    panel:SetScript("OnShow", function()
        WowSync:Import("GameWatcher"):Attach("WowSync_UI")
        -- Attach captures the logged-in character's live setup; rebuild the list
        -- afterwards so a first open (empty store) still shows that character.
        panel._profileList:Refresh()
        -- Land on the logged-in character when the user hasn't picked one yet.
        panel._profileList:SelectCurrentWhenNone()
    end)

    panel:SetScript("OnHide", function()
        WowSync:Import("GameWatcher"):Detach("WowSync_UI")
        -- Close any open dialogs with the window so they don't linger over the world.
        addon:Broadcast("WOWSYNC_UI_CLOSED")
    end)

    -- Tab strip (Profiles, Imports)
    local tabStrip = TabStrip:Build(panel, {
        height = TAB_STRIP_HEIGHT,
        tabs = {
            { key = "profiles", label = L["Profiles"] },
            { key = "imports", label = L["Imports"] },
        },
        onSelect = function(viewKey) panel:ShowView(viewKey) end,
    })
    tabStrip:SetPoint("TOPLEFT", EDGE_INSET, -TITLE_BAR_HEIGHT)
    tabStrip:SetPoint("TOPRIGHT", -EDGE_INSET, -TITLE_BAR_HEIGHT)
    panel._tabStrip = tabStrip

    local contentTop = -(TITLE_BAR_HEIGHT + TAB_STRIP_HEIGHT)

    -- Profiles view: profile list (left) + profile details (right)
    local profilesView = CreateFrame("Frame", nil, panel)
    profilesView:SetPoint("TOPLEFT", EDGE_INSET, contentTop)
    profilesView:SetPoint("BOTTOMRIGHT", -EDGE_INSET, EDGE_INSET)

    local leftSlot = CreateFrame("Frame", nil, profilesView)
    leftSlot:SetPoint("TOPLEFT", 0, 0)
    leftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    leftSlot:SetWidth(LEFT_PANEL_WIDTH)

    local rightSlot = CreateFrame("Frame", nil, profilesView)
    rightSlot:SetPoint("TOPLEFT", leftSlot, "TOPRIGHT", UI.Splitter.Width, 0)
    rightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    panel._profileList = ProfileList:Build(leftSlot)
    panel._profileDetails = ProfilesTabFrame:Build(rightSlot)

    AddPane(profilesView, leftSlot)

    panel._profileList:OnSelect(function(profileName)
        panel._profileDetails:SetProfile(profileName)
    end)

    -- After a save the head collapses into a new snapshot; refresh the list and
    -- keep the saved character selected and in view.
    panel._profileDetails:OnSaved(function(charKey)
        panel._profileList:Refresh()
        panel._profileList:Select(charKey)
        panel._profileList:ScrollToProfile(charKey)
    end)

    panel._profilesView = profilesView

    -- Imports view: imported-container list (left) + import details (right)
    local importsView = CreateFrame("Frame", nil, panel)
    importsView:SetPoint("TOPLEFT", EDGE_INSET, contentTop)
    importsView:SetPoint("BOTTOMRIGHT", -EDGE_INSET, EDGE_INSET)

    local importLeftSlot = CreateFrame("Frame", nil, importsView)
    importLeftSlot:SetPoint("TOPLEFT", 0, 0)
    importLeftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    importLeftSlot:SetWidth(LEFT_PANEL_WIDTH)

    local importRightSlot = CreateFrame("Frame", nil, importsView)
    importRightSlot:SetPoint("TOPLEFT", importLeftSlot, "TOPRIGHT", UI.Splitter.Width, 0)
    importRightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    panel._importList = ImportList:Build(importLeftSlot)
    panel._importDetails = ImportsTabFrame:Build(importRightSlot)

    AddPane(importsView, importLeftSlot)

    panel._importList:OnSelect(function(importID)
        panel._importDetails:SetImport(importID)
    end)

    panel._importDetails:OnRefresh(function()
        panel._importList:Refresh()
    end)

    importsView:Hide()
    panel._importsView = importsView

    -- React to the panel's own chrome events. Only our window fires lock/resize
    -- (dialogs share the Panel object but never enable those), so filter to it and
    -- persist + re-lay-out here; the Panel already applied the lock to its own
    -- moving and resizing, so we only add the splitters.
    local function LockSplitters(locked)
        for _, pane in ipairs(panel._panes) do
            pane.splitter:SetLocked(locked)
        end
    end

    Panel:RegisterEvent("WOWSYNC_UI_PANEL_LOCK_CHANGED", function(_, _, firing, locked)
        if firing ~= panel then return end
        Settings:SetLocked(locked)
        LockSplitters(locked)
    end)

    Panel:RegisterEvent("WOWSYNC_UI_PANEL_MOVED", function(_, _, firing)
        if firing ~= panel then return end
        local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
        Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
    end)

    Panel:RegisterEvent("WOWSYNC_UI_PANEL_RESIZED", function(_, _, firing, width, height)
        if firing ~= panel then return end
        Settings:SetWindowSize(width, height)
        -- Sizing re-anchors the frame to its top-left corner; persist that so the
        -- window reopens where it was left rather than snapping back.
        local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
        Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
        Reflow()
    end)

    Panel:RegisterEvent("WOWSYNC_UI_PANEL_RESIZE_RESET", function(_, _, firing)
        if firing ~= panel then return end
        panel:SetSize(defaultFrameWidth, defaultFrameHeight)
        panel:ClearAllPoints()
        panel:SetPoint("CENTER")
        Settings:SetWindowSize(defaultFrameWidth, defaultFrameHeight)
        local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
        Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
        Reflow()
    end)

    -- Apply the persisted lock to the splitters (the Panel handled its own move
    -- and resize when the lock button was enabled).
    LockSplitters(Settings:IsLocked())
    Reflow()

    -- Modal scrim that blocks the window's contents while in combat, since
    -- saving and applying are off-limits then. It leaves the title bar usable so
    -- the window can still be moved and closed.
    CombatOverlay:Build(panel, { topInset = TITLE_BAR_HEIGHT })

    -- The frame starts shown; hide it so the first Toggle() reveals it instead
    -- of hiding it.
    panel:Hide()
end

-- Switch the active view and reflect it in the tab visuals. Both views share
-- the same split ratio (every pane is re-laid out together).
function Methods:ShowView(viewKey)
    if viewKey ~= "imports" then
        viewKey = "profiles"
    end
    if viewKey == "imports" then
        self._profilesView:Hide()
        self._importsView:Show()
        self._importList:Refresh()
    else
        self._importsView:Hide()
        self._profilesView:Show()
        self._profileList:Refresh()
    end
    self._tabStrip:Select(viewKey)
end

-- Flip the window's visibility, landing on the Profiles view when opening.
function Methods:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:ShowView("profiles")
        self:Show()
    end
end

-- Build the single window instance on first use; subsequent calls reuse it.
local function Build()
    if instance then return end

    instance = Panel:Build({
        name = "WowSyncUIFrame",
        methods = Methods,
    })
end

function MainFrame:Toggle()
    Build()
    instance:Toggle()
end
