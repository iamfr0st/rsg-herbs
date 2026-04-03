HerbShared = {}

local RESOURCE_NAME = GetCurrentResourceName()

function HerbShared.GetTimestamp()
    if type(os) == 'table' and type(os.time) == 'function' then
        return os.time()
    end

    if type(GetCloudTimeAsInt) == 'function' then
        local timestamp = GetCloudTimeAsInt()
        if timestamp and timestamp > 0 then
            return timestamp
        end
    end

    if type(GetGameTimer) == 'function' then
        return math.floor(GetGameTimer() / 1000)
    end

    return 0
end

function HerbShared.NormalizeVector3(coords)
    if type(coords) == 'vector3' then
        return coords
    end

    if type(coords) ~= 'table' then
        return nil
    end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then
        return nil
    end

    return vector3(x, y, z)
end

function HerbShared.BuildNodeKey(index, node)
    local coords = HerbShared.NormalizeVector3(node and node.coords or nil) or vector3(0.0, 0.0, 0.0)
    return ('%s:%s:%0.2f:%0.2f:%0.2f'):format(
        tostring(node and node.herbId or 'herb'),
        tostring(index or 0),
        coords.x,
        coords.y,
        coords.z
    )
end

function HerbShared.HashSeed(...)
    local hash = 2166136261

    for index = 1, select('#', ...) do
        local value = tostring(select(index, ...))
        for i = 1, #value do
            hash = (hash ~ string.byte(value, i)) & 0xffffffff
            hash = (hash * 16777619) & 0xffffffff
        end
    end

    if hash == 0 then
        hash = 1
    end

    return hash
end

function HerbShared.CreateSeededRng(seed)
    local state = tonumber(seed) or 1
    if state == 0 then
        state = 1
    end

    return function()
        state = (1103515245 * state + 12345) & 0x7fffffff
        return state / 0x7fffffff
    end
end

function HerbShared.BuildZoneNodeKey(zoneId, slot, herbId)
    return ('zone:%s:%s:%s'):format(
        tostring(zoneId or 'zone'),
        tostring(slot or 0),
        tostring(herbId or 'herb')
    )
end

function HerbShared.ParseZoneNodeKey(nodeKey)
    if type(nodeKey) ~= 'string' then
        return nil
    end

    local zoneId, slot, herbId = nodeKey:match('^zone:(.-):([^:]+):([^:]+)$')
    if not zoneId or not slot or not herbId then
        return nil
    end

    return zoneId, tonumber(slot) or slot, herbId
end

local function debugEnabled()
    return type(Config) == 'table' and Config.Debug == true
end

local function stringifyArgs(...)
    local parts = {}

    for index = 1, select('#', ...) do
        parts[index] = tostring(select(index, ...))
    end

    return table.concat(parts, ' ')
end

local function noop()
end

if IsDuplicityVersion() then
    ClientDebug = noop

    function ServerDebug(...)
        if not debugEnabled() then
            return
        end

        print(('[%s][server] %s'):format(RESOURCE_NAME, stringifyArgs(...)))
    end
else
    ServerDebug = noop

    function ClientDebug(...)
        if not debugEnabled() then
            return
        end

        print(('[%s][client] %s'):format(RESOURCE_NAME, stringifyArgs(...)))
    end
end
