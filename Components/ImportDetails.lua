local _, addon = ...

--[[
    ImportDetails object (right panel, Imports tab).

    Shows the selected imported container: an empty-state prompt until one is
    picked, then the container's name and its snapshot timeline. Apply controls
    are added in a later slice.

    addon:GetObject("ImportDetails"):Build(region)
        -> self {
            SetImport(importID or nil),
        }
]]

local ImportDetails = addon:NewObject("ImportDetails")
local ImportSnapshotList = addon:GetObject("ImportSnapshotList")

local C = LibStub("Contracts-1.0")
local L = addon.L
local UI = addon.UI

local ImportManager = WowSync:GetImportManager()

local emptyLabel
local content
local titleText
local timeline

function ImportDetails:Build(region)
    C:IsTable(region, 2)

    local root = CreateFrame("Frame", nil, region, "BackdropTemplate")
    root:SetAllPoints(region)
    root:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(unpack(UI.Backdrop.Panel))
    root:SetBackdropBorderColor(unpack(UI.Backdrop.PanelBorder))

    -- Empty state, shown until a container is selected.
    emptyLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    emptyLabel:SetPoint("CENTER")
    emptyLabel:SetText(L["Select an import"])

    -- Content, revealed once a container is selected.
    content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    content:Hide()

    titleText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 0, 0)
    titleText:SetPoint("RIGHT", 0, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)

    -- Snapshot timeline, filling the rest of the panel below the title.
    local timelineSlot = CreateFrame("Frame", nil, content)
    timelineSlot:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
    timelineSlot:SetPoint("BOTTOMRIGHT", 0, 0)
    timeline = ImportSnapshotList:Build(timelineSlot)

    return self
end

function ImportDetails:SetImport(importID)
    local record = importID and ImportManager:GetImport(importID)
    if not record then
        content:Hide()
        emptyLabel:Show()
        timeline:Clear()
        return
    end

    emptyLabel:Hide()
    titleText:SetText(record.Name or "")
    timeline:SetImport(importID)
    content:Show()
end
