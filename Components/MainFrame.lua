local _, addon = ...

--[[
    MainFrame object.

    The top-level movable window shell and composition root. Owns the backdrop,
    title bar, drag and escape handling, and a tab strip that switches between
    two top-level views: Profiles (ProfileList + ProfileDetails) and Characters
    (CharacterList + CharacterDetails). Builds and wires those panels, and is
    built lazily on the first Toggle().

    addon:GetObject("MainFrame"):Toggle()
]]

local MainFrame = addon:NewObject("MainFrame")
local TitleBar = addon:GetObject("TitleBar")
local ProfileList = addon:GetObject("ProfileList")
local ProfileDetails = addon:GetObject("ProfileDetails")
local CharacterList = addon:GetObject("CharacterList")
local CharacterDetails = addon:GetObject("CharacterDetails")
local SaveDialog = addon:GetObject("SaveDialog")
local Splitter = addon:GetObject("Splitter")
local ResizeGrip = addon:GetObject("ResizeGrip")

local L = addon.L
local UI = addon.UI
local Settings = addon.Settings

local frame
local profileList, profileDetails
local characterList, characterDetails
local showView

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

-- Tab strip metrics.
local TAB_WIDTH = 110
local TAB_GAP = 4
local TAB_UNDERLINE_INSET = 0
local TAB_UNDERLINE_THICKNESS = 2

-- Colour escape applied to the window title.
local ACCENT_HEX = "ff40a5f7"

-- Underline drawn beneath the active tab.
local TAB_UNDERLINE_COLOR = CreateColor(0.25, 0.65, 0.95, 1)

-- A slim tab that switches the active top-level view. Active tabs show an accent
-- underline and a highlighted background; inactive tabs are dimmed.
local function CreateTab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(TAB_WIDTH, TAB_STRIP_HEIGHT)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(UI.Row.Normal:GetRGBA())

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(label)

    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetPoint("BOTTOMLEFT", TAB_UNDERLINE_INSET, 0)
    tab.underline:SetPoint("BOTTOMRIGHT", -TAB_UNDERLINE_INSET, 0)
    tab.underline:SetHeight(TAB_UNDERLINE_THICKNESS)
    tab.underline:SetColorTexture(TAB_UNDERLINE_COLOR:GetRGBA())
    tab.underline:Hide()

    tab.active = false

    function tab:SetActive(active)
        self.active = active
        self.underline:SetShown(active)
        self.text:SetFontObject(active and "GameFontNormal" or "GameFontDisable")
        self.bg:SetColorTexture((active and UI.Row.Selected or UI.Row.Normal):GetRGBA())
    end

    tab:SetScript("OnEnter", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.Row.Hover:GetRGBA())
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.active then
            self.bg:SetColorTexture(UI.Row.Normal:GetRGBA())
        end
    end)
    tab:SetScript("OnClick", onClick)

    return tab
end

