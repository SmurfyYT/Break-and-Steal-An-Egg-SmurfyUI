# Smurfy's UI — Steal An Egg

Private source for the Steal An Egg script, built on the Smurfy's UI framework
(same window, tabs, phone layout, S button, themes, saved spots as the Ride A
Pet script).

## Features (v1.0)

| Tab | What's in it |
|---|---|
| 🏠 Home | Session time, eggs stolen, your Speed (+ gained), Money/s, Discord |
| 👤 Player | WalkSpeed, JumpPower, infinite jump, fly, noclip |
| 📍 Teleport | My plot, my treadmill, all 13 areas (with the Speed each needs), shops and machines, saved spots, Back |
| 🥚 Steal | **Auto steal**: teleport to an egg → Steal → home. Rare first, then the hardest area you're allowed in. Filters: only areas your Speed can handle, rare only, per-area toggles. Teleport or fly home. Guard alert / auto escape. Live list of eggs out (tap to teleport). On-screen 🥚 button on phones. |
| 👁️ ESP | Eggs (rare in gold, with area), guards (red when awake, who they chase), players |
| 🌍 World | Fullbright, no shadows, remove trees / weather |
| ⚙️ Settings | Keybinds, device layout, themes, battery saver, anti-AFK, server hop, **🧪 Debug report** |

The game's scripts couldn't be decompiled, so the game parts are built from the
place's instance tree: see [docs/GAME_NOTES.md](docs/GAME_NOTES.md) for what's
known and what still needs checking in game.

## Testing

```bash
./build/test/run.sh SmurfysUI.lua
```

Runs the UI as a phone and a PC, then plays auto steal in a fake Steal An Egg
(`build/test/steal_game.lua` + `steal_driver.lua`): rare first, speed filter,
area filter, fly home, guard escape, teleports, ESP, debug report, unload.
Needs the `luau` CLI (github.com/luau-lang/luau/releases).

## Reading a saved place

```bash
python3 tools/rbxl_tree.py place.rbxl out/scripts       # scripts + tree.txt
python3 tools/rbxl_attrs.py place.rbxl all.txt [prefix]  # classes, positions, sizes, tags, attributes, prompt texts
python3 tools/rbxl_positions.py place.rbxl               # part positions
```

Needs Python 3 with `lz4` and `zstandard`.

## Release rules

See [docs/HANDOFF.md](docs/HANDOFF.md). Public builds are **Luraph only**;
this repo stays private.
