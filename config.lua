Config = {}

Config.Debug = true
Config.InteractDistance = 1.8
Config.SpawnDistance = 100.0
Config.DespawnDistance = 125.0
Config.ZoneActivationDistance = 125.0
Config.PickupDurationMs = 5500
Config.SessionTimeoutSeconds = 15
Config.CleanupIntervalMs = 30000
Config.ZoneReconcileIntervalMs = 1250
Config.ZoneCandidateMultiplier = 2.0
Config.ZoneCandidateAttemptsPerNode = 10
Config.ZoneSpawnRetryAttempts = 18
Config.ZoneMinNodeDistance = 9.0
Config.ZonePlayerSpawnBuffer = 20.0
Config.ZoneRoadBuffer = 8.0
Config.ZoneGroundProbeHeight = 80.0
Config.ZoneGroundProbeDepth = 80.0
Config.ZoneSaveFile = 'data/zones.json'
Config.AdminCommand = 'herbzones'
Config.AdminAcePermission = nil

Config.Blips = {
    enabled = true,
    target = 'zones', -- 'zones' or 'nodes'
    style = 1664425300,
    sprite = 'blip_plant', -- alternatives from rdr3_discoveries: blip_grub, blip_region_hunting, blip_ambient_tracking
    scale = 0.55,
    visibleDisplay = 2,
    hiddenDisplay = 0,
    visibleAlpha = 255,
    hiddenAlpha = 0,
    cycleIntervalSeconds = 90,
    cycleMode = 'multiple', -- 'single' or 'multiple'
    minVisibleZones = 1,
    maxVisibleZones = 2,
    herbTypes = {
        yarrow = {
            color = 1, -- red
            sprite = 'blip_plant',
            label = 'Yarrow Area',
        },
        burdock_root = {
            color = 17, -- brown
            sprite = 'blip_plant',
            label = 'Burdock Root Area',
        },
        ginseng = {
            color = 40, -- black / dark
            sprite = 'blip_plant',
            label = 'Ginseng Area',
        },
    },
}

Config.Herbs = {
    yarrow = {
        label = 'Yarrow',
        item = 'yarrow',
        composite = 'COMPOSITE_LOOTABLE_YARROW_DEF',
        amount = { min = 1, max = 1 },
        cooldownSeconds = 1200,
    },
    burdock_root = {
        label = 'Burdock Root',
        item = 'burdock_root',
        composite = 'COMPOSITE_LOOTABLE_BURDOCK_ROOT_DEF',
        amount = { min = 1, max = 2 },
        cooldownSeconds = 1500,
    },
    ginseng = {
        label = 'American Ginseng',
        item = 'ginseng',
        composite = 'COMPOSITE_LOOTABLE_AMERICAN_GINSENG_ROOT_DEF',
        amount = { min = 1, max = 2 },
        cooldownSeconds = 1800,
    },
}

Config.Zones = {
    {
        id = 'big_valley_yarrow_east',
        center = vector3(-382.22, 786.38, 115.76),
        radius = 55.0,
        maxActiveNodes = 4,
        density = 2.0,
        minNodeDistance = 10.0,
        playerSpawnBuffer = 18.0,
        roadBuffer = 8.0,
        allowedHerbs = { 'yarrow' },
    },
    {
        id = 'big_valley_yarrow_west',
        center = vector3(-468.54, 742.13, 112.14),
        radius = 70.0,
        maxActiveNodes = 5,
        density = 2.2,
        minNodeDistance = 10.0,
        playerSpawnBuffer = 20.0,
        roadBuffer = 10.0,
        allowedHerbs = { 'yarrow' },
    },
    {
        id = 'lower_montana_burdock_marsh_east',
        center = vector3(-2778.49, -2968.75, 66.66),
        radius = 58.0,
        maxActiveNodes = 4,
        density = 2.0,
        minNodeDistance = 11.0,
        playerSpawnBuffer = 20.0,
        roadBuffer = 7.0,
        allowedHerbs = { 'burdock_root' },
    },
    {
        id = 'lower_montana_burdock_marsh_west',
        center = vector3(-2842.16, -3018.42, 64.91),
        radius = 64.0,
        maxActiveNodes = 5,
        density = 2.2,
        minNodeDistance = 11.0,
        playerSpawnBuffer = 20.0,
        roadBuffer = 7.0,
        allowedHerbs = { 'burdock_root' },
    },
    {
        id = 'heartlands_ginseng_shade_east',
        center = vector3(1412.68, 816.66, 104.05),
        radius = 52.0,
        maxActiveNodes = 4,
        density = 2.0,
        minNodeDistance = 10.0,
        playerSpawnBuffer = 20.0,
        roadBuffer = 9.0,
        allowedHerbs = { 'ginseng' },
    },
    {
        id = 'dakota_ginseng_shade_west',
        center = vector3(-1260.03, 171.44, 48.82),
        radius = 58.0,
        maxActiveNodes = 4,
        density = 2.1,
        minNodeDistance = 10.0,
        playerSpawnBuffer = 20.0,
        roadBuffer = 9.0,
        allowedHerbs = { 'ginseng' },
    },
}

Config.Nodes = Config.Nodes or {}
