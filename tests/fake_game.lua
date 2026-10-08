-- Fake "Break & Steal an Egg", appended after harness.lua. Rules from the real
-- game's client scripts:
--   * eggs: parts tagged BreakableEgg (Health / Broken / HatchId attributes), hit
--     through ReplicatedStorage.EggHitRequest(egg, id) with the Pickaxe held,
--     from within 8 studs of the surface, at most once per 0.5 s swing (x0.92).
--   * a broken egg drops an animal (Model tagged AnimalPickup, same HatchId)
--     whose StealPrompt sits on a "PromptAnchor" part in workspace.
--   * taking one raises CarryCount (up to SatchelCapacity); being inside your
--     plot's Hitbox banks everything you carry.
-- "Server view": what replicates is the root's CFrame + velocity right after
-- Heartbeat. A flung frame is one where that velocity is huge.
local SG = { hits = 0, fastHits = 0, farHits = 0, unheldHits = 0, broken = 0, taken = 0, banked = 0,
    flungFrames = 0, flungOnPlot = 0, bankedWhileFlung = 0, carriedUnflungOutside = 0, log = {} }
__SG = SG

local Tags = {}
local function tag(inst, name)
    Tags[name] = Tags[name] or {}
    table.insert(Tags[name], inst)
end
Services.CollectionService = newInstance("CollectionService", "CollectionService")
Services.CollectionService.__props.GetTagged = function(_, name)
    local out = {}
    for _, inst in ipairs(Tags[name] or {}) do if inst.Parent then table.insert(out, inst) end end
    return out
end

local function part(name, parent, pos, size)
    local p = newInstance("Part", name)
    p.CFrame = CFrame.new(pos)
    p.Size = size or Vector3.new(4, 4, 4)
    p.Parent = parent
    return p
end

lp:SetAttribute("CarryCount", 0)
lp:SetAttribute("SatchelCapacity", 2)

local backpack = newInstance("Backpack", "Backpack"); backpack.Parent = lp
local hum = char:FindFirstChildOfClass("Humanoid")
hum.__props.EquipTool = function(_, tool)
    for _, c in ipairs(char:GetChildren()) do if c.ClassName == "Tool" then c.Parent = backpack end end
    tool.Parent = char
end
-- MoveTo: walk at 16 studs/s (moved by __runFrames below)
local walkTarget
hum.__props.MoveTo = function(_, pos) walkTarget = pos end
local pickaxe = newInstance("Tool", "Pickaxe"); pickaxe.Parent = backpack

-- the game's Auto Swing button (PlayerScripts.Client.Controllers.AutoSwingController), left ON
local clientFolder = newInstance("Folder", "Client"); clientFolder.Parent = ps
local controllers = newInstance("Folder", "Controllers"); controllers.Parent = clientFolder
local autoSwingModule = newInstance("ModuleScript", "AutoSwingController"); autoSwingModule.Parent = controllers
local autoSwingOn = true
local autoSwingChanged = { Event = Signal() }
SG.autoSwing = {
    IsOn = function() return autoSwingOn end,
    SetOn = function(v) autoSwingOn = v == true; autoSwingChanged.Event:Fire(autoSwingOn) end,
    Changed = autoSwingChanged,
}
function SG.autoSwingOn() return autoSwingOn end
local baseRequire = require
require = function(m)
    if m == autoSwingModule then return SG.autoSwing end
    return baseRequire(m)
end
root.CFrame = CFrame.new(Vector3.new(0, 3, 0))

-- your plot: a 60 x 20 x 60 hitbox around the origin; another player's plot next to it
local plots = newInstance("Folder", "Plots"); plots.Parent = workspace
local plot = newInstance("Model", "Base_1"); plot.Parent = plots
plot:SetAttribute("OwnerUserId", 1)
local hitbox = part("Hitbox", plot, Vector3.new(0, 10, 0), Vector3.new(60, 20, 60))
local other = newInstance("Model", "Base_2"); other.Parent = plots
other:SetAttribute("OwnerUserId", 99)
part("Hitbox", other, Vector3.new(0, 10, 200), Vector3.new(60, 20, 60))
__hitbox = hitbox

