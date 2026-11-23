# Trainer Pilot

A training and hunting bot for Pokémon FireRed/LeafGreen on Gen1Recomp (mod API 3). It plays by pressing the game's own buttons; any button you press pauses it.

## What it does

- **Routes:** grass routes recorded by walking them; fishing, VS Seeker and Sweet Scent spots marked where you stand.
- **Training:** fights with the party members you mark, with moves you can forbid per Pokémon; stops at a target level, a shiny, a species from your list, a new move, an evolution, or running out of PP.
- **EV training:** a target per stat and per Pokémon (up to 252); runs from species that would give the wrong EVs; stops when the target is reached. Not on VS Seeker routes.
- **Healing:** walks to the nearest Pokémon Center through a map of how the world's maps connect (or along a recorded healing path), or uses Potions and Ethers from the bag up to the limit you set.
- **Obstacles on the way:** Surf, Cut, Rock Smash, Strength and Waterfall.
- **Hunting:** up to 30 named targets that filter by species, gender, nature, ability, IVs, Hidden Power, level, held item and shiny; optional automatic catching (weaken without making it faint, sleep or paralysis, balls in your order); the Safari Zone; reset hunting for starters, gifts and legendaries.
- **Control:** game speed while it runs, the numbers of the run, and a history of the last 40 stops.

It will not start on a grass route with a Repel active, and stops if a Repel is used during the run. It stops by itself when it runs out of balls or when the party and PC are full.

## Compatibility

| | |
| --- | --- |
| Games | FireRed and LeafGreen |
| Gen1Recomp | 0.3.93 or newer (mod API 3); tested on 0.4.8 |

## Installation

Copy the `trainer_pilot` folder into the game's mods folder:

```
%APPDATA%\pokemon-love2d\mods\trainer_pilot
```

The control panel appears in the Trainer Desk docks, so Trainer Desk is needed to use it.

## Options

| Option | Default | What it does |
| --- | --- | --- |
| Language | English | Language of the control panel: ENGLISH, ESPANOL, PORTUGUES or JAPANESE. |

## Panel

| Tab | What is there |
| --- | --- |
| Control | Start state, the reason of the last stop, the run's numbers, finds per hunt target, game speed, rod choice, CONTINUE / FINISH / STOP, and the stop history. |
| Routes | Record a grass route or a healing path by walking; mark a fishing, VS Seeker or Sweet Scent spot; choose the training route. |
| Team | Who fights, forbidden moves, and EV targets per Pokémon. |
| Training | Stop conditions, healing (Center, HP threshold, potions and ethers), and START TRAINING. |
| Hunt | Targets and their editor, automatic catching, the Safari Zone, reset hunting, and START HUNT. |

The panel follows the Language option (see below).

## Reset hunting

Stand in front of the Pokémon (or the person who gives it), with room in the party, and start a reset hunt. The bot saves the game there, presses A, looks at what came, and loads the save again until it matches a target or is shiny. While the hunt exists, nothing else may write the save, so a bad attempt is never kept; the lock is released when the target is found or caught, when you press FINISH, or when you walk away from the spot.

## Languages

The control panel is in English, Spanish, Portuguese and Japanese: choose one with the **Language** option in the mod's settings. Names that come from the game itself (Pokémon, moves, items, places) stay in the language of your game.

Each language is a file in `trainer_pilot/lang/` (`en.lua`, `es.lua`, `pt.lua`, `ja.lua`); English is the reference, and a text missing from another language shows in English. Japanese text is drawn with a cut-down copy of Noto Sans JP in `trainer_pilot/fonts/` (SIL Open Font License, `fonts/OFL.txt`). See [docs/TRANSLATING.md](docs/TRANSLATING.md) to fix or add a translation.

## Documentation

- [docs/GUIDE.md](docs/GUIDE.md): player guide, routes, training, EV training, hunting and reset hunting, step by step.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the bot is organised, its main loop and hooks.
- [docs/DATA.md](docs/DATA.md): settings, saved data formats and stop reasons.
- [docs/ENGINE_NOTES.md](docs/ENGINE_NOTES.md): the game functions the bot relies on and the pitfalls found on the way.
- [docs/TRANSLATING.md](docs/TRANSLATING.md): how the translations work and how to change them.
- [docs/PUBLISHING.md](docs/PUBLISHING.md): releases and the Gen1Recomp mod index.
- [CHANGELOG.md](CHANGELOG.md): version history.
- [tests/README.md](tests/README.md): running the automated checks.

## Known limits

- Caves with puzzles (Victory Road, Seafoam Islands, Icefall Cave, Pokémon Mansion, Lost Cave) are never crossed; record a healing path there.
- In double battles only the first opponent is targeted.
- Item healing restores HP and PP only: it does not cure status or revive.
- Some places are still unreliable: hitches on Routes 15 and 14 and a "blocked path" on Route 10.

## History

Until version 0.24.0 this mod was called PokeBot (id `poke_bot`).

## License

MIT (see LICENSE). The bundled Japanese font is under the SIL Open Font License (`fonts/OFL.txt`).
