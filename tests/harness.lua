--!nocheck
-- Fake Roblox used by tests/run.sh to run SmurfySimple.lua outside Roblox.
local DEVICE = __DEVICE__ -- "phone" | "pc"
local SCREEN = DEVICE == "phone" and { 800, 360 } or { 1600, 900 }

local Heartbeats, Steps, Delayed = {}, {}, {}
local AllInstances = {}

-- signals
__errors = {}
local function resume(co, ...)
    local ok, e = coroutine.resume(co, ...)
    if not ok then table.insert(__errors, debug.traceback(co, tostring(e))) end
end
local function Signal()
    local s = { fns = {}, waiters = {} }
    function s:Connect(fn)
        local entry = { fn = fn, on = true }
        table.insert(self.fns, entry)
        return { Disconnect = function() entry.on = false end, Connected = true }
    end
    function s:Once(fn) return self:Connect(fn) end
    function s:Wait() table.insert(self.waiters, coroutine.running()); return coroutine.yield() end
    function s:Fire(...)
        for _, e in ipairs(table.clone(self.fns)) do
            if e.on then resume(coroutine.create(e.fn), ...) end
        end
        local w = self.waiters
        self.waiters = {}
        for _, co in ipairs(w) do resume(co, ...) end
    end
    return s
end

-- value types
local V2mt = {}
function V2mt.__add(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
function V2mt.__sub(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
function V2mt.__mul(a, b) if type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end if type(a) == "number" then return Vector2.new(b.X * a, b.Y * a) end return Vector2.new(a.X * b.X, a.Y * b.Y) end
function V2mt.__div(a, b) if type(b) == "number" then return Vector2.new(a.X / b, a.Y / b) end return Vector2.new(a.X / b.X, a.Y / b.Y) end
function V2mt.__eq(a, b) return a.X == b.X and a.Y == b.Y end
V2mt.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2) end
    if k == "Unit" then local m = math.sqrt(v.X ^ 2 + v.Y ^ 2); return Vector2.new(v.X / m, v.Y / m) end
end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0, __t = "Vector2" }, V2mt) end }
Vector2.zero = Vector2.new(0, 0)

local V3mt = {}
function V3mt.__add(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function V3mt.__sub(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function V3mt.__mul(a, b) if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end if type(a) == "number" then return b * a end return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
function V3mt.__div(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
function V3mt.__unm(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) end
    if k == "Unit" then local m = math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2); return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
    if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
    if k == "Lerp" then return function(a, b, t) return a + (b - a) * t end end
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __t = "Vector3" }, V3mt) end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.one = Vector3.new(1, 1, 1)

local function udim(s, o) return { Scale = s or 0, Offset = o or 0, __t = "UDim" } end
UDim = { new = udim }
UDim2 = {
    new = function(xs, xo, ys, yo) return { X = udim(xs, xo), Y = udim(ys, yo), __t = "UDim2" } end,
    fromOffset = function(x, y) return { X = udim(0, x), Y = udim(0, y), __t = "UDim2" } end,
    fromScale = function(x, y) return { X = udim(x, 0), Y = udim(y, 0), __t = "UDim2" } end,
}
Color3 = {
    new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0, __t = "Color3" } end,
    fromRGB = function(r, g, b) return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255, __t = "Color3" } end,
}
Color3.fromHSV = function() return Color3.new(1, 1, 1) end
ColorSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequence = { new = function(a, b)
    if type(a) == "table" and a.__t == nil and a[1] then return { Keypoints = a } end
    return { Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }
end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(a) return { a } end }
NumberRange = { new = function(a, b) return { Min = a, Max = b } end }
TweenInfo = { new = function() return {} end }
-- CFrame: a position, no rotation (enough for these tests)
local CFmt = {}
CFmt.__mul = function(a, b)
    if type(b) == "table" and b.__t == "Vector3" then return a.__pos + b end
    if type(b) == "table" and b.__t == "CFrame" then return CFrame.new(a.__pos + b.__pos) end
    return a
end
CFmt.__add = function(a, b) return CFrame.new(a.__pos + b) end
CFmt.__index = function(c, k)
    if k == "LookVector" then return Vector3.new(0, 0, -1) end
    if k == "RightVector" then return Vector3.new(1, 0, 0) end
    if k == "Position" or k == "p" then return c.__pos end
    if k == "X" or k == "Y" or k == "Z" then return c.__pos[k] end
    if k == "Rotation" then return CFrame.new() end
    if k == "PointToObjectSpace" then return function(self, v) return v - self.__pos end end
    if k == "PointToWorldSpace" then return function(self, v) return v + self.__pos end end
    if k == "VectorToObjectSpace" then return function(_, v) return v end end
