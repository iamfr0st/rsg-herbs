local previewBlip = nil

local function notify(description, notificationType)
    lib.notify({
        title = 'Herb Zones',
        description = description,
        type = notificationType or 'inform',
    })
end

local function getPlayerCoords()
    local ped = PlayerPedId()
    if not ped or ped <= 0 then
        return nil
    end

    return GetEntityCoords(ped)
end

local function removePreviewBlip()
    if previewBlip and previewBlip ~= 0 and type(RemoveBlip) == 'function' then
        pcall(RemoveBlip, previewBlip)
    end

    previewBlip = nil
end

local function showZonePreview(zone)
    removePreviewBlip()

    local center = HerbShared.NormalizeVector3(zone and zone.center or nil)
    if not center then
        notify('Zone center is missing.', 'error')
        return
    end

    previewBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, center.x, center.y, center.z)
    if previewBlip and previewBlip ~= 0 then
        Citizen.InvokeNative(0x9CB1A1623062F402, previewBlip, ('Zone Preview (%s m)'):format(math.floor(tonumber(zone.radius) or 0)))

        CreateThread(function()
            Wait(15000)
            removePreviewBlip()
        end)
    end
end

local function buildHerbInputOptions(herbOptions)
    local options = {}

    for _, herb in ipairs(herbOptions or {}) do
        options[#options + 1] = {
            value = herb.value,
            label = herb.label,
        }
    end

    return options
end

local function openZoneEditor(zone, herbOptions)
    local currentCenter = HerbShared.NormalizeVector3(zone and zone.center or nil) or getPlayerCoords()
    if not currentCenter then
        notify('Could not resolve a zone center from your position.', 'error')
        return
    end

    local herbId = HerbZones.GetZoneHerbId(zone or {})
    local input = lib.inputDialog(zone and ('Edit Herb Zone: %s'):format(zone.id) or 'Create Herb Zone', {
        {
            type = 'input',
            label = 'Zone Id',
            description = 'Unique zone identifier.',
            required = true,
            default = zone and zone.id or '',
        },
        {
            type = 'select',
            label = 'Herb Type',
            required = true,
            options = buildHerbInputOptions(herbOptions),
            default = herbId,
        },
        {
            type = 'number',
            label = 'Radius',
            required = true,
            default = tonumber(zone and zone.radius or 35.0) or 35.0,
            min = 5,
            max = 250,
        },
        {
            type = 'number',
            label = 'Max Active Spawns',
            required = true,
            default = tonumber(zone and zone.maxActiveNodes or 4) or 4,
            min = 1,
            max = 25,
        },
        {
            type = 'number',
            label = 'Reward Min',
            required = true,
            default = tonumber(zone and zone.rewardMin or 1) or 1,
            min = 1,
            max = 25,
        },
        {
            type = 'number',
            label = 'Reward Max',
            required = true,
            default = tonumber(zone and zone.rewardMax or 2) or 2,
            min = 1,
            max = 25,
        },
        {
            type = 'number',
            label = 'Min Node Distance',
            required = false,
            default = tonumber(zone and zone.minNodeDistance or Config.ZoneMinNodeDistance or 9.0) or 9.0,
            min = 2,
            max = 50,
        },
        {
            type = 'checkbox',
            label = 'Enabled',
            checked = zone == nil or zone.enabled ~= false,
        },
    })

    if not input then
        return
    end

    TriggerServerEvent('rsg-herbs:server:saveZone', {
        oldId = zone and zone.id or nil,
        id = input[1],
        herbId = input[2],
        radius = input[3],
        maxActiveNodes = input[4],
        rewardMin = input[5],
        rewardMax = input[6],
        minNodeDistance = input[7],
        enabled = input[8] == true,
        center = currentCenter,
    })
end

