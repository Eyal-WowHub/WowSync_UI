local _, addon = ...

--[[
    Checkbox object (the labelled checkbox every module row is built from).

    A Checkbox IS a CheckButton wearing WoW's flat "minimal" Settings checkbox
    art, with a label to its right. Clicking either the box or the label toggles
    it, and hovering the row lights the faint white highlight WoW's Settings list
    draws behind a hovered row.

    Build one directly for a plain labelled toggle:

        addon:GetObject("Checkbox"):Build({
            parent = frame,
            text = L["Sticky targeting"],
            onToggle = function(checked) ... end,   -- fires on box or label click
        })

    Or hand it a concrete methods table to grow a specialised row on top; its
    Constructor runs with the box, label, and hover already in place:

        addon:GetObject("Checkbox"):Build({ parent = frame, methods = RowMethods })

    Members a row builds against:
        self.label       -- the label FontString, anchored right of the box
        self.labelButton -- transparent overlay over the label that toggles
        self:SetLabel(text)
        self:AddHoverRegion(region)   -- extend the row highlight over a hit area
]]

local Checkbox = addon:NewObject("Checkbox")

local C = LibStub("Contracts-1.0")

-- WoW's flat Settings checkbox art: a thin square with a plain checkmark.
local CHECK_ATLAS = "checkbox-minimal"
local CHECKMARK_ATLAS = "checkmark-minimal"
local CHECKMARK_DISABLED_ATLAS = "checkmark-minimal-disabled"

-- The faint white highlight WoW's Settings list draws behind a hovered row.
local HOVER_COLOR = { 1, 1, 1, 0.1 }

-- How far the row highlight bleeds past the box on each side, so it keeps matching
-- left and right margins instead of sitting flush on one edge.
local HIGHLIGHT_BLEED = 4

local Methods = {}

-- Set the checkbox's label text.
function Methods:SetLabel(text)
    self.label:SetText(text or "")
end

-- Show the row highlight while the pointer is over any registered hit area, and
-- clear it otherwise. Called as regions gain and lose the pointer.
function Methods:RefreshHighlight()
    for _, region in ipairs(self._hoverRegions) do
        if region:IsMouseOver() then
            self.hoverBg:Show()
            return
        end
    end
    self.hoverBg:Hide()
end

-- Register a hit area so hovering it lights the row highlight. A row adds its own
-- areas (e.g. a change badge, a mode button) so the highlight tracks the whole
-- row, not just the box and label.
function Methods:AddHoverRegion(region)
    tinsert(self._hoverRegions, region)
    region:HookScript("OnEnter", function() self.hoverBg:Show() end)
    region:HookScript("OnLeave", function() self:RefreshHighlight() end)
end

-- Dress a fresh check button in the minimal art and add the label, the row
-- highlight, and the label-click-to-toggle overlay. Runs before a concrete row's
-- Constructor so the row builds on top.
local function ApplyCheckbox(frame)
    frame._hoverRegions = {}

    frame:SetNormalAtlas(CHECK_ATLAS)
    frame:SetPushedAtlas(CHECK_ATLAS)
    frame:GetCheckedTexture():SetAtlas(CHECKMARK_ATLAS)
    frame:GetDisabledCheckedTexture():SetAtlas(CHECKMARK_DISABLED_ATLAS)

    -- Settings relies on the row highlight, not a per-box glow, so drop the
    -- template's gold hover texture.
    local boxHighlight = frame:GetHighlightTexture()
    if boxHighlight then
        boxHighlight:SetTexture(nil)
    end

    -- The row highlight, drawn behind the box and label: it spans from just left
    -- of the box to just past the parent's right edge, with matching margins on
    -- both sides, and tracks the box's height.
    local hoverBg = frame:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetColorTexture(unpack(HOVER_COLOR))
    hoverBg:SetPoint("TOPLEFT", frame, "TOPLEFT", -HIGHLIGHT_BLEED, 0)
    hoverBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -HIGHLIGHT_BLEED, 0)
    hoverBg:SetPoint("RIGHT", frame:GetParent(), "RIGHT", HIGHLIGHT_BLEED, 0)
    hoverBg:Hide()
    frame.hoverBg = hoverBg

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", frame, "RIGHT", 2, 0)
    frame.label = label

    -- A transparent overlay over the label so clicking the name toggles the box.
    local labelButton = CreateFrame("Button", nil, frame)
    labelButton:SetAllPoints(label)
    labelButton:SetScript("OnClick", function() frame:Click() end)
    frame.labelButton = labelButton

    -- A row-wide, mouse-enabled strip beneath the box and controls. It reports
    -- hover only (never a click), so the highlight tracks the whole row -- across
    -- the gaps between the label, the badge, and any trailing controls -- with no
    -- flicker, while the box and the controls above it keep their own clicks. It
    -- sits one level below the box so it never steals their input, and is parented
    -- to the list (not the box) so it can span past the box's own width.
    local parent = frame:GetParent()
    local rowHit = CreateFrame("Frame", nil, parent)
    rowHit:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    rowHit:SetPoint("TOPLEFT", frame, "TOPLEFT", -HIGHLIGHT_BLEED, 0)
    rowHit:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -HIGHLIGHT_BLEED, 0)
    rowHit:SetPoint("RIGHT", parent, "RIGHT", HIGHLIGHT_BLEED, 0)
    rowHit:EnableMouse(true)
    frame.rowHit = rowHit

    -- Tie the strip's visibility to the row it serves so a pooled row that is
    -- hidden does not leave a live hover strip behind.
    frame:HookScript("OnShow", function() rowHit:Show() end)
    frame:HookScript("OnHide", function() rowHit:Hide() end)

    frame:AddHoverRegion(frame)
    frame:AddHoverRegion(labelButton)
    frame:AddHoverRegion(rowHit)
end

-- Wire a directly built checkbox from its config. Rows built with their own
-- methods table replace this with their own Constructor.
function Methods:Constructor(config)
    if config.text then self:SetLabel(config.text) end
    if config.onToggle then
        C:Ensures(type(config.onToggle) == "function", "Build: 'config.onToggle' must be a function")
        self:HookScript("OnClick", function(frame)
            config.onToggle(frame:GetChecked() and true or false)
        end)
    end
end

-- The base methods merged with a row type's own methods, cached by that method
-- table so each type merges once rather than once per checkbox built.
local mergedMethods = setmetatable({}, { __mode = "k" })

local function ResolveMethods(concreteMethods)
    if not concreteMethods then
        return Methods
    end

    local merged = mergedMethods[concreteMethods]
    if not merged then
        merged = {}
        for key, value in pairs(Methods) do
            merged[key] = value
        end
        -- The row type's methods win over the base on a name clash.
        for key, value in pairs(concreteMethods) do
            merged[key] = value
        end
        mergedMethods[concreteMethods] = merged
    end
    return merged
end

-- Build a checkbox: create the check button, dress it in minimal art with a
-- label and row highlight, mix the base and any concrete methods onto it, and
-- run the concrete Constructor with everything in place. Returns the frame.
function Checkbox:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")

    local frame = CreateFrame("CheckButton", config.name, config.parent, config.template or "UICheckButtonTemplate")

    return addon:NewWidget(config, {
        frame = frame,
        methods = ResolveMethods(config.methods),
        onReady = ApplyCheckbox,
    })
end
