# Tests

`main.lua` is a LÖVE program that runs Trainer Pilot against a stand-in for the game: a few small maps (routes, a cave, a Pokémon Center), a simple battle, a bag and a PC. It checks recording and following routes, battles, healing at the Center and with items, travelling through the map of links, obstacles, hunting and catching, the Safari Zone, EV training, reset hunting with the save lock, the stop history, and clicks on the panel.

It runs on Linux with LÖVE 11.5 and a virtual X server:

```
BOT_MOD=/path/to/trainer-pilot/trainer_pilot \
xvfb-run -a -s "-screen 0 1280x800x24" love tests
```

`BOT_MOD` is the path to the `trainer_pilot` mod folder; `TEST_OUT` (default `/tmp/kg_out`) is where screenshots of the panel are written.

The run ends with `ALL BOT CHECKS PASSED`; a failing check prints `CHECK FAILED` with the reason and stops.

The stand-in has no pass-through building and no double battle, and passing here says nothing about how the real game behaves at those points (see docs/ENGINE_NOTES.md).
