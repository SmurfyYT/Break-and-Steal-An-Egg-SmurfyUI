--[[
    Smurfy's Simple UI — Movement Lab (Break & Steal an Egg)
    Made for Delta (Android / BlueStacks). Paste the whole file into the executor.

    Main    : restore settings, unload.
    Snap    : live snap-back watcher (did the server drag you back?) + a quick check.
    Ladder  : plain teleports at growing distances: where does the server pull you back?
    VPin    : velocity to a pinned target (walk there, press Set, then launch).
    VLdr    : velocity at 10→1000 studs — where does the server pull you back?
    VSpd    : velocity at 100→10000 studs/s — fastest speed the server accepts.
    Warmup  : how long you must be hidden before the jump (0, 1 frame, 0.05, 0.15, 0.5 s).
    Glide   : fastest glide speed the server accepts.
    Endure  : how long you can stay hidden (5, 15, 30, 60 s) before something happens.
    Under   : travel under the map and come up at the target.
    Remotes : remote spy — what your client sends (→) and receives (←); never sends anything.

    Hiding methods (what replicates right after physics, then you're put back on a "hold"
    point before the next physics step and before drawing, so you stand still on screen):
      Ghost: CFrame moved 9e9 studs away (the game's own scripts read your real spot via
             hookmetamethod when the executor has it).
      Fling: velocity set huge.
    A test result "ok" = you stayed where you went for 2 s after arriving (not hidden).
    "BACK" = something moved you more than 8 studs away from there (server pull-back).
]]

