# Trainer Pilot architecture

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Mod id `trainer_pilot`, API 3, FireRed and LeafGreen, optional dependency `trainer_desk`, permission `engine_internals`. |
| `main.lua` | The bot: saved data, the game, walking, travelling, battle, catching, field work, the main loop and hooks. Shares itself as `mod.exports.bot`. |
| `panel.lua` | The control panel drawn inside Trainer Desk. Gets the `Bot` table and draws from it; buttons call `Bot` functions. |

## Map of main.lua

Sections are marked with banner comments, in this order:

1. **Saved data** – routes and settings, their text encoding, reading and writing the cache.
2. **The game** – `host()` gathers the engine modules once (field, player, map, collision, objects, connections, battle, bag); `session()`.
3. **Buttons** – `tap`, `hold`, `release`, over `mod.input`.
4. **Walking** – a breadth-first search over cells with the game's own collision (`Collision.canEnter`, ledges, water, obstacles) and the step-by-step walker.
5. **Travelling** – going to a cell on another map.
6. **The map of links** – `mapLinks(id)` (edges cost 1, doors, caves and stairs cost 3), `planHop` (shortest path map by map, maximum cost 16, the `AVOID` list), remembered crossings and portals, `findCenter`.
7. **Following a route** – the recorded points, cursor and loop.
8. **Recording** – turning the player's walk into points.
9. **The team** – who fights (`pickLead`), forbidden moves, HP percentage, eggs.
10. **EV training** – `Bot.evTarget`, `evDone`, `evWasted` (from `Pokemon.evYield`).
11. **Stopping and starting** – `Bot.start(mode, resume)`, `Bot.stop(reason)`, `Bot.finish()`, game speed, the stop history.
12. **Reset hunting** – save, press A, check, reload; the save lock.
13. **Battle** – reading the battle state and answering the battle prompt through `BattleAPI`.
14. **Catching** – `catchStep`: weaken (`maxDamage`), status moves, the ball (`Bot.pickBall`), Safari steps.
15. **Field work** – `fieldTick`: healing, the Center and the nurse, item healing, Sweet Scent, fishing, VS Seeker, the Safari Zone, the "ready to hunt" rule.
16. **One step** – `tick()`: what the bot does on this game step.
17. **Control panel** – loading `panel.lua` and registering it with Trainer Desk.

## The main loop

`tick()` runs inside the `input.step` hook, once per game step, so every button the bot presses goes into the same step the game reads. It does nothing unless `Bot.running`. In a battle it answers the battle prompt; otherwise it calls `fieldTick()`, which picks the job of the moment (heal, go back to the route, follow the route, fish, call the VS Seeker...).

Waiting is always measured both in game steps and in real seconds (`mark()` and `late(since, ticks, seconds)`): at high game speed hundreds of steps pass while a map is still loading.

An error inside `tick` releases held buttons, stops the run with reason `error`, and logs it once.

## Modes

`Bot.start(mode)` with `mode` one of:

- `train` – walk the training route and fight (or train EVs).
- `hunt` – walk the route looking for targets; fight or run from the others; catch if set.
- `reset` – reset hunting at the current spot.

`Bot.start(mode, true)` (CONTINUE) resumes keeping the run's numbers; `Bot.finish()` clears a stopped run.

## Hooks

| Hook | Priority | Use |
| --- | --- | --- |
| `input.step` | default | The main loop. |
| `input.key`, `input.gamepad` | 3000 | A pressed button stops the run with reason `player`. |
| `input.key` | 3200 | While a target's name is being typed, keys go to the panel and not to the game. |
| `save.write` | 3000 | Refuses to write the save while a reset hunt holds the lock. |
| `core.update` | 880 | Applies settings reloaded from the panel; registers the panel with Trainer Desk. |
| `core.quit_to_launcher` | 900 | Stops the run and forgets the game. |
| `game.ready` (event) | | Remembers the game. |

Reset hunting reloads the save from `core.update`, the same way the game's own F2 key does (`_tearDownField`, then `_handleBootAction{ action = "continue" }`).

## The panel

`panel.lua` returns a function `(mod, Bot)` giving `{ W, H, draw, pointer, key, wantsKeys, theme }`. It draws on a 480x432 sheet that is stretched to the room the dock gives (`responsive = true`); every box, text and clickable rectangle goes through helpers that apply the scale, so clicks are looked up in the same rectangles that were drawn. Colours come from the Trainer Desk theme.

Colour rule in the panel: blue = chosen or on, green = start, red = stop or forbidden, amber = warning only, grey = secondary.

## What other mods may read

`mod.exports.bot` is the `Bot` table. Trainer Lens reads `Bot.running`, `Bot.reason` and `Bot.reasonText(code)` for its Notices panel. Nothing else is promised.
