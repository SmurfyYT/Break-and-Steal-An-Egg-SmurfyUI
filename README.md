# Smurfy's Simple UI — Break & Steal an Egg

`SmurfySimple.lua`: a small script for Delta (Android / BlueStacks). Paste the whole file into the executor.

## Window
- Drag the top bar (mouse or touch). The position is remembered.
- **–** hides the window; tap the round **S** button to bring it back (the S is draggable too).
- **X** / **Unload** stops everything and removes the UI.
- **Restore settings** stops the farm and the fling, puts every option back to default and resets the window position.

## Test tab
- **Auto farm (fling)**: break an egg → grab the animal that dropped from it → go home → bank.
  You stay flung the whole time and the fling stops only once you're just *outside* your plot.
  Then you walk in so the game banks the animal.
- **Zone**: Any (nearest egg) or 1-9.
- **Fling power**: how hard the character looks flung to everyone else.
- **Bank after every grab** (off = fill the satchel first), **Walk in to bank**.
- Manual tests: **Fling in place**, **Fling TP → nearest egg**, **Fling TP → outside my plot**.

### How the fling TP works
Every frame, right after physics (Heartbeat), the character's velocity is set to a huge value. That's
what the server and other players get, so you look flung out of the map. Before the next physics step
(Stepped / RenderStepped) the velocity is zeroed and you're pinned to a hold point, so on your screen
you stand still and can hit eggs and press prompts. Teleporting moves that hold point in hops while
the fling stays on. It never flings you on your own plot: you're stepped just outside it first.

## Tests
```bash
./tests/run.sh      # needs the luau CLI; LUAU=/path/to/luau to point at it, VERBOSE=1 for the log
```
Runs the script in a fake Roblox + fake game (rules copied from the place's client scripts) as a phone
and as a PC. It isn't the real game: the server's anti-cheat and guard behaviour can't be tested here.
