# Smurfy's UI — Steal An Egg

Private source for the Steal An Egg script, built on the Smurfy's UI framework
(same window, tabs, phone layout, S button, themes, saved spots as the Ride A
Pet script).

## Features (v1.1)

| Tab | What's in it |
|---|---|
| 🏠 Home | Session time, eggs stolen, your Speed (+ gained), Money/s, Discord |
| 👤 Player | WalkSpeed, JumpPower, infinite jump, fly, noclip |
| 📍 Teleport | My plot, my treadmill, all 13 areas (with the Speed each needs), shops and machines, saved spots, Back |
| 🥚 Steal | **Auto steal** with the game's own steal request: rarest first, then the hardest area you're allowed in. Filters: lowest rarity, only areas your Speed can handle, per-area toggles. Teleport or fly home, waits for "You stole an EGG!". Trains on your treadmill while no eggs are out. Guard alert / auto escape. Live egg list (pet · rarity · area). **Base**: auto place eggs, auto hatch, auto collect away earnings, auto equip best, stand on treadmill. |
| 👁️ ESP | Eggs (pet, rarity color, area), guards (red when awake, who they chase), players |
| 🌍 World | Fullbright, no shadows, remove trees / weather |
| ⚙️ Settings | Keybinds, device layout, themes, battery saver, anti-AFK, server hop, 🧪 Debug report |

How the game works (remotes, arguments, records) is in
[docs/GAME_NOTES.md](docs/GAME_NOTES.md), read from the game's decompiled
client scripts. The script uses the game's own modules (`Client.EggState`,
`Client.PlotState`, `Data.Assets`) and falls back to calling the remotes
directly if an executor can't require them.

## Testing

```bash
./build/test/run.sh SmurfysUI.lua
```

Runs the UI as a phone and a PC, then plays auto steal in a fake Steal An Egg
(`build/test/steal_game.lua` + `steal_driver.lua`, built from the real game's
rules): rarest first, tutorial slot key, speed / rarity / area filters, fly
home, treadmill training, place + hatch + collect + equip best, guard escape,
teleports, ESP, debug report, unload. The PC pass runs without the game's
modules to check the remotes-only fallback.
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
