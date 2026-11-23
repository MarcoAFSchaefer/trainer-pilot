# Changelog

## 0.28.1

- Control tab: while hunting, the encounters of each target's species (whatever the target's other filters), instead of the finds; a target for any species lists every species met.

## 0.28.0

- Walking decides at once instead of waiting: when there is no way to a place at all (a ledge, a cave in between), the bot plans around it straight away; it only waits, 4 seconds at most, when a person is standing in the way. The 0.27.0 retries are gone.
- A Pokémon Center on the same map that cannot be walked to (Route 4's, from the east of Mt. Moon) is skipped for the next nearest one.
- Map links given up on are forgotten when the player changes map.
- Routes tab: routes listed nearest first (this map, by distance, then by how many maps away), with an **All** / **Nearby** filter (this map and the ones right next to it).
- `log/blocked` now also lists every way given up on during a trip.

## 0.27.0 (not released)

- Control tab: how many of each hunt target the run has found, instead of encounters by species.
- Waits 2 seconds (was 1) on a map edge before giving that crossing up, since the next map can take that long to load at high speed.
- `log/blocked`: every blocked stop, with where the bot was heading and what failed.

## 0.26.0

- Control panel in English, Spanish, Portuguese and Japanese (new Language option; English by default), including stop reasons, natures, Hidden Power types and route names.
- Japanese text drawn with a bundled Noto Sans JP subset.
- Declares the engine versions it supports (`game_version`).
- MIT license, release workflow and a ready mod index entry (docs/PUBLISHING.md).

## 0.25.0

- Renamed from PokeBot to Trainer Pilot; mod id `poke_bot` becomes `trainer_pilot`.
- English documentation and code comments; the Portuguese development notes became docs/ENGINE_NOTES.md.

## 0.24.0

- Stop history (last 40, with map and position).
- Up to 30 hunt targets, each with a name.
- Stops when party and PC are full (`pc_full`).

## 0.23.x

- EV training: targets per stat and Pokémon, running from wrong yields, no switching by choice.
- Hunt editor and catching screens in the new look; the fight button is an icon.

## 0.22.0 / 0.21.x

- New look matching Trainer Lens; panel is responsive. Tabs reordered (Control, Routes, Team, Training, Hunt), page buttons, a livelier Team tab.

## 0.20.x

- Healing with Potions and Ethers from the bag, with a limit per run.
- Reset hunting ends by itself when the player leaves the spot.
- Will not start with a Repel active on grass or Sweet Scent routes; stops if one is used.

## 0.19.0

- Reset hunting for starters, gifts and legendaries, with a save lock.

## 0.18.x

- Safari Zone re-entry; FINISH button.

## 0.17.0 / 0.16.x

- Sweet Scent spots; the Safari Zone (baits, then balls).

## 0.15.x

- Puzzle caves avoided; fishing hunts and rod choice; hunt score.

## 0.14.0 / 0.13.0

- The map of links between maps for travelling anywhere; recorded healing paths again for puzzle caves.

## 0.12.0

- Rock Smash, Strength and Waterfall on the way.

## 0.11.x

- Automatic catching: weakening, status, ball order, Master Ball option; "ready to hunt" rule.

## 0.7.0 – 0.10.0

- Hunting: targets and filters, separate training and hunting modes, Hidden Power, natures, level, held item, Sweet Scent.

## 0.1.0 – 0.6.x

- Training on recorded grass routes, fishing and VS Seeker spots; Pokémon Center healing; stop conditions; game speed.
