# rsg-herbs

Standalone herb gathering resource for RedM/RSG that spawns harvestable herbs inside configurable zones, rewards players through `rsg-inventory`, and includes an in-game admin menu for creating and managing herb zones.

## Features

- Dynamic herb spawning inside circular zones
- Per-node cooldown handling synced between server and clients
- Support for multiple herb definitions with custom rewards and cooldowns
- Automatic local item registration into `RSGCore.Shared.Items`
- Rotating herb discovery blips with per-herb labels, colors, and sprites
- In-game admin zone editor powered by `ox_lib`
- Saved zone persistence to `data/zones.json`
- Legacy static node fallback through `Config.Nodes`
- Server-side distance and payload validation for reward events

## Dependencies

This resource requires:

- `ox_lib`
- `rsg-core`
- `rsg-inventory`

Defined in `fxmanifest.lua`:

```lua
dependencies {
    'ox_lib',
    'rsg-core',
    'rsg-inventory',
}
```

## Resource Structure

```text
rsg-herbs/
|-- client/
|   |-- admin.lua
|   `-- main.lua
|-- data/
|   |-- items.lua
|   `-- zones.json
|-- server/
|   |-- admin.lua
|   `-- main.lua
|-- shared/
|   |-- helpers.lua
|   `-- zones.lua
|-- config.lua
|-- fxmanifest.lua
`-- README.md
```

## How It Works

1. Zones are loaded from `data/zones.json`.
2. If the file is empty or invalid, the script falls back to `Config.Zones`.
3. When a player gets near a zone, the client attempts to spawn valid herb nodes inside that zone.
4. Players hold the interact key near a spawned herb to harvest it.
5. The server validates the pickup, gives the configured item reward, and applies a cooldown to that node.
6. Admins can create, edit, enable, disable, preview, and delete zones in-game. Changes are saved back to `data/zones.json`.

## Installation

1. Place the resource in your server resources folder.
2. Make sure the folder name is `rsg-herbs` unless you also update references accordingly.
3. Ensure the required dependencies are installed and started.
4. Add the resource to your server startup config after its dependencies.

Example `server.cfg` order:

```cfg
ensure ox_lib
ensure rsg-core
ensure rsg-inventory
ensure rsg-herbs
```

## Inventory Item Setup

This resource already includes local herb item definitions in `data/items.lua` and will register them into `RSGCore.Shared.Items` at runtime if they do not already exist.

Included items:

- `yarrow`
- `burdock_root`
- `ginseng`

If your server already defines these items elsewhere, the resource will not overwrite the existing shared item definitions.

## Default Herbs

The default herb types are configured in `config.lua`:

- `yarrow`
  - Item: `yarrow`
  - Reward: `1-1`
  - Cooldown: `1200` seconds
- `burdock_root`
  - Item: `burdock_root`
  - Reward: `1-2`
  - Cooldown: `1500` seconds
- `ginseng`
  - Item: `ginseng`
  - Reward: `1-2`
  - Cooldown: `1800` seconds

Each herb also defines a world composite used to spawn the harvestable plant model.

## Configuration

Main settings live in `config.lua`.

### General

| Setting | Default | Description |
|---|---:|---|
| `Config.Debug` | `true` | Enables client/server debug prints. |
| `Config.InteractDistance` | `1.8` | Harvest interaction range. |
| `Config.SpawnDistance` | `100.0` | General spawn distance baseline. |
| `Config.DespawnDistance` | `125.0` | Distance at which active spawned herbs are removed. |
| `Config.ZoneActivationDistance` | `125.0` | Extra distance used to determine when a zone becomes active. |
| `Config.PickupDurationMs` | `5500` | Time the player must complete the harvest action. |
| `Config.SessionTimeoutSeconds` | `15` | Reserved session timing value. |
| `Config.CleanupIntervalMs` | `30000` | Server cleanup interval for expired cooldowns. |
| `Config.ZoneReconcileIntervalMs` | `1250` | Client zone/node reconciliation loop interval. |
| `Config.ZoneCandidateMultiplier` | `2.0` | Multiplier used to generate extra candidate spawn slots per zone. |
| `Config.ZoneCandidateAttemptsPerNode` | `10` | Reserved candidate attempt value. |
| `Config.ZoneSpawnRetryAttempts` | `18` | Attempts to find a valid spawn point for a node. |
| `Config.ZoneMinNodeDistance` | `9.0` | Minimum separation between nodes. |
| `Config.ZonePlayerSpawnBuffer` | `20.0` | Prevents spawning too close to players. |
| `Config.ZoneRoadBuffer` | `8.0` | Prevents spawning too close to roads. |
| `Config.ZoneGroundProbeHeight` | `80.0` | Height used when probing for ground Z. |
| `Config.ZoneGroundProbeDepth` | `80.0` | Depth used when probing for ground Z. |
| `Config.ZoneSaveFile` | `data/zones.json` | File used to persist runtime-edited zones. |
| `Config.AdminCommand` | `herbzones` | Admin command that opens the zone editor. |
| `Config.AdminAcePermission` | `nil` | Optional ACE permission checked in addition to RSG admin roles. |

### Blips

`Config.Blips` controls herb map markers.

| Setting | Default | Description |
|---|---:|---|
| `enabled` | `true` | Enables herb blips. |
| `target` | `zones` | Show zone blips or node blips. Current script behavior is zone-focused. |
| `style` | `1664425300` | Native blip style hash. |
| `sprite` | `blip_plant` | Default blip sprite. |
| `scale` | `0.55` | Default blip scale. |
| `visibleDisplay` | `2` | Display mode when visible. |
| `hiddenDisplay` | `0` | Display mode when hidden. |
| `visibleAlpha` | `255` | Alpha when visible. |
| `hiddenAlpha` | `0` | Alpha when hidden. |
| `cycleIntervalSeconds` | `90` | How often visible herb zones rotate. |
| `cycleMode` | `multiple` | `single` or `multiple`. |
| `minVisibleZones` | `1` | Minimum visible zones during cycling. |
| `maxVisibleZones` | `2` | Maximum visible zones during cycling. |

Per-herb blip overrides are supported through `Config.Blips.herbTypes`.

### Zones

Each zone supports:

| Field | Description |
|---|---|
| `id` | Unique zone identifier. |
| `center` | Zone center as `vector3(x, y, z)`. |
| `radius` | Zone radius. |
| `maxActiveNodes` | Max simultaneous herbs spawned in the zone. |
| `density` | Candidate multiplier used for spawn selection. |
| `minNodeDistance` | Minimum spacing between herbs. |
| `playerSpawnBuffer` | Player-safe spawn distance buffer. |
| `roadBuffer` | Prevents nodes spawning near roads. |
| `allowedHerbs` | Herb types allowed in the zone. |
| `rewardMin` | Optional reward override minimum. |
| `rewardMax` | Optional reward override maximum. |
| `enabled` | Set `false` to disable the zone without deleting it. |

The bundled config includes starter zones for:

- Yarrow
- Burdock Root
- American Ginseng

## Admin Usage

Admins can manage zones in-game with:

```text
/herbzones
```

By default, access is granted when the player has:

- `god` permission in `rsg-core`
- `admin` permission in `rsg-core`
- The ACE permission defined in `Config.AdminAcePermission` if you set one

### Admin Menu Actions

- Create a zone from your current location
- Edit zone herb type, radius, reward range, and active spawn count
- Save a new zone center from your current location
- Preview a zone with a temporary blip
- Enable or disable a zone
- Delete a zone
- Reload the saved zone list

## Zone Persistence

Edited zones are saved to:

[`E:\[RedM]\[fr0st scripts]\rsg-herbs\data\zones.json`](E:\[RedM]\[fr0st scripts]\rsg-herbs\data\zones.json)

Important behavior:

- If `data/zones.json` contains valid data, it becomes the active zone source.
- If it is empty or invalid, the resource rebuilds from `Config.Zones`.
- Saving zones in-game updates `data/zones.json`.

The current bundled `zones.json` is empty, so the resource will initially use the zones defined in `config.lua` until zones are saved in-game.

## Adding New Herbs

To add another herb type:

1. Add a new herb entry to `Config.Herbs` in `config.lua`.
2. Add its inventory item to `data/items.lua` or ensure it already exists in `RSGCore.Shared.Items`.
3. Add the herb to one or more zone `allowedHerbs` lists.
4. Optionally add a blip style under `Config.Blips.herbTypes`.

Example:

```lua
Config.Herbs.black_berry = {
    label = 'Black Berry',
    item = 'black_berry',
    composite = 'COMPOSITE_LOOTABLE_BLACK_BERRY_DEF',
    amount = { min = 1, max = 3 },
    cooldownSeconds = 900,
}
```

## Legacy Static Nodes

The resource still supports `Config.Nodes` as a fallback path for older static herb setups. If no valid zone data is available, node entries can be built from that table instead.

For normal use, zone-based spawning is the intended mode.

## Notes

- Harvesting uses the RedM loot/interact control (`R` / `INPUT_LOOT3`).
- Rewards are granted through `rsg-inventory` when available, with a fallback to player item functions.
- Spawn points are validated against ground height, water, roads, player distance, and nearby existing herbs.
- Cooldowns are tracked per node key, not globally per herb type.

## Troubleshooting

### Herbs do not spawn

Check the following:

- `ox_lib`, `rsg-core`, `rsg-inventory`, and `rsg-herbs` are all started
- `Config.Debug` is enabled so you can read debug logs
- Your zone centers and radii are valid
- Spawn buffers are not too strict for the chosen area
- The configured herb composite names are valid on your RedM build

### Players do not receive items

Check:

- `rsg-inventory` is running
- The item exists in your shared item list or `data/items.lua`
- The player is close enough to the herb when the reward is validated
- Another cooldown has not already been applied to that same node

### Admin menu does not open

Check:

- The player has `admin` or `god` permission in `rsg-core`
- Or you have set and granted the ACE permission in `Config.AdminAcePermission`
- `ox_lib` is installed and working correctly

## Recommended Production Changes

Before moving this to production, you will usually want to:

- Set `Config.Debug = false`
- Review all default zone locations
- Confirm your item icons/images exist in your inventory UI
- Tune cooldowns and reward amounts for your economy
- Optionally set `Config.AdminAcePermission` for tighter zone-editor access

## Credits

- Author: `fr0st / Codex`
- Framework: `rsg-core`
- UI/helpers: `ox_lib`
