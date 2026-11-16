local _, addon = ...
local WIDTH, HEIGHT, GAP, LIMIT, LIFETIME = 300, 84, 8, 4, 8
local holder, header, done, reset
local cards, previews, pending = {}, {}, {}
local moving = false

local function Duration(seconds)
    seconds = math.max(0, math.ceil(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    local text = minutes .. "m " .. seconds % 60 .. "s"
    if hours > 0 or days > 0 then text = hours .. "h " .. text end
    if days > 0 then text = days .. "d " .. text end
    return text
end

local function Timestamp(stamp)
    local now = GetServerTime()
    if C_DateAndTime and C_DateAndTime.AdjustTimeByMinutes then
        local current = C_DateAndTime.GetCurrentCalendarTime()
        local value = C_DateAndTime.AdjustTimeByMinutes(current,
            math.floor(stamp / 60) - math.floor(now / 60))
        return string.format("%02d/%02d/%04d %02d:%02d", value.monthDay, value.month,
            value.year, value.hour, value.minute)
    end
    return date("%d/%m/%Y %H:%M", stamp)
end

local function RefreshText(card)
    local info = card.info
    card.title:SetText((info.upcoming and "Upcoming: " or "") .. info.title)
    card.timestamp:SetText(Timestamp(info.startTime or info.created))
    local now = GetServerTime()
    local text = info.zone or "Available now"
    if info.upcoming and info.startTime then
        text = info.startTime > now and ("Starts in " .. Duration(info.startTime - now)) or "Active now"
    elseif info.endTime then
        text = info.endTime > now and ("Ends in " .. Duration(info.endTime - now)) or "Event ended"
    end
    card.details:SetText(text)
end

local function CreateCard()
    local card = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    card:SetSize(WIDTH, HEIGHT)
    card:EnableMouse(false)
    card:SetBackdrop({
        bgFile = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropBorderColor(1, 0.76, 0.25, 1)
    local strip = card:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 72, -7)
    strip:SetPoint("TOPRIGHT", -6, -7)
    strip:SetHeight(22)
    strip:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Borders")
    strip:SetTexCoord(0, 0.9765625, 0.66015625, 0.73828125)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(50, 50)
    card.icon:SetPoint("LEFT", 12, 0)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = card:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\AchievementFrame\\AchievementToast")
    border:SetTexCoord(0.107421875, 0.1796875, 0.505859375, 0.578125)
    border:SetSize(74, 74)
    border:SetPoint("CENTER", card.icon, "CENTER", 0, 0)
    local function Text(template, y, height)
        local text = card:CreateFontString(nil, "OVERLAY", template)
        text:SetPoint("TOPLEFT", 76, y)
        text:SetSize(216, height)
        text:SetJustifyH("CENTER")
        text:SetMaxLines(1)
        text:SetWordWrap(false)
        return text
    end
    card.title = Text("GameFontHighlightSmall", -11, 16)
    card.timestamp = Text("GameFontBlack", -34, 17)
    card.details = Text("GameFontBlack", -53, 17)
    card:Hide()
    return card
end

local function Position()
    holder:ClearAllPoints()
    local saved = addon.db.notificationPosition
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
        and saved.x == saved.x and saved.y == saved.y then
        holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            math.max(0, math.min(1, saved.x)) * UIParent:GetWidth(),
            math.max(0, math.min(1, saved.y)) * UIParent:GetHeight())
    else
        holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -35, -150)
    end
end

local function SavePosition()
    local x, y = holder:GetLeft(), holder:GetTop()
    if x and y then
        addon.db.notificationPosition = { x = x / UIParent:GetWidth(), y = y / UIParent:GetHeight() }
    end
end

local Update
local function FillCards()
    local shown = 0
    for _, card in ipairs(cards) do
        if not card.info and #pending > 0 then
            card.info = table.remove(pending, 1)
            card.remaining, card.textElapsed = LIFETIME, 0
            card.icon:SetTexture(card.info.icon or "Interface\\Icons\\INV_Misc_PocketWatch_01")
            RefreshText(card)
        end
        if card.info then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 10, -32 - shown * (HEIGHT + GAP))
            card:SetAlpha(math.min(1, card.remaining))
            card:SetShown(not moving)
            shown = shown + 1
        else
            card:Hide()
        end
    end
    holder:SetShown(moving or shown > 0)
    holder:SetScript("OnUpdate", not moving and shown > 0 and Update or nil)
