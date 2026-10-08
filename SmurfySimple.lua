--[[
    Smurfy's Simple UI — Break & Steal an Egg
    Made for Delta (Android / BlueStacks). Paste the whole file into the executor.

    Main tab : restore settings, unload.
    Test tab : "fling TP" + auto farm.

    Fling TP: every frame, right after physics (Heartbeat) the character's velocity
    is set to a huge number, so what gets sent to the server / other players is a
    character being flung out of the universe. Before the next physics step
    (Stepped / RenderStepped) the velocity is zeroed again and the character is
    pinned to a "hold" CFrame, so on your screen you stand perfectly still and can
    keep hitting eggs and pressing prompts. Teleporting = moving that hold point
    (in hops) while the fling is on.

    Auto farm (game rules from the place's client scripts):
      1. pick a live egg (parts tagged "BreakableEgg", in Build.ZoneBuilds.ZoneN.Eggs)
      2. fling TP next to it, hold the Pickaxe, fire EggHitRequest(egg, hitId) once per swing
      3. the broken egg drops an animal in workspace.AnimalPickups (same "HatchId")
      4. fling TP to it and trigger its StealPrompt (CarryCount goes up)
      5. stay flung while going back, stop flinging just OUTSIDE your plot's Hitbox,
         then walk in so the game banks it (it banks inside your Hitbox or the SafeZone)
]]

local ENV = (getgenv and getgenv()) or _G
if ENV.SmurfySimple and ENV.SmurfySimple.Unload then
    pcall(ENV.SmurfySimple.Unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local App = { Alive = true, Conns = {} }
ENV.SmurfySimple = App

local function track(conn)
    table.insert(App.Conns, conn)
    return conn
end

---------------------------------------------------------------- settings
local CONFIG_FILE = "SmurfySimple_BreakStealEgg.json"
local Defaults = {
    Zone = 0,            -- 0 = any zone, else 1-9
    FlingLevel = 4,      -- index into FlingPowers (Max)
    BankEachGrab = true, -- go home after every animal (off = fill the satchel first)
    WalkInToBank = true, -- after landing outside the plot, walk in to bank
    WalkOutFirst = true, -- at the egg: stop flinging, walk out of dig reach and back, then mine
    WindowX = 80,
    WindowY = 80,
}
local FlingPowers = { { "High", 5e3 }, { "Very high", 5e4 }, { "Out of the universe", 5e5 }, { "Max", 1e6 } }
local Settings = table.clone(Defaults)

local function saveSettings()
    if type(writefile) ~= "function" then return end
    pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Settings)) end)
end

local function loadSettings()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    pcall(function()
        if not isfile(CONFIG_FILE) then return end
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        for k, v in pairs(data) do
            if Defaults[k] ~= nil and type(v) == type(Defaults[k]) then Settings[k] = v end
        end
    end)
end
loadSettings()

---------------------------------------------------------------- character helpers
local function getChar() return LocalPlayer.Character end
local function getRoot()
    local c = getChar()
    local r = c and c:FindFirstChild("HumanoidRootPart")
    return r and r:IsA("BasePart") and r or nil
end
local function getHumanoid()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
local function alive()
    local h = getHumanoid()
    return h ~= nil and h.Health > 0 and getRoot() ~= nil
end

local function attr(inst, name)
    local ok, v = pcall(inst.GetAttribute, inst, name)
    return ok and v or nil
end
local function num(inst, name, default)
    local v = attr(inst, name)
    return type(v) == "number" and v or default
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- the game's own "inside a part" test (2 studs of slack up/down)
local function inPart(part, pos)
    local rel = part.CFrame:PointToObjectSpace(pos)
    local half = part.Size * 0.5
    return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 2 and math.abs(rel.Z) <= half.Z
end

local function groundBelow(pos)
    local ok, hit = pcall(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { getChar() }
        return workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), params)
    end)
    return ok and hit and hit.Position or nil
end

---------------------------------------------------------------- fling engine
local Fling = { On = false, Hold = nil, Conns = {} }

local function zeroMotion(root)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

-- pin the character to the hold point and kill its motion (runs before physics and before render)
local function pin()
    local root = getRoot()
    if not root then return end
    zeroMotion(root)
    if Fling.Hold then root.CFrame = Fling.Hold end
end