local ENV = (getgenv and getgenv()) or _G
if ENV.SmurfySimple and ENV.SmurfySimple.Unload then
    pcall(ENV.SmurfySimple.Unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local App = { Alive = true, Conns = {} }
ENV.SmurfySimple = App

local function track(conn)
    table.insert(App.Conns, conn)
    return conn
end

---------------------------------------------------------------- settings
local CONFIG_FILE = "SmurfySimple_MovementLab.json"
local Defaults = {
    FlingLevel = 4,      -- index into FlingPowers (Max)
    Warmup = 0.15,       -- seconds hidden before a jump (Warmup tab can change it)
    Watch = true,        -- live snap-back watcher
    WarmupMethod = "Ghost",
    WarmupDist = 250,
    GlideDist = 250,
    EndureMethod = "Ghost",
    UnderDepth = 50,
    UnderDist = 250,
    UnderSpeed = 300,
    WindowX = 80,
    WindowY = 80,
    PinX = false,  -- pinned target position (false = none)
    PinY = false,
    PinZ = false,
    PinSpeed = 500,
    VLdrSpeed = 300,
    VSpdDist = 250,
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
            if Defaults[k] ~= nil then
                if type(v) == type(Defaults[k]) then Settings[k] = v
                elseif (k == "PinX" or k == "PinY" or k == "PinZ") and type(v) == "number" then Settings[k] = v
                end
            end
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

local function attr(inst, name)
    local ok, v = pcall(inst.GetAttribute, inst, name)
    return ok and v or nil
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

---------------------------------------------------------------- movers (fling / ghost)
-- Both hide where you really are from the server / other players, while on your own
-- screen you stand still on a "hold" CFrame:
--   Fling: after physics (Heartbeat) the velocity is set huge -> you look flung away.
--   Ghost: after physics the CFrame is moved 9e9 studs away -> the server sees you far away.
-- Before the next physics step and before drawing (Stepped / RenderStepped) the character is
-- put back on the hold point with no velocity. A TP just moves the hold point (one frame).

local function zeroMotion(root)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

-- jumps made by this script (so the snap-back watcher doesn't count them)
local ownMoveUntil = 0
local function markOwn(seconds) ownMoveUntil = math.max(ownMoveUntil, os.clock() + (seconds or 0.1)) end

local SETTLE = 0.1  -- seconds hidden on arrival before doing anything there
local GHOST_FAR = CFrame.new(9e9, 0, 9e9)

local leavePlot -- defined with the plot helpers: walks off your plot if you're on it

local function newMover(name, afterPhysics)
    local M = { Name = name, On = false, Hold = nil, Conns = {} }

    -- back on the hold point, no motion (before physics and before drawing)
    local function pin()
        local root = getRoot()
        if not root then return end
        zeroMotion(root)
        if M.Hold then root.CFrame = M.Hold end
        M.Away = false
    end

    function M.Start(hold)
        local root = getRoot()
        M.Hold = hold or (root and root.CFrame) or M.Hold
        if M.On then return end
        M.On = true
        M.Since = os.clock()
        M.Root = root
        -- after physics: what replicates
        table.insert(M.Conns, RunService.Heartbeat:Connect(function()
            local r = getRoot()
            if not r then return end
            M.Root = r
            afterPhysics(r, M)
        end))
        table.insert(M.Conns, RunService.Stepped:Connect(pin))
        table.insert(M.Conns, RunService.RenderStepped:Connect(pin))
    end

    function M.Stop()
        for _, c in ipairs(M.Conns) do c:Disconnect() end
        table.clear(M.Conns)
        local wasOn = M.On
        M.On = false
        local root = getRoot()
        if root and wasOn then
            zeroMotion(root)
            if M.Away and M.Hold then root.CFrame = M.Hold end
        end
        M.Away = false
        M.Hold = nil
        return wasOn
    end

    -- the "teleport": hidden for a moment, then the whole trip in ONE frame.
    -- Only the hold point moves; the pin applies it before physics
    -- warmup: seconds hidden in place before the jump (-1 = one frame, 0 = none)
    function M.TP(target, warmup)
        local root = getRoot()
        if not root then return false end
        if not M.On then
            -- never hidden while on the plot: walk off it first
            if leavePlot then leavePlot() end
            root = getRoot()
            if not root then return false end
            M.Start(root.CFrame)
        end
        warmup = warmup or Settings.Warmup
        local t = os.clock()
        if warmup < 0 then
            RunService.Stepped:Wait()
        else
            while M.On and App.Alive and os.clock() - (M.Since or t) < warmup do
                RunService.Stepped:Wait()
            end
        end
        if not App.Alive or not M.On then return false end
        markOwn()
        M.Hold = target
        RunService.Stepped:Wait()
        t = os.clock()
        while M.On and App.Alive and os.clock() - t < SETTLE do
            RunService.Stepped:Wait()
        end
        return M.On
    end

    return M
end

local Fling = newMover("Fling", function(r)
    local power = (FlingPowers[Settings.FlingLevel] or FlingPowers[#FlingPowers])[2]
    r.AssemblyLinearVelocity = Vector3.new(power, power, power)
    r.AssemblyAngularVelocity = Vector3.new(0, power, 0)
end)

local Ghost = newMover("Ghost", function(r, M)
    M.Away = true
    r.CFrame = (M.Hold or r.CFrame) * GHOST_FAR
end)

-- while ghosting, the game's own scripts (not this one) read your real spot, not 9e9
local hookOriginal
local function installGhostHook()
    if hookOriginal or type(hookmetamethod) ~= "function" or type(newcclosure) ~= "function"
        or type(checkcaller) ~= "function" then return end
    pcall(function()
        hookOriginal = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if Ghost.On and Ghost.Hold and (key == "CFrame" or key == "Position") and self == Ghost.Root
                and not checkcaller() then
                return key == "CFrame" and Ghost.Hold or Ghost.Hold.Position
            end
            return hookOriginal(self, key)
        end))
    end)
end
local function removeGhostHook()
    if hookOriginal then
        pcall(hookmetamethod, game, "__index", hookOriginal)
        hookOriginal = nil
    end
end
local ghostStart = Ghost.Start
function Ghost.Start(hold)
    installGhostHook()
    ghostStart(hold)
end

local function hidden() return Fling.On or Ghost.On end
local function stopMovers()
    Fling.Stop()
    Ghost.Stop()
end
-- stop hiding; after a ghost wait until the server has your real spot again
local function unhide()
    local wasGhost = Ghost.Stop()
    Fling.Stop()
    if wasGhost then task.wait(0.2) end
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
    local towards = zoneHitbox(1)
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
    -- stop walking, or the humanoid keeps heading for the spot after a teleport
    root = getRoot()
    if hum and root then pcall(hum.MoveTo, hum, root.Position) end
end


---------------------------------------------------------------- lab: shared test helpers
local Lab = { Busy = false, Token = 0 }
local function labRunning(token) return App.Alive and Lab.Token == token end

-- noclip while travelling under the map
local noclipConn, noclipSaved = nil, {}
local function noclip(on)
    if on and not noclipConn then
        noclipConn = RunService.Stepped:Connect(function()
            local char = getChar()
            for _, p in ipairs(char and char:GetDescendants() or {}) do
                if p:IsA("BasePart") and p.CanCollide then
                    noclipSaved[p] = true
                    p.CanCollide = false
                end
            end
        end)
    elseif not on and noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
        for p in pairs(noclipSaved) do pcall(function() p.CanCollide = true end) end
        table.clear(noclipSaved)
    end
end

local function stopLab()
    Lab.Token += 1
    Lab.Busy = false
    stopMovers()
    noclip(false)
end

-- run fn(token) as the only test; out(text) shows errors
local function runLab(fn, out)
    if Lab.Busy then out("Another test is running. Press Stop first.") return end
    Lab.Busy = true
    Lab.Token += 1
    local token = Lab.Token
    task.spawn(function()
        local ok, err = pcall(fn, token)
        if not ok then out("Error: " .. tostring(err)) end
        stopMovers()
        noclip(false)
        if Lab.Token == token then Lab.Busy = false end
    end)
end

-- ground under (x, z), searching from above the reference height
local function groundAt(pos, refY)
    local ok, hit = pcall(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { getChar() }
        pcall(function() params.RespectCanCollide = true end)
        return workspace:Raycast(Vector3.new(pos.X, refY + 150, pos.Z), Vector3.new(0, -600, 0), params)
    end)
    return ok and hit and hit.Position or nil
end

-- a standing spot `dist` studs away with ground under it: camera direction first, then turning
local function findTarget(origin, dist)
    local cam = workspace.CurrentCamera
    local look = cam and flat(cam.CFrame.LookVector) or Vector3.new(0, 0, -1)
    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
    look = look.Unit
    for i = 0, 7 do
        local a = math.rad(45 * i)
        local dir = Vector3.new(look.X * math.cos(a) - look.Z * math.sin(a), 0, look.X * math.sin(a) + look.Z * math.cos(a))
        local ground = groundAt(origin.Position + dir * dist, origin.Position.Y)
        if ground then
            local pos = ground + Vector3.new(0, 3, 0)
            return CFrame.lookAt(pos, pos + dir)
        end
    end
    return nil
end

-- after arriving: stay unhidden for `seconds` and see whether something moves you away
local WATCH_TIME, WATCH_LIMIT = 2, 8
local function watch(target, origin, token, seconds)
    local t0 = os.clock()
    local worst, at = 0, nil
    while labRunning(token) and os.clock() - t0 < (seconds or WATCH_TIME) do
        local hum, root = getHumanoid(), getRoot()
        if not hum or hum.Health <= 0 or not root then return { died = true } end
        local d = (root.Position - target.Position).Magnitude
        if d > worst then
            worst = d
            if d > WATCH_LIMIT and not at then at = os.clock() - t0 end
        end
        RunService.Heartbeat:Wait()
    end
    local root = getRoot()
    local toStart = (root and origin) and (root.Position - origin.Position).Magnitude or nil
    return { ok = worst <= WATCH_LIMIT, worst = worst, at = at, backToStart = toStart ~= nil and toStart < 15 }
end

local function describe(r)
    if not r then return "skipped" end
    if r.noGround then return "no ground there" end
    if r.died then return "<font color='#ff6b6b'>DIED</font>" end
    if r.ok then return "<font color='#6be08a'>ok</font>" end
    return ("<font color='#ffb347'>BACK</font> %d studs%s after %.1fs"):format(
        math.floor(r.worst), r.backToStart and " (to start)" or "", r.at or 0)
end
local function short(r)
    if not r or r.noGround then return " -- " end
    if r.died then return "DIED" end
    return r.ok and " ok " or "BACK"
end

-- glide along points at `speed` studs/s (not hidden), one small step per frame
local function glidePath(points, speed, token)
    for i = 2, #points do
        local from, to = points[i - 1], points[i]
        local dist = (to - from).Magnitude
        local t0 = os.clock()
        while labRunning(token) do
            local root = getRoot()
            if not root then return false end
            local k = dist > 0 and math.min((os.clock() - t0) * speed / dist, 1) or 1
            markOwn()
            zeroMotion(root)
            root.CFrame = CFrame.new(from:Lerp(to, k))
            if k >= 1 then break end
            RunService.Stepped:Wait()
        end
    end
    return labRunning(token)
end

-- go to target with a method: "Plain", "Ghost", "Fling", "Glide",
-- "Velocity", "VForce", or "PlatStand"
local function travel(method, target, token, opts)
    opts = opts or {}
    local root = getRoot()
    if not root then return false end
    if method == "Plain" then
        markOwn()
        zeroMotion(root)
        root.CFrame = target
        RunService.Stepped:Wait()
    elseif method == "Glide" then
        glidePath({ root.Position, target.Position }, opts.speed or 300, token)
    elseif method == "Velocity" then
        -- LinearVelocity constraint with huge MaxForce overrides humanoid + gravity
        local dist = (target.Position - root.Position).Magnitude
        if dist < 0.1 then return labRunning(token) end
        local speed = opts.speed or math.clamp(dist / 0.4, 50, 2000)
        markOwn(dist / speed + 0.5)
        noclip(true)
        local att = Instance.new("Attachment")
        att.Parent = root
        local lv = Instance.new("LinearVelocity")
        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.MaxForce = 1e6
        lv.VectorVelocity = (target.Position - root.Position).Unit * speed
        lv.Parent = root
        local t0 = os.clock()
        local limit = dist / speed + 0.5
        while labRunning(token) and os.clock() - t0 < limit do
            local r2 = getRoot()
            if not r2 then break end
            local remaining = target.Position - r2.Position
            if remaining.Magnitude < 4 then break end
            lv.VectorVelocity = remaining.Unit * speed  -- re-aim each frame
            RunService.Stepped:Wait()
        end
        pcall(function() lv:Destroy() att:Destroy() end)
        noclip(false)
        local r2 = getRoot()
        if r2 then zeroMotion(r2) end
    elseif method == "VForce" then
        -- VectorForce impulse: use physics engine to push the character
        local dir = (target.Position - root.Position)
        local dist = dir.Magnitude
        if dist < 0.1 then return labRunning(token) end
        local speed = opts.speed or math.clamp(dist / 0.4, 50, 2000)
        local mass = root.AssemblyMass > 0 and root.AssemblyMass or 1
        local att = Instance.new("Attachment")
        att.Parent = root
        local vf = Instance.new("VectorForce")
        vf.Attachment0 = att
        vf.RelativeTo = Enum.ActuatorRelativeTo.World
        vf.ApplyAtCenterOfMass = true
        vf.Force = dir.Unit * mass * speed * 60  -- one-frame impulse equivalent
        vf.Parent = root
        markOwn(dist / speed + 0.5)
        RunService.Stepped:Wait()  -- let physics apply one frame of force
        pcall(function() vf:Destroy() att:Destroy() end)
        -- glide the rest of the way so the test reaches the target reliably
        glidePath({ (getRoot() or root).Position, target.Position }, speed, token)
    elseif method == "PlatStand" then
        -- PlatformStand disables humanoid joint control; CFrame the character while it's off
        local hum = getHumanoid()
        if hum then
            pcall(function() hum.PlatformStand = true end)
            RunService.Stepped:Wait()  -- let humanoid relinquish joints
        end
        markOwn()
        zeroMotion(root)
        root.CFrame = target
        RunService.Stepped:Wait()
        if hum then pcall(function() hum.PlatformStand = false end) end
    else
        local m = method == "Fling" and Fling or Ghost
        if (m == Fling and Ghost.On) or (m == Ghost and Fling.On) then stopMovers() end
        m.TP(target, opts.warmup)
        unhide()
    end
    return labRunning(token)
end

-- one trial: from where you stand, go `dist` studs with `method`, watch, come back
local function trial(method, dist, token, opts)
    local root = getRoot()
    if not root then return { died = true } end
    if (method == "Ghost" or method == "Fling") and leavePlot then leavePlot() end
    root = getRoot()
    local origin = root.CFrame
    local target = findTarget(origin, dist)
    if not target then return { noGround = true } end
    travel(method, target, token, opts)
    local r = watch(target, origin, token)
    if r.died then
        -- wait for the respawn before the next trial
        local t = os.clock()
        while labRunning(token) and not (getHumanoid() and getHumanoid().Health > 0) and os.clock() - t < 10 do task.wait(0.5) end
        task.wait(1)
        return r
    end
    -- come back the same way (not judged), then rest a moment
    if labRunning(token) then
        local now = getRoot()
        if now and (now.Position - origin.Position).Magnitude > WATCH_LIMIT then travel(method, origin, token, opts) end
        task.wait(1)
    end
    return r
end

---------------------------------------------------------------- live snap-back watcher
local Snap = { Events = {}, Count = 0 }
local snapChanged -- set by the UI
do
    local last
    track(RunService.Heartbeat:Connect(function()
        local root = getRoot()
        if not root then last = nil return end
        -- read before the movers hide anything (they act after this on Heartbeat too,
        -- so skip hidden frames entirely)
        if hidden() then last = nil return end
        local pos = root.Position
        if last and Settings.Watch and os.clock() > ownMoveUntil then
            local jump = (pos - last).Magnitude
            if jump > WATCH_LIMIT then
                Snap.Count += 1
                table.insert(Snap.Events, 1, ("%s  moved %d studs in one frame"):format(os.date and os.date("%H:%M:%S") or "", math.floor(jump)))
                if #Snap.Events > 8 then table.remove(Snap.Events) end
                if snapChanged then task.defer(snapChanged) end
            end
        end
        last = pos
    end))
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

local WIDTH, HEIGHT = 310, 380
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

-- tabs (scroll sideways when they don't fit)
local tabBar = new("ScrollingFrame", {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(10, 44),
    Size = UDim2.new(1, -20, 0, 34),
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X,
    ScrollBarThickness = 3,
    Parent = main,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })

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
        Position = UDim2.fromOffset(10, 84),
        Size = UDim2.new(1, -20, 1, -94),
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
        TextSize = 13,
        TextColor3 = Theme.Text,
        BackgroundColor3 = Theme.Item,
        Size = UDim2.fromOffset(66, 28),
        LayoutOrder = #tabBar:GetChildren(),
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
        if not ok then warn("[SmurfySimple] " .. tostring(err)) end
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
-- a results box (monospace) for a test page
local function resultsBox(page)
    local l = label(page, "")
    l.Font = Enum.Font.Code
    l.TextColor3 = Theme.Text
    return function(text) l.Text = text end
end

-- the usual Run / Stop pair; run(token, out) does the test
local function runStop(page, runText, out, run)
    button(page, runText, Theme.On, function()
        runLab(function(token) run(token, out) end, out)
    end)
    button(page, "Stop", Theme.Danger, function()
        stopLab()
        out("Stopped.")
    end)
end

local function pickCycle(page, prefix, key, options, fmt)
    return cycle(page, function()
        return prefix .. (fmt and fmt(Settings[key]) or tostring(Settings[key]))
    end, function()
        local idx = table.find(options, Settings[key]) or 0
        Settings[key] = options[idx % #options + 1]
        saveSettings()
    end)
end

local mainPage = makePage("Main")
local snapPage = makePage("Snap")
local ladderPage = makePage("Ladder")
local vpinPage = makePage("VPin")
local vldrPage = makePage("VLdr")
local vspdPage = makePage("VSpd")
local warmupPage = makePage("Warmup")
local glidePage = makePage("Glide")
local endurePage = makePage("Endure")
local underPage = makePage("Under")
local remotesPage = makePage("Remotes")

---------------- Main
label(mainPage, "Movement Lab. Each tab is one test: stand somewhere open, press its green button, then send the results.\nDrag the top bar to move. <b>–</b> hides the window (tap <b>S</b> to bring it back).")
local unload -- defined below
button(mainPage, "Restore settings", Theme.Item, function()
    stopLab()
    Settings = table.clone(Defaults)
    pcall(function() if type(delfile) == "function" and isfile(CONFIG_FILE) then delfile(CONFIG_FILE) end end)
    saveSettings()
    main.Position = UDim2.fromOffset(Defaults.WindowX, Defaults.WindowY)
    refreshAll()
end)
button(mainPage, "Unload", Theme.Danger, function() unload() end)

---------------- Snap
label(snapPage, "<b>Snap-back watcher</b>: while on, any time something moves you more than 8 studs in one frame (not this script), it's listed here. That's what a server pull-back looks like.")
toggle(snapPage, "Watch for snap-backs", function() return Settings.Watch end, function(v)
    Settings.Watch = v
    saveSettings()
end)
local snapOut = resultsBox(snapPage)
snapChanged = function()
    snapOut(("Seen: %d\n%s"):format(Snap.Count, #Snap.Events > 0 and table.concat(Snap.Events, "\n") or "(nothing yet)"))
end
snapChanged()
button(snapPage, "Clear list", nil, function()
    table.clear(Snap.Events)
    Snap.Count = 0
    snapChanged()
end)
local snapCheck = resultsBox(snapPage)
runStop(snapPage, "Quick check: plain TP 50 studs", snapCheck, function(token, out)
    out("Teleporting 50 studs and watching for 2 s...")
    local r = trial("Plain", 50, token)
    out("Plain TP 50 studs: " .. describe(r) .. "\nDone.")
end)

---------------- Ladder
label(ladderPage, "<b>Plain TP ladder</b>: a normal teleport (no hiding) at 10, 25, 50, 100, 250, 500, 1000 studs. Shows where the server starts pulling you back.")
local ladderOut = resultsBox(ladderPage)
runStop(ladderPage, "Run ladder", ladderOut, function(token, out)
    local lines = {}
    for _, d in ipairs({ 10, 25, 50, 100, 250, 500, 1000 }) do
        if not labRunning(token) then return end
        out(table.concat(lines, "\n") .. ("\n%5d studs: testing..."):format(d))
        local r = trial("Plain", d, token)
        table.insert(lines, ("%5d studs: %s"):format(d, describe(r)))
    end
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- VPin
label(vpinPage, "<b>Velocity to pin</b>: walk to your target, press Set, then launch there via raw AssemblyLinearVelocity from anywhere.")
do
    local pinOut = resultsBox(vpinPage)
    local pinLabel

    local function pinDesc()
        if Settings.PinX then
            return ("Pin: %.1f, %.1f, %.1f"):format(Settings.PinX, Settings.PinY, Settings.PinZ)
        end
        return "Pin: not set — stand at your target and press Set"
    end

    pinLabel = cycle(vpinPage, pinDesc, function() end)

    button(vpinPage, "Set pin here", Theme.Item, function()
        local root = getRoot()
        if not root then pinOut("No character.") return end
        local p = root.Position
        Settings.PinX, Settings.PinY, Settings.PinZ = p.X, p.Y, p.Z
        saveSettings()
        pinLabel()
        pinOut("Pinned at " .. ("%0.1f, %0.1f, %0.1f"):format(p.X, p.Y, p.Z))
    end)

    pickCycle(vpinPage, "Speed: ", "PinSpeed", { 200, 500, 1000, 2000 }, function(v) return v .. " studs/s" end)

    runStop(vpinPage, "Velocity to pin", pinOut, function(token, out)
        if not Settings.PinX then out("No pin set. Stand at your target and press Set pin here.") return end
        local target = CFrame.new(Settings.PinX, Settings.PinY, Settings.PinZ)
        local root = getRoot()
        if not root then out("No character.") return end
        local dist = (root.Position - target.Position).Magnitude
        out(("Going %.0f studs to pin..."):format(dist))
        markOwn(dist / Settings.PinSpeed + 1)
        local dir = (target.Position - root.Position)
        if dir.Magnitude < 0.1 then out("Already there.") return end
        noclip(true)
        local att = Instance.new("Attachment")
        att.Parent = root
        local lv = Instance.new("LinearVelocity")
        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.MaxForce = 1e6
        lv.VectorVelocity = dir.Unit * Settings.PinSpeed
        lv.Parent = root
        local t0 = os.clock()
        local limit = dist / Settings.PinSpeed + 1
        while labRunning(token) and os.clock() - t0 < limit do
            local r2 = getRoot()
            if not r2 then break end
            local remaining = target.Position - r2.Position
            if remaining.Magnitude < 5 then break end
            lv.VectorVelocity = remaining.Unit * Settings.PinSpeed
            RunService.Stepped:Wait()
        end
        pcall(function() lv:Destroy() att:Destroy() end)
        noclip(false)
        local r2 = getRoot()
        if r2 then zeroMotion(r2) end
        local r = watch(target, root.CFrame, token)
        out(("Velocity to pin %.0f studs: %s"):format(dist, describe(r)))
    end)
end

---------------- VLdr
label(vldrPage, "<b>Velocity ladder</b>: raw AssemblyLinearVelocity at 10, 25, 50, 100, 250, 500, 1000 studs. Shows where the server starts pulling you back.")
pickCycle(vldrPage, "Speed: ", "VLdrSpeed", { 300, 1000, 3000 }, function(v) return v .. " studs/s" end)
local vldrOut = resultsBox(vldrPage)
runStop(vldrPage, "Run ladder", vldrOut, function(token, out)
    local lines = {}
    for _, d in ipairs({ 10, 25, 50, 100, 250, 500, 1000 }) do
        if not labRunning(token) then return end
        out(table.concat(lines, "\n") .. ("\n%5d studs: testing..."):format(d))
        local r = trial("Velocity", d, token, { speed = Settings.VLdrSpeed })
        table.insert(lines, ("%5d studs: %s"):format(d, describe(r)))
    end
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- VSpd
label(vspdPage, "<b>Velocity speed finder</b>: same distance, increasing velocity — 100, 300, 1000, 3000, 10000 studs/s. Finds the fastest the server accepts.")
pickCycle(vspdPage, "Distance: ", "VSpdDist", { 100, 250, 500 }, function(v) return v .. " studs" end)
local vspdOut = resultsBox(vspdPage)
runStop(vspdPage, "Run speed test", vspdOut, function(token, out)
    local lines, fastest = {}, nil
    for _, speed in ipairs({ 100, 300, 1000, 3000, 10000 }) do
        if not labRunning(token) then return end
        out(table.concat(lines, "\n") .. ("\n%6d/s: testing..."):format(speed))
        local r = trial("Velocity", Settings.VSpdDist, token, { speed = speed })
        table.insert(lines, ("%6d/s: %s"):format(speed, describe(r)))
        if r.ok then fastest = speed end
    end
    table.insert(lines, fastest and ("Fastest ok: " .. fastest .. " studs/s") or "No speed worked.")
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- Warmup
label(warmupPage, "<b>Warmup tuner</b>: how long you're hidden before the jump. Tries none, 1 frame, 0.05, 0.15 and 0.5 s (2 tries each) and keeps the shortest that always worked.")
pickCycle(warmupPage, "Method: ", "WarmupMethod", { "Ghost", "Fling" })
pickCycle(warmupPage, "Distance: ", "WarmupDist", { 100, 250, 500, 1000 }, function(v) return v .. " studs" end)
cycle(warmupPage, function() return ("Current warmup: %s"):format(Settings.Warmup < 0 and "1 frame" or (Settings.Warmup .. " s")) end, function() end)
local warmupOut = resultsBox(warmupPage)
local WARMUPS = { { "none", 0 }, { "1 frame", -1 }, { "0.05 s", 0.05 }, { "0.15 s", 0.15 }, { "0.5 s", 0.5 } }
runStop(warmupPage, "Run warmup test", warmupOut, function(token, out)
    local lines, best = {}, nil
    for _, w in ipairs(WARMUPS) do
        local good = 0
        for try = 1, 2 do
            if not labRunning(token) then return end
            out(table.concat(lines, "\n") .. ("\n%-8s try %d..."):format(w[1], try))
            local r = trial(Settings.WarmupMethod, Settings.WarmupDist, token, { warmup = w[2] })
            if r.ok then good += 1 end
        end
        table.insert(lines, ("%-8s %d/2 ok"):format(w[1], good))
        if good == 2 and not best then best = w end
    end
    if best then
        Settings.Warmup = best[2]
        saveSettings()
        refreshAll()
        table.insert(lines, "Best: " .. best[1] .. " (now used for Ghost / Fling TPs)")
    else
        table.insert(lines, "None worked every time. Warmup left as it was.")
    end
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- Glide
label(glidePage, "<b>Glide speed finder</b>: slides you there (not hidden) at 100, 300, 1000, 3000 and 10000 studs/s and shows the fastest the server accepts.")
pickCycle(glidePage, "Distance: ", "GlideDist", { 100, 250, 500 }, function(v) return v .. " studs" end)
local glideOut = resultsBox(glidePage)
runStop(glidePage, "Run glide test", glideOut, function(token, out)
    local lines, fastest = {}, nil
    for _, speed in ipairs({ 100, 300, 1000, 3000, 10000 }) do
        if not labRunning(token) then return end
        out(table.concat(lines, "\n") .. ("\n%6d/s: testing..."):format(speed))
        local r = trial("Glide", Settings.GlideDist, token, { speed = speed })
        table.insert(lines, ("%6d/s: %s"):format(speed, describe(r)))
        if r.ok then fastest = speed end
    end
    table.insert(lines, fastest and ("Fastest ok: " .. fastest .. " studs/s") or "No speed worked.")
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- Endure
label(endurePage, "<b>Hide endurance</b>: stays hidden in place for 5, 15, 30 and 60 s, then checks whether you died or got pulled when you come back. About 2 minutes.")
pickCycle(endurePage, "Method: ", "EndureMethod", { "Ghost", "Fling" })
local endureOut = resultsBox(endurePage)
runStop(endurePage, "Run endurance", endureOut, function(token, out)
    local lines = {}
    for _, secs in ipairs({ 5, 15, 30, 60 }) do
        if not labRunning(token) then return end
        if leavePlot then leavePlot() end
        local root = getRoot()
        if not root then return end
        local spot = root.CFrame
        local m = Settings.EndureMethod == "Fling" and Fling or Ghost
        m.Start(spot)
        local t0, died = os.clock(), false
        while labRunning(token) and os.clock() - t0 < secs do
            local hum = getHumanoid()
            if not hum or hum.Health <= 0 then died = true break end
            out(table.concat(lines, "\n") .. ("\n%2d s: hidden, %d s left"):format(secs, math.ceil(secs - (os.clock() - t0))))
            task.wait(0.25)
        end
        unhide()
        local r
        if died then
            r = { died = true }
            local t = os.clock()
            while labRunning(token) and not (getHumanoid() and getHumanoid().Health > 0) and os.clock() - t < 10 do task.wait(0.5) end
        else
            r = watch(spot, spot, token)
        end
        table.insert(lines, ("%2d s: %s"):format(secs, describe(r)))
        task.wait(2)
    end
    out(table.concat(lines, "\n") .. "\nDone.")
end)

---------------- Under
label(underPage, "<b>Under-the-map route</b>: drops below the floor, glides under the map (no collisions) and comes up at the target. Never goes deeper than the game's kill height allows.")
pickCycle(underPage, "Depth: ", "UnderDepth", { 20, 50, 100 }, function(v) return v .. " studs under" end)
pickCycle(underPage, "Distance: ", "UnderDist", { 100, 250, 500 }, function(v) return v .. " studs" end)
pickCycle(underPage, "Speed: ", "UnderSpeed", { 300, 1000 }, function(v) return v .. " studs/s" end)
local underOut = resultsBox(underPage)

local function underTrial(depth, dist, speed, token)
    local root = getRoot()
    if not root then return { died = true } end
    local origin = root.CFrame
    local target = findTarget(origin, dist)
    if not target then return { noGround = true } end
    local floorY = math.min(origin.Position.Y, target.Position.Y) - 3
    local killY = (workspace.FallenPartsDestroyHeight or -500) + 50
    local y = math.max(floorY - depth, killY)
    noclip(true)
    glidePath({
        origin.Position,
        Vector3.new(origin.Position.X, y, origin.Position.Z),
        Vector3.new(target.Position.X, y, target.Position.Z),
        target.Position,
    }, speed, token)
    noclip(false)
    local r = watch(target, origin, token)
    if not r.died and labRunning(token) then
        local now = getRoot()
        if now and (now.Position - origin.Position).Magnitude > WATCH_LIMIT then
            noclip(true)
            glidePath({ now.Position, Vector3.new(now.Position.X, y, now.Position.Z),
                Vector3.new(origin.Position.X, y, origin.Position.Z), origin.Position }, speed, token)
            noclip(false)
        end
        task.wait(1)
    end
    return r
end

runStop(underPage, "Run once (settings above)", underOut, function(token, out)
    out("Going under...")
    local r = underTrial(Settings.UnderDepth, Settings.UnderDist, Settings.UnderSpeed, token)
    out(("%d under, %d studs, %d/s: %s\nDone."):format(Settings.UnderDepth, Settings.UnderDist, Settings.UnderSpeed, describe(r)))
end)
button(underPage, "Run all depths", Theme.On, function()
    runLab(function(token)
        local lines = {}
        for _, depth in ipairs({ 20, 50, 100 }) do
            if not labRunning(token) then return end
            underOut(table.concat(lines, "\n") .. ("\n%3d under: testing..."):format(depth))
            local r = underTrial(depth, Settings.UnderDist, Settings.UnderSpeed, token)
            table.insert(lines, ("%3d under: %s"):format(depth, describe(r)))
        end
        underOut(table.concat(lines, "\n") .. "\nDone.")
    end, underOut)
end)

---------------- Remotes (spy: what your client sends and receives; read-only)
local Spy = { Out = true, In = true, Rows = {}, Conns = {}, Pending = {} }

-- short text for an argument
local function fmtArg(v, depth)
    local t = typeof(v)
    if t == "Instance" then return v.Name end
    if t == "string" then return '"' .. (#v > 24 and (v:sub(1, 24) .. "…") or v) .. '"' end
    if t == "number" then return tostring(math.floor(v * 100 + 0.5) / 100) end
    if t == "Vector3" then return ("V3(%d,%d,%d)"):format(v.X, v.Y, v.Z) end
    if t == "CFrame" then local p = v.Position return ("CF(%d,%d,%d)"):format(p.X, p.Y, p.Z) end
    if t == "table" then
        if (depth or 0) >= 1 then return "{…}" end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n > 4 then table.insert(parts, "…") break end
            table.insert(parts, (type(k) == "string" and (k .. "=") or "") .. fmtArg(x, (depth or 0) + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end
local function fmtArgs(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, math.min(n, 5) do table.insert(parts, fmtArg((select(i, ...)))) end
    if n > 5 then table.insert(parts, "…") end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local spyRender -- set below
local spyDirty = false
local function spyLog(dir, remote, ...)
    if not App.Alive or not Spy.On then return end
    if (dir == "→" and not Spy.Out) or (dir == "←" and not Spy.In) then return end
    local key = dir .. remote:GetFullName()
    local row = Spy.Rows[key]
    if not row then
        row = { Dir = dir, Name = remote.Name, Count = 0 }
        Spy.Rows[key] = row
    end
    row.Count += 1
    row.Last = fmtArgs(...)
    row.At = os.clock()
    spyDirty = true
end

-- incoming: listen to every RemoteEvent the game has
local function watchRemote(r)
    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
        table.insert(Spy.Conns, r.OnClientEvent:Connect(function(...) spyLog("←", r, ...) end))
    end
end
local function startIncoming()
    for _, c in ipairs(Spy.Conns) do c:Disconnect() end
    table.clear(Spy.Conns)
    local rs = game:GetService("ReplicatedStorage")
    for _, d in ipairs(rs:GetDescendants()) do watchRemote(d) end
    table.insert(Spy.Conns, rs.DescendantAdded:Connect(watchRemote))
end

-- outgoing: the game's own FireServer / InvokeServer calls (needs hookmetamethod)
local namecallOriginal
local function startOutgoing()
    if namecallOriginal then return true end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" or type(newcclosure) ~= "function" then
        return false
    end
    local ok = pcall(function()
        namecallOriginal = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- IMPORTANT: no colon calls (self:Something()) in here before the original runs:
            -- they'd change the current namecall method and the game's FireServer would
            -- turn into that call instead. Only copy the call, log it later on another thread.
            if Spy.On then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance"
                    and not (type(checkcaller) == "function" and checkcaller()) and #Spy.Pending < 500 then
                    table.insert(Spy.Pending, { self, table.pack(...) })
                end
            end
            return namecallOriginal(self, ...)
        end))
    end)
    return ok and namecallOriginal ~= nil
end
local function removeSpyHook()
    if namecallOriginal then
        pcall(hookmetamethod, game, "__namecall", namecallOriginal)
        namecallOriginal = nil
    end
end

label(remotesPage, "<b>Remote spy</b>: lists the remotes your game client sends (→) and receives (←), how often, and the last arguments. Just watching — it never sends anything itself.")
local spyInfo = label(remotesPage, "")
toggle(remotesPage, "Spy on remotes", function() return Spy.On == true end, function(v)
    Spy.On = v
    if v then
        startIncoming()
        Spy.CanOut = startOutgoing()
    else
        for _, c in ipairs(Spy.Conns) do c:Disconnect() end
        table.clear(Spy.Conns)
    end
    spyInfo.Text = v and (Spy.CanOut and "Watching both ways." or "Watching ← only (this executor has no hookmetamethod, so → can't be seen).") or ""
    spyDirty = true
end)
toggle(remotesPage, "Show sent (→)", function() return Spy.Out end, function(v) Spy.Out = v end)
toggle(remotesPage, "Show received (←)", function() return Spy.In end, function(v) Spy.In = v end)
local spyOut = resultsBox(remotesPage)
spyRender = function()
    local list = {}
    for _, row in pairs(Spy.Rows) do
        if (row.Dir == "→" and Spy.Out) or (row.Dir == "←" and Spy.In) then table.insert(list, row) end
    end
    table.sort(list, function(a, b) return a.At > b.At end)
    local lines = {}
    for i = 1, math.min(#list, 25) do
        local r = list[i]
        table.insert(lines, ("%s %s ×%d\n   %s"):format(r.Dir, r.Name, r.Count, r.Last or ""))
    end
    spyOut(#lines > 0 and table.concat(lines, "\n") or (Spy.On and "(nothing yet — play a bit)" or "(spy is off)"))
end
spyRender()
button(remotesPage, "Clear", nil, function()
    table.clear(Spy.Rows)
    spyRender()
end)
button(remotesPage, "Copy list", nil, function()
    local lines = {}
    for _, row in pairs(Spy.Rows) do
        table.insert(lines, ("%s %s x%d %s"):format(row.Dir == "→" and "OUT" or "IN", row.Name, row.Count, row.Last or ""))
    end
    table.sort(lines)
    if type(setclipboard) == "function" then
        pcall(setclipboard, table.concat(lines, "\n"))
        spyInfo.Text = "Copied " .. #lines .. " lines."
    else
        spyInfo.Text = "This executor can't copy (no setclipboard)."
    end
end)
local allOut = resultsBox(remotesPage)
button(remotesPage, "List every remote in the game", nil, function()
    local names = {}
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
            table.insert(names, (d:IsA("RemoteFunction") and "F " or "E ") .. d.Name)
        end
    end
    table.sort(names)
    allOut(#names .. " remotes (E = event, F = function)\n" .. table.concat(names, "\n"))
end)
-- log the copied sends (outside the hook), redraw a few times a second at most
task.spawn(function()
    while App.Alive do
        if #Spy.Pending > 0 then
            local pending = Spy.Pending
            Spy.Pending = {}
            for _, call in ipairs(pending) do
                pcall(spyLog, "→", call[1], table.unpack(call[2], 1, call[2].n))
            end
        end
        if spyDirty then
            spyDirty = false
            spyRender()
        end
        task.wait(0.3)
    end
end)

showPage("Main")

track(LocalPlayer.CharacterAdded:Connect(function()
    stopMovers()
    noclip(false)
    refreshAll()
end))

---------------------------------------------------------------- unload
unload = function()
    if not App.Alive then return end
    App.Alive = false
    stopLab()
    removeGhostHook()
    Spy.On = false
    removeSpyHook()
    for _, c in ipairs(Spy.Conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(App.Conns) do pcall(function() c:Disconnect() end) end
    table.clear(App.Conns)
    pcall(function() gui:Destroy() end)
    if ENV.SmurfySimple == App then ENV.SmurfySimple = nil end
end
App.Unload = unload
closeButton.MouseButton1Click:Connect(unload)
