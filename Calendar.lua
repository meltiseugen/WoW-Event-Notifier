local _, addon = ...
local windows = {}
local requestAt = 0

local function Accessible(value)
    return not canaccessvalue or canaccessvalue(value)
end

-- A civil-date value for differences between realm calendar times. This avoids
-- interpreting a realm date in the computer's timezone or daylight-saving time.
local function CalendarSeconds(value)
    if not Accessible(value) or not value then
        return nil
    end
    for _, key in ipairs({ "year", "month", "monthDay", "hour", "minute" }) do
        local field = value[key]
        if not Accessible(field) or type(field) ~= "number" then
            return nil
        end
    end
    local year, month, day = value.year, value.month, value.monthDay
    local hour, minute = value.hour, value.minute
    if month <= 2 then
        year, month = year - 1, month + 12
    end
    local days = 365 * year + math.floor(year / 4) - math.floor(year / 100)
        + math.floor(year / 400) + math.floor((153 * (month - 3) + 2) / 5) + day
    return days * 86400 + hour * 3600 + minute * 60
end

local function IsTimewalking(title)
    if not Accessible(title) or type(title) ~= "string" then
        return false
    end
    title = title:lower()
    local localized = PLAYER_DIFFICULTY_TIMEWALKER
    return title:find("timewalking", 1, true)
        or (type(localized) == "string" and localized ~= ""
            and title:find(localized:lower(), 1, true))
end

function addon:GetReminderDay()
    if not C_DateAndTime then
        return nil
    end
    local current = C_DateAndTime.GetCurrentCalendarTime()
    if CalendarSeconds(current) then
        return string.format("%04d-%02d-%02d", current.year, current.month, current.monthDay)
    end
end

local function ReadDay(current)
    local viewed = C_Calendar.GetMonthInfo(0)
    if not viewed then
        return nil
    end
    -- Calendar offsets are relative to its viewed month, which the user may
    -- have changed. Read today without changing that view or opening its UI.
    local offset = (current.year - viewed.year) * 12 + current.month - viewed.month
    local count = C_Calendar.GetNumDayEvents(offset, current.monthDay)
    if not Accessible(count) or type(count) ~= "number" then
        return nil
    end
    local result = {}
    for index = 1, count do
        local info = C_Calendar.GetDayEvent(offset, current.monthDay, index)
        if not info or not Accessible(info.calendarType) then
            return nil -- Keep known windows while calendar data is unavailable/restricted.
        end
        if info.calendarType == "HOLIDAY" and IsTimewalking(info.title) then
            if not Accessible(info.eventID) then
                return nil
            end
            local startTime = CalendarSeconds(info.startTime)
            local endTime = CalendarSeconds(info.endTime)
            if not startTime or not endTime then
                return nil
            end
            result[#result + 1] = {
                title = info.title,
                startTime = startTime,
                endTime = endTime,
                key = tostring(info.eventID) .. ":" .. tostring(startTime),
            }
        end
    end
    return result
end

local function ReadUpcoming(current)
    local today = ReadDay(current)
    if not today then return nil end
    -- Include tomorrow so reminders can fire before a start just after midnight.
    local tomorrow = C_DateAndTime.AdjustTimeByDays(current, 1)
    local nextDay = ReadDay(tomorrow)
    if not nextDay then return nil end
    for _, entry in ipairs(nextDay) do today[#today + 1] = entry end
    return today
end

function addon:GetTimewalking(now)
    if not self.db.selected.timewalking or not C_Calendar or not C_DateAndTime then
        return nil
    end
    if not InCombatLockdown() and now >= requestAt then
        requestAt = now + 6 * 3600
        C_Calendar.OpenCalendar() -- Request data; this does not show CalendarFrame.
    end
    local current = C_DateAndTime.GetCurrentCalendarTime()
    local currentSeconds = CalendarSeconds(current)
    if not currentSeconds then
        return nil
    end
    if not InCombatLockdown() then
        windows = ReadUpcoming(current) or windows
    end

    local minuteNow = now - now % 60
    local nextChange = minuteNow + 86400 - current.hour * 3600 - current.minute * 60
    local active
    local upcoming = {}
    for _, window in ipairs(windows) do
        local startTime = minuteNow + window.startTime - currentSeconds
        local endTime = minuteNow + window.endTime - currentSeconds
        if startTime > now then
            nextChange = math.min(nextChange, startTime)
            upcoming[#upcoming + 1] = {
                title = window.title, key = window.key,
                startTime = startTime, endTime = endTime,
            }
        elseif endTime > now then
            nextChange = math.min(nextChange, endTime)
            active = {
                event = self.timewalkingEvent,
                startTime = startTime,
                endTime = endTime,
                occurrenceKey = window.key,
                calendar = true,
                message = window.title .. " is active.",
            }
        end
    end
    return active, nextChange, upcoming
end