function Fling.Start(hold)
    local root = getRoot()
    Fling.Hold = hold or (root and root.CFrame) or Fling.Hold
    if Fling.On then return end
    Fling.On = true
    Fling.Since = os.clock()
    -- after physics: this is what replicates -> flung out of the universe
    table.insert(Fling.Conns, RunService.Heartbeat:Connect(function()
        local r = getRoot()
        if not r then return end
        local power = (FlingPowers[Settings.FlingLevel] or FlingPowers[#FlingPowers])[2]
        r.AssemblyLinearVelocity = Vector3.new(power, power, power)
        r.AssemblyAngularVelocity = Vector3.new(0, power, 0)
    end))
    -- before physics and before drawing: stand still on the hold point
    table.insert(Fling.Conns, RunService.Stepped:Connect(pin))
    table.insert(Fling.Conns, RunService.RenderStepped:Connect(pin))
end

function Fling.Stop()
    for _, c in ipairs(Fling.Conns) do c:Disconnect() end
    table.clear(Fling.Conns)
    local wasOn = Fling.On
    Fling.On = false
    Fling.Hold = nil
    local root = getRoot()
    if root and wasOn then zeroMotion(root) end
end

-- the "teleport": keep flinging and move the hold point there in hops
local WARMUP = 0.15 -- seconds flung in place before the jump, so the jump itself is never seen
local SETTLE = 0.1  -- seconds flung on arrival before doing anything there

local leavePlot -- defined with the plot helpers: steps out of your plot (no fling) if you're on it

function Fling.TP(target)
    local root = getRoot()
    if not root then return false end
    if not Fling.On then
        -- never fling while on the plot: step outside it first
        if leavePlot then leavePlot() end
        root = getRoot()
        if not root then return false end
        Fling.Start(root.CFrame)
    end
    -- already flung for a moment, then the whole trip in ONE frame (looks like a teleport).
    -- Only the hold point moves: the Stepped / RenderStepped pin applies it before physics,
    -- so the flung velocity set after physics is never touched here
    local t = os.clock()
    while Fling.On and App.Alive and os.clock() - (Fling.Since or t) < WARMUP do
        RunService.Stepped:Wait()
    end
    if not App.Alive or not Fling.On then return false end
    Fling.Hold = target
    RunService.Stepped:Wait()
    t = os.clock()
    while Fling.On and App.Alive and os.clock() - t < SETTLE do
        RunService.Stepped:Wait()
    end
    return Fling.On
end

---------------------------------------------------------------- game: places
local function myPlot()
    local plots = workspace:FindFirstChild("Plots")
    for _, plot in ipairs(plots and plots:GetChildren() or {}) do
        if attr(plot, "OwnerUserId") == LocalPlayer.UserId then return plot end
    end
    return nil
end

local function plotHitbox()
    local plot = myPlot()
    local hb = plot and plot:FindFirstChild("Hitbox")
    return hb and hb:IsA("BasePart") and hb or nil
end

local function zoneHitbox(n)
    local build = workspace:FindFirstChild("Build")
    local folder = build and build:FindFirstChild("ZoneHitboxes")
    local part = folder and folder:FindFirstChild(tostring(n))
    return part and part:IsA("BasePart") and part or nil
end

-- a spot just OUTSIDE your plot's Hitbox, on the side facing the zones
local function outsidePlotCFrame()
    local hb = plotHitbox()
    if not hb then return nil end
    local towards = zoneHitbox(math.max(Settings.Zone, 1)) or zoneHitbox(1)
    local dir = towards and flat(towards.Position - hb.Position) or Vector3.zero
    if dir.Magnitude < 1 then
        local root = getRoot()
        dir = root and flat(root.Position - hb.Position) or Vector3.new(1, 0, 0)
        if dir.Magnitude < 1 then dir = Vector3.new(1, 0, 0) end
    end
    dir = dir.Unit
    -- how far from the center to the hitbox edge along dir (in the hitbox's own axes)
    local localDir = hb.CFrame:VectorToObjectSpace(dir)
    local half = hb.Size * 0.5
    local tx = math.abs(localDir.X) > 1e-3 and half.X / math.abs(localDir.X) or math.huge
    local tz = math.abs(localDir.Z) > 1e-3 and half.Z / math.abs(localDir.Z) or math.huge
    local edge = math.min(tx, tz)
    local bottom = hb.Position.Y - half.Y
    for _, extra in ipairs({ 8, 14, 22, 32 }) do
        local p = hb.Position + dir * (edge + extra)
        local ground = groundBelow(Vector3.new(p.X, hb.Position.Y + half.Y, p.Z))
        local spot = Vector3.new(p.X, (ground and ground.Y or bottom) + 3, p.Z)
        if not inPart(hb, spot) then
            return CFrame.lookAt(spot, Vector3.new(hb.Position.X, spot.Y, hb.Position.Z)), hb
        end
    end
    return nil
end

leavePlot = function()
    local hb, root = plotHitbox(), getRoot()
    if not hb or not root or not inPart(hb, root.Position) then return end
    local spot = outsidePlotCFrame()
    if not spot then return end
    -- walk off the plot (a step would look like a teleport); snap only if stuck
    local hum = getHumanoid()
    local t = os.clock()
    while App.Alive and os.clock() - t < 6 do
        local r = getRoot()
        if not r or not inPart(hb, r.Position) then break end
        if hum then pcall(hum.MoveTo, hum, spot.Position) end
        task.wait(0.1)
    end
    root = getRoot()
    if root and inPart(hb, root.Position) then
        zeroMotion(root)
        root.CFrame = spot
        RunService.Stepped:Wait()
    end
end

local function plotWalkTarget(hb)
    local ground = groundBelow(hb.Position)
    return Vector3.new(hb.Position.X, ground and ground.Y or (hb.Position.Y - hb.Size.Y / 2), hb.Position.Z)
end

---------------------------------------------------------------- game: eggs
local function isLive(egg)
    return egg and egg.Parent ~= nil and not attr(egg, "Broken") and not attr(egg, "Hatching") and not attr(egg, "Despawning")
end

local function eggZone(egg)
    local node = egg
    while node and node ~= workspace do
        local n = node.Name:match("^Zone(%d+)$")
        if n then return tonumber(n) end
        node = node.Parent
    end
    return nil
end

local function allEggs()
    local list, seen = {}, {}
    local ok, tagged = pcall(CollectionService.GetTagged, CollectionService, "BreakableEgg")
    for _, egg in ipairs(ok and tagged or {}) do
        if egg:IsA("BasePart") and not seen[egg] then seen[egg] = true; table.insert(list, egg) end
    end
    local build = workspace:FindFirstChild("Build")
    local zones = build and build:FindFirstChild("ZoneBuilds")
    for _, zone in ipairs(zones and zones:GetChildren() or {}) do
        local eggs = zone:FindFirstChild("Eggs")
        for _, d in ipairs(eggs and eggs:GetDescendants() or {}) do
            if d.Name == "Egg" and d:IsA("BasePart") and not seen[d] then seen[d] = true; table.insert(list, d) end
        end
    end
    return list
end

local Skip = setmetatable({}, { __mode = "k" }) -- eggs we gave up on

local function pickEgg()
    local root = getRoot()
    if not root then return nil end
    local best, bestDist = nil, math.huge
    for _, egg in ipairs(allEggs()) do
        if isLive(egg) and not Skip[egg] and (Settings.Zone == 0 or eggZone(egg) == Settings.Zone) then
            local d = (egg.Position - root.Position).Magnitude
            if d < bestDist then best, bestDist = egg, d end
        end
    end
    return best
end

-- where to stand to hit an egg: next to it, feet on its bottom (hit range is 8 from the surface)
local function besideEgg(egg)
    local root = getRoot()
    local dir = root and flat(root.Position - egg.Position) or Vector3.zero
    if dir.Magnitude < 0.5 then dir = Vector3.new(1, 0, 0) end
    dir = dir.Unit
    local reach = math.max(egg.Size.X, egg.Size.Z) / 2 + 3
    local pos = egg.Position + dir * reach
    pos = Vector3.new(pos.X, egg.Position.Y - egg.Size.Y / 2 + 3, pos.Z)
    return CFrame.lookAt(pos, Vector3.new(egg.Position.X, pos.Y, egg.Position.Z))
end

---------------------------------------------------------------- game: pickaxe + hits
local function pickaxe()
    local char, backpack = getChar(), LocalPlayer:FindFirstChild("Backpack")
    local tool = char and char:FindFirstChild("Pickaxe")
    if tool and tool:IsA("Tool") then return tool, true end
    tool = backpack and backpack:FindFirstChild("Pickaxe")
    if tool and tool:IsA("Tool") then return tool, false end
    return nil, false
end

local function equipPickaxe()
    local tool, held = pickaxe()
    if held then return true end
    local hum = getHumanoid()
    if tool and hum then pcall(hum.EquipTool, hum, tool) end
    return select(2, pickaxe())
end

local Mods = {}
pcall(function()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local m = shared and shared:FindFirstChild("RobuxShopConfig")
    if m then Mods.Shop = require(m) end
end)
pcall(function()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local client = ps and ps:FindFirstChild("Client")
    local controllers = client and client:FindFirstChild("Controllers")
    local m = controllers and controllers:FindFirstChild("EggLocalHits")
    if m then Mods.LocalHits = require(m) end
end)
pcall(function()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local client = ps and ps:FindFirstChild("Client")
    local controllers = client and client:FindFirstChild("Controllers")
    local m = controllers and controllers:FindFirstChild("AutoSwingController")
    if m then Mods.AutoSwing = require(m) end
end)

-- the game's own Auto Swing button must stay off (the farm does its own hits)
local function keepAutoSwingOff()
    local auto = Mods.AutoSwing
    if not auto or type(auto.SetOn) ~= "function" then return end
    local ok, on = pcall(function() return auto.IsOn() end)
    if ok and on == true then pcall(auto.SetOn, false) end
end
keepAutoSwingOff()
if Mods.AutoSwing and Mods.AutoSwing.Changed then
    pcall(function()
        track(Mods.AutoSwing.Changed.Event:Connect(function(on)
            if on and App.Alive then task.defer(keepAutoSwingOff) end
        end))
    end)
end

local function swingCooldown()
    local mult = 1
    if Mods.Shop and Mods.Shop.SwingMultiplierFor then
        local ok, v = pcall(Mods.Shop.SwingMultiplierFor, LocalPlayer)
        if ok and type(v) == "number" and v > 0 then mult = v end
    end
    return 0.5 / mult + 0.04
end

local hitCounter = 0
local function hitEgg(egg)
    local remote = ReplicatedStorage:FindFirstChild("EggHitRequest")
    if not remote then return false end
    local id
    if Mods.LocalHits and Mods.LocalHits.Announce then
        local ok, v = pcall(Mods.LocalHits.Announce, egg, 1)
        if ok and type(v) == "number" then id = v end
    end
    if not id then hitCounter += 1; id = hitCounter end
    return pcall(remote.FireServer, remote, egg, id)
end

---------------------------------------------------------------- game: animals + prompts
local function carrying() return num(LocalPlayer, "CarryCount", 0) end
local function capacity() return math.max(num(LocalPlayer, "SatchelCapacity", 1), 1) end

local function reservedForOther(inst)
    local id = attr(inst, "ReservedUserId")
    return type(id) == "number" and id ~= LocalPlayer.UserId
end

local function pickups()
    local list, seen = {}, {}
    local ok, tagged = pcall(CollectionService.GetTagged, CollectionService, "AnimalPickup")
    for _, m in ipairs(ok and tagged or {}) do
        if m:IsA("Model") and not seen[m] then seen[m] = true; table.insert(list, m) end
    end
    local folder = workspace:FindFirstChild("AnimalPickups")
    for _, m in ipairs(folder and folder:GetChildren() or {}) do
        if m:IsA("Model") and not seen[m] then seen[m] = true; table.insert(list, m) end
    end
    return list
end

local function pivotOf(model)
    local ok, cf = pcall(model.GetPivot, model)
    return ok and cf.Position or nil
end

-- the animal that came out of this egg. The game spawns it after the hatch animation as an
-- AnimalPickup with the egg's HatchId, reserved (ReservedUserId) for whoever broke the egg
local function pickupFor(hatchId, eggPos)
    local reserved, reservedDist = nil, 60
    local near, nearDist = nil, 30
    for _, m in ipairs(pickups()) do
        if m.Parent and not attr(m, "Despawning") and not reservedForOther(m) then
            if hatchId ~= nil and attr(m, "HatchId") == hatchId then return m end
            local pos = pivotOf(m)
            if pos then
                local d = flat(pos - eggPos).Magnitude
                if attr(m, "ReservedUserId") == LocalPlayer.UserId and d < reservedDist then
                    reserved, reservedDist = m, d
                elseif hatchId == nil and attr(m, "Hatched") ~= false and d < nearDist then
                    near, nearDist = m, d
                end
            end
        end
    end
    return reserved or near
end

-- the StealPrompt: inside the animal, or on the "PromptAnchor" part the game moved it to.
-- Takes the prompt nearest the animal even if it's still disabled (then returns nil to wait),
-- so a neighbour's enabled prompt is never picked by mistake
local function promptFor(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return (d.Enabled and not reservedForOther(d)) and d or nil
        end
    end
    local pos = pivotOf(model)
    if not pos then return nil end
    local best, bestDist = nil, 20
    for _, anchor in ipairs(workspace:GetChildren()) do
        if anchor.Name == "PromptAnchor" and anchor:IsA("BasePart") then
            local prompt = anchor:FindFirstChild("StealPrompt")
            if prompt and prompt:IsA("ProximityPrompt") then
                local d = (anchor.Position - pos).Magnitude
                if d < bestDist then best, bestDist = prompt, d end
            end
        end
    end
    if best and best.Enabled and not reservedForOther(best) then return best end
    return nil
end

local function firePrompt(prompt)
    if type(fireproximityprompt) == "function" then
        if pcall(fireproximityprompt, prompt) then return true end
    end
    return pcall(function()
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0) + 0.1)
        prompt:InputHoldEnd()
    end)
end

---------------------------------------------------------------- auto farm
local Farm = { On = false, Token = 0, Stats = { Broken = 0, Grabbed = 0, Banked = 0 } }
local setStatus -- set by the UI

local function status(text)
    if setStatus then setStatus(text) end
end

local function running(token) return App.Alive and Farm.On and Farm.Token == token end

local SWING_DELAY = 1     -- seconds to wait next to an egg (still flung) before anything else
local HIT_RANGE = 8        -- the game's EggConfig.HitRange (from the egg's surface)
local HATCH_TIMEOUT = 20   -- the hatch animation plays before the animal spawns

-- distance from a point to the egg's surface, like the game's EggTargeting.SurfaceDistance
local function surfaceDistance(egg, pos)
    local size = egg.Size
    local d = pos - egg.Position
    local h = math.max(flat(d).Magnitude - math.max(size.X, size.Z) / 2, 0)
    local v = math.max(math.abs(d.Y) - size.Y / 2, 0)
    return math.sqrt(h * h + v * v)
end

local function rootDistance(egg)
    local root = getRoot()
    return root and surfaceDistance(egg, root.Position) or math.huge
end

-- walk (no fling) towards pos until done() or timeout
local function walkTo(pos, token, timeout, done)
    local t = os.clock()
    while running(token) and alive() and os.clock() - t < timeout do
        if done() then return true end
        local hum = getHumanoid()
        if hum then pcall(hum.MoveTo, hum, pos) end
        task.wait(0.1)
    end
    return done()
end

local function eggBroke(egg)
    return egg.Parent == nil or attr(egg, "Broken") == true or attr(egg, "Hatching") == true
        or num(egg, "Health", 1) <= 0
end

-- stop flinging, walk out of dig reach, walk back next to the egg
local function walkOutAndBack(egg, token)
    Fling.Stop()
    local root = getRoot()
    if not root then return false end
    local dir = flat(root.Position - egg.Position)
    dir = dir.Magnitude > 0.5 and dir.Unit or Vector3.new(1, 0, 0)
    local reach = math.max(egg.Size.X, egg.Size.Z) / 2
    local out = egg.Position + dir * (reach + HIT_RANGE + 6)
    out = Vector3.new(out.X, root.Position.Y, out.Z)
    status("Walking out of dig reach")
    walkTo(out, token, 4, function() return rootDistance(egg) > HIT_RANGE + 2 end)
    if not running(token) or not isLive(egg) then return false end
    status("Walking back to the egg")
    local back = besideEgg(egg)
    if not walkTo(back.Position, token, 4, function() return rootDistance(egg) <= HIT_RANGE - 3 end) then
        -- stuck: small step back next to it
        local r = getRoot()
        if r then r.CFrame = back end
    end
    return running(token) and isLive(egg)
end

-- break one egg. true when it broke (the game marks it Hatching / Broken)
local function breakEgg(egg, token)
    status("Going to " .. (egg.Parent and egg.Parent.Name or "egg"))
    if not Fling.TP(besideEgg(egg)) then return false end
    keepAutoSwingOff()
    equipPickaxe()
    -- arrived: hold still (flung) for a second before anything else
    local arrived = os.clock()
    while running(token) and isLive(egg) and os.clock() - arrived < SWING_DELAY do
        Fling.Hold = besideEgg(egg)
        task.wait(0.1)
    end
    if Settings.WalkOutFirst then
        if not walkOutAndBack(egg, token) then return eggBroke(egg) end
    end
    status("Mining " .. (egg.Parent and egg.Parent.Name or "egg"))
    local lastHp, lastChange = num(egg, "Health", 0), os.clock()
    local cooldown = swingCooldown()
    while running(token) and isLive(egg) and alive() do
        if Fling.On then
            Fling.Hold = besideEgg(egg)
        elseif rootDistance(egg) > HIT_RANGE - 2 then
            -- got pushed away: walk back into reach
            walkTo(besideEgg(egg).Position, token, 3, function() return rootDistance(egg) <= HIT_RANGE - 3 end)
        end
        keepAutoSwingOff()
        if not equipPickaxe() then
            status("No Pickaxe in your backpack")
            task.wait(1)
            return false
        end
        hitEgg(egg)
        task.wait(cooldown)
        local hp = num(egg, "Health", lastHp)
        if hp < lastHp then lastHp, lastChange = hp, os.clock() end
        if os.clock() - lastChange > 6 and not eggBroke(egg) then
            status("Egg isn't taking damage, skipping it")
            Skip[egg] = true
            return false
        end
    end
    return eggBroke(egg)
end

-- wait for the hatch animation, then grab the animal. true when CarryCount went up
local function grabAnimal(hatchId, eggPos, token)
    status("Egg hatching, waiting for the animal")
    local before = carrying()
    local t = os.clock()
    while running(token) and alive() and os.clock() - t < HATCH_TIMEOUT do
        local animal = pickupFor(hatchId, eggPos)
        local prompt = animal and promptFor(animal)
        if animal and prompt then
            status("Grabbing " .. animal.Name)
            local pos = pivotOf(animal)
            if pos then
                local root = getRoot()
                local dir = root and flat(root.Position - pos) or Vector3.zero
                dir = dir.Magnitude > 0.5 and dir.Unit or Vector3.new(1, 0, 0)
                local stand = pos + dir * 3
                Fling.TP(CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z)))
                firePrompt(prompt)
                local w = os.clock()
                while os.clock() - w < 0.8 and carrying() <= before and animal.Parent do task.wait(0.1) end
                if carrying() > before then return true end
            end
        end
        task.wait(0.15)
    end
    if carrying() <= before then status("Animal never showed up") end
    return carrying() > before