local function Build()
    if frame then return end

    -- Layout state shared by both top-level views (Profiles and Characters):
    -- they use the same left/right split ratio and the same lock state.
    local panes = {}
    local locked = false

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
    local splitRatio = Settings:GetSplitRatio() or (LEFT_PANEL_WIDTH / defaultContentWidth)
    local resizeGrip
    local setLocked

    -- Clamp a left-panel width (in pixels) for a pane of the given width: neither
    -- panel may drop below its minimum, and the left panel never passes
    -- MAX_LEFT_PANEL_RATIO of the pane so the right panel keeps the majority.
    local function ClampLeftWidth(leftWidth, viewWidth)
        local maxLeft = math.max(MIN_LEFT_PANEL_WIDTH,
            math.min(viewWidth - UI.Splitter.Width - MIN_RIGHT_PANEL_WIDTH,
                viewWidth * MAX_LEFT_PANEL_RATIO))
        return Clamp(leftWidth, MIN_LEFT_PANEL_WIDTH, maxLeft)
    end

    -- Apply the current split ratio to every view. Re-run whenever the window or
    -- the ratio changes.
    local function ApplyLayout()
        for _, pane in ipairs(panes) do
            local viewWidth = pane.view:GetWidth()
            if viewWidth and viewWidth > 0 then
                pane.leftSlot:SetWidth(ClampLeftWidth(splitRatio * viewWidth, viewWidth))
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
                    splitRatio = ClampLeftWidth(ratio * viewWidth, viewWidth) / viewWidth
                end
                ApplyLayout()
            end,
            onCommit = function()
                Settings:SetSplitRatio(splitRatio)
            end,
        })
        -- Reflow whenever the view is first laid out (0 -> width), revealed, or
        -- resized with the window. A frame-level handler would miss the initial
        -- layout and the first reveal of the hidden view.
        view:SetScript("OnSizeChanged", ApplyLayout)
        tinsert(panes, pane)
    end

    frame = CreateFrame("Frame", "WowSyncUIFrame", UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(unpack(UI.Backdrop.Main))
    frame:SetBackdropBorderColor(unpack(UI.Backdrop.MainBorder))
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(minFrameWidth, minFrameHeight, maxFrameWidth, maxFrameHeight)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:RegisterForDrag("LeftButton")

    -- Restore the persisted size and position; the first time the window opens
    -- it falls back to the default size, centred on screen. Clamp to the resolved
    -- bounds in case a saved size predates the current panel minimums.
    local savedWidth, savedHeight = Settings:GetWindowSize()
    frame:SetSize(
        Clamp(savedWidth, minFrameWidth, maxFrameWidth),
        Clamp(savedHeight, minFrameHeight, maxFrameHeight))
    local point, relativePoint, x, y = Settings:GetWindowAnchor()
    if point then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relativePoint, x, y)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetScript("OnDragStart", function(self)
        if not locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Settings:SetWindowAnchor(point, relativePoint, x, y)
    end)

    -- Registering with UISpecialFrames makes ESC close the window.
    tinsert(UISpecialFrames, "WowSyncUIFrame")

    -- Title bar region
    local titleSlot = CreateFrame("Frame", nil, frame)
    titleSlot:SetPoint("TOPLEFT", 0, 0)
    titleSlot:SetPoint("TOPRIGHT", 0, 0)
    titleSlot:SetHeight(TITLE_BAR_HEIGHT)
    TitleBar:Build(titleSlot, {
        title = "|c" .. ACCENT_HEX .. "WowSync|r",
        onClose = function() frame:Hide() end,
        onToggleLock = function(value) setLocked(value) end,
    })

    -- Tab strip (Profiles | Characters)
    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT", EDGE_INSET, -TITLE_BAR_HEIGHT)
    tabStrip:SetPoint("TOPRIGHT", -EDGE_INSET, -TITLE_BAR_HEIGHT)
    tabStrip:SetHeight(TAB_STRIP_HEIGHT)

    local profilesTab = CreateTab(tabStrip, L["Profiles"], function() showView("profiles") end)
    profilesTab:SetPoint("LEFT", 0, 0)

    local charactersTab = CreateTab(tabStrip, L["Characters"], function() showView("characters") end)
    charactersTab:SetPoint("LEFT", profilesTab, "RIGHT", TAB_GAP, 0)

    local contentTop = -(TITLE_BAR_HEIGHT + TAB_STRIP_HEIGHT)

    -- Profiles view: profile list (left) + profile details (right)
    local profilesView = CreateFrame("Frame", nil, frame)
    profilesView:SetPoint("TOPLEFT", EDGE_INSET, contentTop)
    profilesView:SetPoint("BOTTOMRIGHT", -EDGE_INSET, EDGE_INSET)

    local leftSlot = CreateFrame("Frame", nil, profilesView)
    leftSlot:SetPoint("TOPLEFT", 0, 0)
    leftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    leftSlot:SetWidth(LEFT_PANEL_WIDTH)

    local rightSlot = CreateFrame("Frame", nil, profilesView)
    rightSlot:SetPoint("TOPLEFT", leftSlot, "TOPRIGHT", UI.Splitter.Width, 0)
    rightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    profileList = ProfileList:Build(leftSlot)
    profileDetails = ProfileDetails:Build(rightSlot)

    AddPane(profilesView, leftSlot)

    profileList:OnSelect(function(profileName)
        profileDetails:SetProfile(profileName)
    end)

    -- Capture a snapshot (optionally a subset, optionally a note) and reflect it
    -- in the list. Shared by the quick Save and the Save… dialog.
    local function DoSave(name, moduleSet, note)
        local pm = WowSync:GetProfileManager()
        local snapshot, reason = pm:Save(name, moduleSet, note)
        if snapshot then
            WowSync:Print(L["Profile 'X' saved."]:format(name))
            profileList:Refresh()

            -- Select the freshly saved profile so the list highlights it and
            -- the detail panel updates through the selection callback.
            profileList:Select(name)
            profileList:ScrollToProfile(name)
        elseif reason == "unchanged" then
            WowSync:Print(L["Profile 'X': nothing changed."]:format(name))
        end
    end

    profileList:OnSave(function(name)
        DoSave(name)
    end)

    profileList:OnSaveAdvanced(function(name)
        SaveDialog:Show({
            profileName = name,
            onConfirm = function(moduleSet, note)
                DoSave(name, moduleSet, note)
            end,
        })
    end)

    profileDetails:OnRefresh(function()
        profileList:Refresh()
        profileList:ClearSelection()
        profileDetails:SetProfile(nil)
    end)

    -- Characters view: character list (left) + character details (right)
    local charactersView = CreateFrame("Frame", nil, frame)
    charactersView:SetPoint("TOPLEFT", EDGE_INSET, contentTop)
    charactersView:SetPoint("BOTTOMRIGHT", -EDGE_INSET, EDGE_INSET)
    charactersView:Hide()

    local charLeftSlot = CreateFrame("Frame", nil, charactersView)
    charLeftSlot:SetPoint("TOPLEFT", 0, 0)
    charLeftSlot:SetPoint("BOTTOMLEFT", 0, 0)
    charLeftSlot:SetWidth(LEFT_PANEL_WIDTH)

    local charRightSlot = CreateFrame("Frame", nil, charactersView)
    charRightSlot:SetPoint("TOPLEFT", charLeftSlot, "TOPRIGHT", UI.Splitter.Width, 0)
    charRightSlot:SetPoint("BOTTOMRIGHT", 0, 0)

    characterList = CharacterList:Build(charLeftSlot)
    characterDetails = CharacterDetails:Build(charRightSlot)

    AddPane(charactersView, charLeftSlot)

    characterList:OnSelect(function(entry)
        characterDetails:SetCharacter(entry)
    end)

    -- A cross-character save creates or updates a profile, so refresh the
    -- profile list to reflect it the next time that view is shown.
    characterDetails:OnSaved(function()
        profileList:Refresh()
    end)

    -- Switch the active top-level view and reflect it in the tab visuals.
    showView = function(which)
        if which == "characters" then
            profilesView:Hide()
            charactersView:Show()
            characterList:Refresh()
            characterList:ClearSelection()
        else
            which = "profiles"
            charactersView:Hide()
            profilesView:Show()
            profileList:Refresh()
        end
        profilesTab:SetActive(which == "profiles")
        charactersTab:SetActive(which == "characters")
    end

    -- Resize grip in the bottom-right corner; hidden while the window is locked.
    resizeGrip = ResizeGrip:Build(frame, {
        onResizeStop = function(width, height)
            Settings:SetWindowSize(width, height)
            -- Sizing re-anchors the frame to its top-left corner; persist that so
            -- the window reopens where it was left rather than snapping back.
            local point, _, relativePoint, x, y = frame:GetPoint()
            Settings:SetWindowAnchor(point, relativePoint, x, y)
            ApplyLayout()
        end,
        -- Double-click restores the default size and re-centres the window.
        onReset = function()
            frame:SetSize(defaultFrameWidth, defaultFrameHeight)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER")
            Settings:SetWindowSize(defaultFrameWidth, defaultFrameHeight)
            local point, _, relativePoint, x, y = frame:GetPoint()
            Settings:SetWindowAnchor(point, relativePoint, x, y)
            ApplyLayout()
        end,
    })

    -- Lock toggle: blocks moving, resizing, and splitter dragging, and hides the
    -- resize grip. Persisted so the choice survives reloads.
    setLocked = function(value)
        locked = value and true or false
        Settings:SetLocked(locked)
        resizeGrip:SetLocked(locked)
        for _, pane in ipairs(panes) do
            pane.splitter:SetLocked(locked)
        end
        TitleBar:SetLocked(locked)
    end

    setLocked(Settings:IsLocked())
    ApplyLayout()

    -- CreateFrame leaves the window shown; start hidden so the first Toggle()
    -- reveals it instead of hiding it.
    frame:Hide()
end

function MainFrame:Toggle()
    Build()

    if frame:IsShown() then
        frame:Hide()
    else
        showView("profiles")
        frame:Show()
    end
end
