-- Fake server for the Movement Lab, appended after harness.lua.
-- What replicates is the root's position / velocity right after Heartbeat. Rules the
-- tests should discover:
--   * not hidden: moving more than 20 studs in one frame -> pulled back 0.25 s later
--     (plain TPs over 20 studs fail, glides over 1200 studs/s fail)
--   * hidden (flung = huge speed, ghosted = far away): the server ignores you, but a jump
--     made with fewer than 2 hidden frames before it is caught -> pulled back on unhide
--   * hidden for 40 s in a row -> you die (respawn 1 s later where the server last saw you)
--   * the floor is at y = 0 for |x|, |z| <= 3000 (raycasts); kill height -500
local SG = { pulls = 0, deaths = 0, log = {}, hiddenFrames = 0, hiddenRun = 0 }
__SG = SG

local hum = char:FindFirstChildOfClass("Humanoid")
local walkTarget
hum.__props.MoveTo = function(_, pos) walkTarget = pos end
root.CFrame = CFrame.new(Vector3.new(0, 3, 0))
workspace.__props.FallenPartsDestroyHeight = -500

-- floor raycasts
RaycastParams = { new = function() return {} end }
workspace.__props.Raycast = function(_, origin, dir)
    local endY = origin.Y + dir.Y
    if math.abs(origin.X) <= 3000 and math.abs(origin.Z) <= 3000 and origin.Y >= 0 and endY <= 0 then
        return { Position = Vector3.new(origin.X, 0, origin.Z) }
    end
    return nil
end

local function part(name, parent, pos, size)
    local p = newInstance("Part", name)
    p.CFrame = CFrame.new(pos)
    p.Size = size or Vector3.new(4, 4, 4)
    p.Parent = parent
    return p
end
-- your plot around the origin (hidden tests walk off it first)
local plots = newInstance("Folder", "Plots"); plots.Parent = workspace
local plot = newInstance("Model", "Base_1"); plot.Parent = plots
plot:SetAttribute("OwnerUserId", 1)
local hitbox = part("Hitbox", plot, Vector3.new(0, 10, 0), Vector3.new(60, 20, 60))
local function inHitbox(pos)
    local rel = pos - hitbox.Position
    return math.abs(rel.X) <= 30 and math.abs(rel.Z) <= 30 and math.abs(rel.Y) <= 12
end
__inHitbox = inHitbox

local hb = rs.__signals.Heartbeat
local fire = hb.Fire
hb.Fire = function(self, ...)
    fire(self, ...)
    SG.serverPos = root.Position
    SG.serverVel = root.AssemblyLinearVelocity
end

local function pullBack(to, why)
    SG.pulls += 1
    SG.pulling = true
    table.insert(SG.log, ("pull back (%s)"):format(why))
    task.delay(0.25, function()
        root.CFrame = CFrame.new(to)
        SG.pulling = false
        SG.good = to
    end)
end

local runFrames = __runFrames
function __runFrames(n)
    for _ = 1, n do
        local before = root.Position
        runFrames(1)
        local real = root.Position
        local v = SG.serverVel
        local flung = v ~= nil and v.Magnitude > 1000
        local ghosted = SG.serverPos ~= nil and (SG.serverPos - real).Magnitude > 1e5
        local hiddenNow = flung or ghosted
        SG.lastHidden = hiddenNow
        if hiddenNow then SG.hiddenFrames += 1 end
        if hum.Health > 0 then
            if hiddenNow then
                SG.hiddenRun += 1
                -- a jump this frame: how long were we hidden before it?
                if (real - before).Magnitude > 20 and SG.hiddenRun < 3 then SG.badJump = true end
                if SG.hiddenRun >= 60 * 40 then
                    hum.Health = 0
                    SG.deaths += 1
                    table.insert(SG.log, "died (hidden too long)")
                    task.delay(1, function()
                        hum.Health = 100
                        root.CFrame = CFrame.new(SG.good or Vector3.new(0, 3, 0))
                        SG.hiddenRun = 0
                    end)
                end
            else
                local wasHidden = SG.hiddenRun > 0
                SG.hiddenRun = 0
                if not SG.pulling then
                    if wasHidden then
                        if SG.badJump then pullBack(SG.good, "jump without warmup") else SG.good = SG.serverPos end
                        SG.badJump = false
                    elseif SG.good and SG.serverPos and (SG.serverPos - SG.good).Magnitude > 20 then
                        pullBack(SG.good, ("moved %d studs in a frame"):format((SG.serverPos - SG.good).Magnitude))
                    else
                        SG.good = SG.serverPos
                    end
                end
            end
        end
        if walkTarget then
            local d = Vector3.new(walkTarget.X - root.Position.X, 0, walkTarget.Z - root.Position.Z)
            if d.Magnitude > 0.5 then
                root.CFrame = CFrame.new(root.Position + d.Unit * math.min(d.Magnitude, 16 / 60))
            else
                walkTarget = nil
            end
        end
    end
end

-- remotes + a pretend executor hook (__namecall) so the Remotes tab can be tested
SG.serverCalls = 0
SG.remotes = {}
for _, name in ipairs({ "EggHitRequest", "Notify", "PlaceAnimalRemote" }) do
    local r = newInstance("RemoteEvent", name)
    r.__server = function() SG.serverCalls += 1 end
    r.Parent = Services.ReplicatedStorage
    SG.remotes[name] = r
end
local fn = newInstance("RemoteFunction", "BackpackSellRemote"); fn.Parent = Services.ReplicatedStorage
-- like Roblox: every colon call sets the shared "namecall method", and the original
-- __namecall handler runs whatever method is current when it's called
local realMethods = {}
local namecallMethod = nil
for _, name in ipairs({ "FireServer", "GetFullName", "IsA" }) do
    local f = methods[name]
    realMethods[name] = f
end
local hooks = {}
local function originalNamecall(self, ...)
    return realMethods[namecallMethod](self, ...)
end
for name, f in pairs(realMethods) do
    methods[name] = function(self, ...)
        namecallMethod = name
        if hooks.__namecall then return hooks.__namecall(self, ...) end
        return f(self, ...)
    end
end
function hookmetamethod(_, mm, f)
    local old = hooks[mm] or originalNamecall
    hooks[mm] = f
    return old
end
function getnamecallmethod() return namecallMethod end
function newcclosure(f) return f end
function checkcaller() return false end
local clip
function setclipboard(t) clip = t end
function SG.clipboard() return clip end