end

-- stay flung all the way back, land just OUTSIDE the plot, stop flinging, walk in to bank
local function goHome(token)
    local spot, hb = outsidePlotCFrame()
    if not spot then
        status("Can't find your plot")
        task.wait(1)
        return false
    end
    status("Flinging home (outside the plot)")
    Fling.TP(spot)
    task.wait(0.25)
    local hum = getHumanoid()
    -- start walking in on the same frame the fling ends
    local walk = Settings.WalkInToBank and carrying() > 0
    if walk and hum then pcall(hum.MoveTo, hum, plotWalkTarget(hb)) end
    Fling.Stop()
    if carrying() == 0 then return true end
    if not walk then
        status("Outside your plot. Walk in to bank")
        return false
    end
    status("Walking in to bank")
    local carried = carrying()
    local t = os.clock()
    while running(token) and carrying() > 0 and os.clock() - t < 8 do
        if hum then pcall(hum.MoveTo, hum, plotWalkTarget(hb)) end
        task.wait(0.25)
    end
    -- banked: stop walking (stay near the edge of the plot)
    local r = getRoot()
    if hum and r then pcall(hum.MoveTo, hum, r.Position) end
    local banked = carried - carrying()
    if banked > 0 then Farm.Stats.Banked += banked end
    return carrying() == 0
