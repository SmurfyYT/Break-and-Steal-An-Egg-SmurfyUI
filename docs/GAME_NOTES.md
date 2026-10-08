# Steal An Egg — what we know about the game

From the saved place `Place_107778070777162_Steal_An_Egg_08-10-2026` (place id
`107778070777162`, compare it as text). **The save's scripts couldn't be
decompiled** (1983 of 2024 say "decompilation panicked"), so everything here
comes from the instance tree, attributes, prompt texts and remote names
(`tools/rbxl_tree.py`, `tools/rbxl_attrs.py`). Things marked ❓ are guesses
that still need checking in the real game: use **Settings → 🧪 Debug → Copy
debug report** in game to check them.

## Map layout

Everything sits on one line along **X** (Z ≈ -365, floor Y ≈ 68):

| Part | Position | Notes |
|---|---|---|
| `World.Areas.EggCarryBounds.SafeZone` | x 362–552 | Where the plots are. |
| `World.Areas.SeparationLine` | x ≈ 552 | Between the plots and the areas. |
| Guarded areas | x 553 → 7070 | 13 areas, east of the plots, harder the further east. |

`EggCarryBounds` has the attribute *"Playable floor footprints for carried-egg
cancellation. Upper height is ignored."*: a carried egg is cancelled when you
leave those floors (so flying high is fine, leaving the map sideways isn't).

## Plots — `workspace.Plots.<1..7>`

- Owner: `PlotSign.PlayerPlotSign.Frame.PlayerName.Text` = the owner's **user
  name** (no Owner value or attribute).
- Parts: `SpawnPoint` (home spot, used by auto steal), `CenterPoint`,
  `TreadmillBottom`, `ToUpdate.PetArea` (50×49 pen floor),
  `ToUpdate.StarterPen.Prompt1..3` (parts; prompts are made at runtime ❓).
- Attribute `BaseUpgradeLevel`.

## Areas — `workspace.World.Areas.GuardAreas.<Area>`

Each area model has `Bounds` (floor part), `ClosestExitPoint`, `Nests`,
`RequiredSpeedSign`, and a `Guard` model with attributes `AreaId`,
`GuardState` ("Sleeping"…), `Sleeping`, `TargetPlayer` (name ❓),
`WakeTargetPlayer`. The area's `GuardEscapeSpeeds` (Vector2): **X = Speed
needed** (the Rift Machine says "Unlocked at 700M speed", Cosmic needs 700M),
Y = maybe the guard's run speed ❓.

| Area | Speed needed | Bounds center X | Width |
|---|---|---|---|
| Forest | 11 | 600 | 93 |
| Lake | 900 | 722 | 140 |
| Desert | 10K | 901 | 205 |
| Jungle | 40K | 1125 | 230 |
| Snow | 170K | 1405 | 318 |
| Volcano | 700K | 1759 | 379 |
| Abyss Ocean | 2.5M | 2166 | 423 |
| Prehistoric | 18M | 2634 | 502 |
| Cosmic | 700M | 3207 | 642 |
| Cherry Blossom | 2.5B | 3928 | 676 |
| Titan Temple | 7B | 4698 | 860 |
| Light Dark | 20B | 5577 | 894 |
| Enchanted Forest | 50B | 6524 | 1090 |

## Eggs in the areas

- Models in `workspace.AreaEggSlotsClient` (GUID names, drawn by the client),
  each with a `Hitbox` part. Some have `PreparedSourceName =
  "Workspace.NewEggs.<Name>"` (used as the egg's name), rare ones have a
  `RareAreaEggHighlight` child.
- The steal button: a `ProximityPrompt` named **`CarryAreaEgg`** (ActionText
  "Steal", ObjectText "Egg") on a part named `SmartPromptPart` straight in
  `workspace`, sitting on the egg. Matched to the egg model by position.
- A few `SmartPromptPart`s carry a prompt "Apply Mutation" instead.

## Stats

`leaderstats.Speed` and `leaderstats["Money/s"]` (NumberValues). Player
attributes include `ActiveTrapCount`, `RagdollEndTime`, cash pack amounts.

## Shops and machines

| Thing | Path |
|---|---|
| Sell all / sell held | `Stands.Prompts.SellAll` / `SellHeldAsset` (prompts) |
| Gear shop | `Stands.Models.GearShopStand` |
| Trail shop | `Stands.Pads.TrailShop` |
| Group reward | `World.GroupReward` (prompt "CLAIM!") |
| Fuse / Rift / Butterfly | `World.Machines.FuseMachine` / `RiftMachine` / `ButterflyStation` |
| Enchanted Tree | `World.Build.EnchantedTreeInterior.Markers.EnterTrigger` |

## Remotes — `ReplicatedStorage.Packages.Networking.<RE|RF>.<Group>.<Name>`

Folders (not the `RE/Name` single-instance style of the other game). The
interesting ones (arguments unknown ❓):

- `RE.EggWorld`: `FieldEggCarry`, `FieldEggGone`, `FieldEggRedeemVerdict`,
  `FieldEggShifted`, `FieldEggBatchShifted`, `FieldEggCycleCountdown`,
  `OwnerDropped`, `OwnerShifted`
- `RF.EggWorld`: `AskFieldEggCarry`, `AskFieldEggDrop`, `AskPlaceEgg`,
  `AskHatch`, `AskFinishHatch`, `AskSkipGrowth`, `AskWearTool`, `AskDoffTool`
- `RE.GuardPatrol`: `Rouse`, `ForestStrike`, `SpeedTollWarning`, `SpeedTollOffer`
- `RF.AwayEarnings`: `AskCollect`, `FetchSummary` — `RF.Haul`: `WriteAutoSell`, `WearBest`
- `RE.PetSatchel`: `SellPet`, `SellEveryPet` — `RE.Treadmill.SpeedGained`

The script only **listens** to the `RE` ones (counting steals / deliveries and
logging them for the debug report). It doesn't call any `RF` yet: their
arguments need to be seen first (turn on event printing and copy the report).

## Open questions (check in game)

1. Does a teleported egg count at home, or does it need walking/flying in?
2. What does `FieldEggCarry` send (who carries, which egg)?
3. Where exactly does an egg count as delivered (safe zone, plot, pen)?
4. How are eggs placed and hatched (prompts in the pen, or a GUI)?
5. Does the server check speed / teleports (the `SpeedToll` remotes)?
