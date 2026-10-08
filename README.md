# Smurfy's Simple UI — Break & Steal an Egg

`SmurfySimple.lua`: a small script for Delta (Android / BlueStacks). Paste the whole file into the executor.

## Window
- Drag the top bar (mouse or touch). The position is remembered.
- **–** hides the window; tap the round **S** button to bring it back (the S is draggable too).
- **X** / **Unload** stops everything and removes the UI.
- **Restore settings** stops the farm and the fling, puts every option back to default and resets the window position.

## Test tab
- **Auto farm (fling)**, one round:
  1. Fling TP next to an egg and wait 1 second.
  2. Stop flinging, walk out of dig reach, walk back (**Walk out & back before mining**, on by default).
  3. Mine the egg (not flung).
  4. Wait for the hatch animation (up to 20 s) until the egg's own animal spawns, then fling TP to it and grab it.
  5. Stay flung back home, stop just *outside* your plot, walk in so the game banks it.
  The game's own **Auto Swing** button is kept off (turned off on load and whenever it gets switched on);
  the farm sends its own hits.
- **Zone**: Any (nearest egg) or 1-9.
- **Fling power**: how hard the character looks flung to everyone else (High → Max, default Max).
- **Bank after every grab** (off = fill the satchel first), **Walk in to bank**.
- Manual tests: **Fling in place**, **Fling TP → nearest egg**, **Fling TP → outside my plot**.

### How the fling TP works
Every frame, right after physics (Heartbeat), the character's velocity is set to a huge value. That's
what the server and other players get, so you look flung out of the map. Before the next physics step
(Stepped / RenderStepped) the velocity is zeroed and you're pinned to a hold point, so on your screen
you stand still and can hit eggs and press prompts. Teleporting: you're flung in place for 0.15 s,
then the hold point jumps to the target in a single frame, so it looks like a teleport. Fling power
defaults to **Max**. It never flings you on your own plot: you walk just off it first.

## Tests
```bash
./tests/run.sh      # needs the luau CLI; LUAU=/path/to/luau to point at it, VERBOSE=1 for the log
```
Runs the script in a fake Roblox + fake game (rules copied from the place's client scripts) as a phone
and as a PC. It isn't the real game: the server's anti-cheat and guard behaviour can't be tested here.
