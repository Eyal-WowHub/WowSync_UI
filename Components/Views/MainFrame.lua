local _, addon = ...

--[[
    MainFrame widget (the window shell and composition root).

    The top-level movable window: it IS the frame. Owns the backdrop, title bar,
    drag and escape handling, and a tab strip above the Profiles and Imports
    views (each a list + details pair sharing one split ratio). Builds and wires
    those panels in its Constructor, and the single instance is built lazily on
    the first Toggle().

    addon:GetObject("MainFrame"):Toggle()
    addon:GetObject("MainFrame"):OpenShareDialog(action)
]]

local MainFrame = addon:NewObject("MainFrame")
local TitleBar = addon:GetObject("TitleBar")
local TabStrip = addon:GetObject("TabStrip")
local ProfileList = addon:GetObject("ProfileList")
local ProfileDetails = addon:GetObject("ProfileDetails")
local ImportList = addon:GetObject("ImportList")
local ImportDetails = addon:GetObject("ImportDetails")
local Splitter = addon:GetObject("Splitter")
local ResizeGrip = addon:GetObject("ResizeGrip")
local CombatOverlay = addon:GetObject("CombatOverlay")

local L = addon.L
local UI = addon.UI
local Settings = addon.Settings

-- The single window instance, built lazily on the first Toggle/OpenShareDialog.
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
local TITLE_BAR_HEIGHT = 28
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

local Verbs = {}

function Verbs:Constructor(config)
    local panel = self

    -- Layout state shared across the panes: the same left/right split ratio and
    -- the same lock state.
    panel._panes = {}
    panel._locked = false

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
    local resizeGrip
    local setLocked

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

    -- A crisp 1px edge (rather than the soft, beige tooltip border) matches the
    -- flat banner and bevelled divider in the title bar. It also removes the 16px
    -- corner art that used to peek over the banner where the two met.
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(unpack(UI.Backdrop.Main))
    panel:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))
    panel:SetMovable(true)
    panel:SetResizable(true)
    panel:SetResizeBounds(minFrameWidth, minFrameHeight, maxFrameWidth, maxFrameHeight)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:RegisterForDrag("LeftButton")

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

    panel:SetScript("OnDragStart", function()
        if not panel._locked then
            panel:StartMoving()
        end
    end)

    panel:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
        Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
    end)

    -- While the window is open, ask the core to keep the live setup mirrored;
    -- release it on close so on-demand tracking can idle.
    panel:SetScript("OnShow", function()
        WowSync:Attach("WowSync_UI")
        -- Attach captures the logged-in character's live setup; rebuild the list
        -- afterwards so a first open (empty store) still shows that character.
        panel._profileList:Refresh()
        -- Land on the logged-in character when the user hasn't picked one yet.
        panel._profileList:SelectCurrentWhenNone()
    end)

    panel:SetScript("OnHide", function()
        WowSync:Detach("WowSync_UI")
        -- Close any open dialogs with the window so they don't linger over the world.
        addon:Broadcast("WOWSYNC_UI_CLOSED")
    end)

    -- Registering with UISpecialFrames makes ESC close the window.
    tinsert(UISpecialFrames, "WowSyncUIFrame")

    -- Title bar region
    local titleSlot = CreateFrame("Frame", nil, panel)
    titleSlot:SetPoint("TOPLEFT", 0, 0)
    titleSlot:SetPoint("TOPRIGHT", 0, 0)
    titleSlot:SetHeight(TITLE_BAR_HEIGHT)
    local titleBar = TitleBar:Build(titleSlot, {
        title = "|c" .. ACCENT_HEX .. "WowSync|r",
        onClose = function() panel:Hide() end,
        onToggleLock = function(value) setLocked(value) end,
    })

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
    panel._profileDetails = ProfileDetails:Build(rightSlot)

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
    panel._importDetails = ImportDetails:Build(importRightSlot)

    AddPane(importsView, importLeftSlot)

    panel._importList:OnSelect(function(importID)
        panel._importDetails:SetImport(importID)
    end)

    panel._importDetails:OnRefresh(function()
        panel._importList:Refresh()
    end)

    importsView:Hide()
    panel._importsView = importsView

    -- Resize grip in the bottom-right corner; hidden while the window is locked.
    resizeGrip = ResizeGrip:Build(panel, {
        onResizeStop = function(width, height)
            Settings:SetWindowSize(width, height)
            -- Sizing re-anchors the frame to its top-left corner; persist that so
            -- the window reopens where it was left rather than snapping back.
            local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
            Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
            Reflow()
        end,
        -- Double-click restores the default size and re-centres the window.
        onReset = function()
            panel:SetSize(defaultFrameWidth, defaultFrameHeight)
            panel:ClearAllPoints()
            panel:SetPoint("CENTER")
            Settings:SetWindowSize(defaultFrameWidth, defaultFrameHeight)
            local anchorPoint, _, anchorRelative, anchorX, anchorY = panel:GetPoint()
            Settings:SetWindowAnchor(anchorPoint, anchorRelative, anchorX, anchorY)
            Reflow()
        end,
    })

    -- Lock toggle: blocks moving, resizing, and splitter dragging, and hides the
    -- resize grip. Persisted so the choice survives reloads.
    setLocked = function(value)
        panel._locked = value and true or false
        Settings:SetLocked(panel._locked)
        resizeGrip:SetLocked(panel._locked)
        for _, pane in ipairs(panel._panes) do
            pane.splitter:SetLocked(panel._locked)
        end
        titleBar:SetLocked(panel._locked)
    end

    setLocked(Settings:IsLocked())
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
function Verbs:ShowView(viewKey)
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
function Verbs:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:ShowView("profiles")
        self:Show()
    end
end

-- Open the window for a share action: "import" lands on the Imports tab and
-- opens the import dialog; any other action opens the profile share flow.
function Verbs:OpenShare(action)
    if action == "import" then
        self:ShowView("imports")
    else
        self:ShowView("profiles")
    end

    if not self:IsShown() then
        self:Show()
    end

    if action == "import" then
        self._importList:BeginImport()
    else
        self._profileDetails:ShareSelected()
    end
end

-- Build the single window instance on first use; subsequent calls reuse it.
local function Build()
    if instance then return end

    instance = addon:NewWidget({ parent = UIParent }, {
        frameType = "Frame",
        name = "WowSyncUIFrame",
        template = "BackdropTemplate",
        verbs = Verbs,
    })
end

function MainFrame:Toggle()
    Build()
    instance:Toggle()
end

-- Opens the window for a share action: "import" lands on the Imports tab and
-- opens the import dialog; any other action just opens the window.
function MainFrame:OpenShareDialog(action)
    Build()
    instance:OpenShare(action)
end
