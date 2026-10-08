# Smurfy's UI — Break & Steal an Egg

Script for **Break & Steal an Egg** built on the Smurfy's UI framework (v1.0).

## Tabs
- **Home**: session time, eggs broken, animals banked, cash per hour, Discord.
- **Player**: walk speed, jump, infinite jump, fly, noclip.
- **Teleport**: my base, safe zone, my treadmill, zones 1-9, saved spots, back.
- **Farm**: auto farm (break eggs → grab the animal → bring it home → place it in your pen),
  zone picker, egg targeting (nearest / weakest / best zone), skip slow eggs,
  minimum animal rarity, teleport or fly travel, one-off buttons.
- **Base**: pen info, place animals now, equip best, sell backpack animals up to a rarity,
  upgrade base / treadmill, buy next pickaxe / trail.
- **Auto**: auto buy pickaxes and trails, auto upgrade base and treadmill, auto claim rewards.
- **ESP**: eggs (type, health, time to break), animals to grab (rarity, despawn timer),
  guards, players, fullbright / no shadows / no fog.
- **Buttons** (phone / tablet) and **Settings** (keybinds, layout, theme, battery saver,
  anti AFK, server hop, unload).

## Testing
```bash
./build/test/run.sh SmurfysUI.lua   # phone + PC UI checks, then the farm in a fake game
```
Needs the `luau` CLI. `tools/rbxl_tree.py` and `tools/rbxl_positions.py` read a saved place file.
