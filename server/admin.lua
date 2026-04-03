local RSGCore = exports['rsg-core']:GetCoreObject()

HerbZoneStore = HerbZoneStore or {}

local RESOURCE_NAME = GetCurrentResourceName()
local ZONE_FILE = tostring(Config.ZoneSaveFile or 'data/zones.json')
local RuntimeZones = {}
local ZoneIndex = {}

local function notify(src, description, notificationType)
    if not src or src <= 0 then
        return
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Herb Zones',
        description = description,
        type = notificationType or 'inform',
    })
end

local function isAdmin(src)
    if not src or src <= 0 then
        return true
    end

    if RSGCore.Functions.HasPermission(src, 'god') or RSGCore.Functions.HasPermission(src, 'admin') then
        return true
    end

    if Config.AdminAcePermission and IsPlayerAceAllowed(src, Config.AdminAcePermission) then
        return true
    end

    return false
end

local function rebuildZoneIndex()
    ZoneIndex = {}

    for _, zone in ipairs(RuntimeZones) do
        ZoneIndex[zone.id] = zone
    end
end

local function syncZones(target)
    TriggerClientEvent('rsg-herbs:client:syncZones', target or -1, {
        zones = HerbZones.SerializeZones(RuntimeZones),
    })
end

local function saveZonesToDisk()
    local encoded = json.encode(HerbZones.SerializeZones(RuntimeZones))
    SaveResourceFile(RESOURCE_NAME, ZONE_FILE, encoded or '[]', -1)
end

local function normalizeZoneList(list)
    local zones = {}
    local ids = {}

    for index, zone in ipairs(list or {}) do
        local normalized, err = HerbZones.NormalizeZone(zone, ('zone_%s'):format(index))
        if not normalized then
            return nil, err
        end

        if ids[normalized.id] then
            return nil, ('Duplicate zone id: %s'):format(normalized.id)
        end

        ids[normalized.id] = true
        zones[#zones + 1] = normalized
    end

    return zones
end

local function loadZonesFromDisk()
    local raw = LoadResourceFile(RESOURCE_NAME, ZONE_FILE)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            local zones, err = normalizeZoneList(decoded)
            if zones then
                RuntimeZones = zones
                rebuildZoneIndex()
                return
            end

            ServerDebug('Zone file invalid, falling back to config', err)
        else
            ServerDebug('Zone file decode failed, falling back to config')
        end
    end

    local zones, err = normalizeZoneList(Config.Zones or {})
    if not zones then
        ServerDebug('Config zones invalid', err)
        RuntimeZones = {}
    else
        RuntimeZones = zones
    end

    rebuildZoneIndex()
    saveZonesToDisk()
end

local function replaceZone(zoneId, nextZone)
    local updated = false

    for index, zone in ipairs(RuntimeZones) do
        if zone.id == zoneId then
            RuntimeZones[index] = nextZone
            updated = true
            break
        end
    end

    if not updated then
        RuntimeZones[#RuntimeZones + 1] = nextZone
    end
end

local function removeZone(zoneId)
    for index, zone in ipairs(RuntimeZones) do
        if zone.id == zoneId then
            table.remove(RuntimeZones, index)
            return true
        end
    end

    return false
end

local function persistAndBroadcast()
    rebuildZoneIndex()
    saveZonesToDisk()

    if HerbRuntimeNodes and type(HerbRuntimeNodes.Rebuild) == 'function' then
        HerbRuntimeNodes.Rebuild()
    end

    syncZones(-1)
end

HerbZoneStore.IsAdmin = isAdmin
HerbZoneStore.GetZones = function()
    return HerbZones.CloneZones(RuntimeZones)
end
HerbZoneStore.GetZoneById = function(zoneId)
    return ZoneIndex[tostring(zoneId or '')]
end
HerbZoneStore.Reload = function()
    loadZonesFromDisk()
    persistAndBroadcast()
end

loadZonesFromDisk()

lib.callback.register('rsg-herbs:server:isAdmin', function(src)
    return isAdmin(src)
end)

lib.callback.register('rsg-herbs:server:getZones', function(src)
    if not isAdmin(src) then
        return { ok = false, error = 'No permission.' }
    end

    return {
        ok = true,
        zones = HerbZones.SerializeZones(RuntimeZones),
        herbOptions = HerbZones.GetHerbOptions(),
    }
end)

RegisterNetEvent('rsg-herbs:server:requestAdminMenu', function()
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to manage herb zones.', 'error')
        return
    end

    TriggerClientEvent('rsg-herbs:client:openAdminMenu', src)
end)

RegisterNetEvent('rsg-herbs:server:saveZone', function(payload)
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to save herb zones.', 'error')
        return
    end

    payload = type(payload) == 'table' and payload or {}

    local oldId = tostring(payload.oldId or payload.previousId or payload.originalId or payload.id or ''):lower()
    local normalized, err = HerbZones.NormalizeZone(payload, oldId ~= '' and oldId or 'zone')
    if not normalized then
        notify(src, err or 'Zone data is invalid.', 'error')
        return
    end

    for _, zone in ipairs(RuntimeZones) do
        if zone.id == normalized.id and zone.id ~= oldId then
            notify(src, ('Zone id "%s" already exists.'):format(normalized.id), 'error')
            return
        end
    end

    replaceZone(oldId ~= '' and oldId or normalized.id, normalized)
    persistAndBroadcast()
    notify(src, ('Saved herb zone "%s".'):format(normalized.id), 'success')
    TriggerClientEvent('rsg-herbs:client:openAdminMenu', src, normalized.id)
end)

RegisterNetEvent('rsg-herbs:server:deleteZone', function(zoneId)
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to delete herb zones.', 'error')
        return
    end

    zoneId = tostring(zoneId or ''):lower()
    if zoneId == '' then
        notify(src, 'Zone id is required.', 'error')
        return
    end

    if not removeZone(zoneId) then
        notify(src, 'Zone not found.', 'error')
        return
    end

    persistAndBroadcast()
    notify(src, ('Deleted herb zone "%s".'):format(zoneId), 'success')
    TriggerClientEvent('rsg-herbs:client:openAdminMenu', src)
end)

RegisterCommand(tostring(Config.AdminCommand or 'herbzones'), function(source)
    if source <= 0 then
        print(('[%s] Herb zone admin menu is player-only.'):format(RESOURCE_NAME))
        return
    end

    if not isAdmin(source) then
        notify(source, 'You do not have permission to manage herb zones.', 'error')
        return
    end

    TriggerClientEvent('rsg-herbs:client:openAdminMenu', source)
end, false)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE_NAME then
        return
    end

    loadZonesFromDisk()
    syncZones(-1)
end)

RegisterNetEvent('RSGCore:Server:PlayerLoaded', function()
    syncZones(source)
end)