end
CFrame = { new = function(x, y, z)
    local pos = type(x) == "table" and x or (x and Vector3.new(x, y, z)) or Vector3.zero
    return setmetatable({ __t = "CFrame", __pos = pos }, CFmt)
end }
CFrame.lookAt = function(p) return CFrame.new(p) end
CFrame.lookAlong = CFrame.lookAt
CFrame.Angles = function() return CFrame.new() end
Random = { new = function() return {
    NextNumber = function(_, a, b) a = a or 0; b = b or 1; return a + (b - a) * math.random() end,
    NextInteger = function(_, a, b) return math.random(a, b) end,
} end }
Rect = {}

-- Enum: Enum.Foo.Bar is a unique object with a Name
local enumCache = {}
Enum = setmetatable({}, { __index = function(_, group)
    enumCache[group] = enumCache[group] or setmetatable({}, { __index = function(t, item)
        local e = { Name = item, EnumType = group, __t = "EnumItem" }
        rawset(t, item, e)
        return e
    end })
    return enumCache[group]
end })

function typeof(v)
    if type(v) == "table" then
        if v.__t then return v.__t end
        if v.__inst then return "Instance" end
    end
    return type(v)
end

-- instances: store any property, unknown events are signals
local Instance_mt = {}
local function newInstance(class, name)
    local inst = { __inst = true, __props = { ClassName = class, Name = name or class }, __children = {}, __signals = {} }
    table.insert(AllInstances, inst)
    return setmetatable(inst, Instance_mt)
end
local methods = {}
function methods:IsA(c)
    local cls = self.__props.ClassName
    return cls == c or c == "GuiObject" or c == "Instance" or (c == "BasePart" and (cls == "Part" or cls == "MeshPart"))
end
function methods:GetChildren() return table.clone(self.__children) end
function methods:GetDescendants()
    local out = {}
    local function walk(i) for _, c in ipairs(i.__children) do table.insert(out, c); walk(c) end end
    walk(self)
    return out
end
function methods:FindFirstChild(n, recursive)
    for _, c in ipairs(self.__children) do if c.__props.Name == n then return c end end
    if recursive then
        for _, c in ipairs(self.__children) do local f = c:FindFirstChild(n, true); if f then return f end end
    end
    return nil
end
function methods:GetPivot() return CFrame.new(self.__pivot or Vector3.zero) end
function methods:FireServer(...) if self.__server then self.__server(...) end end
function methods:GetServerTimeNow() return os.clock() end
function methods:FindFirstChildOfClass(n) for _, c in ipairs(self.__children) do if c.__props.ClassName == n then return c end end return nil end
function methods:FindFirstChildWhichIsA(n) return self:FindFirstChildOfClass(n) end
function methods:FindFirstAncestorOfClass() return nil end
function methods:WaitForChild(n) return self:FindFirstChild(n) or newInstance("Folder", n) end
function methods:Destroy() self.Parent = nil end
function methods:Clone() return newInstance(self.__props.ClassName) end
function methods:GetPropertyChangedSignal(p) local k = "__prop_" .. p; self.__signals[k] = self.__signals[k] or Signal(); return self.__signals[k] end
function methods:GetAttribute(n) return self.__attrs and self.__attrs[n] end
function methods:GetAttributeChangedSignal(n) local k = "__attr_" .. n; self.__signals[k] = self.__signals[k] or Signal(); return self.__signals[k] end
function methods:SetAttribute(n, v)
    self.__attrs = self.__attrs or {}
    self.__attrs[n] = v
    local sig = self.__signals["__attr_" .. n]
    if sig then sig:Fire() end
