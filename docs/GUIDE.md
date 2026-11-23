# Trainer Pilot: player guide

Trainer Pilot is a bot for FireRed and LeafGreen that trains and hunts for you by pressing the game's own buttons. **Any button or key you press pauses it.** Its control panel lives in Trainer Desk.

## Installing

1. Install **Trainer Desk** (needed for the control panel).
2. Download `trainer_pilot-<version>.zip`, or install it from the launcher's **Find mods** tab. If you downloaded it, use **Import mod .zip**, or unpack it into `%APPDATA%\pokemon-love2d\mods\trainer_pilot`.
3. Turn both mods on and start the game. The **Trainer Pilot** panel appears in the right dock.

The panel has five tabs: **Control**, **Routes**, **Team**, **Training** and **Hunt**.

## Quick start: level up on a grass route

1. Walk to the start of a patch of grass and stand still.
2. **Routes** tab: under *Record by walking*, click **Grass**.
3. Walk back and forth through the grass the way you want the bot to walk, then click **SAVE**.
4. Click the new route in the list, then **Use this route**.
5. **Team** tab: click the crossed swords of each Pokémon that should fight (green = fights).
6. **Training** tab: set when to stop (for example *Reaching level* 30) and click **START TRAINING**.

The **Control** tab now shows what the bot is doing. Press any button to pause it; **CONTINUE** resumes, **FINISH** ends the run and clears its numbers.

## Routes

| Kind | How to make it | What the bot does |
| --- | --- | --- |
| Grass | *Record by walking* > **Grass**, walk, **SAVE**. | Walks the recorded path back and forth. |
| VS Seeker | *Record by walking* > **VS Seeker**, or *Mark the spot* > **VS Seeker**. | Charges the VS Seeker, uses it, and battles the trainers who want a rematch. |
| Fishing | Face the water, *Mark the spot* > **Fishing**. | Fishes from that spot. Choose the rod on the Control tab (the best you have, by default). |
| Sweet Scent | Stand in grass, *Mark the spot* > **Sweet Scent**. | Calls wild Pokémon with Sweet Scent without walking. |
| Healing path | *Record by walking* > **Healing path**, from the route to the nurse. | Uses that path to heal instead of finding the Center by itself. |

Only make a healing path where the bot cannot find the way alone, such as inside puzzle caves. Elsewhere it walks to the nearest Pokémon Center by itself, using Surf, Cut, Rock Smash, Strength and Waterfall on the way when your party can.

**The first time in a Pokémon Center** the bot may not know where the nurse stands. If it stops with that message, heal there once by hand; it learns the spot.

## Team

- **Crossed swords:** green means this Pokémon fights. The bot fights with the first marked one that is fit, and switches when it faints or runs out of PP.
- **Moves:** shown in their type's colour. Click a move to forbid it (red); the bot will not use it. Moves without damage are not used for fighting (status moves are only used when catching).
- **EV:** opens EV training for that Pokémon (below).

## Training

**STOP WHEN:** reaching a level, a shiny appearing, an evolution, a Pokémon wanting to learn a move (off: it does not learn it), PP running out (off: switches and heals).

**HEALING:** the minimum HP to keep fighting, whether to go to the Pokémon Center (off: the bot stops instead), and how many Potions and Ethers it may use from your bag before going (0 = none).

**ON THE WAY:** run from wild Pokémon met while going to the Center or back to the route.

**STOP IF IT APPEARS:** click species of this map to stop when one shows up.

## EV training

1. **Team** tab: click **EV** next to the Pokémon.
2. Set a target for each stat (click the number to jump between 0 and 252; the most a stat can hold is 252, and 510 in total).
3. The list *On this map* shows what each species gives: green means the bot fights it, red means it would give EVs this Pokémon does not want, so the bot runs.
4. Start training as usual. The bot stops when the targets are reached.

EV training works on grass, fishing and Sweet Scent routes. It is off on VS Seeker routes.

## Hunting

1. **Hunt** tab: click **+ New target**.
2. Choose a species of this map (or none for any), and on the two pages the filters: gender, ability, minimum IVs (per stat or total), natures, level, Hidden Power type and power, held item, shiny only. Click the title to give the target a name.
3. Click **SAVE TARGET**. You can have up to 30 targets; a Pokémon matching any one of them counts.
4. Choose a route on the Routes tab and click **START HUNT**.

Options on the Hunt tab:

- **Also stop for any SHINY**, even one that matches no target.
- **Fight the ones that are not targets** for EXP; off, the bot runs from them.
- **Use Sweet Scent instead of walking** on a grass route.

### Automatic catching

Click **Automatic catching (set up >)** on the Hunt tab.

- **Catch by itself when a target is found**; off, the bot stops with the battle open and leaves it to you.
- **After catching, keep hunting.**
- **Before the ball:** lower the target's HP only with a move that cannot make it faint (or only with False Swipe), and put it to sleep or paralyse it.
- **Balls:** the order to throw them in; the Master Ball only if you allow it.
- **Safari Zone:** how many baits, then how many balls, repeated; and how many times to pay and go back in when a visit ends.

The bot will not start hunting with catching if you have no balls, or if your party and PC are full.

## Reset hunting (starters, gifts, legendaries)

For Pokémon you meet only once.

1. Create the targets on the Hunt tab (or just leave **Also stop for any SHINY** on).
2. Stand facing the Pokémon or the person who gives it. For a gift, leave room in your party.
3. **Hunt** tab > **Reset hunting >** > **SAVE HERE AND START**.

The bot saves the game there, presses A, checks what came, and loads that save again until it matches.

**Important:** while a reset hunt exists, the game does not save, not even when you close it, so a bad attempt is never kept. Saving is allowed again when the target is found or caught, when you press **FINISH**, or when you walk away from the spot while it is paused.

With **Try to catch it by itself** on, a failed catch reloads and brings the same Pokémon back (up to 10 times).

## The Control tab

- What the bot is doing, and why it stopped (gold for good news, red for a problem).
- The run in numbers: battles, heals, items used, time; targets found and caught when hunting.
- While hunting, how many of each target the run has found (a shiny that matched no target counts on its own).
- **Speed while running:** the game speed while the bot runs; your own speed comes back when it stops.
- **Stop history:** the last 40 stops, with the reason, route, time and place.

## Repels

On grass and Sweet Scent routes the bot will not start while a Repel is active, and stops if one is used during the run, because a Repel keeps the Pokémon away.

## Settings

| Setting | What it does |
| --- | --- |
| Language | English, Spanish, Portuguese or Japanese for the control panel. Names from the game stay in your game's language. |

## When it stops

The reason is always on the Control tab and in the history. The most common ones:

| Message | What to do |
| --- | --- |
| Paused: you pressed a button | Click **CONTINUE**. |
| I don't know where this Center's nurse is | Heal there once by hand. |
| Path blocked | The bot already tried again three times. If it keeps happening at the same place, record a healing path from the route to the nurse; `log/blocked` in the mod's data says what failed. |
| No Pokémon Center found nearby | Record a healing path from the route to the nurse. |
| A Repel is active | Wait for it to wear off. |
| Party and PC are full | Make room in the PC. |
| No balls in the bag | Buy balls. |
| The game asked a question | Answer it yourself, then **CONTINUE**. |

## Known limits

- Puzzle caves (Victory Road, Seafoam Islands, Icefall Cave, Pokémon Mansion, Lost Cave) are never crossed: record a healing path there.
- In double battles only the first opponent is targeted.
- Items from the bag restore HP and PP, but do not cure status or revive.
