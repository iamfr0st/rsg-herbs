HerbZones = HerbZones or {}

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then
        value = minValue
    end
    if maxValue and value > maxValue then
        value = maxValue
    end
    return value
end

local function normalizeId(value, fallback)
    local text = tostring(value or fallback or ''):lower()
    text = text:gsub('[^%w_%-]+', '_')
    text = text:gsub('_+', '_')
    text = text:gsub('^[_%-]+', '')
    text = text:gsub('[_%-]+$', '')

    if text == '' then
        text = tostring(fallback or 'zone')
    end

    return text
end

local function getSortedHerbIds()
    local herbIds = {}

    for herbId in pairs(Config.Herbs or {}) do
        herbIds[#herbIds + 1] = tostring(herbId):lower()
    end

    table.sort(herbIds)
    return herbIds
end

function HerbZones.GetZoneHerbId(zone)
    if type(zone) ~= 'table' then
        return nil
    end

    local herbId = tostring(zone.herbId or ''):lower()
    if herbId ~= '' and Config.Herbs and Config.Herbs[herbId] then
        return herbId
    end

    local allowed = zone.allowedHerbs or zone.herbIds
    if type(allowed) == 'table' then
        for _, entry in ipairs(allowed) do
            herbId = tostring(entry or ''):lower()
            if herbId ~= '' and Config.Herbs and Config.Herbs[herbId] then
                return herbId
            end
        end
    end

    local herbIds = getSortedHerbIds()
    return herbIds[1]
end

function HerbZones.GetHerbOptions()
    local options = {}

    for _, herbId in ipairs(getSortedHerbIds()) do
        local herb = Config.Herbs[herbId]
        options[#options + 1] = {
            value = herbId,
            label = herb and herb.label or herbId,
        }
    end

    return options
end

function HerbZones.NormalizeZone(zone, fallbackId)
    if type(zone) ~= 'table' then
        return nil, 'Zone payload is missing.'
    end

    local center = HerbShared.NormalizeVector3(zone.center)
    if not center then
        return nil, 'Zone center is missing.'
    end

    local herbId = HerbZones.GetZoneHerbId(zone)
    if not herbId then
        return nil, 'Herb type is required.'
    end

    local herb = Config.Herbs and Config.Herbs[herbId] or nil
    if not herb then
        return nil, 'Invalid herb type selected.'
    end

    local id = normalizeId(zone.id or zone.name, fallbackId or 'zone')
    local radius = clamp(zone.radius, 5.0, 250.0)
    local maxActiveNodes = math.floor(clamp(zone.maxActiveNodes or zone.maxSpawns, 1, 25))
    local rewardMin = math.floor(clamp(zone.rewardMin or zone.amountMin or (herb.amount and herb.amount.min) or 1, 1, 25))
    local rewardMax = math.floor(clamp(zone.rewardMax or zone.amountMax or (herb.amount and herb.amount.max) or rewardMin, rewardMin, 25))
    local minNodeDistance = clamp(zone.minNodeDistance or Config.ZoneMinNodeDistance or 9.0, 2.0, radius)

    return {
        id = id,
        center = vector3(center.x, center.y, center.z),
        radius = radius,
        herbId = herbId,
        maxActiveNodes = maxActiveNodes,
        rewardMin = rewardMin,
        rewardMax = rewardMax,
        minNodeDistance = minNodeDistance,
        playerSpawnBuffer = clamp(zone.playerSpawnBuffer or Config.ZonePlayerSpawnBuffer or 20.0, 4.0, 80.0),
        roadBuffer = clamp(zone.roadBuffer or Config.ZoneRoadBuffer or 8.0, 0.0, 50.0),
        density = clamp(zone.density or Config.ZoneCandidateMultiplier or 2.0, 1.0, 4.0),
        enabled = zone.enabled ~= false,
        label = herb.label,
        allowedHerbs = { herbId },
    }
end

function HerbZones.CloneZones(zones)
    local clone = {}

    for index, zone in ipairs(zones or {}) do
        local normalized = HerbZones.NormalizeZone(zone, zone.id or ('zone_%s'):format(index))
        if normalized then
            clone[#clone + 1] = normalized
        end
    end

    return clone
end

function HerbZones.SerializeZones(zones)
    local payload = {}

    for _, zone in ipairs(zones or {}) do
        payload[#payload + 1] = {
            id = zone.id,
            center = {
                x = zone.center.x,
                y = zone.center.y,
                z = zone.center.z,
            },
            radius = zone.radius,
            herbId = zone.herbId,
            maxActiveNodes = zone.maxActiveNodes,
            rewardMin = zone.rewardMin,
            rewardMax = zone.rewardMax,
            minNodeDistance = zone.minNodeDistance,
            playerSpawnBuffer = zone.playerSpawnBuffer,
            roadBuffer = zone.roadBuffer,
            density = zone.density,
            enabled = zone.enabled ~= false,
        }
    end

    return payload
end
