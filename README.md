# Smurfy's Simple UI — Movement Lab (Break & Steal an Egg)

`SmurfySimple.lua`: movement / teleport tests for Delta (Android / BlueStacks).

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/SmurfyYT/Break-and-Steal-An-Egg-SmurfyUI/claude/funny-meitner-mtnvz3/SmurfySimple.lua"))()
```

## Window
- Drag the top bar (touch or mouse). **–** hides it; tap the round **S** to bring it back.
- Tabs scroll sideways. **Main** has **Restore settings** and **Unload** (also the **X**).

## Tests (one per tab)
Stand somewhere open, press the green button, send the results. A result is **ok** when you
stay where you went for 2 s after arriving, **BACK** when something moves you more than 8 studs
away (a server pull-back), **DIED** if you die. Each trial goes back to where you started after.

| Tab | What it does |
|---|---|
| **Snap** | Live watcher: lists every time you're moved > 8 studs in one frame by something other than the script. Plus a quick check (plain TP 50 studs). |
| **Ladder** | Plain teleport (no hiding) at 10, 25, 50, 100, 250, 500, 1000 studs. |
| **Methods** | Plain / Ghost / Fling / 300 studs/s glide at 50, 250, 1000 studs, as a table. |
| **Warmup** | Hidden time before the jump: none, 1 frame, 0.05, 0.15, 0.5 s (2 tries each). The shortest that always works becomes the warmup used by Ghost / Fling TPs. |
| **Glide** | Slide there at 100, 300, 1000, 3000, 10000 studs/s; shows the fastest that's accepted. |
| **Endure** | Stay hidden 5, 15, 30, 60 s, then check you're alive and not pulled. |
| **Under** | Drop under the floor (20 / 50 / 100 studs), glide under the map with no collisions, come up at the target. Stays 50 studs above the game's kill height. |
| **Remotes** | Remote spy: every remote your client sends (→) and receives (←), how often, last arguments. Copy list, list every remote in the game. Only watches, never sends. Sent (→) needs `hookmetamethod`. |

### Hiding methods
Both change what replicates right after physics (Heartbeat), then put you back on a "hold" point
before the next physics step and before drawing, so you stand still on screen:
- **Ghost**: your CFrame is moved 9e9 studs away (the game's own scripts read your real spot via
  `hookmetamethod`, when the executor has it).
- **Fling**: your velocity is set huge (Max power).

A hidden TP = hidden in place for the warmup, then the jump in one frame. Hidden tests walk off
your own plot first.

## Tests of the script
```bash
./tests/run.sh      # needs the luau CLI; LUAU=/path/to/luau, VERBOSE=1 for the log
```
Runs every tab against a fake server with known rules (plain moves over 20 studs a frame get
pulled back, a jump needs 2 hidden frames before it, 40 s hidden kills you) and checks each test
finds them. It isn't the real game: the real numbers come from running the tabs in-game.
