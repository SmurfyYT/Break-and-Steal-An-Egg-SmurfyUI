-- Fake Steal An Egg, appended after harness.lua for steal_driver.lua.
-- Copies the real game's rules (from its client scripts, docs/GAME_NOTES.md):
--   * egg records live in ReplicatedStorage.Client.EggState (ReadFieldEggs);
--     State "Slot" can be stolen, BoundsCFrame is where the egg is
--   * stealing = EggState.CarryFieldEgg(uid, key) / RF.EggWorld.AskFieldEggCarry:
--     only past the separation line (x > 60) and within 10 studs of the egg
--   * the server sends RE.EggWorld.FieldEggCarry({ IsCarrying, Uid, ... }), then
--     claims the egg once you're within 15 studs of your plot's SpawnPoint:
--     RE.EggWorld.FieldEggRedeemVerdict({ DisplayName, Rarity, ... }) and an egg
--     Tool (ItemType "AssetEgg", UID) lands in your Backpack
--   * PlantEgg(uid, localCFrame) needs that tool held; eggs grow for 5 s, then
--     BeginHatch + FinishHatch
-- __NO_MODULES = true: the game's modules can't be required (remotes only).
local SG = { delivered = 0, stolen = {}, log = {}, carrying = nil, placed = 0, hatched = 0, collected = 0, woreBest = 0 }
__SG = SG

local function part(name, parent, pos, size)
    local p = newInstance("Part", name)
    p.CFrame = CFrame.new(pos)
    p.Size = size or Vector3.new(4, 1, 4)
    p.Parent = parent
    return p
end
local function folder(name, parent, class)
    local f = newInstance(class or "Folder", name)
    f.Parent = parent
    return f
end

methods.GetAttributes = function(self) return table.clone(self.__attrs or {}) end
methods.InvokeServer = function(self, ...) if self.__server then return self.__server(...) end end
methods.EquipTool = function(self, tool) tool.Parent = lp.Character end
methods.UnequipTools = function()
    for _, c in ipairs(lp.Character:GetChildren()) do
        if c.ClassName == "Tool" then c.Parent = SG.backpack end
    end
