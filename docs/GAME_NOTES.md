# Steal An Egg — how the game works

From the decompiled client scripts of `stealnegg.rbxl` (second save; the first
one's scripts failed to decompile). Script paths below are under
`ReplicatedStorage`. Read the place with `tools/rbxl_tree.py` and
`tools/rbxl_attrs.py`.

## Map

Everything sits on one line along **X** (Z ≈ -365, floor Y ≈ 68):

- `World.Areas.SeparationLine` (x ≈ 552): its LookVector points into the areas.
  Past it you're "in gameplay" (`Shared.Util.GuardAreaGeometry.IsPastLine`).
- Plots are west of the line (`EggCarryBounds.SafeZone`, x 362–552).
- 13 guarded areas east of it, harder the further east.

| Area | Speed needed | Bounds center X |
|---|---|---|
| Forest | 11 | 600 |
| Lake | 900 | 722 |
| Desert | 10K | 901 |
| Jungle | 40K | 1125 |
| Snow | 170K | 1405 |
| Volcano | 700K | 1759 |
| Abyss Ocean | 2.5M | 2166 |
| Prehistoric | 18M | 2634 |
| Cosmic | 700M | 3207 |
| Cherry Blossom | 2.5B | 3928 |
| Titan Temple | 7B | 4698 |
| Light Dark | 20B | 5577 |
| Enchanted Forest | 50B | 6524 |

Area model: `Bounds`, `ClosestExitPoint`, `Nests`, `Guard` (attributes
`GuardState` = "Sleeping" / "Waking" / "Chasing", `TargetPlayer` = player
name or "", `WakeTargetPlayer`), area attribute `GuardEscapeSpeeds`
(Vector2, X = Speed needed). Without enough Speed the server sends
`GuardPatrol.SpeedTollWarning` ("You don't have enough speed!").

## Field eggs (the ones you steal) — `Client.EggState`

The module keeps every field egg as a record (`Shared.Types.AreaEggs`):

```
Uid, AreaId, NestId, AssetCategory (the pet), AssetScale, Mutations,
BottomCFrame, BoundsCFrame (where it is), BoundsSize,
State = "Slot" | "Carried" | "Dropped" | "GuardCarried" | "Claimed",
CarrierUserId?, DroppedAt?, Version
```

- `EggState.ReadFieldEggs()` → `{ Records, ServerTime }` (kept live by the
  `RE.EggWorld.FieldEgg*` events). Fallback: `RF.EggWorld.AskFieldEggSnapshot`.
- **Steal**: `EggState.CarryFieldEgg(uid, slotKey)` =
  `RF.EggWorld.AskFieldEggCarry:InvokeServer({ Uid, FirstAreaSlotKey })` →
  `ok, reason`. `slotKey` = `"<AreaId>:<NestId>"` only for uids starting with
  `FirstAreaEgg_` (the tutorial egg), else nil.
- The game's prompt (`Controllers.Game.AreaEggsController`): `CarryAreaEgg`,
  MaxActivationDistance 8, hold 1.2 s (0.25 s with the workspace attribute
  `FastEggPickupTime`), enabled only past the SeparationLine and when the
  character isn't `IsTrapped`.
- `RE.EggWorld.FieldEggCarry` → `{ IsCarrying, Uid?, AreaId?, AssetCategory?,
  RunBackWakeDelayRequired?, GuardDisabled?, SpeedMultiplier }`.
- Delivery: back at your plot's spawn (the tutorial's "Go to your Pen!" points
  at the plot spawn). The server then sends `RE.EggWorld.FieldEggRedeemVerdict`
  → `{ AssetCategory, DisplayName, Rarity, Color, Position }` ("You stole an
  EGG!"). Decided server-side; the exact radius isn't in the client.
- Drop: `RF.EggWorld.AskFieldEggDrop({ Reason })`.

## Your eggs — place and hatch

- A stolen egg becomes a **Tool**: attributes `ItemType = "AssetEgg"`, `UID`.
- **Place** (`Controllers.Game.Eggs.EggPlacementController`): with the tool
  held, `EggState.PlantEgg(uid, CenterPoint.CFrame:ToObjectSpace(CFrame.new(hit)))`
  = `RF.EggWorld.AskPlaceEgg({ Uid, LocalCFrame })`, where `hit` is a point on
  the plot's `ToUpdate.PetArea` and `CenterPoint` is the plot's own.
- `EggState.ReadOwnerEggs(userId)` → `{ [uid] = record }`; placed ones have
  `Placement = { LocalCFrame, PlacedAt, GrowthDuration?, ReadyAt?, ... }`.
- **Hatch** (`Shared.Eggs.PlacedEggRenderer`): when `EggState.IsReadyToHatch(uid)`,
  `EggState.BeginHatch(uid)` (`RF.EggWorld.AskHatch`), the animation plays,
  then `EggState.FinishHatch(uid)` (`RF.EggWorld.AskFinishHatch`) → granted pet uid.
  Not ready yet → the prompt offers "Skip Growth" (Robux) instead.

## Pets, rarities

- `Data.Assets.Directory[AssetCategory]` → `{ DisplayName, Rarity, EarningRate, Egg = { GrowthTime, ... } }`.
- `Data.Rarity` ranks: Common 1, Uncommon / SuperRare 2, Rare 3, Epic 4,
  Legendary 5, Mythic / Rainbow / BrainrotGod 6, Cosmic 7, Secret 8,
  Eternal / Limited 9, Divine / Transcendent 10, Titan 11, LightDark 12.

## Plots — `workspace.Plots.<n>`

`Client.PlotState.ResolvePlot()` → `{ PlotFolder, PetArea, CenterPoint, ... }`
for your plot (ownership comes from the server, the sign just shows it).
Parts: `SpawnPoint`, `CenterPoint`, `TreadmillBottom`, `ToUpdate.PetArea`.

## Other remotes (arguments from the game's calls)

| What | Call |
|---|---|
| Away earnings | `RF.AwayEarnings.AskCollect({ Kind = "Claim" })` → ok, _, `{ AwardedAmount }` |
| Equip best pets | `RF.Haul.WearBest()` |
| Treadmill | standing on your treadmill: the client calls `RF.Treadmill.AskWearStill()` and the server trains Speed (`RE.Treadmill.SpeedGained`) |
| Treadmill upgrade | `RF.Treadmill.AskTierRaise(id)` |
| Base upgrade | `RE.Homestead.AskBaseTierRaise:FireServer()` |
| Index rewards | `RF.Codex.AskRedeemAll()` |
| Group reward | `RF.GroupPerk.RedeemPerk(id)` |
| Sell all (NPC) | `RE.PetSatchel.SellEveryPet:FireServer(list)` |

## Anti-cheat seen in the client

- `ObbyAntiTPClientController` only covers the monster event's obby region.
- Nothing client-side checks teleports on the main map; the server decides
  carries and deliveries (unknown checks). Fly home is there as the safer option.
