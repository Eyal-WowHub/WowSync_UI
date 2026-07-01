local _, addon = ...

--[[
    TimelineSpan widget (the timeline chrome for a snapshot row).

    A thin vertical rail down a row with a single node dot near the top, marking
    one point on the profile history. A profile row owns a span as a sibling of
    its text content; import rows carry no timeline and simply omit it. The row
    decides what a node means (latest / pinned / ordinary) and supplies its
    colour; this owns the rail and node geometry so every row draws the timeline
    the same, and enables no mouse so clicks and hover fall through to the row.

    local timeline = addon:GetObject("TimelineSpan"):Build({
        parent = row,
        anchor = function(span) span:SetPoint(...) end,
    })

    timeline:SetNodeColor(color)   -- recolour the node dot on every render
]]

local TimelineSpan = addon:NewObject("TimelineSpan")

local C = LibStub("Contracts-1.0")

-- X position of the rail within the span; the row's content inset clears it.
local RAIL_X = 14

-- Y offset of the node's centre below the top, aligning it with the subject line.
local NODE_Y = 16

-- Rail thickness and node diameter.
local RAIL_THICKNESS = 2
local NODE_SIZE = 14

-- Horizontal nudge centring the node on the rail.
local NODE_RAIL_NUDGE = 1

-- The rail's neutral colour; the node's colour is supplied per render by the row.
local RAIL_COLOR = CreateColor(0.35, 0.35, 0.35, 0.8)

local Methods = {}

-- Build the rail and node once; the row recolours the node on each render.
function Methods:Constructor()
    self.rail = self:CreateTexture(nil, "ARTWORK")
    self.rail:SetColorTexture(RAIL_COLOR:GetRGBA())
    self.rail:SetWidth(RAIL_THICKNESS)
    self.rail:SetPoint("TOPLEFT", self, "TOPLEFT", RAIL_X, 0)
    self.rail:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", RAIL_X, 0)

    self.node = self:CreateTexture(nil, "OVERLAY")
    self.node:SetTexture("Interface\\COMMON\\Indicator-Gray")
    self.node:SetSize(NODE_SIZE, NODE_SIZE)
    self.node:SetPoint("CENTER", self, "TOPLEFT", RAIL_X + NODE_RAIL_NUDGE, -NODE_Y)
end

-- Recolour the node dot (latest, pinned, or ordinary) for the current row.
function Methods:SetNodeColor(color)
    self.node:SetVertexColor(color:GetRGB())
end

function TimelineSpan:Build(config)
    C:IsTable(config, 2)
    C:Ensures(config.parent ~= nil, "Build: 'config.parent' is required")
    C:Ensures(type(config.anchor) == "function", "Build: 'config.anchor' must be a function")

    return addon:NewWidget(config, {
        frameType = "Frame",
        methods = Methods,
    })
end