end
-- CFrame:ToObjectSpace (positions only, like the harness's CFrames)
do
    local index = CFmt.__index
    CFmt.__index = function(c, k)
        if k == "ToObjectSpace" then return function(self, other) return CFrame.new(other.Position - self.Position) end end
        return index(c, k)
    end
end

-- leaderstats + backpack
local stats = folder("leaderstats", lp)
local speedStat = newInstance("NumberValue", "Speed"); speedStat.Value = 5000; speedStat.Parent = stats
local moneyStat = newInstance("NumberValue", "Money/s"); moneyStat.Value = 1234; moneyStat.Parent = stats
SG.speed = speedStat
SG.backpack = folder("Backpack", lp, "Backpack")

-- plots: 1 is someone else's, 2 is yours (spawn at 20, 5, 60)
local plots = folder("Plots", workspace)
local function plot(name, owner, z)
    local m = folder(name, plots, "Model")
    local sign = part("PlotSign", m, Vector3.new(0, 40, z))
    local bb = folder("PlayerPlotSign", sign, "BillboardGui")
    local frame = folder("Frame", bb, "Frame")
    local label = newInstance("TextLabel", "PlayerName"); label.Text = owner; label.Parent = frame
    part("SpawnPoint", m, Vector3.new(20, 5, z))
    part("CenterPoint", m, Vector3.new(0, 1, z))
    part("TreadmillBottom", m, Vector3.new(30, 1, z + 10))
    local toUpdate = folder("ToUpdate", m, "Model")
    part("PetArea", toUpdate, Vector3.new(-20, 1, z), Vector3.new(30, 0, 30))
    return m
end
plot("1", "SomeoneElse", 0)
SG.plot = plot("2", "Tester", 60)
SG.home = Vector3.new(20, 5, 60)
SG.treadmill = Vector3.new(30, 1, 70)
__root.CFrame = CFrame.new(Vector3.new(20, 8.5, 60))

-- areas
local world = folder("World", workspace)
local areasFolder = folder("Areas", world)
local guardAreas = folder("GuardAreas", areasFolder)
SG.guards = {}
local function area(name, x, need)
    local m = folder(name, guardAreas, "Model")
    m:SetAttribute("GuardEscapeSpeeds", Vector2.new(need, 20))
    part("Bounds", m, Vector3.new(x, 0, 0), Vector3.new(200, 0, 150))
    part("ClosestExitPoint", m, Vector3.new(x - 90, 1, 40))
    local guard = folder("Guard", m, "Model")
    guard.__pivot = Vector3.new(x, 5, -50)
    guard:SetAttribute("GuardState", "Sleeping")
    guard:SetAttribute("Sleeping", true)
    guard:SetAttribute("TargetPlayer", "")
    SG.guards[name] = guard
    return m
end
area("Forest", 200, 10)
area("Snow", 500, 1000000)

-- remotes (Networking package)
local packages = folder("Packages", Services.ReplicatedStorage)
local networking = folder("Networking", packages, "ModuleScript")
local function remote(kind, group, name)
    local k = networking:FindFirstChild(kind) or folder(kind, networking)
    local g = k:FindFirstChild(group) or folder(group, k)
    local r = newInstance(kind == "RE" and "RemoteEvent" or "RemoteFunction", name)
    r.Parent = g
    return r
end
local carryEvent = remote("RE", "EggWorld", "FieldEggCarry")
local verdictEvent = remote("RE", "EggWorld", "FieldEggRedeemVerdict")
remote("RE", "EggWorld", "FieldEggGone")

-- the pets inside the eggs: Data.Assets.Directory
local RARITY = {
    Common = { _id = "Common", DisplayName = "Common", Rank = 1, Color = Color3.fromRGB(200, 200, 200) },
    Epic = { _id = "Epic", DisplayName = "Epic", Rank = 4, Color = Color3.fromRGB(170, 90, 255) },
    Mythic = { _id = "Mythic", DisplayName = "Mythic", Rank = 6, Color = Color3.fromRGB(255, 80, 120) },
}
local ASSETS = { Directory = {
    ["Petal Beetle"] = { DisplayName = "Petal Beetle", Rarity = RARITY.Common },
    ["Prism Gecko"] = { DisplayName = "Prism Gecko", Rarity = RARITY.Mythic },
    ["Frost Owl"] = { DisplayName = "Frost Owl", Rarity = RARITY.Epic },
    ["Moss Toad"] = { DisplayName = "Moss Toad", Rarity = RARITY.Common },
} }

-- field eggs
local records = {}
local slots = folder("AreaEggSlotsClient", workspace)
local nextId = 0
function SG.spawnEgg(name, x, z)
    nextId += 1
    local uid = (nextId == 1 and "FirstAreaEgg_1_" or "egg") .. nextId
    local r = {
        Uid = uid, AreaId = x < 350 and "Forest" or "Snow", NestId = "Nest" .. nextId,
        AssetCategory = name, BoundsCFrame = CFrame.new(Vector3.new(x, 2, z)), State = "Slot", Version = 1,
    }
    records[uid] = r
    local m = folder(uid, slots, "Model")
    m.__pivot = Vector3.new(x, 2, z)
    return r
end
function SG.eggOut(r) return records[r.Uid] ~= nil and r.State == "Slot" end

local function copy(r)
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    return c
end
local function fieldRows()
    local rows = {}
    for _, r in pairs(records) do table.insert(rows, copy(r)) end
    return { Records = rows, ServerTime = os.clock() }
end

-- the server
local owned = {}
local ownedId = 0
local function carry(request)
    local r = type(request) == "table" and records[request.Uid]
    if not r then return false, "Egg not found" end
    if SG.carrying then return false, "Already carrying" end
    if r.State ~= "Slot" and r.State ~= "Dropped" then return false, "Not available" end
    if string.find(r.Uid, "FirstAreaEgg_", 1, true) == 1 and request.FirstAreaSlotKey ~= r.AreaId .. ":" .. r.NestId then
        return false, "Bad slot key"
    end
    local pos = SG.serverPos or __root.Position -- where the server last saw you
    if pos.X <= 60 then return false, "Not in gameplay" end
    if (pos - r.BoundsCFrame.Position).Magnitude > 10 then
        table.insert(SG.log, "too far from " .. r.AssetCategory)
        return false, "Too far"
    end
    r.State = "Carried"
    SG.carrying = r
    table.insert(SG.stolen, r.AssetCategory)
    table.insert(SG.log, "stole " .. r.AssetCategory)
    carryEvent.OnClientEvent:Fire({ IsCarrying = true, Uid = r.Uid, AreaId = r.AreaId, AssetCategory = r.AssetCategory, SpeedMultiplier = 1 })
    return true
end
local function plant(request)
    local uid, cf = request.Uid, request.LocalCFrame
    local tool
    for _, c in ipairs(lp.Character:GetChildren()) do
        if c.ClassName == "Tool" and c:GetAttribute("UID") == uid then tool = c end
    end
    if not tool then return false, "Hold the egg first" end
    for _, o in pairs(owned) do
        if o.Placement and (o.Placement.LocalCFrame.Position - cf.Position).Magnitude < 5 then return false, "Spot taken" end
    end
    tool.Parent = nil
    owned[uid] = { Uid = uid, AssetCategory = tool:GetAttribute("Category"), Placement = { LocalCFrame = cf, PlacedAt = os.clock(), ReadyAt = os.clock() + 5 } }
    SG.placed += 1
    return true
end
local function ready(uid)
    local o = owned[uid]
    return o ~= nil and o.Placement ~= nil and os.clock() >= o.Placement.ReadyAt
end
local function beginHatch(uid)
    if not ready(uid) then return false, "Not ready" end
    owned[uid].Hatching = true
    return true
end
local function finishHatch(uid)
    local o = owned[uid]
    if not (o and o.Hatching) then return false, "Not hatching" end
    owned[uid] = nil
    SG.hatched += 1
    return true, nil, "pet_" .. uid
end

remote("RF", "EggWorld", "AskFieldEggCarry").__server = carry
remote("RF", "EggWorld", "AskFieldEggSnapshot").__server = fieldRows
remote("RF", "EggWorld", "AskPlaceEgg").__server = plant
remote("RF", "EggWorld", "AskHatch").__server = beginHatch
remote("RF", "EggWorld", "AskFinishHatch").__server = finishHatch
remote("RF", "AwayEarnings", "AskCollect").__server = function(request)
    if type(request) ~= "table" or request.Kind ~= "Claim" then return false, "bad request" end
    SG.collected += 1
    return true, nil, { AwardedAmount = 100 }
end
remote("RF", "Haul", "WearBest").__server = function() SG.woreBest += 1 return true end

-- the game's modules (what the script requires)
local client = folder("Client", Services.ReplicatedStorage)
local eggStateModule = folder("EggState", client, "ModuleScript")
local plotStateModule = folder("PlotState", client, "ModuleScript")
local data = folder("Data", Services.ReplicatedStorage)
local assetsModule = folder("Assets", data, "ModuleScript")
local function deep(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and deep(v) or v end
    return c
end
local EggState = {
    ReadFieldEggs = fieldRows,
    CarryFieldEgg = function(uid, key) return carry({ Uid = uid, FirstAreaSlotKey = key }) end,
    ReadOwnerEggs = function(userId) return userId == lp.UserId and deep(owned) or {} end,
    PlantEgg = function(uid, cf) return plant({ Uid = uid, LocalCFrame = cf }) end,
    IsReadyToHatch = ready,
    BeginHatch = beginHatch,
    FinishHatch = finishHatch,
}
local harnessRequire = require
require = function(m)
    if not __NO_MODULES then
        if m == eggStateModule then return EggState end
        if m == plotStateModule then return { ResolvePlot = function() return { PlotFolder = SG.plot } end } end
        if m == assetsModule then return ASSETS end
    end
    return harnessRequire(m)
end

-- the server only gets the root's position as it is right after Heartbeat
-- (what the ghost tests rely on)
do
    local heartbeat = Services.RunService.__signals.Heartbeat
    local fire = heartbeat.Fire
    heartbeat.Fire = function(self, ...)
        fire(self, ...)
        SG.serverPos = __root.Position
    end
end

-- executor hook: hookmetamethod(game, "__index", fn) swaps the instances'
-- __index; checkcaller() is false while SG.gameReading (a game script reads)
hookmetamethod = function(_, name, fn)
    assert(name == "__index", "only __index is faked")
    local original = Instance_mt.__index
    Instance_mt.__index = fn
    SG.hooked = true
    return original
end
checkcaller = function() return not SG.gameReading end
newcclosure = function(f) return f end

-- Humanoid:MoveTo walks the root (flat) at WalkSpeed
methods.MoveTo = function(self, pos) self.__moveTo = pos end
-- per frame: walking, falling under the floor (Y < 0), the void at -500
workspace.FallenPartsDestroyHeight = -500
SG.respawns = 0
function SG.physics()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = __root
    if hum and hum.__moveTo then
        local pos = root.Position
        local flat = (hum.__moveTo - pos) * Vector3.new(1, 0, 1)
        local step = hum.WalkSpeed / 60
        if flat.Magnitude <= step then
            root.CFrame = CFrame.new(Vector3.new(hum.__moveTo.X, pos.Y, hum.__moveTo.Z))
            hum.__moveTo = nil
        else
            root.CFrame = CFrame.new(pos + flat.Unit * step)
        end
    end
    local pos = root.Position
    if pos.Y < 0 then
        SG.fallSpeed = (SG.fallSpeed or 0) + 196.2 / 60
        root.CFrame = CFrame.new(pos - Vector3.new(0, SG.fallSpeed / 60, 0))
    else
        SG.fallSpeed = 0
    end
    if root.Position.Y < workspace.FallenPartsDestroyHeight then
        -- the void: the character dies, a carried egg drops, respawn at the plot
        SG.fallSpeed = 0
        local r = SG.carrying
        if r then
            SG.carrying = nil
            r.State = "Dropped"
            table.insert(SG.log, "void dropped " .. r.AssetCategory)
            carryEvent.OnClientEvent:Fire({ IsCarrying = false, SpeedMultiplier = 1 })
        end
        root.Parent = nil
        local newChar = newInstance("Model", "Tester")
        local newHum = newInstance("Humanoid", "Humanoid")
        for k, v in pairs(hum.__props) do if k ~= "Parent" then newHum.__props[k] = v end end
        newHum.Parent = newChar
        local newRoot = newInstance("Part", "HumanoidRootPart")
        newRoot.CFrame = CFrame.new(SG.home + Vector3.new(0, 3.5, 0))
        newRoot.Parent = newChar
        __root = newRoot
        SG.serverPos = nil
        lp.__props.Character = newChar
        SG.respawns += 1
        lp.CharacterAdded:Fire(newChar)
    end
end

-- runs after every frame: claim at home, train on the treadmill
local runFrames = __runFrames
function __runFrames(n)
    for _ = 1, n do
        runFrames(1)
        SG.physics()
        local pos = SG.serverPos or __root.Position
        local r = SG.carrying
        if r and ((pos - SG.home) * Vector3.new(1, 0, 1)).Magnitude < 15 then
            SG.carrying = nil
            records[r.Uid] = nil
            r.State = "Claimed"
            SG.delivered += 1
            table.insert(SG.log, "DELIVERED " .. r.AssetCategory)
            carryEvent.OnClientEvent:Fire({ IsCarrying = false, SpeedMultiplier = 1 })
            local asset = ASSETS.Directory[r.AssetCategory]
            verdictEvent.OnClientEvent:Fire({ AssetCategory = r.AssetCategory, DisplayName = asset.DisplayName,
                Rarity = asset.Rarity._id, Color = asset.Rarity.Color, Position = pos })
            ownedId += 1
            local tool = newInstance("Tool", r.AssetCategory .. " Egg")
            tool:SetAttribute("ItemType", "AssetEgg")
            tool:SetAttribute("UID", "owned" .. ownedId)
            tool:SetAttribute("Category", r.AssetCategory)
            tool.Parent = SG.backpack
        end
        if ((pos - SG.treadmill) * Vector3.new(1, 0, 1)).Magnitude < 6 then speedStat.Value += 1 end
    end
end
