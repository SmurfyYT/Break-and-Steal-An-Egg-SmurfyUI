-- Fake "Break & Steal an Egg", appended after harness.lua for steal_driver.lua.
-- Rules copied from the real game's client scripts:
--   * eggs: parts tagged BreakableEgg, Health / Broken attributes, hit through
--     ReplicatedStorage.EggHitRequest(egg, id) with the Pickaxe held, from
--     within 8 studs of the surface, at most once per 0.5 s swing (x0.92 slack).
--   * a broken egg drops an animal (Model tagged AnimalPickup) whose StealPrompt
--     sits on a "PromptAnchor" part in workspace.
--   * CarryCount goes up when you take one, up to SatchelCapacity; reaching
--     your plot's Hitbox banks them as AnimalTool tools in the Backpack.
--   * PlaceAnimalRemote(tool, pos, seq): tool held, pos inside the Hitbox,
--     within 50 studs (flat) of you, and room in the pen.
local SG = { hits = 0, fastHits = 0, farHits = 0, unheldHits = 0, broken = 0, taken = 0, banked = 0, placed = 0, refusedPlace = 0, log = {} }
__SG = SG

local Tags = {}
local function tag(inst, name)
    Tags[name] = Tags[name] or {}
    table.insert(Tags[name], inst)
end
Services.CollectionService = {
    GetTagged = function(_, name)
        local out = {}
        for _, inst in ipairs(Tags[name] or {}) do if inst.Parent then table.insert(out, inst) end end
        return out
    end,
    HasTag = function(_, inst, name)
        for _, i in ipairs(Tags[name] or {}) do if i == inst then return true end end
        return false
    end,
}

local function part(name, parent, pos, size)
    local p = newInstance("Part", name)
    p.CFrame = CFrame.new(pos)
    p.Size = size or Vector3.new(4, 4, 4)
    p.Parent = parent
    return p
end

lp:SetAttribute("Cash", 0)
lp:SetAttribute("CarryCount", 0)
lp:SetAttribute("SatchelCapacity", 2)
lp:SetAttribute("PickaxeTier", 1)

-- character tools
local backpack = newInstance("Backpack", "Backpack"); backpack.Parent = lp
local char = lp.Character
local hum = char:FindFirstChildOfClass("Humanoid")
hum.__props.EquipTool = function(_, tool)
    for _, c in ipairs(char:GetChildren()) do if c.ClassName == "Tool" then c.Parent = backpack end end
    tool.Parent = char
end
hum.__props.UnequipTools = function()
    for _, c in ipairs(char:GetChildren()) do if c.ClassName == "Tool" then c.Parent = backpack end end
end
local pickaxe = newInstance("Tool", "Pickaxe"); pickaxe.Parent = backpack

-- your plot: a 60 x 20 x 60 hitbox at the origin (you start in it)
local plots = newInstance("Folder", "Plots"); plots.Parent = workspace
local plot = newInstance("Model", "Base_1"); plot.Parent = plots
plot:SetAttribute("OwnerUserId", 1)
plot:SetAttribute("AnimalsPlaced", 0)
plot:SetAttribute("MaxAnimals", 3)
local hitbox = part("Hitbox", plot, Vector3.new(0, 10, 0), Vector3.new(60, 20, 60))
part("SpawnPoint", plot, Vector3.new(0, 1, 0), Vector3.new(6, 1, 6))
local other = newInstance("Model", "Base_2"); other.Parent = plots
other:SetAttribute("OwnerUserId", 99)

-- zones: zone 1 hitbox far along -X, three eggs in it
local build = newInstance("Folder", "Build"); build.Parent = workspace
local zh = newInstance("Folder", "ZoneHitboxes"); zh.Parent = build
part("1", zh, Vector3.new(-300, 30, 0), Vector3.new(200, 60, 200))
part("SafeZone", zh, Vector3.new(25, 100, 0), Vector3.new(40, 200, 40))
local zb = newInstance("Folder", "ZoneBuilds"); zb.Parent = build
local zone1 = newInstance("Model", "Zone1"); zone1.Parent = zb
local eggsFolder = newInstance("Folder", "Eggs"); eggsFolder.Parent = zone1

local remotes = {}
for _, name in ipairs({ "EggHitRequest", "PlaceAnimalRemote", "PickaxeShopRequest", "TrailShopRequest", "UpgradePlotRequest",
    "UpgradeTreadmillRequest", "UnlockTreadmillRequest", "OfflineRewardRemote", "GroupRewardRemote", "IndexRemote", "PetsInventoryRemote" }) do
    remotes[name] = newInstance("RemoteEvent", name)
    remotes[name].Parent = Services.ReplicatedStorage
end

local pickups = newInstance("Folder", "AnimalPickups"); pickups.Parent = workspace
local animals = { { "Chicken", "Common" }, { "Bear", "Legendary" }, { "Cat", "Common" }, { "Parrot", "Rare" }, { "Badger", "Rare" } }
local nextAnimal = 0

