# Changelog

## 0.3.0

- New: the war screen redone after the two games. The HELLDIVERS 2 galaxy fills the window, enemy sectors carry the stripes of the HELLDIVERS 2 map and the enemy names run across their territory, and planets show only once a sector is open. Around it, the galactic campaign screen of HELLDIVERS: the title and tabs, the war stats, callouts with progress bars on the campaigns, table panels and key prompts.
- New: the sector under the pointer is named in a box beside it, with the planets and who holds them.
- Changed: larger text throughout, and planets, operations and missions named on plates.
- Changed: the map takes the same share of the window at any interface scale, and the panels sit at the edges of the window.
- Changed: a planet up close is a hologram, dark with a glowing grid.
- Fixed: keys and clicks did nothing on the war screen. The game reads the scroll wheel as 0 when it is idle, which the mod took for a zoom out on every frame.
- Fixed: the key prompts showed blocks in place of the keys.

## 0.2.2

- Fixed: the galaxy map of an Evolved war stayed the stock one. The game sends every request as POST, so asking for the war with GET never reached it; the mod now asks with POST. Needs Obsidian built on 2026-11-11 or later, whose relay takes it.
- Fixed: the names of the sides read "Cyborg Homeworld" and the like, from the game's text, in place of Cyborgs, Bugs and Illuminates.
- Changed: when the war refuses the request, the log says who refused it.

## 0.2.1

- Changed: the HELLDIVERS campaign colours are back: Super Earth yellow, Bugs green, Cyborgs red, Illuminates blue.

## 0.2.0

- New: the sectors of the HELLDIVERS 2 map, rings cut by stepped spokes, in place of the planet cells. A sector is tinted by the enemy holding planets there, and a click anywhere inside one opens it.
- Changed: the colours of every Commander war, as the war screens draw them: Super Earth blue, Bugs orange yellow, Cyborgs red, Illuminates purple.
- Changed: the log names the war address the game uses each time it changes (scheme, host and port, never the relay token), and says whether the Evolved map takes over or the stock map stays.
- Fixed: planet names with an apostrophe or a moon letter, such as Widow's Harbor and Cerberus IIIc.

## 0.1.0

- New: the galaxy map of an Evolved war, with the HELLDIVERS 2 galaxy layout: sectors tinted by who holds them, supply lines, campaign marks, the Major Order and the campaign list.
- New: zoom from the galaxy to a sector, a planet and an operation; planets show as globes, with the operations on the surface and the missions around the open operation.
- New: picking a mission jumps the ship to the planet and opens the hellpods; the squad follows the host through the game countdown.
- New: the host reports each mission to the war server, once per squad.
- New: dispatches scroll along the bottom of the map.
