local addonName, addon = ...

local frame = CreateFrame("Frame")
local scheduled = {}
local ongoing = {}
local notified = {}
local ready, queued, reading
local boundaryTimer
local readRequested = true
local nextRead = 0
local worldEntered = false
local reminderDay

local function ShowInitialSetup()
    if ready and worldEntered and addon.db.showSetup and not InCombatLockdown() then
        addon:ShowOptions()
        addon.db.showSetup = nil
    end
end

local function Chat(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc66Event Notifier:|r " .. message)
end

function addon:Notify(message, details)
    self:ShowNotification(details or { title = "Event Notifier", message = message })
    Chat(message)
end

function addon:TestAlert()
    self:Notify("Test alert: Aqir Invasion starts in 5 minutes.", {
        title = "Aqir Invasions", icon = self.events[2].icon,
        startTime = GetServerTime() + 300, upcoming = true,
    })
end

local function GetPOI(id, mapID)
    return C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
        or (mapID and C_AreaPoiInfo.GetAreaPOIInfo(nil, id))
end

local function ReadSchedule(now)
    if not C_EventScheduler or InCombatLockdown() then
        return
    end
    if not readRequested and now < nextRead then
        return
    end
    readRequested = false
    nextRead = now + 6 * 3600
    reading = true
    local events = C_EventScheduler.GetScheduledEvents()
    local current = C_EventScheduler.GetOngoingEvents()
    reading = false
    if events then
        scheduled = events
    else
        -- The API requests its data asynchronously; retry if no update arrives.
        nextRead = now + 15
    end
    if current then
        ongoing = current
    end
end

function addon:Refresh()
    if not ready then
        return
    end
    local now = GetServerTime()
    local today = self:GetReminderDay()
    -- Keep the session's login day: staying online past midnight must not
    -- produce another all-day reminder. The next login can remind again.
    reminderDay = reminderDay or today
    ReadSchedule(now)
    local active, hasSchedule = {}, {}
    local nextChange = nextRead > now and nextRead or (now + 6 * 3600)

    local function ConsiderEarly(event, id, poi, startTime, endTime, occurrenceKey)
        if not event.earlyReminder then return end
        local settings = self.db.earlyReminders[event.key]
        if not self.db.enabled or not self.db.selected[event.key] or not settings.enabled
            or not startTime or startTime <= now or (poi and poi.isLocked) then
            return
        end
        local identity = event.key == "aqirInvasions" and "aqir" or tostring(id)
        local key = "early:" .. identity .. ":" .. tostring(occurrenceKey or startTime)
        if self.db.notified[key] then return end
        local reminderAt = startTime - self:NormalizeEarlyMinutes(settings.minutes) * 60
        if reminderAt > now then
            nextChange = math.min(nextChange, reminderAt)
        else
            local minutes = math.ceil((startTime - now) / 60)
            local name = poi and poi.name or event.name
            self:Notify(name .. " starts in " .. minutes .. (minutes == 1 and " minute." or " minutes."), {
                title = name, icon = event.icon, startTime = startTime, endTime = endTime, upcoming = true,
            })
            self.db.notified[key] = endTime or startTime
        end
    end

    local function Consider(id, poi, startTime, endTime, mapID)
        local event = self:MatchEvent(id, poi)
        if not event or (poi and poi.isLocked) then
            return
        end
        if not self.db.selected[event.key] then
            return
        end
        local current = active[id]
        if not current or (startTime and not current.startTime) then
            active[id] = {
                event = event,
                poi = poi,
                startTime = startTime,
                endTime = endTime,
                mapID = mapID,
            }
        end
    end

    local poiCache = {}
    local function CachedPOI(id)
        if poiCache[id] == nil then
            poiCache[id] = GetPOI(id) or false
        end
        return poiCache[id] or nil
    end

    for _, info in ipairs(scheduled) do
        local id = info.areaPoiID
        local poi = CachedPOI(id)
        local event = self:MatchEvent(id, poi)
        if event and self.db.selected[event.key] then
            -- Even an expired/future scheduled marker must not be promoted to
            -- active by a stale map marker between scheduler updates.
            hasSchedule[id] = true
            local startTime, endTime = self:GetWindow(event, info, now)
            if startTime then
                ConsiderEarly(event, id, poi, startTime, endTime)
                -- A weekly Aqir rotation represents an hourly invasion. During
                -- the current invasion, its next hourly start is already known.
                if event.key == "aqirInvasions" and info.endTime - info.startTime > 3600 then
                    local nextStart, nextEnd = self:GetWindow(event, info, startTime + 600)
                    ConsiderEarly(event, id, poi, nextStart, nextEnd)
                end
                if startTime > now then
                    nextChange = math.min(nextChange, startTime)
                else
                    Consider(id, poi, startTime, endTime)
                    nextChange = math.min(nextChange, endTime)
                end
            end
        end
    end

    local function ConsiderLive(id, poi, mapID)
        if hasSchedule[id] then
            return
        end
        local event = self:MatchEvent(id, poi)
        if not event or not self.db.selected[event.key] then
            return
        end
        local endTime
        local seconds = C_AreaPoiInfo.GetAreaPOISecondsLeft(id)
        if seconds and seconds <= 0 then
            return
        end
        if seconds and seconds > 0 then
            endTime = now + seconds
        end
        if event.key == "aqirInvasions" then
            local hour = now - now % 3600
            if not endTime or endTime > hour + 3600 then
                ConsiderEarly(event, id, poi, hour + 3600, hour + 4200)
            end
            if now < hour + 600 then
                Consider(id, poi, hour, hour + 600, mapID)
                nextChange = math.min(nextChange, hour + 600)
            else
                nextChange = math.min(nextChange, hour + 3600)
            end
        elseif not seconds or seconds > 0 then
            Consider(id, poi, nil, endTime, mapID)
            if endTime then
                nextChange = math.min(nextChange, endTime)
            end
        end
    end

    -- Ongoing events remain available from outside their zones. They have no
    -- scheduled start time, so only the game's current list can activate them.
    for _, info in ipairs(ongoing) do
        ConsiderLive(info.areaPoiID, CachedPOI(info.areaPoiID))
    end

    -- Event POIs have a separate API from ordinary area POIs. Inspect both;
    -- markers advertised in advance must not become active alerts.
    for _, mapID in ipairs(self.mapIDs) do
        local ids = {}
        for _, id in ipairs(C_AreaPoiInfo.GetEventsForMap(mapID) or {}) do
            ids[id] = true
        end
        for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
            ids[id] = true
        end
        for id in pairs(ids) do
            local poi = GetPOI(id, mapID)
            if poi and poi.isCurrentEvent then
                ConsiderLive(id, poi, mapID)
            end
        end
    end

    local timewalking, calendarChange = self:GetTimewalking(now)
    active.timewalking = timewalking
    if calendarChange then
        nextChange = math.min(nextChange, calendarChange)
    end

    for key, expires in pairs(self.db.notified) do
        if expires <= now then
            self.db.notified[key] = nil
        end
    end

    self.active = active
    for id, entry in pairs(active) do
        local daily = entry.event.reminder == "daily"
        -- Aqir has several aliases/projections for the same hourly invasion.
        local identity = entry.event.key == "aqirInvasions" and "aqir" or tostring(id)
        local key = identity .. ":" .. tostring(entry.occurrenceKey or entry.startTime or "live")
        local previous = notified[id]
        if previous and previous.endTime and previous.endTime <= now then
            previous = nil
            notified[id] = nil
        end
        local alreadySeen = self.db.notified[key] or (previous and previous.key == key)
        if daily then
            alreadySeen = not today or today ~= reminderDay
                or self.db.dailyNotified[entry.event.key] == today
        end
        -- Data may first arrive as a live marker, then acquire a schedule.
        if not daily and previous and previous.live and previous.endTime and entry.endTime
            and math.abs(previous.endTime - entry.endTime) < 5 then
            alreadySeen = true
        end
        if self.db.enabled and not alreadySeen then
            if entry.message then
                self:Notify(entry.message, { title = entry.event.name, icon = entry.event.icon,
                    startTime = entry.startTime, endTime = entry.endTime })
            else
                local zone = C_EventScheduler and C_EventScheduler.GetEventZoneName(id)
                if not zone and entry.mapID then
                    local map = C_Map.GetMapInfo(entry.mapID)
                    zone = map and map.name
                end
                local name = entry.poi and entry.poi.name or entry.event.name
                self:Notify(name .. " is available" .. (zone and " in " .. zone or "") .. ".", {
                    title = name, icon = entry.event.icon, zone = zone,
                    startTime = entry.startTime, endTime = entry.endTime,
                })
            end
            alreadySeen = true
            if daily then
                self.db.dailyNotified[entry.event.key] = today
            end
        end
        -- A known schedule identifies every occurrence separately. For live
        -- markers, retain the last sighting briefly across missing map data.
        if alreadySeen and not daily then
            self.db.notified[key] = entry.endTime or (now + 3600)
            if not entry.calendar then
                notified[id] = {
                    key = key, lastSeen = now, endTime = entry.endTime,
                    live = entry.startTime == nil,
                }
            end
        end
    end
    for id, entry in pairs(notified) do
        if entry.endTime and entry.endTime <= now then
            notified[id] = nil
        elseif not active[id] and now - entry.lastSeen >= 60 then
            notified[id] = nil
            self.db.notified[entry.key] = nil
        elseif not active[id] then
            nextChange = math.min(nextChange, entry.lastSeen + 60)
        end
    end

    if self.UpdateOptions then
        self:UpdateOptions()
    end
    if boundaryTimer then
        boundaryTimer:Cancel()
    end
    boundaryTimer = C_Timer.NewTimer(math.max(1, nextChange - now), function()
        self:Refresh()
    end)
end

function addon:QueueRefresh(requestRead)
    if requestRead then
        readRequested = true
    end
    if queued or not ready then
        return
    end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        self:Refresh()
    end)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("AREA_POIS_UPDATED")