local build = newInstance("Folder", "Build"); build.Parent = workspace
local zh = newInstance("Folder", "ZoneHitboxes"); zh.Parent = build
part("1", zh, Vector3.new(-300, 30, 0), Vector3.new(200, 60, 200))
part("2", zh, Vector3.new(-600, 30, 0), Vector3.new(200, 60, 200))
local zb = newInstance("Folder", "ZoneBuilds"); zb.Parent = build
local eggFolders = {}
for i = 1, 2 do
    local zone = newInstance("Model", "Zone" .. i); zone.Parent = zb
    eggFolders[i] = newInstance("Folder", "Eggs"); eggFolders[i].Parent = zone
end

local remotes = {}
for _, name in ipairs({ "EggHitRequest" }) do
    remotes[name] = newInstance("RemoteEvent", name)
    remotes[name].Parent = Services.ReplicatedStorage
end

local pickups = newInstance("Folder", "AnimalPickups"); pickups.Parent = workspace
local nextHatch = 100

local function dropAnimal(pos, hatchId, name, reservedFor, promptDelay)
    local m = newInstance("Model", name)
    m.__pivot = pos + Vector3.new(0, 1, 0)
    m:SetAttribute("HatchId", hatchId)
    m:SetAttribute("Hatched", true)
    if reservedFor then m:SetAttribute("ReservedUserId", reservedFor) end
    m.Parent = pickups
    tag(m, "AnimalPickup")
    local anchor = part("PromptAnchor", workspace, m.__pivot + Vector3.new(1, 0, 0), Vector3.new(1, 1, 1))
    local prompt = newInstance("ProximityPrompt", "StealPrompt")
    prompt.Enabled = promptDelay == nil
    if promptDelay then task.delay(promptDelay, function() prompt.Enabled = true end) end
    prompt.HoldDuration = 0.5
    prompt.__pickup = m
    prompt.Parent = anchor
    m.__anchor = anchor
    table.insert(SG.log, "dropped " .. name .. " (hatch " .. hatchId .. ")")
    return m
end
SG.dropAnimal = dropAnimal

function SG.spawnEgg(zone, name, pos, health)
    local model = newInstance("Model", "1: " .. name)
    model.Parent = eggFolders[zone]
    local egg = part("Egg", model, pos, Vector3.new(4, 5, 4))
    egg:SetAttribute("Health", health)
    egg:SetAttribute("MaxHealth", health)
    nextHatch += 1
    egg:SetAttribute("HatchId", nextHatch)
    tag(egg, "BreakableEgg")
    SG.eggs = SG.eggs or {}
    table.insert(SG.eggs, egg)
    return egg
end

local lastHit = -10
remotes.EggHitRequest.__server = function(egg, id)
    SG.hits += 1
    if os.clock() - lastHit < 0.5 * 0.92 then SG.fastHits += 1 return end
    lastHit = os.clock()
    if not char:FindFirstChild("Pickaxe") then SG.unheldHits += 1 return end
    local rel = root.Position - egg.Position
    local flatDist = math.max(Vector3.new(rel.X, 0, rel.Z).Magnitude - 2, 0)
    local vertical = math.max(math.abs(rel.Y) - 2.5, 0)
    if math.sqrt(flatDist * flatDist + vertical * vertical) > 8.3 then SG.farHits += 1 return end
    if egg:GetAttribute("Broken") then return end
    if SG.lastFlung then SG.flungHits = (SG.flungHits or 0) + 1 end
    if SG.expectWalkOut and not egg.__wentOut then
        SG.noWalkOutHits = (SG.noWalkOutHits or 0) + 1
    end
    if not egg.__arrived or os.clock() - egg.__arrived < 0.95 then
        SG.earlyHits = (SG.earlyHits or 0) + 1
        table.insert(SG.log, ("early hit %.2fs after arriving"):format(egg.__arrived and os.clock() - egg.__arrived or -1))
    end
    local hp = egg:GetAttribute("Health") - 1
    egg:SetAttribute("Health", hp)
    if hp <= 0 then
        -- like the game: Hatching (not Broken), the hatch animation, then the animal
        egg:SetAttribute("Hatching", true)
        SG.broken += 1
        table.insert(SG.log, "broke " .. egg.Parent.Name .. ", hatching")
        local n = SG.broken
        task.delay(SG.hatchTime or 4, function()
            local pos = egg.Position
            egg.Parent.Parent = nil
            dropAnimal(pos + Vector3.new(4, 0, 0), egg:GetAttribute("HatchId"), "Animal" .. n, 1, 0.5)
        end)
    end