end
function methods:GetFullName() return self.__props.Name end
function methods:ClearAllChildren() self.__children = {} end
Instance_mt.__index = function(self, k)
    if methods[k] then return methods[k] end
    local v = self.__props[k]
    if v ~= nil then return v end
    if self.__signals[k] then return self.__signals[k] end
    if k == "AbsoluteSize" then return self.__props.ClassName == "ScreenGui" and Vector2.new(SCREEN[1], SCREEN[2]) or Vector2.new(100, 40) end
    if k == "AbsolutePosition" then return Vector2.new(0, 0) end
    if k == "Visible" or k == "Enabled" then return true end
    if k == "Position" and self.__props.CFrame then return self.__props.CFrame.Position end -- parts
    if k == "Position" then return UDim2.new(0, 0, 0, 0) end
    if k == "Size" then return UDim2.new(0, 0, 0, 0) end
    if k == "Rotation" or k == "Scale" or k == "BackgroundTransparency" or k == "TextTransparency" or k == "Transparency" then return 0 end
    if k == "BackgroundColor3" or k == "TextColor3" or k == "Color" or k == "ImageColor3" or k == "ScrollBarImageColor3" then return Color3.new(0, 0, 0) end
    if k == "Text" then return "" end
    -- events
    if k:match("^[A-Z]") and (k:match("Changed$") or k:match("Began$") or k:match("Ended$") or k:match("Click$") or k:match("Enter$")
        or k:match("Leave$") or k:match("Added$") or k:match("Removing$") or k:match("Activated$") or k:match("Down$") or k:match("Up$")
        or k:match("Triggered$") or k:match("Completed$") or k:match("Idled$") or k:match("Failed$") or k:match("Shown$") or k:match("Hidden$") or k == "JumpRequest" or k == "Chatted" or k == "OnClientEvent") then
        self.__signals[k] = self.__signals[k] or Signal()
        return self.__signals[k]
    end
    return nil
end
Instance_mt.__newindex = function(self, k, v)
    if k == "Parent" then
        local old = self.__props.Parent
        if old then for i, c in ipairs(old.__children) do if c == self then table.remove(old.__children, i) break end end end
        if v then table.insert(v.__children, self) end
    end
    if v ~= nil and type(v) == "table" and v.__t == "EnumItem" and k:match("Color") then error("bad enum for " .. k) end
    self.__props[k] = v
end
Instance = { new = function(class, parent) local i = newInstance(class); if parent then i.Parent = parent end return i end }

-- services
local Services = {}
local function service(name, extra)
    local s = newInstance(name, name)
    for k, v in pairs(extra or {}) do s.__props[k] = v end
    Services[name] = s
    return s
end
local UIS = service("UserInputService", {
    TouchEnabled = DEVICE == "phone", KeyboardEnabled = DEVICE ~= "phone", MouseEnabled = DEVICE ~= "phone",
})
methods.GetPlatform = function() return DEVICE == "phone" and Enum.Platform.Android or Enum.Platform.Windows end
methods.GetFocusedTextBox = function() return nil end
methods.IsKeyDown = function() return false end
methods.GetGuiInset = function() return Vector2.new(0, 58), Vector2.new(0, 0) end
methods.Create = function(_, obj, info, props)
    for k, v in pairs(props) do obj[k] = v end
    local c = Signal()
    return { Play = function() end, Cancel = function() end, Completed = c }
end
methods.GetUserThumbnailAsync = function() return "rbxthumb://" end
methods.GetService = function(_, n) return Services[n] or service(n) end
methods.HttpGet = function() return "{}" end
methods.JSONEncode = function() return "{}" end
methods.JSONDecode = function() return {} end
methods.GenerateGUID = function() return "guid" end
request = function(t) print("  request ->", t.Url, t.Body) return {} end
methods.GetPlayers = function() return {} end
methods.GetMouse = function() return newInstance("Mouse") end
methods.CaptureController = function() end
methods.ClickButton2 = function() end
methods.ChangeState = function() end
service("GuiService", { TopbarInset = { Min = Vector2.new(140, 0), Width = 600, Height = 58, __t = "Rect" } })
service("RunService", {})
service("TweenService")
service("HttpService")
service("CoreGui")
service("Lighting")
service("ReplicatedStorage")
service("TeleportService")
service("VirtualUser")
local Players = service("Players")
local lp = newInstance("Player", "Tester")
lp.__props.DisplayName = "Tester"; lp.__props.UserId = 1
lp.Parent = Players
Players.__props.LocalPlayer = lp
local pg = newInstance("PlayerGui", "PlayerGui"); pg.Parent = lp

workspace = newInstance("Workspace", "Workspace")
local cam = newInstance("Camera", "Camera")
cam.__props.ViewportSize = Vector2.new(SCREEN[1], SCREEN[2])
cam.__props.CFrame = CFrame.new()
workspace.__props.CurrentCamera = cam
game = newInstance("DataModel", "Game")
game.__props.PlaceId = 1; game.__props.JobId = "x"
Services.Workspace = workspace