end

local function farmStep(token)
    if not alive() then
        Fling.Stop()
        status("Waiting for your character")
        task.wait(1)
        return
    end
    if carrying() >= capacity() then
        goHome(token)
        return
    end
    local egg = pickEgg()
    if not egg then
        if carrying() > 0 then goHome(token) return end
        status(Settings.Zone == 0 and "No eggs right now" or ("No eggs in zone " .. Settings.Zone))
        task.wait(1)
        return
    end
    local hatchId, eggPos = attr(egg, "HatchId"), egg.Position
    if not breakEgg(egg, token) then return end
    Farm.Stats.Broken += 1
    hatchId = hatchId or attr(egg, "HatchId")
    if not running(token) then return end
    if grabAnimal(hatchId, eggPos, token) then
        Farm.Stats.Grabbed += 1
        if Settings.BankEachGrab or carrying() >= capacity() then goHome(token) end
    end
end

function Farm.Start()
    if Farm.On then return end
    keepAutoSwingOff()
    Farm.On = true
    Farm.Token += 1
    local token = Farm.Token
    task.spawn(function()
        while running(token) do
            local ok, err = pcall(farmStep, token)
            if not ok then
                status("Error: " .. tostring(err):sub(1, 80))
                task.wait(1)
            end
            task.wait(0.1)
        end
    end)
