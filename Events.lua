local _, addon = ...

addon.events = {
    {
        key = "voidAssaults",
        icon = "Interface\\Icons\\Spell_Shadow_Twilight",
        name = "Void Assaults",
        timing = "Each Void Strike or Void Incursion",
        description = "Void Strikes and Void Incursions in Eversong Woods and Zul'Aman.",
        patterns = { "voidassault", "voidstrike", "voidincursion" },
    },
    {
        key = "aqirInvasions",
        icon = "Interface\\Icons\\Achievement_Zone_Silithus_01",
        earlyReminder = true,
        name = "Aqir Invasions",
        timing = "Hourly, at the start of the hour",
        description = "Hourly invasions in Eversong Woods or Zul'Aman.",
        poiIDs = { 8812, 8813, 9026, 9027, 9045 },
        patterns = { "aqirinvasion" },
    },
    {
        key = "stormarionAssault",
        icon = "Interface\\Icons\\Spell_Shadow_Shadowfury",
        name = "Stormarion Assault",
        timing = "Each assault",
        description = "Defend Stormarion Citadel in Voidstorm.",
        poiIDs = { 8419, 8421, 8422 },
        patterns = { "stormarionassault" },
    },
    {
        key = "abundance",
        icon = "Interface\\Icons\\INV_Misc_Herb_01",
        name = "Abundance: Abundant Harvest",
        timing = "When the empowered cave rotates",
        description = "The empowered Abundance cave as its location rotates.",
        poiIDs = { 8525, 8526, 8527, 8528 },
        patterns = { "abundantharvest" },
    },
    {
        key = "curseSurges",
        icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
        earlyReminder = true,
        name = "Curse Surges",
        timing = "Each Curse Surge",
        description = "Rotating public events on the Coiled Isle.",
        poiIDs = { 8936, 8937, 8938, 8939, 8940 },
        patterns = { "cursesurge" },
    },
}

addon.timewalkingEvent = {
    key = "timewalking",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    category = "general",
    name = "Timewalking",
    reminder = "daily",
    timing = "All-day event: login reminder, once per realm day",
    description = "Notify when a Timewalking dungeon event is active on the calendar.",
    patterns = {},
}
table.insert(addon.events, addon.timewalkingEvent)

addon.mapIDs = { 2395, 2437, 2405, 2413, 2512 }

function addon:NormalizeEarlyMinutes(value)
    value = tonumber(value) or 5
    if value ~= value then value = 5 end
    return math.max(1, math.min(10, math.floor(value)))
end

local byID = {}
for _, event in ipairs(addon.events) do
    for _, id in ipairs(event.poiIDs or {}) do
        byID[id] = event
    end
end

local function Normalize(text)
    return (text or ""):lower():gsub("[^%w]", "")
end

function addon:MatchEvent(id, poi)
    -- Ordinary Abundance entrances are always present; only notify for the harvest.
    if id >= 8415 and id <= 8418 then
        return nil
    end
    if byID[id] then
        return byID[id]
    end
    local name = Normalize(poi and poi.name)
    local atlas = Normalize(poi and poi.atlasName)
    for _, event in ipairs(self.events) do
        for _, pattern in ipairs(event.patterns) do
            if name:find(pattern, 1, true) or atlas:find(pattern, 1, true) then
                return event
            end
        end
    end
end

function addon:GetWindow(event, info, now)
    local startTime, endTime = info.startTime, info.endTime
    if not startTime or not endTime or endTime <= now or endTime <= startTime then
        return nil
    end

    -- Some Aqir scheduler entries describe the weekly zone rotation, rather
    -- than the actual invasion: it runs for the first ten minutes of each hour.
    if event.key == "aqirInvasions" and endTime - startTime > 3600 then
        local hour = now - now % 3600
        if now < startTime then
            hour = startTime - startTime % 3600
        end
        if hour + 600 <= now or hour < startTime then
            hour = hour + 3600
        end
        startTime, endTime = hour, math.min(hour + 600, endTime)
    end

    if endTime <= startTime then
        return nil
    end
    return startTime, endTime
end
