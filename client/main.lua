local isLoaded = false
local activeNodes = {}
local nodeEntries = {}
local zones = {}
local runtimeZones = nil
local pickupState = nil
local activeCooldowns = {}
local holdState = nil
local visibleZoneIds = {}
local zoneCycleOrder = {}
local zoneCycleRng = HerbShared.CreateSeededRng(HerbShared.HashSeed(GetCurrentResourceName(), 'zone_blip_cycle'))

local INPUT_CONTEXT_X = 0x27D1C284 -- R / INPUT_LOOT3
local MAP_CREATE_BLIP = 0x554D9D53F696D002
local SET_BLIP_NAME_FROM_PLAYER_STRING = 0x9CB1A1623062F402

print(('[%s][client] client/main.lua loaded'):format(GetCurrentResourceName()))

local function normalizeHash(value)
    local number = tonumber(value) or 0
    number = number % 0x100000000
    if number >= 0x80000000 then
        number = number - 0x100000000
    end
    return number
end

local function loadComposite(compositeHash)
    if not compositeHash or compositeHash == 0 then
        ClientDebug('Spawn blocked: invalid composite hash', compositeHash)
        return false
    end

    Citizen.InvokeNative(0x73F0D0327BFA0812, compositeHash)

    local timeoutAt = GetGameTimer() + 5000
    while not Citizen.InvokeNative(0x5E5D96BE25E9DF68, compositeHash) do
        if GetGameTimer() >= timeoutAt then
            ClientDebug('Spawn blocked: composite failed to load in time', compositeHash)
            return false
        end

        Wait(0)
    end

    return true
end

local function clearPickupState(reason)
    if pickupState then
        ClientDebug(reason or 'Pickup cancelled', pickupState.nodeKey, pickupState.herbLabel)
    end
    pickupState = nil
    holdState = nil
end

local function isBlipEnabled()
    return type(Config.Blips) == 'table' and Config.Blips.enabled == true
end

local function getBlipConfig()
    return type(Config.Blips) == 'table' and Config.Blips or {}
end

local function useZoneBlips()
    return tostring(getBlipConfig().target or 'zones'):lower() ~= 'nodes'
end

local function isDebugEnabled()
    return type(Config) == 'table' and Config.Debug == true
end

local function getHerbBlipConfig(herbId)
    local blipConfig = getBlipConfig()
    local herbTypes = type(blipConfig.herbTypes) == 'table' and blipConfig.herbTypes or {}
    local herbConfig = herbTypes[herbId]

    if type(herbConfig) ~= 'table' then
        herbConfig = {}
    end

    return herbConfig
end

local function buildLookupSet(values)
    local lookup = {}

    for _, value in ipairs(values or {}) do
        lookup[tostring(value or '')] = true
    end

    return lookup
end

local function visibilitySetsMatch(left, right)
    for key in pairs(left or {}) do
        if not right or not right[key] then
            return false
        end
    end

    for key in pairs(right or {}) do
        if not left or not left[key] then
            return false
        end
    end

    return true
end

local function isZoneVisible(zoneId)
    return visibleZoneIds[tostring(zoneId or '')] == true
end

local function setBlipVisible(blip, isVisible)
    if not blip or blip == 0 then
        return false
    end

    local blipConfig = getBlipConfig()
    local visibleDisplay = tonumber(blipConfig.visibleDisplay)
    local hiddenDisplay = tonumber(blipConfig.hiddenDisplay)
    local visibleAlpha = tonumber(blipConfig.visibleAlpha)
    local hiddenAlpha = tonumber(blipConfig.hiddenAlpha)
    local updated = false

    if type(SetBlipDisplay) == 'function' and visibleDisplay and hiddenDisplay then
        pcall(SetBlipDisplay, blip, isVisible and visibleDisplay or hiddenDisplay)
        updated = true
    end

    if type(SetBlipAlpha) == 'function' and visibleAlpha and hiddenAlpha then
        pcall(SetBlipAlpha, blip, isVisible and visibleAlpha or hiddenAlpha)
        updated = true
    end

    return updated
end

local function removeZoneBlip(zone)
    if not zone or not zone.blip or zone.blip == 0 then
        return
    end

    if type(RemoveBlip) == 'function' then
        pcall(RemoveBlip, zone.blip)
    end

    zone.blip = nil
    zone.blipVisible = nil
end