local function openZoneDetail(zone, herbOptions)
    local center = HerbShared.NormalizeVector3(zone.center)
    local options = {
        {
            title = zone.id,
            description = string.format(
                'Herb: %s\nRadius: %.1f\nActive spawns: %s\nReward: %s to %s\nCenter: %.2f, %.2f, %.2f',
                zone.herbId,
                tonumber(zone.radius) or 0.0,
                tonumber(zone.maxActiveNodes) or 0,
                tonumber(zone.rewardMin) or 1,
                tonumber(zone.rewardMax) or 1,
                center and center.x or 0.0,
                center and center.y or 0.0,
                center and center.z or 0.0
            ),
            disabled = true,
        },
        {
            title = 'Save center from current location',
            description = 'Updates the zone center using your current position.',
            onSelect = function()
                local coords = getPlayerCoords()
                if not coords then
                    notify('Could not resolve your current location.', 'error')
                    return
                end

                zone.center = coords
                TriggerServerEvent('rsg-herbs:server:saveZone', zone)
            end,
        },
        {
            title = 'Edit settings',
            description = 'Update herb type, radius, spawn count, and reward range.',
            onSelect = function()
                openZoneEditor(zone, herbOptions)
            end,
        },
        {
            title = 'Refresh zone preview',
            description = 'Drops a temporary preview blip at the current zone center.',
            onSelect = function()
                showZonePreview(zone)
            end,
        },
        {
            title = zone.enabled == false and 'Enable zone' or 'Disable zone',
            description = 'Quick toggle for the zone without deleting it.',
            onSelect = function()
                zone.enabled = zone.enabled == false
                TriggerServerEvent('rsg-herbs:server:saveZone', zone)
            end,
        },
        {
            title = 'Delete zone',
            description = 'Removes this herb zone permanently.',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Delete Herb Zone',
                    content = ('Delete zone "%s"?'):format(zone.id),
                    centered = true,
                    cancel = true,
                })

                if confirm == 'confirm' then
                    TriggerServerEvent('rsg-herbs:server:deleteZone', zone.id)
                end
            end,
        },
    }

    lib.registerContext({
        id = ('rsg-herbs-zone-%s'):format(zone.id),
        title = ('Herb Zone: %s'):format(zone.id),
        menu = 'rsg-herbs-admin',
        options = options,
    })

    lib.showContext(('rsg-herbs-zone-%s'):format(zone.id))
end

local function openAdminMenu(focusZoneId)
    local isAdmin = lib.callback.await('rsg-herbs:server:isAdmin', false)
    if not isAdmin then
        notify('You do not have permission to open the herb zone menu.', 'error')
        return
    end

    local response = lib.callback.await('rsg-herbs:server:getZones', false)
    if not response or not response.ok then
        notify(response and response.error or 'Failed to load herb zones.', 'error')
        return
    end

    local zones = response.zones or {}
    local herbOptions = response.herbOptions or {}
    local options = {
        {
            title = 'Create zone from current location',
            description = 'Uses your current position as the zone center.',
            onSelect = function()
                openZoneEditor(nil, herbOptions)
            end,
        },
        {
            title = 'Reload saved zones',
            description = 'Refreshes your local admin view.',
            onSelect = function()
                TriggerServerEvent('rsg-herbs:server:requestAdminMenu')
            end,
        },
    }

    table.sort(zones, function(left, right)
        return tostring(left.id or '') < tostring(right.id or '')
    end)

    for _, zone in ipairs(zones) do
        options[#options + 1] = {
            title = zone.id,
            description = ('%s | radius %.1f | spawns %s | reward %s-%s | %s'):format(
                zone.herbId,
                tonumber(zone.radius) or 0.0,
                tonumber(zone.maxActiveNodes) or 0,
                tonumber(zone.rewardMin) or 1,
                tonumber(zone.rewardMax) or 1,
                zone.enabled == false and 'disabled' or 'enabled'
            ),
            onSelect = function()
                openZoneDetail(zone, herbOptions)
            end,
        }
    end

    lib.registerContext({
        id = 'rsg-herbs-admin',
        title = 'Herb Zone Admin',
        options = options,
    })

    lib.showContext('rsg-herbs-admin')

    if focusZoneId then
        for _, zone in ipairs(zones) do
            if zone.id == focusZoneId then
                openZoneDetail(zone, herbOptions)
                break
            end
        end
    end
end

RegisterNetEvent('rsg-herbs:client:openAdminMenu', function(focusZoneId)
    openAdminMenu(focusZoneId)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    removePreviewBlip()
end)
