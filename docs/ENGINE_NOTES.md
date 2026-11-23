# Engine notes

What the bot relies on in Gen1Recomp 0.4.8 (FireRed), and the pitfalls already paid for. Module names are the game's own. "Seen in the real game" means confirmed by playing; anything else was checked only against the test stand-in.

## Talking to the game

- **Buttons:** `mod.input:tap(game, "a")`; `mod.input:press(game, dir)` returns a token for `mod.input:release(token)`. The loop runs in the `input.step` hook. *Seen in the real game.*
- **Battle:** `require("src.battle.game3.BattleAPI").new(game)`. `snapshot()` gives `prompt` (`advance`, `menu`, `moves`, `target`, `party`, `locked`) and `revision`; `submit{ id, revision, kind = "menu" | "move" | "target" | "back", ... }`. The menu accepts `choice = "fight" | "bag" | "pokemon" | "run"`. There is no ready-made intent for using an item. *Seen in the real game.*
- **Battle state:** `src.core.game3.battle` `getState()` gives `wild`, `double`, `safari`, `result`, `enemy.mon`, `player.mon`, `battlers[0..3]`, `foeParty`. The phase is in `src.core.game3.battle.init` (`shift_prompt` is the "switch?" question).
- **Throwing a ball without the bag screen:** at the battle menu, set `require("src.core.game3.battle.ui")._pendingCommand = { kind = "bag", user = "player", itemId = <ball> }` and `_mode = "none"`, which is what the bag screen itself does; the battle takes the ball from the bag. A catch is read from `result == "catch"`.
- **Safari battle:** the menu is BALL / BAIT / ROCK / RUN in the positions of fight / bag / party / run.
- **Pokémon:** `src.core.game3.pokemon` (`speciesOf`, `name`, `isShiny`, `isEgg`, `types`, `abilityId`, `abilityName`, `evYield`, `monIcon`); `summary_data` (`gender`, `nature`). IVs in `mon.ivs.{hp,atk,def,spe,spa,spd}`, EVs in `mon.evs`.
- **Field:** `src.core.game3.{field,player,map,collision,objects}`; `Collision.canEnter(game, x, y, { fromX, fromY, dir, surfing, elevation })`, `ledgeLanding`, `isWater`, `inBounds`, `behavior`, `isWarpMetatileBehavior`.
- **Field moves:** `require("src.world.game3.WorldAPI").new(game, id):useFieldAction("surf" | "cut" | "rock_smash" | "strength" | "waterfall" | "sweet_scent" | ...)`; `availableFieldActions()`; `reorderParty`. Obstacles are objects by graphics id (`FieldMoves.GFX_IDS`: 95 tree, 96 cracked rock, 97 boulder).
- **Items in the field:** `item_use.useField(session, bag, id, slot, moveSlot)` applies the item and takes it from the bag without a screen. Used for potions, ethers, rods and the VS Seeker.
- **Maps:** `game.data.maps[id]` with `warps` (`x`, `y`, `destMap`, `destWarp` counted from 1); edges through `src.core.game3.connections` (`each`, `incoming`, `sizeOf`).
- **Repel:** `field_semantics.getVar(session, "repelSteps")`, as the encounter check reads it.
- **Safari Zone:** `Safari.isActive(session)`; money in `session.money` (a visit costs 500).
- **PC room:** `Storage.findOpenSlot` (read only).
- **Speed:** `game.options.speedOverworld` and `speedBattle`; the bot restores them when it stops.
- **Saving and loading:** `game:saveGame()`; the F2 reload is `_tearDownField` followed by `_handleBootAction{ action = "continue" }`. The game saves on its way out (`Game3:quit`), which is why reset hunting blocks `save.write`.
- **Randomness:** `Rng.perturb()` on continue (16 bits from the clock); `Rng.getState` / `setState`.

## Pitfalls

- Wait in game steps **and** real seconds: at 200x hundreds of steps pass while a map is still loading.
- Halfway through crossing between maps the position is one cell outside the new map.
- Water answers `"elevation"`, not `"water"`, in `canEnter`: check `isWater`.
- A Pokémon Center's `warps` include cells next to the mat that do not work; prefer the ones with warp behaviour.
- The battle holds a **copy** of each Pokémon: compare by `personality` plus species, never by table.
- Double battles have two Pokémon on each side (`player` and `battlers[2]`).
- Version 0.5.3 tried looking for the pass-through building on the spot and remembering "no path" for 0.4 s; it made the bot stop on Route 15 and was reverted without finding why.
- Typing text: the game does not pass `textinput` to mods, so target names are typed through `input.key`.

## Not confirmed in the real game

- Stopping for a shiny.
- Automatic catching, the Safari Zone and its re-entry gate.
- Waterfall.
- Reset hunting bringing the same Pokémon back after `Rng.setState`: it depends on the game being deterministic between the load and the encounter.

## Open problems

- Hitches on Route 15 (before the pass-through building and at the edge with Route 14): unknown whether the game is loading the map or the bot is at fault.
- "Blocked path" on Route 10; the history now records the map and position of each stop to find it.
- The test stand-in has no pass-through building and no double battle.