end

function fireproximityprompt(prompt)
    local m = prompt.__pickup
    if not m or not m.Parent or not prompt.Enabled then return end
    if (root.Position - m.__pivot).Magnitude > 10 then table.insert(SG.log, "prompt too far") return end
    local count = lp:GetAttribute("CarryCount")
    if count >= lp:GetAttribute("SatchelCapacity") then return end
    m.Parent = nil
    m.__anchor.Parent = nil
    lp:SetAttribute("CarryCount", count + 1)
    SG.taken += 1
    SG.takenNames = SG.takenNames or {}
    table.insert(SG.takenNames, m.Name)
    table.insert(SG.log, "took " .. m.Name)
end

local function inHitbox(pos)
    local rel = pos - hitbox.Position
    return math.abs(rel.X) <= 30 and math.abs(rel.Z) <= 30 and math.abs(rel.Y) <= 12
end

-- server view after Heartbeat: flung or not, where
local hb = rs.__signals.Heartbeat
local fire = hb.Fire
hb.Fire = function(self, ...)
    fire(self, ...)
    local v = root.AssemblyLinearVelocity
    local flung = v ~= nil and v.Magnitude > 1000
    SG.lastFlung = flung
    if flung then
        SG.flungFrames += 1
        if inHitbox(root.Position) then SG.flungOnPlot += 1 end
    end
end

local runFrames = __runFrames
function __runFrames(n)
    for _ = 1, n do
        runFrames(1)
        -- when the character first gets within hit range of each egg
        for _, egg in ipairs(SG.eggs or {}) do
            if egg.Parent and not egg.__arrived then
                local rel = root.Position - egg.Position
                if Vector3.new(rel.X, 0, rel.Z).Magnitude < 8 and math.abs(rel.Y) < 5 then egg.__arrived = os.clock() end
            end
            -- walked (not flung) out of dig reach after arriving
            if egg.Parent and egg.__arrived and not egg.__wentOut and not SG.lastFlung then
                local rel = root.Position - egg.Position
                local h = math.max(Vector3.new(rel.X, 0, rel.Z).Magnitude - 2, 0)
                local v = math.max(math.abs(rel.Y) - 2.5, 0)
                if math.sqrt(h * h + v * v) > 8.3 then egg.__wentOut = os.clock() end
            end
        end
        -- while flinging, the client must look still: no drift between frames except hold moves
        local v = root.AssemblyLinearVelocity
        if SG.lastFlung and v and v.Magnitude > 0 then SG.notStillFrames = (SG.notStillFrames or 0) + 1 end
        if walkTarget then
            local d = Vector3.new(walkTarget.X - root.Position.X, 0, walkTarget.Z - root.Position.Z)
            if d.Magnitude > 0.5 then
                local step = math.min(d.Magnitude, 16 / 60)
                root.CFrame = CFrame.new(root.Position + d.Unit * step)
            else
                walkTarget = nil
            end
        end
        if lp:GetAttribute("CarryCount") > 0 and inHitbox(root.Position) then
            if SG.lastFlung then SG.bankedWhileFlung += 1 end
            SG.banked += lp:GetAttribute("CarryCount")
            table.insert(SG.log, "banked " .. lp:GetAttribute("CarryCount"))
            lp:SetAttribute("CarryCount", 0)
        end
        -- carrying, not flung, outside the plot and not walking home = exposed to the guard
        if lp:GetAttribute("CarryCount") > 0 and not SG.lastFlung and not inHitbox(root.Position) and not walkTarget then
            SG.carriedUnflungOutside += 1
        end
    end
end
__inHitbox = inHitbox
