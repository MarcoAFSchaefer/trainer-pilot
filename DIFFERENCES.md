# Differences from the unmodded game

Trainer Pilot plays the game for you by pressing the game's own buttons. It does not change what the game does when a button is pressed.

## Game data and rules

Nothing. No species, moves, items, maps, text, trainers or battle rules are changed. Encounter rates, shiny odds, catch rates, experience and EV gains are the game's own: the bot only repeats what a player could do by hand.

## What it does that a player would otherwise do

- Walks routes, fishes, uses VS Seeker and Sweet Scent, fights, runs, switches, throws balls and uses items from the bag.
- Walks to a Pokémon Center and back, using Surf, Cut, Rock Smash, Strength and Waterfall on the way when the party can.
- **Reset hunting:** saves the game where you stand (through the game's own save), takes the Pokémon, and reloads the save if it is not a target. This overwrites your save at the spot where you start the hunt, the same as saving there by hand.
- Sets the game speed while it runs and puts it back when it stops.
- **Restart on long reset hunts** (off by default): closes and reopens the game every few minutes during a reset hunt and carries on. It needs the game started with a game chosen in advance; see [docs/GUIDE.md](docs/GUIDE.md).

Any button you press pauses the bot.

## Screen and input

The control panel is a Trainer Desk panel. While the bot runs, it sends button presses to the game; nothing else about input changes.

## Saves

The mod adds nothing of its own to the save. Routes, targets, settings and the history of stops are kept in the mod's own cache. What the bot does in the game (experience, catches, items used, money) is saved by the game as usual.

## Turning it off

Disable the mod and the game plays as before. Nothing is left in the save.
