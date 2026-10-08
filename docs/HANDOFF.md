# Smurfy's UI — handoff for a new project

Everything a new chat needs to build a script for another Roblox game with the
same UI system. Upload this whole folder (or the zip) to the new chat together
with the starter prompt at the bottom.

## What's in this folder

| File | What it is |
|---|---|
| `SmurfysUI.lua` | The full v1.3 source (Ride A Pet). Use it as the template: keep the framework, replace the game features. |
| `build/test/harness.lua` | Fake Roblox for testing scripts outside the game (instances, signals, a scheduler with a fake clock, CFrame/Vector3/UDim2 mocks, executor functions). |
| `build/test/driver.lua` | UI checks run as a phone and as a PC (menu opens, tabs, fly, buttons, saved spots…). |
| `build/test/egg_game.lua` + `egg_driver.lua` | Example of a *fake game* + checks for a game feature (Ride A Pet's auto collect). Copy this pattern for the new game's features. |
| `build/test/run.sh` | Runs all tests: `./build/test/run.sh SmurfysUI.lua` |
| `build/build.sh`, `build/obfuscate.config.lua` | Old Prometheus build (no Vmify). Only for private quick tests now. Public builds are Luraph. |
| `tools/rbxl_tree.py` | Reads a saved place file (`.rbxl`) and dumps every script's source + the instance tree. |
| `tools/rbxl_positions.py` | Reads a `.rbxl` and prints the position (and tags) of every part. This is how the teleport regions were found. |

Tools needed: the `luau` command-line tool (github.com/luau-lang/luau/releases)
for tests; Python 3 with `lz4` and `zstandard` for the `.rbxl` tools.

## How `SmurfysUI.lua` is laid out

Framework (reuse as is) vs. game-specific (replace), by the `-- ===== X =====` headers:

| Section | Keep / replace |
|---|---|
| CONFIG, SERVICES, STATE, SETTINGS FILE, HELPERS, DEVICE | **Keep** (change `CONFIG.Title`, `Version`, `DiscordLink`) |
| SCREEN GUI, WINDOW, STARS, TOP BAR, SIDEBAR, CONTENT AREA, NOTIFICATIONS | **Keep** |
| TABS, ELEMENTS (`Section`, `Label`, `Button`, `Toggle`, `Slider`, `Dropdown` + `Option`, `Keybind`) | **Keep** |
| PLAYER FEATURES (walk speed, jump, inf jump, fly, noclip) | **Keep** |
| EGG COLLECTOR ENGINE, AUTO FEATURES ENGINE | **Replace** (Ride A Pet only) |
| OPEN / CLOSE / MINIMIZE, DRAGGING, OPEN BUTTON + TOUCH CONTROLS, KEY HANDLING | **Keep** |
| BUILD TABS: Home, Player, Teleport (saved spots, My plot, Back) | **Keep**, but drop Ride A Pet bits (Shops, Egg regions) |
| BUILD TABS: Eggs, Auto, ESP egg parts, World trees/weather | **Replace** with the new game's tabs |
| BUILD TABS: Buttons, Settings | **Keep** |
| START, DISCORD INVITE | **Keep** |

### Using the framework

```lua
local MyTab = createTab("Farm", "🌾", "Short description under the title")
MyTab:Section("🌾 Auto farm")
local t = MyTab:Toggle("Auto farm", false, function(on) Farm.Enabled = on end)
MyTab:Slider("Range", 10, 200, 50, function(v) Farm.Range = v end)
MyTab:Button("Do it now", function() ... end)
local list = MyTab:Dropdown("🗺️ Places", false)     -- scrollable dropdown
list:Option("Spawn", function() ... end)            -- compact item
list:Toggle("Option inside", false, function(on) end)
notify("Title", "Message", 3)
-- an on-screen mobile button for a toggle:
table.insert(Mobile.Targets, { Id = "Farm", Icon = "🌾", Label = "Farm", Toggle = t })
```
Toggles and sliders save themselves between sessions. Wrap big blocks in
`isolate(function() ... end)` (see below).

## Hard-learned rules (follow these)

1. **Luau allows max 200 locals per function.** The main chunk is near the
   limit: build each tab inside `isolate(function() ... end)`, and put new
   helpers on tables (`Farm.Thing = function...`) instead of new top-level locals.
2. **Obfuscators mangle big numbers.** Compare large IDs as text:
   `tostring(game.PlaceId) == "124216119978534"` (and use string keys in tables).
3. **Never `tonumber(x:GetAttribute(...))` directly**: in obfuscated builds it
   can get no argument. Use `Mobile.AttrNumber(inst, name, default)`.
4. **Prometheus Vmify miscompiled builds** (fly broke). Public builds are Luraph.
5. **Executor functions differ.** Always check `type(fn) == "function"` and `pcall`
   (`setclipboard`, `request`, `fireproximityprompt`, `getconnections`, `writefile`…).
6. **The ScreenGui uses `IgnoreGuiInset = true`**: GUI positions and the mouse
   position are both full-screen coordinates (don't subtract the top bar).
7. **Games built with the "Net" package name remotes `RE/<Name>`**: one
   RemoteEvent whose name contains the slash, directly under the Net module,
   not a folder `RE`. Look up `{"packages","Net","RE/VolcanoDip"}`.
8. **Read the game's own client scripts before guessing.** Decompile the place
   (`tools/rbxl_tree.py`), find the remotes and what the game's buttons send, and
   listen to the game's own events (e.g. "dip started/cancelled") instead of
   guessing from timers.
9. **Anti-cheat patterns seen in Ride A Pet** (may apply elsewhere): the server
   counts teleports (a `TeleportFlags` attribute), and items carried in by
   teleport were refused. Dropping and re-picking cleared that. Some areas cap
   speed: move with CFrame steps at a capped speed there.
10. **Mobile first.** Test as phone *and* PC. The S button, on-screen buttons
    and the smaller phone layout are part of the framework.

## Testing

```bash
./build/test/run.sh SmurfysUI.lua      # phone, pc and game tests
```
- For each new game feature, write a small fake game (like `egg_game.lua`) that
  copies the real game's rules, and checks (like `egg_driver.lua`).
- Luraph builds can't run in the harness (Luraph detects it isn't real Roblox),
  so test plain source here and test the Luraph file in Delta.

## Release workflow (rules)

1. Private source repo for the readable code. Only the owner has access.
2. Public repo gets **Luraph builds only**. Never plain or Prometheus builds.
   Removing a file later doesn't erase it from git history.
3. Flow: change source → tests pass → owner runs it through Luraph → owner tests
   the Luraph file in Delta (menu, fly, main features) → upload to the public
   repo → bump `CONFIG.Version`.
4. Users load it with:
   `loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/<repo>/main/<file>"))()`
5. The owner tests on BlueStacks (phone mode) with the Delta executor.

## Starter prompt for the new chat

> I'm making a new Roblox script for **[GAME NAME + link]** using the same UI
> system as my Smurfy's UI script. I've uploaded `HANDOFF.md`, `SmurfysUI.lua`
> (the template), the test harness in `build/test/` and the `.rbxl` tools. Read
> `HANDOFF.md` first and follow its rules.
> Keep the framework from `SmurfysUI.lua` (window, tabs, elements, Player tab,
> saved teleport spots, Buttons and Settings tabs, Discord card), remove the
> Ride A Pet parts (eggs, volcano, auto features, egg regions, shops) and build
> these features for the new game: **[LIST FEATURES]**.
> Title: **[NAME]**, version **v1.0**, Discord: **https://discord.gg/5KFN8bbXhW**.
> I've also uploaded a saved place file (`.rbxl`) of the game. Decompile it and
> read the game's scripts before building anything.
> I test on BlueStacks phone mode with Delta. Public builds are Luraph only.
