-- Fake Steal An Egg, appended after harness.lua for steal_driver.lua.
-- Built like the real place (see docs/GAME_NOTES.md):
--   * plots with the owner's name on the sign, a SpawnPoint in the safe zone
--   * guarded areas east of the plots (Bounds, ClosestExitPoint, Guard,
--     GuardEscapeSpeeds = Vector2(speed needed, ...))
--   * eggs = models in workspace.AreaEggSlotsClient + a SmartPromptPart with a
--     CarryAreaEgg ("Steal") prompt sitting on each one
-- Rules: the prompt only works within 10 studs; a carried egg counts once you
-- stand in the safe zone (x < 60); the server then fires FieldEggRedeemVerdict.
local SG = { delivered = 0, stolen = {}, log = {}, carrying = nil }
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

-- leaderstats
local stats = folder("leaderstats", lp)
local speedStat = newInstance("NumberValue", "Speed"); speedStat.Value = 5000; speedStat.Parent = stats
local moneyStat = newInstance("NumberValue", "Money/s"); moneyStat.Value = 1234; moneyStat.Parent = stats
SG.speed = speedStat

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
    return m
end
plot("1", "SomeoneElse", 0)
SG.plot = plot("2", "Tester", 60)
SG.home = Vector3.new(20, 5, 60)
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
local re = folder("RE", networking)
local eggWorld = folder("EggWorld", re)
local carryRemote = newInstance("RemoteEvent", "FieldEggCarry"); carryRemote.Parent = eggWorld
local verdictRemote = newInstance("RemoteEvent", "FieldEggRedeemVerdict"); verdictRemote.Parent = eggWorld
local goneRemote = newInstance("RemoteEvent", "FieldEggGone"); goneRemote.Parent = eggWorld

-- eggs
local slots = folder("AreaEggSlotsClient", workspace)
local nextId = 0
function SG.spawnEgg(name, x, z, rare)
    nextId += 1
    local m = folder("egg" .. nextId, slots, "Model")
    m:SetAttribute("PreparedSourceName", "Workspace.NewEggs." .. name)
    m.__pivot = Vector3.new(x, 2, z)
    part("Hitbox", m, Vector3.new(x, 2, z))
    if rare then folder("RareAreaEggHighlight", m, "Highlight") end
    local promptPart = part("SmartPromptPart", workspace, Vector3.new(x, 1, z))
    local prompt = newInstance("ProximityPrompt", "CarryAreaEgg")
    prompt.ActionText = "Steal"; prompt.Enabled = true; prompt.HoldDuration = 0
    prompt.__egg = { model = m, part = promptPart, name = name }
    prompt.Parent = promptPart
    return m, promptPart
end

function fireproximityprompt(prompt)
    local egg = prompt.__egg
    if not egg or not egg.part.Parent or SG.carrying then return end
    local d = (__root.Position - egg.part.Position).Magnitude
    if d > 10 then
        table.insert(SG.log, "too far from " .. egg.name .. " (" .. math.floor(d) .. ")")
        return
    end
    egg.part.Parent = nil
    egg.model.Parent = nil
    SG.carrying = egg.name
    table.insert(SG.stolen, egg.name)
    table.insert(SG.log, "stole " .. egg.name)
    carryRemote.OnClientEvent:Fire(lp, egg.name)
end

-- runs after every frame: deliver in the safe zone
local runFrames = __runFrames
function __runFrames(n)
    for _ = 1, n do
        runFrames(1)
        if SG.carrying and __root.Position.X < 60 then
            SG.delivered += 1
            table.insert(SG.log, "DELIVERED " .. SG.carrying)
            SG.carrying = nil
            verdictRemote.OnClientEvent:Fire(true)
        end
    end
end
