# Smurfy's Simple UI — Break & Steal an Egg

`SmurfySimple.lua`: a small script for Delta (Android / BlueStacks). Paste the whole file into the executor.

## Window
- Drag the top bar (mouse or touch). The position is remembered.
- **–** hides the window; tap the round **S** button to bring it back (the S is draggable too).
- **X** / **Unload** stops everything and removes the UI.
- **Restore settings** stops the farm and the fling, puts every option back to default and resets the window position.

## Test tab
- **Auto farm**, one round:
  1. Hidden TP next to an egg and wait 1 second.
  2. Unhide, walk out of dig reach, walk back (**Walk out & back before mining**, on by default).
  3. Mine the egg (the server sees you; the game's Auto Swing is kept off).
  4. Wait for the hatch animation (up to 20 s) until the egg's own animal spawns, then hidden TP to it and grab it.
  5. Hidden all the way home, unhide just *outside* your plot, walk in so the game banks it.
- **Method**: **Ghost** (default) or **Fling**.
- **Zone**: Any (nearest egg) or 1-9.
- **Fling power** (Fling only): High → Max, default Max.
- **Bank after every grab** (off = fill the satchel first), **Walk in to bank**.
- Manual tests: **Hide in place**, **TP → nearest egg**, **TP → outside my plot** (with the picked method).

### How hiding works
Both methods change what replicates right after physics (Heartbeat), then put you back on a
"hold" point before the next physics step and before drawing (Stepped / RenderStepped), so on
your screen you stand still:
- **Ghost**: your CFrame is moved 9e9 studs away, so the server and other players see you far away.
  The game's own scripts keep reading your real spot (`hookmetamethod`, when the executor has it).
- **Fling**: your velocity is set huge, so you look flung out of the map.

A TP = hidden in place for 0.15 s, then the hold point jumps to the target in one frame, so it looks
like a teleport. You're never hidden on your own plot (you walk off it first). Hitting eggs, grabbing
and banking need the server to see you there, so the ghost is turned off for those.

## Tests
```bash
./tests/run.sh      # needs the luau CLI; LUAU=/path/to/luau to point at it, VERBOSE=1 for the log
```
Runs the script in a fake Roblox + fake game (rules copied from the place's client scripts) as a phone
and as a PC. It isn't the real game: the server's anti-cheat and guard behaviour can't be tested here.