frame:RegisterEvent("EVENT_SCHEDULER_UPDATE")
frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then
            return
        end
        local freshInstall = type(EventNotifierDB) ~= "table"
            or type(EventNotifierDB.selected) ~= "table"
        EventNotifierDB = type(EventNotifierDB) == "table" and EventNotifierDB or {}
        addon.db = EventNotifierDB
        addon.db.selected = type(addon.db.selected) == "table" and addon.db.selected or {}
        addon.db.notified = type(addon.db.notified) == "table" and addon.db.notified or {}
        addon.db.live = type(addon.db.live) == "table" and addon.db.live or {}
        addon.db.dailyNotified = type(addon.db.dailyNotified) == "table" and addon.db.dailyNotified or {}
        addon.db.earlyReminders = type(addon.db.earlyReminders) == "table" and addon.db.earlyReminders or {}
        if freshInstall then
            addon.db.showSetup = true
        end
        notified = addon.db.live
        if addon.db.enabled == nil then
            addon.db.enabled = true
        end
        for _, entry in ipairs(addon.events) do
            local early = addon.db.earlyReminders[entry.key]
            if type(early) ~= "table" then early = {} end
            early.enabled = entry.earlyReminder == true and early.enabled == true
            early.minutes = addon:NormalizeEarlyMinutes(early.minutes)
            addon.db.earlyReminders[entry.key] = early
            if addon.db.selected[entry.key] == nil then
                addon.db.selected[entry.key] = false
            end
        end
        ready = true
        Chat("Use /en to choose events to track.")
    elseif event == "EVENT_SCHEDULER_UPDATE" then
        if not reading then
            addon:QueueRefresh(true)
        end
    else
        if event == "PLAYER_ENTERING_WORLD" then
            worldEntered = true
        end
        ShowInitialSetup()
        addon:QueueRefresh(event == "PLAYER_ENTERING_WORLD")
    end
end)

SLASH_EVENTNOTIFIER1 = "/en"
SLASH_EVENTNOTIFIER2 = "/eventnotifier"
SlashCmdList.EVENTNOTIFIER = function(message)
    if not ready then
        return
    end
    if (message or ""):lower():match("^%s*test%s*$") then
        addon:TestAlert()
    elseif (message or ""):lower():match("^%s*move%s*$") then
        addon:ToggleNotificationMove()
    else
        addon:ToggleOptions()
    end
end
