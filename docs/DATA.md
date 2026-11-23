# Settings and saved data

Everything is stored with `mod.cache` under `%APPDATA%\pokemon-love2d\mod_cache\trainer_pilot\`, one file per key.

| Key | Content |
| --- | --- |
| `routes/v1` | Recorded routes and spots. |
| `config/v1` | Settings. |
| `crossings/v1` | Where the player crossed from one map to the next. |
| `nurses/v1` | Where to stand in front of the nurse, per Pokémon Center. |
| `log/last` | The last stop, for diagnosis. |
| `log/history` | The last 40 stops. |

## routes/v1

One route per line: `name|kind|points`, where points are `map,x,y,dir` separated by `;`.

```
Route 1 grass|grass|FR_ROUTE_1,10,20,up;FR_ROUTE_1,10,19,up;FR_ROUTE_1,11,19,right
```

| Kind | Meaning |
| --- | --- |
| `grass` | Walked back and forth. |
| `fish` | One spot, facing the water. |
| `seeker` | One spot where the VS Seeker is used. |
| `scent` | One spot where Sweet Scent is used. |
| `heal` | A recorded path to the nurse, for places the automatic travel cannot cross. |

Map ids are the game's, without `MAP_` (for example `FR_ROUTE_15`, `SEVII_ONE_ISLAND_POKECENTER`).

## config/v1

`key=value` lines. Booleans are `1` or `0`; sets are comma-separated keys.

| Key | Default | Meaning |
| --- | --- | --- |
| `train` | | Name of the training route. |
| `heal` | | Name of a recorded healing path (optional). |
| `healOn` | 1 | Heal when the fighters are tired (else stop with `needs_heal`). |
| `hpPct` | 30 | A fighter below this HP percentage is tired (0 to 90). |
| `stopLevel` | 0 | Stop at this level (0 = never). |
| `stopShiny` | 1 | Training stops for a shiny. |
| `stopLearn` | 1 | Stop when a move wants to be learnt. |
| `stopEvolve` | 1 | Stop when a Pokémon evolves. |
| `travelRun` | 1 | Run from wild Pokémon met while travelling to the Center or the route. |
| `stopNoPP` | 0 | Stop when the fighter runs out of PP (else switch, then heal). |
| `species` | | Species ids that stop training when they appear. |
| `selected` | 1 | Party slots that fight. |
| `speed` | 0 | Game speed while running (0 = leave the game's). |
| `rod` | 0 | Rod item id (262 Old, 263 Good, 264 Super; 0 = the best in the bag). |
| `banned` | | `personality:moveId` pairs the bot must not use. |
| `huntExp` | 0 | Fight Pokémon that are not targets (else run). |
| `huntShiny` | 1 | A hunt also stops for any shiny. |
| `huntScent` | 0 | On a grass route, call encounters with Sweet Scent instead of walking. |
| `huntCatch` | 0 | Try to catch a target (else only stop). |
| `catchContinue` | 1 | After a catch, go on hunting. |
| `catchWeaken` | 1 | Lower the target's HP first, only with a move that cannot make it faint. |
| `catchFalseSwipe` | 0 | Lower HP only with False Swipe. |
| `catchStatus` | 1 | Put the target to sleep or paralyse it before the ball. |
| `catchHeal` | 0 | Go to the Center after every catch attempt. |
| `useMaster` | 0 | The Master Ball may be thrown. |
| `ballOrder` | 2,3,4 | Ball item ids, first choice first (1 Master, 2 Ultra, 3 Great, 4 Poké). |
| `safariBaits` | 2 | In the Safari Zone, this many baits (0 to 5)... |
| `safariBalls` | 3 | ...then this many balls (1 to 9), repeated. |
| `safariReentries` | 0 | Pay and go back in when a visit ends this many times (-1 = while there is money). |
| `resetCatch` | 0 | Reset hunting tries to catch the target (a failed catch reloads for the same Pokémon, up to 10 times). |
| `itemHp` | 0 | Potions the bot may use per run before going to the Center (-1 = no limit). |
| `itemPp` | 0 | The same for Ethers and Elixirs. |
| `targets` | | Hunt targets, see below. |
| `evTargets` | | EV targets, see below. |

### targets

Targets separated by `;`, fields by `,`:

| Field | Meaning |
| --- | --- |
| 1 | Species id (0 = any). |
| 2 | Gender: `M`, `F` or `any`. |
| 3 | Minimum IV total. |
| 4–9 | Minimum IV for HP, Attack, Defense, Speed, Sp. Atk, Sp. Def. |
| 10 | Ability id (0 = any). |
| 11 | Single nature from older saves; always written as -1. |
| 12 | Shiny only (1/0). |
| 13, 14 | Minimum and maximum level (0 = no limit). |
| 15 | Hidden Power type (-1 = any). |
| 16 | Minimum Hidden Power power. |
| 17 | Holding an item (1/0). |
| 18 | Natures (0–24, separated by `.`, or `-` for any). |
| 19 | Name: letters, digits and spaces, up to 20 characters, or `-`. |

### evTargets

`personality:hp.atk.def.spe.spa.spd` entries separated by `;`, each value 0 to 252. The Pokémon is identified by its personality value, so it keeps its target when the party is reordered.

## crossings/v1 and nurses/v1

- `crossings/v1`: `FROM>TO=x,y` lines, the last cell on `FROM` before stepping onto `TO`.
- `nurses/v1`: `MAP=x,y,dir` lines, learnt the first time the player heals at that Center by hand.

## log/last

`reason=`, `phase=`, `status=`, `map=`, `x=`, `y=`, `battles=`, `error=` lines.

## log/history

Newest first, one stop per line: `at|reason|mode|route|map|x|y|battles|seconds|found|caught`, where `at` is a Unix time. Only stops of a running bot are recorded, and quitting the game is not.

## Stop reasons

| Code | Meaning |
| --- | --- |
| `player` | You pressed a button. |
| `shiny` | A shiny appeared. |
| `species` | A species from your list appeared. |
| `learn` | A Pokémon wants to learn a move. |
| `evolve` | A Pokémon is evolving. |
| `level` | Target level reached. |
| `level_healed` | Target level reached; party healed, stopped at the Center. |
| `hunt_found` | A target is on screen; the battle is yours. |
| `caught` | Target caught. |
| `ev_done` | EV target reached. |
| `ev_healed` | EV target reached; party healed, stopped at the Center. |
| `pc_full` | Party and PC are full: a caught Pokémon would have nowhere to go. |
| `repel_on` | A Repel is active on a route where it keeps Pokémon away. |
| `no_balls_ready` | No balls in the bag: hunting with catching cannot go on. |
| `no_balls` | A target is on screen and the balls ran out. |
| `reset_released` | You left the reset hunting spot: hunt ended and saving allowed again. |
| `reset_nothing` | A was pressed and nothing appeared. |
| `reset_trainer` | A trainer battle began: reset hunting is for wild and gift Pokémon. |
| `reset_load` | The save could not be loaded. |
| `no_save` | The game cannot be saved here now. |
| `safari_over` | The Safari visit ended (steps or Safari Balls). |
| `safari_reenter` | Could not get back into the Safari Zone. |
| `safari_money` | Not enough money for another Safari visit. |
| `needs_heal` | The party needs healing and healing is off. |
| `heal_far` | The recorded healing path does not pass through this map. |
| `heal_failed` | Could not heal at the Center. |
| `no_center` | No Pokémon Center found nearby. |
| `nurse` | Unknown nurse position: heal once by hand there. |
| `fainted` | No Pokémon left to fight. |
| `no_pp` | No PP left to attack. |
| `blocked` | Path blocked. |
| `stuck` | Stuck. |
| `question` | The game asked a question. |
| `no_route` | No route chosen. |
| `no_targets` | No hunt target. |
| `other_map` | The training route is on another map. |
| `no_game` | No game running. |
| `no_trainers` | No trainer within VS Seeker reach here. |
| `no_scent` | Sweet Scent ran out of PP and cannot be restored here. |
| `no_scent_move` | Nobody in the party knows Sweet Scent. |
| `no_scent_here` | Sweet Scent does not work here. |
| `no_rod` | The chosen rod is not in the bag. |
| `cant_fish` | Cannot fish here. |
| `no_seeker` | No VS Seeker in the bag. |
| `nobody` | No Pokémon chosen to fight. |
| `party_menu` | Could not switch Pokémon. |
| `battle_menu` | Could not use the battle menu. |
| `error` | Internal error (see the log). |
| `quit` | The game was closed. |