-- RunService events collect callbacks so we can tick them
local rs = Services.RunService
rs.__signals.Heartbeat = Signal(); rs.__signals.RenderStepped = Signal(); rs.__signals.Stepped = Signal()

-- task library
-- task: a real scheduler on the fake clock (__runFrames moves time forward)
local Sleeping = {}
task = {
    spawn = function(f, ...)
        local co = type(f) == "thread" and f or coroutine.create(f)
        resume(co, ...)
        return co
    end,
    -- like Roblox: defer / delay return the thread (task.cancel can stop it)
    defer = function(f, ...)
        local co = type(f) == "thread" and f or coroutine.create(f)
        table.insert(Delayed, { co, { ... } })
        return co
    end,
    delay = function(t, f, ...)
        local args = { ... }
        local co = type(f) == "thread" and f or coroutine.create(function() f(table.unpack(args)) end)
        table.insert(Sleeping, { co, os.clock() + (t or 0) })
        return co
    end,
    wait = function(t)
        table.insert(Sleeping, { coroutine.running(), os.clock() + (t or 0) })
        local started = os.clock()
        coroutine.yield()
        return os.clock() - started
    end,
    cancel = function(co)
        if type(co) == "thread" and coroutine.status(co) == "suspended" then pcall(coroutine.close, co) end
    end,
}
-- Roblox / executor bits that obfuscators (Luraph) check for at load
Path2DControlPoint = { new = function(...) return { __args = { ... } } end }
identifyexecutor = identifyexecutor or function() return "Delta", "test" end
iscclosure = iscclosure or function(f) return debug.info(f, "s") == "[C]" end
islclosure = islclosure or function(f) return debug.info(f, "s") ~= "[C]" end
wait = task.wait
spawn = task.spawn
delay = task.delay
tick = os.clock
warn = function(...) print("WARN", ...) end
local __genv = {}
getgenv = function() return __genv end

local __clock = 0
local __os = os
os = setmetatable({ clock = function() return __clock end }, { __index = __os })
function __runFrames(n)
    for _ = 1, n do
        __clock += 1 / 60
        local d = Delayed; Delayed = {}
        for _, item in ipairs(d) do
            if coroutine.status(item[1]) == "suspended" then resume(item[1], table.unpack(item[2])) end
        end
        local due = {}
        for i = #Sleeping, 1, -1 do
            if Sleeping[i][2] <= __clock then table.insert(due, 1, table.remove(Sleeping, i)) end
        end
        for _, item in ipairs(due) do
            if coroutine.status(item[1]) == "suspended" then resume(item[1]) end
        end
        rs.__signals.Heartbeat:Fire(1 / 60)
        rs.__signals.RenderStepped:Fire(1 / 60)
        rs.__signals.Stepped:Fire(0, 1 / 60)
    end
end
function __find(name)
    for _, i in ipairs(AllInstances) do if i.__props.Name == name then return i end end
end
function __findText(text)
    for _, i in ipairs(AllInstances) do if i.__props.Text == text and i.__props.ClassName == "TextButton" then return i end end
end
__UIS = UIS
__Signal = Signal

function __all() return AllInstances end

-- __flytest: a character and Roblox's control module
local char = newInstance("Model", "Tester")
local hum = newInstance("Humanoid", "Humanoid"); hum.__props.WalkSpeed = 16; hum.__props.Health = 100; hum.__props.JumpPower = 50; hum.__props.JumpHeight = 7.2; hum.__props.UseJumpPower = true
hum.__props.MoveDirection = Vector3.zero; hum.__props.Jump = false
hum.Parent = char
local root = newInstance("Part", "HumanoidRootPart"); root.__props.CFrame = CFrame.new(); root.Parent = char
lp.__props.Character = char
local ps = newInstance("PlayerScripts", "PlayerScripts"); ps.Parent = lp
local pm = newInstance("ModuleScript", "PlayerModule"); pm.Parent = ps
__stick = Vector3.new(0, 0, -1)
require = function(m)
    if m == pm then
        return { GetControls = function() return {
            GetMoveVector = function() return __stick end,
            activeController = { GetIsJumping = function() return false end },
        } end }
    end
    error("no require")
end
__root = root