local function ensureZoneBlip(zone)
    if not isBlipEnabled() or not useZoneBlips() or not zone or zone.blip or not zone.center then
        return
    end

    local blipConfig = getBlipConfig()
    local herbConfig = getHerbBlipConfig(zone.displayHerbId)
    local color = tonumber(herbConfig.color or herbConfig.colour or blipConfig.defaultColor or blipConfig.defaultColour or 1) or 1
    local style = tonumber(blipConfig.style) or 1664425300
    local spriteName = tostring(herbConfig.sprite or blipConfig.sprite or ''):lower()
    local scale = tonumber(herbConfig.scale or blipConfig.scale) or 0.55
    local label = herbConfig.label or zone.label or 'Herb Area'

    local blip = Citizen.InvokeNative(MAP_CREATE_BLIP, style, zone.center.x, zone.center.y, zone.center.z)
    if not blip or blip == 0 then
        ClientDebug('Zone blip create failed', zone.id, zone.displayHerbId)
        return
    end

    if type(SetBlipScale) == 'function' then
        pcall(SetBlipScale, blip, scale)
    end

    if type(SetBlipColour) == 'function' then
        pcall(SetBlipColour, blip, color)
    end

    if spriteName ~= '' and type(SetBlipSprite) == 'function' then
        pcall(SetBlipSprite, blip, joaat(spriteName), true)
    end

    Citizen.InvokeNative(SET_BLIP_NAME_FROM_PLAYER_STRING, blip, label)

    zone.blip = blip
    zone.blipVisible = nil
    setBlipVisible(blip, isZoneVisible(zone.id))
end

local function updateZoneBlipVisibility(zone)
    if not isBlipEnabled() or not useZoneBlips() or not zone then
        return
    end

    ensureZoneBlip(zone)
    if not zone.blip then
        return
    end

    local shouldBeVisible = isZoneVisible(zone.id)
    if zone.blipVisible == shouldBeVisible then
        return
    end

    local visibilityUpdated = setBlipVisible(zone.blip, shouldBeVisible)
    if not visibilityUpdated and not shouldBeVisible then
        removeZoneBlip(zone)
        zone.blipVisible = false
        return
    end

    zone.blipVisible = shouldBeVisible
end

local function refreshAllZoneBlipVisibility(reason)
    if not isBlipEnabled() or not useZoneBlips() then
        return
    end

    for _, zone in ipairs(zones) do
        updateZoneBlipVisibility(zone)
    end

    if reason then
        ClientDebug(reason)
    end
end