end

function Farm.Stop()
    Farm.On = false
    Farm.Token += 1
    Fling.Stop()
    status("Idle")
end

---------------------------------------------------------------- UI
local Theme = {
    Bg = Color3.fromRGB(24, 24, 30),
    Top = Color3.fromRGB(34, 34, 44),
    Item = Color3.fromRGB(40, 40, 52),
    On = Color3.fromRGB(70, 170, 110),
    Off = Color3.fromRGB(85, 85, 100),
    Accent = Color3.fromRGB(110, 140, 255),
    Danger = Color3.fromRGB(200, 70, 70),
    Text = Color3.fromRGB(235, 235, 245),
    Dim = Color3.fromRGB(160, 160, 175),
}

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    return inst
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end

local gui = new("ScreenGui", {
    Name = "SmurfySimple",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})
local parented = false
if type(gethui) == "function" then parented = pcall(function() gui.Parent = gethui() end) end
if not parented then parented = pcall(function() gui.Parent = game:GetService("CoreGui") end) end
if not parented then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- smaller on phones / small BlueStacks windows
local cam = workspace.CurrentCamera
local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
new("UIScale", { Scale = math.min(viewport.X, viewport.Y) < 500 and 0.85 or 1, Parent = gui })

local WIDTH, HEIGHT = 290, 340
local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(WIDTH, HEIGHT),
    Position = UDim2.fromOffset(Settings.WindowX, Settings.WindowY),
    BackgroundColor3 = Theme.Bg,
    BorderSizePixel = 0,
    Active = true,
    Parent = gui,
}, { corner(10) })

