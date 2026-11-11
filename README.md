# Evolved War Engine

A HELLDIVERS (2015) mod for Evolved wars, the HELLDIVERS 2-style Galactic Wars that [Obsidian Commander](https://github.com/Alomare/ObsidianCommander) hosts. In an Evolved war the galaxy map of the ship shows the HELLDIVERS 2 galaxy in place of the three fronts, and the missions picked there count toward the war.

Outside an Evolved war (the official war, a Vanilla Commander war) the mod does nothing.

## The galaxy map

The screen is laid out as the galactic campaign screen of HELLDIVERS: the title with the tabs under it, the war stats and the Major Order at the left, a table at the right, the key prompts at the bottom. The map in the middle is the HELLDIVERS 2 galaxy. It has four levels, each a zoom into the one before, and each has a tab:

1. **Galaxy.** The HELLDIVERS 2 sectors around Super Earth: the Cyborgs to the left, the Bugs to the right and the Illuminates below. Enemy sectors carry the colour of the enemy and the diagonal stripes of the HELLDIVERS 2 map, with the name of the enemy across the territory; light lines mark where the sides meet. Each campaign has a mark and a callout with the planet and the progress. A sector under the pointer is named in a box beside it. The colours are the HELLDIVERS campaign colours, as in the war screens of Commander: Super Earth yellow, Bugs green, Cyborgs red, Illuminates blue.
2. **Sector.** The planets of the sector as small globes with their names, who holds them and how each campaign stands, and the supply lines between them.
3. **Planet.** One globe, as a hologram, turning. The operations of the campaign sit on the surface. The panel shows the biome, the hazards, the liberation or defense progress, and how much one mission moves it.
4. **Operation.** The globe turns to the operation and the missions of the operation show around it, with the difficulty, the mission types and the time of day.

The map takes the same share of the window at any interface scale; the panels follow the interface scale of the game.

Picking a mission jumps the ship to that planet and opens the hellpods. The squad drops through the usual countdown, briefing and loadout, so other players follow the host as in any mission.

Controls: the mouse picks and the wheel zooms; on a planet, dragging turns the globe. The keys of the game menus move between the items of a level (A and D), select (E) and go back a level (Q); a pad uses the shoulder buttons, A and B.

## The war

The war runs on the Commander server of the host:

- Enemy planets linked by a supply line to a Super Earth planet can be liberated. Each won mission lowers the enemy hold, and the enemy regains some every hour.
- Enemies attack Super Earth planets along the front. A defense lasts a set time; win enough missions before it ends or the planet falls.
- An operation is two or three missions on one planet. Finishing all of them counts extra, and a new operation takes the place of the finished one.
- Major Orders give the war a goal and a deadline. The host can write orders, start and end campaigns, set who holds a planet and post dispatches from the war screen in Obsidian.

Only the host reports missions, once per squad.

## Requirements

- Obsidian with the COMMANDER tab, and an Evolved war, hosted on this PC or joined over LAN.
- Obsidian API (installed with Obsidian).
- Every player of the war runs this mod. Playing an Evolved war from Obsidian switches it on.

## Credits

The galaxy layout (planet names, positions, sectors and supply lines) comes from HELLDIVERS 2 by Arrowhead Game Studios, read through the community API at helldivers2.dev. The sector outlines were traced from the HELLDIVERS 2 map by the [HELLDIVERS 2 War History Central](https://github.com/crosswaveomega/helldiversplanettable) project. No game art or files are included.

## License

MIT
