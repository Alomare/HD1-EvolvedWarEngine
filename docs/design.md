# Design

How the mod turns an Evolved war into HELLDIVERS missions. The server side is in Obsidian Commander (`server/src/evolved.rs`, `docs/evolved.md`).

## Data flow

```
Commander server  --GET /w/<id>/evolved/state-->  Obsidian relay  -->  mod (src/net.lua, every 8 s with the map up, 40 s otherwise)
                  <--POST /w/<id>/evolved/report-- Obsidian relay  <--  mod (host only, at mission end)
```

The mod finds the relay from `CampaignManager.url`, which the Obsidian loader points at `http://127.0.0.1:<port>/<token>/1.0/` in a Commander war, and asks `<token>/evolved/` beside it. A 404 means a Vanilla war: the mod stays out of the way. No relay means the official war: the mod does nothing at all.

## The map

`main.lua` mutes the galaxy map screen (`obsidian.ui.mute("campaign")`), hides the globe of the three fronts (`warfront_unit`), takes the screen input (`MenuScreenCampaign.handle_input`), and draws with an `obsidian.ui` kit in a 1920x1080 frame. The starfield behind the map stays.

| Module | What it does |
|---|---|
| `src/galaxy.lua` | The HELLDIVERS 2 galaxy, generated: planets (name, position, sector, environment, Voronoi cell), sectors, supply lines, sector border edges |
| `src/war.lua` | The last state from the server, with lookups by planet, operation and sector, countdowns |
| `src/view.lua` | The four levels, the camera (eased toward a target, scale in log space), picking, input, the jump |
| `src/sphere.lua` | Globes: a point at a latitude and longitude, turned and tilted, drawn flat; grid lines; scanline chords |
| `src/draw.lua` | Every draw call: territory, borders, supply lines, globes, operations, panels, dispatches, the jump |
| `src/launch.lua` | The HELLDIVERS planet record and mission seeds for an operation, and the report at mission end |
| `src/net.lua` | Polling and reports, with retries |

Planets keep one size in map units, so a planet is a dot at the galaxy level, a small globe at the sector level and the whole screen at the planet level: one continuous zoom.

## From a mission to the hellpods

An operation is what HELLDIVERS already calls a planet: a list of missions, each a seed holding the time of day, shading, environment, variant, enemy, mission type and difficulty (`DifficultySettings.modulate_seed`). `src/launch.lua` builds that record from the operation (all values from the server, so every player builds the same missions), names it `evowar_op_<id>` (the text shows the HELLDIVERS 2 planet name through `obsidian.game_text`), and puts it in the first planet slot of that enemy in `available_planets`, keeping the slot position, region and reward, where mission end looks for it.

Then the mod hands the planet to the galaxy map screen as a pick made on that screen would be handed over: `current_planet`, `set_current_planet_on_exit`, `exit()`. The screen saves the planet as it leaves and picks the mission seed; the ship sees the new planet, plays the hyperspace jump (`MenuSpaceManager.planet_changed`) and opens the pods. Clients follow the host through the stock network messages.

## Mission end

`StateMissionEnd.on_enter` on the host who started the mission (`initial_host`): if the planet is the launched operation, the mod sends `{campaign, operation, mission, success, lobby, kills, deaths}`. `lobby` is the host and the mission seed, the same for every player, so the server counts a squad once.

## Not yet

- Clients see the map but can't pick; the host picks for the squad, as in the game.
- Hazards show on the planet panel and change nothing in the mission.
- Rewards are the game's own planet rewards, from the slot the operation takes.
- Text is English only until the translation pass.