local function dropAnimal(pos)
    nextAnimal = nextAnimal % #animals + 1
    local info = animals[nextAnimal]
    local m = newInstance("Model", info[1])
    m.__pivot = pos + Vector3.new(0, 1, 0)
    m:SetAttribute("AnimalName", info[1])
    m:SetAttribute("Rarity", info[2])
    m.Parent = pickups
    tag(m, "AnimalPickup")
    -- the game moves the prompt onto an anchor part in workspace
    local anchor = part("PromptAnchor", workspace, m.__pivot + Vector3.new(1, 0, 0), Vector3.new(1, 1, 1))
    local prompt = newInstance("ProximityPrompt", "StealPrompt")
    prompt.Enabled = true
    prompt.HoldDuration = 0.5
    prompt.__pickup = m
    prompt.Parent = anchor
    m.__anchor = anchor
    table.insert(SG.log, "dropped " .. info[1])
end

function SG.spawnEgg(name, pos, health)
    local model = newInstance("Model", "1: " .. name)
    model.Parent = eggsFolder
    local egg = part("Egg", model, pos, Vector3.new(4, 5, 4))
    egg:SetAttribute("Health", health)
    egg:SetAttribute("MaxHealth", health)
    tag(egg, "BreakableEgg")
    return egg
end

local lastHit = -10
remotes.EggHitRequest.__server = function(egg, id)
    SG.hits += 1
    if os.clock() - lastHit < 0.5 * 0.92 then SG.fastHits += 1 return end
    lastHit = os.clock()
    if not (char:FindFirstChild("Pickaxe")) then SG.unheldHits += 1 return end
    local rel = __root.Position - egg.Position
    local flat = math.max(Vector3.new(rel.X, 0, rel.Z).Magnitude - 2, 0)
    local vertical = math.max(math.abs(rel.Y) - 2.5, 0)
    if math.sqrt(flat * flat + vertical * vertical) > 8.3 then SG.farHits += 1 return end
    if egg:GetAttribute("Broken") then return end
    local hp = egg:GetAttribute("Health") - 1
    egg:SetAttribute("Health", hp)
    if hp <= 0 then
        egg:SetAttribute("Broken", true)
        SG.broken += 1
        table.insert(SG.log, "broke " .. egg.Parent.Name)
        task.delay(0.3, function()
            egg.Parent.Parent = nil
            dropAnimal(egg.Position + Vector3.new(4, 0, 0))
        end)
    end
end

function fireproximityprompt(prompt)
    local m = prompt.__pickup
    if not m or not m.Parent or not prompt.Enabled then return end
    if (__root.Position - m.__pivot).Magnitude > 12 then table.insert(SG.log, "prompt too far") return end
    local count = lp:GetAttribute("CarryCount")
    if count >= lp:GetAttribute("SatchelCapacity") then table.insert(SG.log, "satchel full") return end
    m.Parent = nil
    m.__anchor.Parent = nil
    lp:SetAttribute("CarryCount", count + 1)
    SG.taken += 1
    SG.carried = SG.carried or {}
    table.insert(SG.carried, m)
    table.insert(SG.log, "took " .. m.Name)
end

remotes.PlaceAnimalRemote.__server = function(tool, pos, seq)
    local rel = pos - hitbox.Position
    local flat = Vector3.new(pos.X - __root.Position.X, 0, pos.Z - __root.Position.Z).Magnitude
    if tool.Parent ~= char or math.abs(rel.X) > 30 or math.abs(rel.Z) > 30 or math.abs(rel.Y) > 12 or flat > 50
        or plot:GetAttribute("AnimalsPlaced") >= plot:GetAttribute("MaxAnimals") then
        SG.refusedPlace += 1
        table.insert(SG.log, "place refused")
        return
    end
    tool.Parent = nil
    plot:SetAttribute("AnimalsPlaced", plot:GetAttribute("AnimalsPlaced") + 1)
    SG.placed += 1
    table.insert(SG.log, "placed " .. tool.Name)
end

-- banking: carried animals turn into tools when you're inside your hitbox
local runFrames = __runFrames
function __runFrames(n)
    for _ = 1, n do
        runFrames(1)
        local rel = __root.Position - hitbox.Position
        if lp:GetAttribute("CarryCount") > 0 and math.abs(rel.X) <= 30 and math.abs(rel.Z) <= 30 and math.abs(rel.Y) <= 12 then
            for _, m in ipairs(SG.carried or {}) do
                local tool = newInstance("Tool", m.Name)
                tool:SetAttribute("AnimalName", m.Name)
                tool:SetAttribute("Rarity", m:GetAttribute("Rarity"))
                tag(tool, "AnimalTool")
                tool.Parent = backpack
                SG.banked += 1
                table.insert(SG.log, "banked " .. m.Name)
            end
            SG.carried = {}
            lp:SetAttribute("CarryCount", 0)
        end
    end
end
