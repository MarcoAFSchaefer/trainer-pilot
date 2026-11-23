# Changelog

## 0.27.0

- A blocked way is tried again up to three times (within half a minute), with every given-up cell, crossing and map link forgotten, before the bot stops. Each one is written to `log/blocked` with where it was heading and what failed.
- Waits 2 seconds (was 1) on a map edge before giving that crossing up, since the next map can take that long to load at high speed.
- Control tab: instead of encounters by species, how many of each hunt target the run has found (and shinies that matched no target).

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