local top = new("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = Theme.Top,
    BorderSizePixel = 0,
    Active = true,
    Parent = main,
}, { corner(10) })
new("TextLabel", {
    Text = "Smurfy's UI · Steal an Egg",
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 0),
    Size = UDim2.new(1, -90, 1, 0),
    Parent = top,
})

local function topButton(text, x, color)
    return new("TextButton", {
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = Theme.Text,
        BackgroundColor3 = color,
        AutoButtonColor = true,
        Size = UDim2.fromOffset(32, 28),
        Position = UDim2.new(1, x, 0, 5),
        Parent = top,
    }, { corner(6) })
end
local minimizeButton = topButton("–", -76, Theme.Off)
local closeButton = topButton("X", -40, Theme.Danger)

-- small button shown while minimized (also draggable)
local openButton = new("TextButton", {
    Text = "S",
    Font = Enum.Font.GothamBlack,
    TextSize = 22,
    TextColor3 = Theme.Text,
    BackgroundColor3 = Theme.Accent,
    Size = UDim2.fromOffset(48, 48),
    Position = UDim2.fromOffset(Settings.WindowX, Settings.WindowY),
    Visible = false,
    Parent = gui,
}, { corner(24) })

-- tabs
local tabBar = new("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 44),
    Size = UDim2.new(1, -20, 0, 30),
    Parent = main,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })

