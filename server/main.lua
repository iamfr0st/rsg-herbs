local RSGCore = exports['rsg-core']:GetCoreObject()

local NodeEntries = {}
local NodeCooldowns = {}
local LocalItems = {}

HerbRuntimeNodes = HerbRuntimeNodes or {}

print(('[%s][server] server/main.lua loaded'):format(GetCurrentResourceName()))

local function loadLocalItems()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/items.lua')
    if not raw or raw == '' then
        ServerDebug('Local item file missing')
        return {}
    end

    local chunk, err = load(raw, ('@@%s/data/items.lua'):format(GetCurrentResourceName()))
    if not chunk then
        ServerDebug('Failed to parse local items', err)
        return {}
    end

    local ok, result = pcall(chunk)
    if not ok or type(result) ~= 'table' then
        ServerDebug('Failed to load local items table', result)
        return {}
    end

    return result
end

local function copyHerbList(list)
    local normalized = {}

    if type(list) ~= 'table' then
        return normalized
    end

    for _, herbId in ipairs(list) do
        herbId = tostring(herbId or ''):lower()
        if herbId ~= '' and Config.Herbs[herbId] then
            normalized[#normalized + 1] = herbId
        end
    end

    return normalized
end

local function getZoneHerbIds(zone)
    local herbId = HerbZones.GetZoneHerbId(zone)
    local herbIds = herbId and { herbId } or copyHerbList(zone.allowedHerbs or zone.herbIds)
    if #herbIds > 0 then
        return herbIds
    end

    for herbId in pairs(Config.Herbs or {}) do
        herbIds[#herbIds + 1] = herbId
    end

    table.sort(herbIds)
    return herbIds
end

local function getZoneCandidateCount(zone)
    local maxActiveNodes = math.max(1, math.floor(tonumber(zone.maxActiveNodes) or 1))
    local density = math.max(1.0, tonumber(zone.density) or tonumber(Config.ZoneCandidateMultiplier) or 2.0)
    return math.max(maxActiveNodes, math.floor(maxActiveNodes * density + 0.5))
end

local function isFarEnough(coords, placedNodes, minDistance)
    for _, placed in ipairs(placedNodes) do
        if #(coords - placed) < minDistance then
            return false
        end
    end

    return true
end

local function buildZoneNodeEntries()
    local configuredZones = HerbZoneStore and HerbZoneStore.GetZones and HerbZoneStore.GetZones() or HerbZones.CloneZones(Config.Zones or {})

    for zoneIndex, zone in ipairs(configuredZones) do
        local center = HerbShared.NormalizeVector3(zone.center)
        local radius = tonumber(zone.radius) or 0.0
        if center and radius > 0.0 and zone.enabled ~= false then
            local zoneId = tostring(zone.id or ('zone_%s'):format(zoneIndex))
            local herbIds = getZoneHerbIds(zone)
            local minDistance = math.max(2.0, tonumber(zone.minNodeDistance) or tonumber(Config.ZoneMinNodeDistance) or 9.0)
            local candidateCount = getZoneCandidateCount(zone)
            local herbId = herbIds[1]
            local herb = herbId and Config.Herbs[herbId] or nil

            if herb then
                for slot = 1, candidateCount do
                    local key = HerbShared.BuildZoneNodeKey(zoneId, slot, herbId)
                    NodeEntries[key] = {
                        key = key,
                        zoneId = zoneId,
                        herbId = herbId,
                        herb = herb,
                        coords = center,
                        center = center,
                        radius = radius,
                        minNodeDistance = minDistance,
                        rewardMin = math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                        rewardMax = math.max(
                            math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                            tonumber(zone.rewardMax) or tonumber(herb.amount and herb.amount.max) or 1
                        ),
                    }
                end
            end
        end
    end
end

local function buildLegacyNodeEntries()
    for index, node in ipairs(Config.Nodes or {}) do
        local herb = Config.Herbs[node.herbId]
        if herb then
            local key = HerbShared.BuildNodeKey(index, node)
            NodeEntries[key] = {
                key = key,
                herbId = node.herbId,
                herb = herb,
                coords = HerbShared.NormalizeVector3(node.coords),
            }
        end
    end
end

local function buildNodeEntries()
    NodeEntries = {}

    if type(Config.Zones) == 'table' and #Config.Zones > 0 then
        buildZoneNodeEntries()
    end

    if next(NodeEntries) == nil then
        buildLegacyNodeEntries()
    end
end

HerbRuntimeNodes.Rebuild = buildNodeEntries

local function ensureLocalItemsRegistered()
    local sharedItems = RSGCore.Shared and RSGCore.Shared.Items
    if type(sharedItems) ~= 'table' then
        ServerDebug('RSGCore.Shared.Items unavailable')
        return
    end

    for itemName, itemData in pairs(LocalItems) do
        local normalized = tostring(itemName or ''):lower()
        if normalized ~= '' and not sharedItems[normalized] then
            sharedItems[normalized] = itemData
            ServerDebug('Registered local herb item', normalized)
        end
    end
end

local function getPlayer(src)
    return RSGCore.Functions.GetPlayer(src)
end

local function getItemData(itemName)
    return RSGCore.Shared and RSGCore.Shared.Items and RSGCore.Shared.Items[itemName] or LocalItems[itemName] or { name = itemName, label = itemName }
end

local function cleanupExpiredCooldowns()
    local now = HerbShared.GetTimestamp()
    local changed = false

    for nodeKey, expiresAt in pairs(NodeCooldowns) do
        if not tonumber(expiresAt) or expiresAt <= now then
            NodeCooldowns[nodeKey] = nil
            changed = true
        end
    end

    return changed
end

local function syncCooldowns(target)
    cleanupExpiredCooldowns()
    TriggerClientEvent('rsg-herbs:client:syncCooldowns', target or -1, NodeCooldowns)
end

local function isNearCoords(src, coords, radius)
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then
        return false
    end

    local pedCoords = GetEntityCoords(ped)
    local planarDistance = math.sqrt(((pedCoords.x - coords.x) ^ 2) + ((pedCoords.y - coords.y) ^ 2))
    ServerDebug('Distance check', src, 'planar', ('%.2f'):format(planarDistance), 'radius', radius or 2.0)
    return planarDistance <= (radius or 2.0)
end

local function addItem(player, itemName, amount)
    if not player then
        ServerDebug('AddItem blocked: player missing')
        return false
    end

    local normalized = tostring(itemName or ''):lower()
    if normalized == '' then
        ServerDebug('AddItem blocked: item invalid', itemName)
        return false
    end

    local src = player.PlayerData and player.PlayerData.source or nil
    local itemData = getItemData(normalized)
    if not itemData or not itemData.name then
        ServerDebug('AddItem blocked: item missing from shared items', normalized)
        return false
    end

    local ok = false
    if src and GetResourceState('rsg-inventory') == 'started' then
        ServerDebug('Calling inventory export AddItem', src, normalized, amount)
        local exportOk, exportResult = pcall(function()
            return exports['rsg-inventory']:AddItem(src, normalized, amount, false, {}, 'rsg-herbs reward')
        end)
        if not exportOk then
            ServerDebug('Inventory export AddItem errored', src, normalized, exportResult)
        end
        ok = exportOk and exportResult == true
    elseif player.Functions and type(player.Functions.AddItem) == 'function' then
        ServerDebug('Calling player function AddItem', src, normalized, amount)
        local fnOk, fnResult = pcall(function()
            return player.Functions.AddItem(normalized, amount, false, false)
        end)
        if not fnOk then
            ServerDebug('Player function AddItem errored', src, normalized, fnResult)
        end
        ok = fnOk and fnResult == true
    end

    if ok then
        ServerDebug('AddItem succeeded', src, normalized, amount)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, itemData, 'add', amount)
    else
        ServerDebug('AddItem failed', src, normalized, amount)
    end

    return ok
end

LocalItems = loadLocalItems()
buildNodeEntries()
ensureLocalItemsRegistered()

RegisterNetEvent('rsg-herbs:server:rewardHerb', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}

    local nodeKey = payload.nodeKey
    local herbId = tostring(payload.herbId or ''):lower()
    local itemName = tostring(payload.itemName or ''):lower()
    local pickupCoords = HerbShared.NormalizeVector3(payload.coords)

    ServerDebug('Reward event received', src, 'nodeKey', nodeKey, 'herbId', herbId, 'item', itemName)

    local player = getPlayer(src)
    if not player then
        ServerDebug('Reward blocked: player missing', src)
        return
    end

    cleanupExpiredCooldowns()

    local node = NodeEntries[nodeKey]
    if not node or not node.herb then
        local zoneId, _, keyHerbId = HerbShared.ParseZoneNodeKey(nodeKey)
        local zone = zoneId and HerbZoneStore and HerbZoneStore.GetZoneById and HerbZoneStore.GetZoneById(zoneId) or nil
        local resolvedHerbId = tostring(keyHerbId or herbId or ''):lower()
        local herb = resolvedHerbId ~= '' and Config.Herbs[resolvedHerbId] or Config.Herbs[herbId]

        if zone and herb and pickupCoords then
            node = {
                key = nodeKey,
                zoneId = zone.id,
                herbId = resolvedHerbId,
                herb = herb,
                coords = pickupCoords,
                rewardMin = math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                rewardMax = math.max(
                    math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                    tonumber(zone.rewardMax) or tonumber(herb.amount and herb.amount.max) or 1
                ),
            }
            ServerDebug('Reward fallback: reconstructed zone node from payload', src, nodeKey, resolvedHerbId)
        elseif herb and itemName == tostring(herb.item or ''):lower() and pickupCoords then
            node = {
                key = nodeKey,
                herbId = herbId,
                herb = herb,
                coords = pickupCoords,
            }
            ServerDebug('Reward fallback: reconstructed node from payload', src, nodeKey, herbId)
        else
            ServerDebug('Reward blocked: invalid node', src, nodeKey)
            return
        end
    end

    if herbId == '' then
        herbId = tostring(node.herbId or ''):lower()
    end

    if itemName == '' then
        itemName = tostring(node.herb and node.herb.item or ''):lower()
    end

    if herbId ~= node.herbId then
        ServerDebug('Reward blocked: herbId mismatch', src, herbId, node.herbId)
        return
    end

    if tostring(itemName or ''):lower() ~= tostring(node.herb.item or ''):lower() then
        ServerDebug('Reward blocked: item mismatch', src, itemName, node.herb.item)
        return
    end

    local validationCoords = pickupCoords or node.coords
    if not isNearCoords(src, validationCoords, math.max(2.0, tonumber(Config.InteractDistance) or 1.8) + 0.75) then
        ServerDebug('Reward blocked: too far away', src, nodeKey)
        return
    end

    local now = HerbShared.GetTimestamp()
    if (NodeCooldowns[nodeKey] or 0) > now then
        ServerDebug('Reward blocked: node on cooldown', src, nodeKey, NodeCooldowns[nodeKey], now)
        return
    end

    local amountMin = math.max(1, tonumber(node.rewardMin) or tonumber(node.herb.amount and node.herb.amount.min) or 1)
    local amountMax = math.max(amountMin, tonumber(node.rewardMax) or tonumber(node.herb.amount and node.herb.amount.max) or amountMin)
    local amount = math.random(amountMin, amountMax)

    ServerDebug('Validated reward', src, 'herbType', node.herbId, 'item', node.herb.item, 'amount', amount)

    if not addItem(player, node.herb.item, amount) then
        ServerDebug('Reward blocked: inventory add failed', src, node.herb.item, amount)
        return
    end

    NodeCooldowns[nodeKey] = now + math.max(1, tonumber(node.herb.cooldownSeconds) or 1200)
    syncCooldowns(-1)
    ServerDebug('Reward granted', src, node.herb.item, amount)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    buildNodeEntries()
    ensureLocalItemsRegistered()
    syncCooldowns(-1)
    ServerDebug('Resource started for herb reward test')
end)

RegisterNetEvent('RSGCore:Server:PlayerLoaded', function()
    syncCooldowns(source)
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, tonumber(Config.CleanupIntervalMs) or 30000))

        if cleanupExpiredCooldowns() then
            syncCooldowns(-1)
        end
    end
end)