local function getCyclableZones()
    local availableZones = {}

    for _, zone in ipairs(zones) do
        if zone.center then
            availableZones[#availableZones + 1] = zone
        end
    end

    return availableZones
end

local function selectRandomVisibleZones()
    local availableZones = getCyclableZones()
    local zoneCount = #availableZones
    if zoneCount == 0 then
        return {}
    end

    local blipConfig = getBlipConfig()
    local cycleMode = tostring(blipConfig.cycleMode or 'single'):lower()
    local minVisibleZones = math.max(1, math.floor(tonumber(blipConfig.minVisibleZones) or 1))
    local maxVisibleZones = math.max(minVisibleZones, math.floor(tonumber(blipConfig.maxVisibleZones) or zoneCount))
    local selectionCount = 1

    if cycleMode == 'multiple' then
        minVisibleZones = math.min(minVisibleZones, zoneCount)
        maxVisibleZones = math.min(maxVisibleZones, zoneCount)
        selectionCount = math.max(minVisibleZones, math.floor(zoneCycleRng() * (maxVisibleZones - minVisibleZones + 1)) + minVisibleZones)
    end

    for index = zoneCount, 2, -1 do
        local swapIndex = math.floor(zoneCycleRng() * index) + 1
        availableZones[index], availableZones[swapIndex] = availableZones[swapIndex], availableZones[index]
    end

    local selected = {}
    for index = 1, math.min(selectionCount, zoneCount) do
        selected[#selected + 1] = availableZones[index].id
    end

    table.sort(selected)
    return selected
end

local function cycleVisibleZones(force)
    if not isBlipEnabled() or not useZoneBlips() then
        visibleZoneIds = {}
        zoneCycleOrder = {}
        return
    end

    local availableZones = getCyclableZones()
    if #availableZones == 0 then
        visibleZoneIds = {}
        zoneCycleOrder = {}
        return
    end

    local nextOrder = zoneCycleOrder
    local nextSet = visibleZoneIds

    if force or #availableZones == 1 then
        nextOrder = selectRandomVisibleZones()
        nextSet = buildLookupSet(nextOrder)
    else
        for _ = 1, 5 do
            local candidateOrder = selectRandomVisibleZones()
            local candidateSet = buildLookupSet(candidateOrder)
            if not visibilitySetsMatch(visibleZoneIds, candidateSet) then
                nextOrder = candidateOrder
                nextSet = candidateSet
                break
            end
        end
    end

    if not force and visibilitySetsMatch(visibleZoneIds, nextSet) then
        return
    end

    visibleZoneIds = nextSet
    zoneCycleOrder = nextOrder
    refreshAllZoneBlipVisibility(('Visible herb zones changed: %s'):format(table.concat(zoneCycleOrder, ', ')))
end

local function deleteNode(node, reason)
    if not node then
        return
    end

    if node.debugBlip and node.debugBlip ~= 0 and type(RemoveBlip) == 'function' then
        pcall(RemoveBlip, node.debugBlip)
        node.debugBlip = nil
    end

    if node.scenarioId and node.scenarioId ~= -1 then
        Citizen.InvokeNative(0x5758B1EE0C3FD4AC, node.scenarioId, 0)
    end

    ClientDebug(reason or 'Herb despawned', node.key, node.herb.label)
    activeNodes[node.key] = nil

    if pickupState and pickupState.nodeKey == node.key then
        pickupState = nil
    end

    if holdState and holdState.nodeKey == node.key then
        holdState = nil
    end
end

local function deleteAllNodes(reason)
    local keys = {}
    for key in pairs(activeNodes) do
        keys[#keys + 1] = key
    end

    for _, key in ipairs(keys) do
        deleteNode(activeNodes[key], reason)
    end
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

local function getConfiguredZones()
    if type(runtimeZones) == 'table' then
        return runtimeZones
    end

    return Config.Zones or {}
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

local function buildLegacyNodes()
    zones = {}
    nodeEntries = {}

    for index, node in ipairs(Config.Nodes or {}) do
        local herb = Config.Herbs and Config.Herbs[node.herbId] or nil
        local coords = HerbShared.NormalizeVector3(node.coords)
        if herb and coords then
            local key = HerbShared.BuildNodeKey(index, node)
            local entry = {
                key = key,
                zoneId = 'legacy',
                herbId = node.herbId,
                herb = herb,
                coords = coords,
                heading = tonumber(node.heading) or 0.0,
                compositeHash = normalizeHash(joaat(herb.composite)),
                playerSpawnBuffer = math.max(4.0, tonumber(Config.ZonePlayerSpawnBuffer) or 20.0),
                roadBuffer = math.max(0.0, tonumber(Config.ZoneRoadBuffer) or 8.0),
            }

            nodeEntries[key] = entry
            zones[1] = zones[1] or {
                id = 'legacy',
                center = coords,
                herbIds = { node.herbId },
                displayHerbId = node.herbId,
                label = ('%s Area'):format(herb.label),
                radius = math.max(5.0, tonumber(Config.SpawnDistance) or 100.0),
                maxActiveNodes = math.max(1, #(Config.Nodes or {})),
                candidates = {},
            }
            zones[1].candidates[#zones[1].candidates + 1] = entry
        end
    end
end

local function buildZoneNodes()
    zones = {}
    nodeEntries = {}

    for zoneIndex, zone in ipairs(getConfiguredZones()) do
        local center = HerbShared.NormalizeVector3(zone.center)
        local radius = tonumber(zone.radius) or 0.0
        if center and radius > 0.0 and zone.enabled ~= false then
            local zoneId = tostring(zone.id or ('zone_%s'):format(zoneIndex))
            local herbIds = getZoneHerbIds(zone)
            if #herbIds == 0 then
                ClientDebug('Zone skipped: no valid herbs configured', zoneId)
            else
                local minDistance = math.max(2.0, tonumber(zone.minNodeDistance) or tonumber(Config.ZoneMinNodeDistance) or 9.0)
                local playerSpawnBuffer = math.max(4.0, tonumber(zone.playerSpawnBuffer) or tonumber(Config.ZonePlayerSpawnBuffer) or 20.0)
                local roadBuffer = math.max(0.0, tonumber(zone.roadBuffer) or tonumber(Config.ZoneRoadBuffer) or 8.0)
                local candidateCount = getZoneCandidateCount(zone)
                local herbId = herbIds[1]
                local herb = herbId and Config.Herbs[herbId] or nil
                local candidates = {}

                if herb then
                    for slot = 1, candidateCount do
                        local key = HerbShared.BuildZoneNodeKey(zoneId, slot, herbId)
                        local entry = {
                            key = key,
                            zoneId = zoneId,
                            slot = slot,
                            herbId = herbId,
                            herb = herb,
                            center = center,
                            radius = radius,
                            minNodeDistance = minDistance,
                            compositeHash = normalizeHash(joaat(herb.composite)),
                            playerSpawnBuffer = playerSpawnBuffer,
                            roadBuffer = roadBuffer,
                            rewardMin = math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                            rewardMax = math.max(
                                math.max(1, tonumber(zone.rewardMin) or tonumber(herb.amount and herb.amount.min) or 1),
                                tonumber(zone.rewardMax) or tonumber(herb.amount and herb.amount.max) or 1
                            ),
                            spawnAttempts = math.max(6, tonumber(zone.spawnAttempts) or tonumber(Config.ZoneSpawnRetryAttempts) or 18),
                        }

                        candidates[#candidates + 1] = entry
                        nodeEntries[key] = entry
                    end
                end

                zones[#zones + 1] = {
                    id = zoneId,
                    center = center,
                    herbIds = herbIds,
                    displayHerbId = herbIds[1],
                    label = Config.Herbs[herbIds[1]] and ('%s Area'):format(Config.Herbs[herbIds[1]].label) or 'Herb Area',
                    radius = radius,
                    maxActiveNodes = math.max(1, math.floor(tonumber(zone.maxActiveNodes) or 1)),
                    candidates = candidates,
                }
            end
        end
    end
end

local function buildNodeEntries()
    if type(getConfiguredZones()) == 'table' and #getConfiguredZones() > 0 then
        buildZoneNodes()
    else
        buildLegacyNodes()
    end
end

local function getGroundZ(coords)
    local probeHeight = math.max(20.0, tonumber(Config.ZoneGroundProbeHeight) or 80.0)
    local success, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + probeHeight, false)
    if success then
        return groundZ
    end

    success, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z - math.max(20.0, tonumber(Config.ZoneGroundProbeDepth) or 80.0), false)
    if success then
        return groundZ
    end

    return nil
end

local function getWaterHeightAtCoords(coords)
    local probeZ = coords.z + 2.0
    local waterHeight = nil
    local foundWater = false

    for _, nativeName in ipairs({ 'GetWaterHeightNoWaves', 'GetWaterHeight' }) do
        local nativeFn = _G[nativeName]
        if type(nativeFn) == 'function' then
            local ok, resultA, resultB = pcall(nativeFn, coords.x, coords.y, probeZ)
            if ok then
                if type(resultA) == 'boolean' and resultA and tonumber(resultB) then
                    foundWater = true
                    waterHeight = waterHeight and math.max(waterHeight, resultB) or resultB
                elseif tonumber(resultA) and resultB == nil then
                    foundWater = true
                    waterHeight = waterHeight and math.max(waterHeight, resultA) or resultA
                end
            end
        end
    end

    return foundWater, waterHeight
end

local function isDrySpawnLocation(coords)
    local foundWater, waterHeight = getWaterHeightAtCoords(coords)
    if not foundWater or not waterHeight then
        return true
    end

    if waterHeight >= (coords.z - 0.35) then
        return false
    end

    return true
end

local function isPointNearRoad(coords, roadBuffer)
    roadBuffer = math.max(0.0, tonumber(roadBuffer) or tonumber(Config.ZoneRoadBuffer) or 8.0)
    if roadBuffer <= 0.0 then
        return false
    end

    if type(GetClosestVehicleNode) ~= 'function' then
        return false
    end

    local ok, found, roadPos = pcall(GetClosestVehicleNode, coords.x, coords.y, coords.z, 1, 3.0, 0)
    if not ok or not found or type(roadPos) ~= 'vector3' then
        return false
    end

    return #(coords - vector3(roadPos.x, roadPos.y, roadPos.z or coords.z)) < roadBuffer
end

local function pickRandomPointInZone(center, radius)
    local angle = math.random() * math.pi * 2.0
    local distance = math.sqrt(math.random()) * radius

    return vector3(
        center.x + math.cos(angle) * distance,
        center.y + math.sin(angle) * distance,
        center.z
    )
end

local function findSpawnPointForCandidate(node, playerCoords)
    local cooldownUntil = activeCooldowns[node.key] or 0
    if cooldownUntil > HerbShared.GetTimestamp() then
        return false, 'cooldown'
    end

    if activeNodes[node.key] then
        return false, 'duplicate'
    end

    for _ = 1, math.max(1, tonumber(node.spawnAttempts) or tonumber(Config.ZoneSpawnRetryAttempts) or 18) do
        local candidateCoords = pickRandomPointInZone(node.center, node.radius)
        local groundZ = getGroundZ(candidateCoords)
        if groundZ then
            local spawnCoords = vector3(candidateCoords.x, candidateCoords.y, groundZ)
            if #(playerCoords - spawnCoords) >= node.playerSpawnBuffer
                and not isPointNearRoad(spawnCoords, node.roadBuffer)
                and isDrySpawnLocation(spawnCoords)
            then
                local clear = true

                for _, activeNode in pairs(activeNodes) do
                    if #(spawnCoords - activeNode.coords) < math.max(2.0, tonumber(node.minNodeDistance) or tonumber(Config.ZoneMinNodeDistance) or 9.0) then
                        clear = false
                        break
                    end
                end

                if clear then
                    return true, spawnCoords, math.random() * 360.0
                end
            end
        end
    end

    return false, 'no_valid_point'
end

local function spawnNode(node, spawnCoords, heading)
    if not loadComposite(node.compositeHash) then
        return false
    end

    local scenarioId = Citizen.InvokeNative(
        0x5B4BBE80AD5972DC,
        node.compositeHash,
        spawnCoords.x,
        spawnCoords.y,
        spawnCoords.z,
        heading or 0.0,
        0,
        Citizen.PointerValueInt(),
        -1,
        Citizen.ReturnResultAnyway()
    )

    if not scenarioId or scenarioId == -1 then
        ClientDebug('Spawn blocked: failed to create herb composite', node.key, node.herb.label)
        return false
    end

    local debugBlip = nil
    if isDebugEnabled() then
        debugBlip = Citizen.InvokeNative(MAP_CREATE_BLIP, 1664425300, spawnCoords.x, spawnCoords.y, spawnCoords.z)
        if debugBlip and debugBlip ~= 0 then
            if type(SetBlipSprite) == 'function' then
                pcall(SetBlipSprite, debugBlip, joaat('blip_ambient_ped_small'), true)
            end

            if type(SetBlipColour) == 'function' then
                pcall(SetBlipColour, debugBlip, 1)
            end

            if type(SetBlipScale) == 'function' then
                pcall(SetBlipScale, debugBlip, 0.35)
            end

            Citizen.InvokeNative(SET_BLIP_NAME_FROM_PLAYER_STRING, debugBlip, ('Debug Herb: %s'):format(node.herb.label))
        else
            debugBlip = nil
        end
    end

    activeNodes[node.key] = {
        key = node.key,
        zoneId = node.zoneId,
        herbId = node.herbId,
        herb = node.herb,
        coords = spawnCoords,
        logicCoords = node.center,
        rewardMin = node.rewardMin,
        rewardMax = node.rewardMax,
        debugBlip = debugBlip,
        scenarioId = scenarioId,
    }

    ClientDebug('Herb spawned', node.key, node.herb.label, spawnCoords.x, spawnCoords.y, spawnCoords.z)
    return true
end

local function findNearbySpawnedNode()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        return nil
    end

    local playerCoords = GetEntityCoords(ped)
    local maxDistance = math.max(2.0, tonumber(Config.InteractDistance) or 1.8) + 0.75
    local closestNode = nil
    local closestDistance = nil

    for _, node in pairs(activeNodes) do
        local distance = #(playerCoords - node.coords)
        if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
            closestNode = node
            closestDistance = distance
        end
    end

    return closestNode, closestDistance
end

local function isLootControlJustPressed()
    return Citizen.InvokeNative(0x91AEF906BCA88877, 0, INPUT_CONTEXT_X) == true or IsControlJustPressed(0, INPUT_CONTEXT_X)
end

local function isLootControlPressed()
    return Citizen.InvokeNative(0xF3A21BCD95725A4A, 0, INPUT_CONTEXT_X) == true or IsControlPressed(0, INPUT_CONTEXT_X)
end

local function isLootControlJustReleased()
    return Citizen.InvokeNative(0x50F940259D3841E6, 0, INPUT_CONTEXT_X) == true or IsControlJustReleased(0, INPUT_CONTEXT_X)
end

local function beginPickup(node, distance)
    if pickupState then
        return
    end

    pickupState = {
        nodeKey = node.key,
        herbLabel = node.herb.label,
        coords = node.coords,
        startedAt = GetGameTimer(),
        completesAt = GetGameTimer() + math.max(1500, tonumber(Config.PickupDurationMs) or 5500),
        rewardAt = GetGameTimer() + 4500,
        rewardSent = false,
    }

    ClientDebug('Prompt activated', node.key, node.herb.label, 'distance', ('%.2f'):format(distance))
    ClientDebug('Pickup started', node.key, node.herb.label, 'durationMs', pickupState.completesAt - pickupState.startedAt, 'rewardAtMs', pickupState.rewardAt - pickupState.startedAt)
end

local function sendPickupReward()
    if not pickupState then
        return
    end

    if pickupState.rewardSent then
        return
    end

    local node = nodeEntries[pickupState.nodeKey]
    if not node or not node.herb then
        ClientDebug('Reward blocked: node entry missing on client', pickupState.nodeKey)
        return
    end

    local payload = {
        nodeKey = pickupState.nodeKey,
        herbId = node.herbId,
        itemName = node.herb.item,
        coords = pickupState.coords,
    }

    activeCooldowns[node.key] = HerbShared.GetTimestamp() + math.max(1, tonumber(node.herb.cooldownSeconds) or 1200)

    pickupState.rewardSent = true
    ClientDebug('Early reward fired', pickupState.nodeKey, pickupState.herbLabel)
    ClientDebug('Triggering server reward event', 'rsg-herbs:server:rewardHerb', 'nodeKey', payload.nodeKey, 'herbId', payload.herbId, 'item', payload.itemName)
    TriggerServerEvent('rsg-herbs:server:rewardHerb', payload)
end

local function finishPickup()
    if not pickupState then
        return
    end

    if not pickupState.rewardSent then
        sendPickupReward()
    end

    ClientDebug('Pickup finished', pickupState.nodeKey, pickupState.herbLabel)
    deleteNode(activeNodes[pickupState.nodeKey], 'Herb collected')
    pickupState = nil
end

local function processPickupState()
    if not pickupState then
        return
    end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        clearPickupState('Pickup cancelled: player invalid')
        return
    end

    local node, distance = findNearbySpawnedNode()
    if not node or node.key ~= pickupState.nodeKey then
        clearPickupState('Pickup cancelled: player moved away')
        return
    end

    if GetGameTimer() < pickupState.completesAt then
        if not pickupState.rewardSent and GetGameTimer() >= pickupState.rewardAt then
            sendPickupReward()
        end
        return
    end

    finishPickup()
end

local function processSilentHold()
    local node, distance = findNearbySpawnedNode()
    if not node or pickupState then
        if holdState and not node then
            ClientDebug('Silent hold cancelled: player moved away', holdState.nodeKey)
            holdState = nil
        end
        return
    end

    if isLootControlJustPressed() and not holdState then
        holdState = {
            nodeKey = node.key,
            startedAt = GetGameTimer(),
        }
        ClientDebug('Silent hold started', node.key, node.herb.label, 'distance', ('%.2f'):format(distance))
    end

    if holdState and holdState.nodeKey ~= node.key then
        ClientDebug('Silent hold cancelled: node changed', holdState.nodeKey, node.key)
        holdState = nil
        return
    end

    if holdState and isLootControlPressed() then
        local heldMs = GetGameTimer() - holdState.startedAt
        if heldMs >= 500 then
            beginPickup(node, distance)
            holdState = nil
            return
        end
    end

    if holdState and isLootControlJustReleased() then
        local heldMs = GetGameTimer() - holdState.startedAt
        ClientDebug('Silent hold released', node.key, node.herb.label, 'heldMs', heldMs)
        holdState = nil
    end
end

RegisterNetEvent('rsg-herbs:client:syncCooldowns', function(payload)
    activeCooldowns = type(payload) == 'table' and payload or {}
    ClientDebug('Cooldown sync received')
end)

RegisterNetEvent('rsg-herbs:client:syncZones', function(payload)
    payload = type(payload) == 'table' and payload or {}
    runtimeZones = type(payload.zones) == 'table' and payload.zones or {}

    for _, zone in ipairs(zones) do
        removeZoneBlip(zone)
    end

    deleteAllNodes('Zones refreshed')
    buildNodeEntries()
    cycleVisibleZones(true)
    ClientDebug('Zone sync received', #runtimeZones)
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    isLoaded = true
    ClientDebug('Player loaded')
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    isLoaded = false
    for _, zone in ipairs(zones) do
        removeZoneBlip(zone)
    end
    deleteAllNodes('Player unloaded')
    ClientDebug('Player unloaded')
end)

buildNodeEntries()
cycleVisibleZones(true)

CreateThread(function()
    Wait(3000)

    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn then
        isLoaded = true
        ClientDebug('Late login bootstrap')
    end
end)

CreateThread(function()
    while true do
        if not isLoaded or not isBlipEnabled() or not useZoneBlips() then
            Wait(1000)
        else
            local cycleIntervalSeconds = math.max(5, math.floor(tonumber(getBlipConfig().cycleIntervalSeconds) or 90))
            Wait(cycleIntervalSeconds * 1000)

            if isLoaded and isBlipEnabled() and useZoneBlips() then
                cycleVisibleZones(false)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if not isLoaded then
            Wait(500)
        else
            local ped = PlayerPedId()
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                Wait(500)
            elseif #zones == 0 then
                Wait(1000)
            else
                local playerCoords = GetEntityCoords(ped)
                local spawnDistance = math.max(15.0, tonumber(Config.SpawnDistance) or 100.0)
                local despawnDistance = math.max(spawnDistance + 10.0, tonumber(Config.DespawnDistance) or (spawnDistance + 25.0))
                local zoneActivationDistance = math.max(spawnDistance, tonumber(Config.ZoneActivationDistance) or despawnDistance)
                local desiredKeys = {}

                for _, zone in ipairs(zones) do
                    local zoneDistance = #(playerCoords - zone.center)
                    local zoneIsActive = zoneDistance <= (zone.radius + zoneActivationDistance)

                    if zoneIsActive then
                        local zoneActiveCount = 0

                        for _, candidate in ipairs(zone.candidates) do
                            local activeNode = activeNodes[candidate.key]
                            if activeNode then
                                local activeDistance = #(playerCoords - activeNode.coords)
                                if activeDistance <= (zone.radius + despawnDistance) then
                                    desiredKeys[candidate.key] = true
                                    zoneActiveCount = zoneActiveCount + 1
                                else
                                    deleteNode(activeNode, 'Zone herb despawned: player left area')
                                end
                            end
                        end

                        if zoneActiveCount < zone.maxActiveNodes then
                            for _, candidate in ipairs(zone.candidates) do
                                if zoneActiveCount >= zone.maxActiveNodes then
                                    break
                                end

                                if not activeNodes[candidate.key] then
                                    local canSpawn, spawnCoords, heading = findSpawnPointForCandidate(candidate, playerCoords)
                                    if canSpawn then
                                        if spawnNode(candidate, spawnCoords, heading) then
                                            desiredKeys[candidate.key] = true
                                            zoneActiveCount = zoneActiveCount + 1
                                        end
                                    end
                                else
                                    desiredKeys[candidate.key] = true
                                end
                            end
                        end
                    end
                end

                local activeKeys = {}
                for key in pairs(activeNodes) do
                    activeKeys[#activeKeys + 1] = key
                end

                for _, key in ipairs(activeKeys) do
                    if not desiredKeys[key] then
                        deleteNode(activeNodes[key], 'Zone herb despawned: inactive zone')
                    end
                end

                Wait(math.max(250, tonumber(Config.ZoneReconcileIntervalMs) or 1250))
            end
        end
    end
end)

CreateThread(function()
    while true do
        if not isLoaded then
            Wait(100)
        else
            local ped = PlayerPedId()
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                if holdState then
                    holdState = nil
                end
                Wait(100)
            else
                processSilentHold()
                Wait(0)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if not isLoaded then
            Wait(100)
        else
            processPickupState()
            Wait(50)
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for _, zone in ipairs(zones) do
        removeZoneBlip(zone)
    end
    buildNodeEntries()
    cycleVisibleZones(true)
    ClientDebug('Resource started for zone herb spawning')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for _, zone in ipairs(zones) do
        removeZoneBlip(zone)
    end
    deleteAllNodes('Resource stopped')
    ClientDebug('Resource stopped')
end)