end

Update = function(_, elapsed)
    local expired = false
    for _, card in ipairs(cards) do
        if card.info then
            card.remaining = card.remaining - elapsed
            card.textElapsed = card.textElapsed + elapsed
            if card.remaining <= 0 then
                card.info = nil
                card:Hide()
                expired = true
            else
                card:SetAlpha(math.min(1, card.remaining))
                if card.textElapsed >= 1 then
                    RefreshText(card)
                    card.textElapsed = 0
                end
            end
        end
    end
    if expired then FillCards() end
end

local function EnsureHolder()
    if holder then return end
    holder = CreateFrame("Frame", "EventNotifierNotificationAnchor", UIParent, "BackdropTemplate")
    holder:SetSize(WIDTH + 20, LIMIT * HEIGHT + (LIMIT - 1) * GAP + 64)
    holder:SetFrameStrata("DIALOG")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:EnableMouse(false)
    holder:RegisterForDrag("LeftButton")
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    holder:SetBackdropColor(0, 0, 0, 0)
    holder:SetBackdropBorderColor(0, 0, 0, 0)
    holder:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    header = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -10)
    header:SetText("Drag to move notifications")
    done = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    done:SetSize(90, 24)
    done:SetPoint("BOTTOMLEFT", 12, 6)
    done:SetText("Done")
    done:SetScript("OnClick", function() addon:ToggleNotificationMove() end)
    reset = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    reset:SetSize(130, 24)
    reset:SetPoint("BOTTOMRIGHT", -12, 6)
    reset:SetText("Reset Position")
    reset:SetScript("OnClick", function() addon:ResetNotificationPosition() end)
    for index = 1, LIMIT do
        cards[index], previews[index] = CreateCard(), CreateCard()
        previews[index]:SetPoint("TOPLEFT", 10, -32 - (index - 1) * (HEIGHT + GAP))
    end
    header:Hide(); done:Hide(); reset:Hide()
    Position()
    holder:Hide()
end

function addon:ShowNotification(info)
    EnsureHolder()
    local copy = {}
    for key, value in pairs(info) do copy[key] = value end
    copy.title, copy.created = copy.title or "Event Notifier", GetServerTime()
    if #pending >= 50 then table.remove(pending, 1) end
    pending[#pending + 1] = copy
    FillCards()
end

function addon:ResetNotificationPosition()
    EnsureHolder()
    holder:StopMovingOrSizing()
    self.db.notificationPosition = nil
    Position()
end

function addon:ToggleNotificationMove()
    EnsureHolder()
    moving = not moving
    holder:EnableMouse(moving)
    header:SetShown(moving); done:SetShown(moving); reset:SetShown(moving)
    holder:SetBackdropColor(0.05, 0.05, 0.05, moving and 0.8 or 0)
    holder:SetBackdropBorderColor(0.8, 0.65, 0.25, moving and 1 or 0)
    if moving then
        for index, preview in ipairs(previews) do
            local event = self.events[index]
            preview.info = { title = event.name, icon = event.icon, created = GetServerTime(),
                startTime = GetServerTime() + 300, upcoming = true }
            preview.icon:SetTexture(event.icon)
            RefreshText(preview)
            preview:Show()
        end
    else
        holder:StopMovingOrSizing()
        SavePosition()
        for _, preview in ipairs(previews) do preview:Hide() end
    end
    FillCards()
end