local pages, tabButtons = {}, {}
local function showPage(name)
    for n, page in pairs(pages) do page.Visible = n == name end
    for n, b in pairs(tabButtons) do b.BackgroundColor3 = n == name and Theme.Accent or Theme.Item end
end

local function makePage(name)
    local page = new("ScrollingFrame", {
        Name = name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 80),
        Size = UDim2.new(1, -20, 1, -90),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        Visible = false,
        Parent = main,
    }, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
    pages[name] = page
    local b = new("TextButton", {
        Text = name,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.Text,
        BackgroundColor3 = Theme.Item,
        Size = UDim2.fromOffset(80, 30),
        Parent = tabBar,
    }, { corner(6) })
    tabButtons[name] = b
    b.MouseButton1Click:Connect(function() showPage(name) end)
    return page
end

local order = 0
local function nextOrder() order += 1; return order end

local function label(page, text)
    return new("TextLabel", {
        Text = text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.Dim,
        TextWrapped = true,
        RichText = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = nextOrder(),
        Parent = page,
    })
end

local function button(page, text, color, onClick)
    local b = new("TextButton", {
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.Text,
        BackgroundColor3 = color or Theme.Item,
        Size = UDim2.new(1, 0, 0, 40), -- big enough for fingers
        LayoutOrder = nextOrder(),
        Parent = page,
    }, { corner(8) })
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(onClick, b)
        if not ok then status("Error: " .. tostring(err):sub(1, 80)) end
    end)
    return b
end

local refreshers = {}
local function refreshAll() for _, f in ipairs(refreshers) do pcall(f) end end

-- a button that shows on/off; get() reads the state, set(v) changes it
local function toggle(page, text, get, set)
    local b
    local function refresh()
        local on = get()
        b.Text = text .. (on and "  [ON]" or "  [OFF]")
        b.BackgroundColor3 = on and Theme.On or Theme.Item
    end
    b = button(page, text, nil, function()
        set(not get())
        refresh()
    end)
    table.insert(refreshers, refresh)
    refresh()
    return b
end

-- a button that steps through choices
local function cycle(page, getText, onClick)
    local b
    b = button(page, "", nil, function()
        onClick()
        b.Text = getText()
    end)
    b.Text = getText()
    table.insert(refreshers, function() b.Text = getText() end)
    return b
end

---------------------------------------------------------------- dragging (mouse + touch)
local function makeDraggable(handle, target, onMoved)
    local dragging, dragInput, startPos, startInput = false, nil, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            startInput = input.Position
            startPos = target.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    conn:Disconnect()
                    if onMoved then onMoved() end
                end
            end)
        end
    end))
    track(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and startInput then
            local delta = input.Position - startInput
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

local function rememberPosition(frame)
    Settings.WindowX = frame.Position.X.Offset
    Settings.WindowY = frame.Position.Y.Offset
    saveSettings()
end
makeDraggable(top, main, function() rememberPosition(main) end)
makeDraggable(openButton, openButton, function() rememberPosition(openButton) end)

local openDragStart
track(openButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        openDragStart = openButton.Position
    end
end))
openButton.MouseButton1Click:Connect(function()
    -- a drag isn't a click
    if openDragStart and (openDragStart.X.Offset ~= openButton.Position.X.Offset or openDragStart.Y.Offset ~= openButton.Position.Y.Offset) then return end
    main.Position = openButton.Position
    openButton.Visible = false
    main.Visible = true
end)
minimizeButton.MouseButton1Click:Connect(function()
    openButton.Position = main.Position
    main.Visible = false
    openButton.Visible = true
end)

---------------------------------------------------------------- pages
local mainPage = makePage("Main")
local testPage = makePage("Test")

label(mainPage, "Drag the top bar to move. <b>–</b> hides the window (tap <b>S</b> to bring it back).")
local unload -- defined below

button(mainPage, "Restore settings", Theme.Item, function()
    Farm.Stop()
    Fling.Stop()
    Settings = table.clone(Defaults)
    table.clear(Skip)
    pcall(function() if type(delfile) == "function" and isfile(CONFIG_FILE) then delfile(CONFIG_FILE) end end)
    saveSettings()
    local hum = getHumanoid()
    if hum then pcall(hum.ChangeState, hum, Enum.HumanoidStateType.GettingUp) end
    main.Position = UDim2.fromOffset(Defaults.WindowX, Defaults.WindowY)
    refreshAll()
    status("Settings restored")
end)
button(mainPage, "Unload", Theme.Danger, function() unload() end)

-- Test page
local statusLabel = label(testPage, "Idle")
setStatus = function(text)
    local s = Farm.Stats
    statusLabel.Text = ("<b>%s</b>\nBroken %d · Grabbed %d · Banked %d · Carrying %d/%d"):format(
        text, s.Broken, s.Grabbed, s.Banked, carrying(), capacity())
end
setStatus("Idle")

toggle(testPage, "Auto farm (fling)", function() return Farm.On end, function(v)
    if v then Farm.Start() else Farm.Stop() end
end)

cycle(testPage, function()
    return "Zone: " .. (Settings.Zone == 0 and "Any (nearest)" or tostring(Settings.Zone))
end, function()
    Settings.Zone = (Settings.Zone + 1) % 10
    table.clear(Skip)
    saveSettings()
end)

cycle(testPage, function()
    return "Fling power: " .. (FlingPowers[Settings.FlingLevel] or FlingPowers[#FlingPowers])[1]
end, function()
    Settings.FlingLevel = Settings.FlingLevel % #FlingPowers + 1
    saveSettings()
end)

toggle(testPage, "Bank after every grab", function() return Settings.BankEachGrab end, function(v)
    Settings.BankEachGrab = v
    saveSettings()
end)

toggle(testPage, "Walk out & back before mining", function() return Settings.WalkOutFirst end, function(v)
    Settings.WalkOutFirst = v
    saveSettings()
end)

toggle(testPage, "Walk in to bank", function() return Settings.WalkInToBank end, function(v)
    Settings.WalkInToBank = v
    saveSettings()
end)

label(testPage, "<b>Manual tests</b>")

toggle(testPage, "Fling in place (stand still)", function() return Fling.On end, function(v)
    if v then
        leavePlot() -- not on the plot
        Fling.Start()
    else
        Fling.Stop()
    end
    status(v and "Flinging in place" or "Idle")
end)

button(testPage, "Fling TP → nearest egg", nil, function()
    local egg = pickEgg()
    if not egg then return status("No egg found") end
    task.spawn(function()
        Fling.TP(besideEgg(egg))
        status("Holding next to the egg (still flinging)")
        refreshAll()
    end)
end)

button(testPage, "Fling TP → outside my plot", nil, function()
    local spot = outsidePlotCFrame()
    if not spot then return status("Can't find your plot") end
    task.spawn(function()
        Fling.TP(spot)
        task.wait(0.25)
        Fling.Stop()
        status("Outside your plot")
        refreshAll()
    end)
end)

button(testPage, "Stop everything", Theme.Danger, function()
    Farm.Stop()
    refreshAll()
end)

showPage("Test")

-- keep the status line fresh
task.spawn(function()
    while App.Alive do
        if statusLabel.Parent then
            local first = statusLabel.Text:match("^<b>(.-)</b>") or "Idle"
            setStatus(first)
        end
        task.wait(0.5)
    end
end)

track(LocalPlayer.CharacterAdded:Connect(function()
    if Fling.On then Fling.Stop() end
    refreshAll()
end))

---------------------------------------------------------------- unload
unload = function()
    if not App.Alive then return end
    App.Alive = false
    Farm.Stop()
    Fling.Stop()
    for _, c in ipairs(App.Conns) do pcall(function() c:Disconnect() end) end
    table.clear(App.Conns)
    pcall(function() gui:Destroy() end)
    if ENV.SmurfySimple == App then ENV.SmurfySimple = nil end
end
App.Unload = unload
closeButton.MouseButton1Click:Connect(unload)
