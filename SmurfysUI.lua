--[[
    Smurfy's UI  v1.0  ·  Break & Steal an Egg
    ------------------------------------------------------------
    - Farm tab: breaks eggs, grabs the animals that drop, brings them
      home and places them in your pen. Base / Auto tabs: selling,
      upgrades, better pickaxes and trails, rewards.
    - Works on PC, tablet and phone. The device is detected on load
      (Settings > Device can force a layout).
    - PC: drag the window by the top bar, keybinds in Settings,
      click the logo to minimize (an S button + FPS / ping shows while minimized)
      Defaults: Menu = RightShift, Fly = Q
    - Phone / tablet: tap the round S button to open and close the menu
      (drag it to move it). The Buttons tab puts Fly, Noclip and more on
      the screen, and flying gets Up / Down buttons next to jump.
    - Clicks never pass through to game UI behind the menu
    - Always drawn on top of other UIs
]]

-- ========================= CONFIG =========================
local CONFIG = {
    Title       = "Smurfy's",
    Version     = "v1.0",
    DiscordLink = "https://discord.gg/5KFN8bbXhW",
    MenuKey     = Enum.KeyCode.RightShift,
    FlyKey      = Enum.KeyCode.Q,
}

local Theme = {
    BgDeep      = Color3.fromRGB(4, 7, 16),
    BgMid       = Color3.fromRGB(10, 19, 46),
    BgBlue      = Color3.fromRGB(26, 62, 150),
    Sidebar     = Color3.fromRGB(6, 9, 20),
    Panel       = Color3.fromRGB(15, 21, 42),
    PanelHover  = Color3.fromRGB(25, 36, 72),
    Field       = Color3.fromRGB(8, 12, 26),
    Accent      = Color3.fromRGB(45, 125, 255),
    AccentLight = Color3.fromRGB(130, 185, 255),
    AccentDark  = Color3.fromRGB(20, 58, 160),
    Text        = Color3.fromRGB(255, 255, 255),
    SubText     = Color3.fromRGB(155, 170, 205),
    TabText     = Color3.fromRGB(215, 226, 248),
    Stroke      = Color3.fromRGB(48, 74, 135),
}
local ThemeDefaults = table.clone(Theme)

-- ========================= SERVICES =========================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")
local GuiService       = game:GetService("GuiService")
local LocalPlayer      = Players.LocalPlayer

-- ========================= STATE =========================
local Binds       = { Menu = CONFIG.MenuKey, Fly = CONFIG.FlyKey }
local PendingBind = nil
local IsOpen      = true
local NotifsOn    = true
local EffectsOn   = true
local Connections = {}
local Alive       = true -- false after unload; loops check this instead of ScreenGui.Parent
local flyToggle   -- assigned when the Player tab is built
-- touch controls (open button, on-screen buttons) fill this in on phones / tablets
local Mobile      = { FlyUp = false, FlyDown = false, Targets = {} }

-- running the script again unloads the copy that is already running
local GlobalEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(GlobalEnv.SmurfysUnload) == "function" then pcall(GlobalEnv.SmurfysUnload) end

-- ========================= SETTINGS FILE =========================
local SETTINGS_FILE = "SmurfysUI_BreakStealEgg.json"
local SavedSettings = {}
pcall(function()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(SETTINGS_FILE) then
        local data = HttpService:JSONDecode(readfile(SETTINGS_FILE))
        if type(data) == "table" then SavedSettings = data end
    end
end)

local function saveSettings()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode(SavedSettings))
    end)
end

-- toggles, sliders and keybinds remember their value (key = "Tab/Text")
local saveQueued = false
local function queueSave()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.5, function()
        saveQueued = false
        saveSettings()
    end)
end

-- every toggle / slider / keybind registers how to put itself back to default
local DefaultResetters = {}

local function savedValue(tab, text)
    local store = SavedSettings.Values
    return type(store) == "table" and store[tab.Name .. "/" .. text] or nil
end

local function storeValue(tab, text, value)
    if type(SavedSettings.Values) ~= "table" then SavedSettings.Values = {} end
    SavedSettings.Values[tab.Name .. "/" .. text] = value
    queueSave()
end

-- ========================= HELPERS =========================
-- big sections run inside their own function: Roblox allows at most 200
-- local variables alive at once in one function, and the main script is
-- already close to that on its own
local function isolate(build) build() end

local function track(conn)
    table.insert(Connections, conn)
    return conn
end

local function create(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(r) return create("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end
local function round() return create("UICorner", { CornerRadius = UDim.new(1, 0) }) end

local function stroke(color, thickness, transparency)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function padding(t, b, l, r)
    return create("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
    })
end

local function gradient(c0, c1, rotation)
    return create("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 0 })
end

local function tween(obj, time, props, style, dir)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

-- a number attribute, or the default. (Never tonumber(inst:GetAttribute(...))
-- directly: in the obfuscated build a missing attribute can arrive as no
-- argument at all, and tonumber() then errors.) Stored on Mobile, not as a
-- new local: the main chunk is near Lua's local-variable limits.
function Mobile.AttrNumber(inst, name, default)
    local value = inst:GetAttribute(name)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) or default end
    return default
end

local function clampNum(v, lo, hi)
    hi = math.max(lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

-- height of Roblox's top bar (the menu / chat buttons)
local function topInset()
    local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
    return ok and inset and inset.Y or 36
end

-- ========================= DEVICE =========================
-- "PC", "Tablet" or "Phone". Touch devices get the open button, on-screen
-- buttons and bigger controls instead of keybinds.
local function detectDevice()
    local mobilePlatform = false
    pcall(function()
        local platform = UserInputService:GetPlatform()
        mobilePlatform = platform == Enum.Platform.Android or platform == Enum.Platform.IOS
    end)
    local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    if not mobilePlatform and not touchOnly then return "PC" end
    local vp = viewport()
    return math.min(vp.X, vp.Y) < 500 and "Phone" or "Tablet"
end

-- Settings > Device can force a layout when detection picks the wrong one
local DeviceModes = { Auto = true, PC = true, Tablet = true, Phone = true }
local DeviceMode = DeviceModes[SavedSettings.DeviceMode] and SavedSettings.DeviceMode or "Auto"
local Device = DeviceMode == "Auto" and detectDevice() or DeviceMode
local IsTouch = Device ~= "PC"

-- bigger rows and switches for fingers
local UISize = IsTouch
    and { Row = 40, Slider = 58, Chip = 38, Text = 13, SwitchW = 44, SwitchH = 24, Knob = 18 }
    or { Row = 38, Slider = 54, Chip = 34, Text = 13, SwitchW = 40, SwitchH = 20, Knob = 16 }

local TOPBAR_H  = Device == "Phone" and 38 or 46
local SIDEBAR_W = Device == "Phone" and 52 or 150 -- phones show tab icons only
local HEADER_H  = Device == "Phone" and 36 or 56  -- page title (+ description on bigger screens)

local function windowSizeFor(vp)
    if Device == "Phone" then -- most of the screen, under Roblox's top bar, leaving the edges free
        return Vector2.new(math.min(vp.X * 0.78, 600), math.max(200, math.min(vp.Y - topInset() - 28, 320)))
    elseif Device == "Tablet" then
        return Vector2.new(math.min(580, vp.X - 24), math.min(400, vp.Y - topInset() - 24))
    end
    return Vector2.new(600, 400)
end
local WINDOW_SIZE = windowSizeFor(viewport())

-- ========================= SCREEN GUI =========================
local ScreenGui = create("ScreenGui", {
    Name = "SmurfysUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999999999, -- always above other ScreenGuis
})

pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
end)

do
    local targets = {}
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then table.insert(targets, h) end
    end
    table.insert(targets, CoreGui)
    table.insert(targets, LocalPlayer:WaitForChild("PlayerGui"))

    for _, target in ipairs(targets) do
        local ok = pcall(function()
            local old = target:FindFirstChild(ScreenGui.Name)
            if old then old:Destroy() end
            ScreenGui.Parent = target
        end)
        if ok and ScreenGui.Parent == target then break end
    end
end

-- ========================= WINDOW =========================
local vp = viewport()
local Holder = create("Frame", {
    Name = "Holder",
    Parent = ScreenGui,
    AnchorPoint = Vector2.new(0.5, 0),
    -- touch screens keep the window under Roblox's top bar buttons
    Position = UDim2.fromOffset(vp.X / 2, math.max(IsTouch and topInset() + 6 or 0, vp.Y / 2 - WINDOW_SIZE.Y / 2)),
    Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
    BackgroundTransparency = 1,
})
local WindowScale = create("UIScale", { Parent = Holder, Scale = 0 })

-- soft rounded shadow: stacked rounded frames that fade outwards
for i = 1, 8 do
    create("Frame", {
        Name = "Shadow",
        Parent = Holder,
        ZIndex = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 4),
        Size = UDim2.new(1, i * 4, 1, i * 4),
        BackgroundColor3 = Color3.fromRGB(0, 6, 24),
        BackgroundTransparency = 0.86 + i * 0.015,
        BorderSizePixel = 0,
    }, { corner(12 + i * 2) })
end

-- animated glowing border
local MainStroke = stroke(Color3.new(1, 1, 1), 1.5, 0.1)
local StrokeGradient = create("UIGradient", {
    Parent = MainStroke,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentDark),
        ColorSequenceKeypoint.new(0.5, Theme.AccentLight),
        ColorSequenceKeypoint.new(1, Theme.AccentDark),
    }),
})

local Main = create("Frame", {
    Name = "Main",
    Parent = Holder,
    Active = true, -- sinks input so clicks don't reach the game
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, { corner(12), MainStroke })

-- animated background gradient
local BgGradient = create("UIGradient", {
    Parent = Main,
    Rotation = 125,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.BgDeep),
        ColorSequenceKeypoint.new(0.55, Theme.BgMid),
        ColorSequenceKeypoint.new(1, Theme.BgBlue),
    }),
})

-- invisible button covering the whole window: eats every click that
-- doesn't hit one of our own controls, so nothing behind gets clicked
create("TextButton", {
    Name = "InputBlocker",
    Parent = Main,
    ZIndex = 1,
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    Selectable = false,
})

-- ========================= STARS =========================
local StarLayer = create("Frame", {
    Name = "Stars",
    Parent = Main,
    ZIndex = 1,
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
})

local rng = Random.new()
local Stars = {}

for _ = 1, 60 do
    local roll = rng:NextNumber()
    local size = roll < 0.25 and 3 or 2
    local obj = create("Frame", {
        Parent = StarLayer,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = rng:NextNumber() < 0.35 and Theme.AccentLight or Theme.Text,
        BorderSizePixel = 0,
    }, { round() })
    table.insert(Stars, {
        Obj = obj,
        X = rng:NextNumber(), Y = rng:NextNumber(),
        Speed = rng:NextNumber(0.003, 0.01) * size,
        Phase = rng:NextNumber(0, math.pi * 2),
        Rate = rng:NextNumber(0.8, 2.6),
        Min = rng:NextNumber(0.1, 0.4),
    })
end

local function shootingStar()
    local startX = rng:NextNumber(0.05, 0.6)
    local s = create("Frame", {
        Parent = StarLayer,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(startX, -0.05),
        Size = UDim2.fromOffset(90, 2),
        Rotation = 39,
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
    }, {
        round(),
        create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
        }),
    })
    local t = tween(s, 1.2, {
        Position = UDim2.fromScale(startX + 0.45, 0.5),
        BackgroundTransparency = 1,
    }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    t.Completed:Connect(function() s:Destroy() end)
end

local nextShoot = os.clock() + 2
track(RunService.Heartbeat:Connect(function(dt)
    if not Holder.Visible then return end
    local t = os.clock()

    BgGradient.Rotation = 125 + math.sin(t * 0.25) * 30
    StrokeGradient.Rotation = (t * 45) % 360

    if not EffectsOn then return end

    for _, s in ipairs(Stars) do
        s.X = s.X + s.Speed * dt
        if s.X > 1.02 then
            s.X = -0.02
            s.Y = rng:NextNumber()
        end
        s.Obj.Position = UDim2.fromScale(s.X, s.Y)
        local a = 0.5 + 0.5 * math.sin(t * s.Rate + s.Phase)
        s.Obj.BackgroundTransparency = 1 - (s.Min + (1 - s.Min) * a) * 0.9
    end

    if t >= nextShoot then
        nextShoot = t + rng:NextNumber(3, 7)
        shootingStar()
    end
end))

-- ========================= TOP BAR =========================
local TopBar = create("Frame", {
    Name = "TopBar",
    Parent = Main,
    ZIndex = 3,
    Size = UDim2.new(1, 0, 0, TOPBAR_H),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, { corner(12), gradient(Theme.AccentDark, Theme.Accent) })

create("Frame", { -- squares off the bottom corners of the top bar
    Parent = TopBar,
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(1, 0, 0, 12),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, { gradient(Theme.AccentDark, Theme.Accent) })

create("Frame", { -- soft highlight line under the bar
    Parent = Main,
    ZIndex = 3,
    Position = UDim2.fromOffset(0, TOPBAR_H),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Theme.AccentLight,
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
})

local TitleRow = create("Frame", {
    Parent = TopBar,
    ZIndex = 2,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(10, 0),
    Size = UDim2.new(1, -200, 1, 0),
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

-- logo: glossy rounded "S" tile with a spinning light ring
local LogoRing = stroke(Color3.new(1, 1, 1), 1.5, 0)
local LogoRingGradient = create("UIGradient", {
    Parent = LogoRing,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentDark),
        ColorSequenceKeypoint.new(0.5, Theme.Text),
        ColorSequenceKeypoint.new(1, Theme.AccentDark),
    }),
})

local Logo = create("Frame", {
    Parent = TitleRow,
    LayoutOrder = 1,
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = Color3.new(1, 1, 1),
}, {
    corner(9),
    LogoRing,
    create("UIGradient", {
        Rotation = 135,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.AccentLight),
            ColorSequenceKeypoint.new(0.45, Theme.Accent),
            ColorSequenceKeypoint.new(1, Theme.BgDeep),
        }),
    }),
})

create("Frame", { -- glass shine on the top half
    Parent = Logo,
    Size = UDim2.fromScale(1, 0.5),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, {
    corner(9),
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(0.35, 1),
    }),
})

create("TextLabel", { -- drop shadow
    Parent = Logo,
    Size = UDim2.fromScale(1, 1),
    Position = UDim2.fromOffset(0, 1.5),
    BackgroundTransparency = 1,
    Text = "S",
    Font = Enum.Font.FredokaOne,
    TextSize = 21,
    TextColor3 = Theme.BgDeep,
    TextTransparency = 0.35,
})
create("TextLabel", {
    Parent = Logo,
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "S",
    Font = Enum.Font.FredokaOne,
    TextSize = 21,
    TextColor3 = Theme.Text,
})

track(RunService.Heartbeat:Connect(function()
    if not Holder.Visible then return end
    local t = os.clock()
    LogoRingGradient.Rotation = (t * 90) % 360
end))

create("TextLabel", {
    Parent = TitleRow,
    LayoutOrder = 2,
    BackgroundTransparency = 1,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 30),
    Text = CONFIG.Title,
    Font = Enum.Font.GothamBlack,
    TextSize = 19,
    TextColor3 = Theme.Text,
})

create("TextLabel", {
    Parent = TitleRow,
    LayoutOrder = 3,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 18),
    BackgroundColor3 = Theme.Text,
    BackgroundTransparency = 0.85,
    Text = "✨ " .. CONFIG.Version,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = Theme.Text,
}, { corner(9), padding(0, 0, 7, 7) })

-- right side of the top bar (PC): FPS / ping, then the menu key.
-- Touch screens get a close button here instead.
local Perf = { Labels = {} } -- every label that shows FPS / ping
Perf.Row = create("Frame", {
    Parent = TopBar,
    Visible = not IsTouch,
    ZIndex = 2,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 22),
    BackgroundTransparency = 1,
}, {
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

table.insert(Perf.Labels, create("TextLabel", {
    Parent = Perf.Row,
    LayoutOrder = 1,
    ZIndex = 2,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 22),
    BackgroundColor3 = Theme.BgDeep,
    BackgroundTransparency = 0.6,
    RichText = true,
    Text = "",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = Theme.Text,
}, { corner(11), padding(0, 0, 9, 9) }))

local KeyPill = create("TextLabel", {
    Parent = Perf.Row,
    LayoutOrder = 2,
    ZIndex = 2,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 22),
    BackgroundColor3 = Theme.BgDeep,
    BackgroundTransparency = 0.6,
    Text = "⌨️ " .. Binds.Menu.Name,
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = Theme.Text,
}, { corner(11), padding(0, 0, 9, 9) })

-- FPS is counted from frames drawn; ping comes from Roblox's network stats
do
    local frames, last = 0, os.clock()
    local function colored(value, good, okay, lowIsGood)
        local better = lowIsGood and value <= good or not lowIsGood and value >= good
        local fine = lowIsGood and value <= okay or not lowIsGood and value >= okay
        local hex = better and "#50E17D" or fine and "#FFD24A" or "#FF5A5A"
        return string.format('<font color="%s">%d</font>', hex, value)
    end
    track(RunService.Heartbeat:Connect(function()
        frames += 1
        local now = os.clock()
        if now - last < 0.5 then return end
        local fps = math.floor(frames / (now - last) + 0.5)
        frames, last = 0, now

        local ping
        pcall(function() ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
        if type(ping) ~= "number" then
            pcall(function() ping = LocalPlayer:GetNetworkPing() * 1000 end)
        end
        local text = colored(fps, 50, 30, false) .. " FPS"
        if type(ping) == "number" then
            text ..= "  ·  " .. colored(math.floor(ping + 0.5), 100, 200, true) .. " ms"
        end
        for _, label in ipairs(Perf.Labels) do
            if label.Visible then label.Text = text end
        end
    end))
end

-- ========================= SIDEBAR =========================
local Sidebar = create("Frame", {
    Name = "Sidebar",
    Parent = Main,
    ZIndex = 2,
    Active = true,
    Position = UDim2.fromOffset(10, TOPBAR_H + 10),
    Size = UDim2.new(0, SIDEBAR_W, 1, -(TOPBAR_H + 20)),
    BackgroundColor3 = Theme.Sidebar,
    BackgroundTransparency = 0.35,
}, { corner(10), stroke(Theme.Stroke, 1, 0.5) })

local TabList = create("ScrollingFrame", {
    Parent = Sidebar,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 1, Device == "Phone" and 0 or -70),
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 0,
}, {
    create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
    padding(8, 8, 8, 8),
})

local UserCard = create("Frame", {
    Parent = Sidebar,
    Visible = Device ~= "Phone", -- no room in the icon-only sidebar
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -8),
    Size = UDim2.new(1, -16, 0, 54),
    BackgroundColor3 = Theme.Panel,
    BackgroundTransparency = 0.2,
}, { corner(8), stroke(Theme.Stroke, 1, 0.5) })

local Avatar = create("ImageLabel", {
    Parent = UserCard,
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 7, 0.5, 0),
    Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = Theme.AccentDark,
}, { round(), stroke(Theme.Accent, 1, 0.3) })

task.spawn(function()
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
    if ok and img then Avatar.Image = img end
end)

create("TextLabel", {
    Parent = UserCard, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(41, 6), Size = UDim2.new(1, -46, 0, 16),
    Text = LocalPlayer.DisplayName, Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
create("TextLabel", {
    Parent = UserCard, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(41, 21), Size = UDim2.new(1, -46, 0, 14),
    Text = "@" .. LocalPlayer.Name, Font = Enum.Font.Gotham, TextSize = 10,
    TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})

-- session timer (green)
local SessionLabel = create("TextLabel", {
    Parent = UserCard, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(41, 36), Size = UDim2.new(1, -46, 0, 12),
    Text = "● 00:00:00", Font = Enum.Font.GothamBold, TextSize = 10,
    TextColor3 = Color3.fromRGB(80, 225, 125), TextXAlignment = Enum.TextXAlignment.Left,
})
local SessionStart = os.clock()
task.spawn(function()
    while Alive do
        local t = math.floor(os.clock() - SessionStart)
        SessionLabel.Text = string.format("● %02d:%02d:%02d", math.floor(t / 3600), math.floor((t % 3600) / 60), t % 60)
        task.wait(1)
    end
end)

-- ========================= CONTENT AREA =========================
local Content = create("Frame", {
    Parent = Main,
    ZIndex = 2,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(SIDEBAR_W + 20, TOPBAR_H + 10),
    Size = UDim2.new(1, -(SIDEBAR_W + 30), 1, -(TOPBAR_H + 20)),
})

local PageTitle = create("TextLabel", {
    Parent = Content, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -8, 0, 24),
    Text = "", Font = Enum.Font.GothamBold, TextSize = 19,
    TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
})
local PageDesc = create("TextLabel", {
    Parent = Content, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(4, 24), Size = UDim2.new(1, -8, 0, 16),
    Visible = Device ~= "Phone",
    Text = "", Font = Enum.Font.Gotham, TextSize = 12,
    TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
})
create("Frame", {
    Parent = Content, BorderSizePixel = 0,
    Position = UDim2.fromOffset(4, HEADER_H - 8), Size = UDim2.new(1, -8, 0, 1),
    BackgroundColor3 = Theme.Accent,
}, {
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }),
})

local Pages = create("Frame", {
    Parent = Content, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, HEADER_H), Size = UDim2.new(1, 0, 1, -HEADER_H),
})

-- ========================= NOTIFICATIONS =========================
-- PC: bottom right. Touch: top center, where it doesn't cover the
-- thumbstick, the jump button or the game's own side buttons.
local NotifyHolder = create("Frame", {
    Parent = ScreenGui,
    BackgroundTransparency = 1,
    AnchorPoint = IsTouch and Vector2.new(0.5, 0) or Vector2.new(1, 1),
    Position = IsTouch and UDim2.new(0.5, 0, 0, topInset() + 8) or UDim2.new(1, -16, 1, -16),
    Size = IsTouch and UDim2.fromOffset(250, 300) or UDim2.fromOffset(270, 400),
}, {
    create("UIListLayout", {
        VerticalAlignment = IsTouch and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local function buildNotify(title, text, duration)
    -- slides in from the right on PC, drops down from the top on touch
    local hidden = IsTouch and UDim2.fromOffset(0, -(topInset() + 80)) or UDim2.fromOffset(310, 0)
    local wrap = create("Frame", { Parent = NotifyHolder, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, IsTouch and 58 or 64) })
    local card = create("Frame", {
        Parent = wrap,
        Active = true,
        Position = hidden,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, { corner(10), stroke(Theme.Accent, 1, 0.35), gradient(Theme.BgDeep, Theme.BgMid, 0) })

    create("Frame", {
        Parent = card, Position = UDim2.fromOffset(10, 12), Size = UDim2.new(0, 3, 1, -24),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
    }, { corner(2) })
    create("TextLabel", {
        Parent = card, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 10), Size = UDim2.new(1, -32, 0, 18),
        Text = title, Font = Enum.Font.GothamBold, TextSize = IsTouch and 13 or 14,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    })
    create("TextLabel", {
        Parent = card, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 30), Size = UDim2.new(1, -32, 0, IsTouch and 20 or 24),
        Text = text, Font = Enum.Font.Gotham, TextSize = IsTouch and 11 or 12, TextWrapped = true,
        TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local bar = create("Frame", {
        Parent = card, BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 1, -4), Size = UDim2.new(1, -20, 0, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, { round(), gradient(Theme.AccentDark, Theme.AccentLight) })

    tween(card, 0.4, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
    tween(bar, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
    task.delay(duration, function()
        local t = tween(card, 0.3, { Position = hidden }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        t.Completed:Wait()
        wrap:Destroy()
    end)
end

-- worker threads can lose access to our GUI after calling game code, so they
-- only queue notifications and this connection (made here) builds them
local NotifyQueue = {}
local function notify(title, text, duration)
    if not NotifsOn then return end
    table.insert(NotifyQueue, { title, text, duration or 3 })
end
track(RunService.Heartbeat:Connect(function()
    while #NotifyQueue > 0 do
        local n = table.remove(NotifyQueue, 1)
        pcall(buildNotify, n[1], n[2], n[3])
    end
end))

-- ========================= TABS =========================
local Tabs = {}
local ActiveTab
local TabMethods = {}
TabMethods.__index = TabMethods

local function selectTab(tab)
    if ActiveTab == tab then return end
    for _, t in ipairs(Tabs) do
        local on = (t == tab)
        t.Page.Visible = on
        tween(t.TabButton, 0.2, {
            BackgroundColor3 = on and Theme.Accent or Theme.Panel,
            BackgroundTransparency = on and 0 or 0.35,
            TextColor3 = on and Theme.Text or Theme.TabText,
        })
        tween(t.Stroke, 0.2, {
            Color = on and Theme.Text or Theme.AccentLight,
            Transparency = on and 0.4 or 0.65,
        })
        tween(t.Indicator, 0.2, { Size = UDim2.fromOffset(3, on and 18 or 0) })
    end
    ActiveTab = tab

    PageTitle.Text = tab.Icon .. "  " .. tab.Name
    PageDesc.Text = tab.Desc
    PageTitle.TextTransparency, PageDesc.TextTransparency = 1, 1
    tween(PageTitle, 0.3, { TextTransparency = 0 })
    tween(PageDesc, 0.3, { TextTransparency = 0 })

    tab.Page.Position = UDim2.fromOffset(0, 10)
    tween(tab.Page, 0.25, { Position = UDim2.fromOffset(0, 0) })
end

local function createTab(name, icon, desc)
    local tab = setmetatable({ Order = 0, Name = name, Icon = icon, Desc = desc or "" }, TabMethods)

    local iconOnly = Device == "Phone"
    tab.TabButton = create("TextButton", {
        Parent = TabList,
        LayoutOrder = #Tabs + 1,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, IsTouch and 36 or 34),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.35,
        Text = iconOnly and icon or (icon .. "   " .. name),
        Font = Enum.Font.GothamMedium,
        TextSize = iconOnly and 16 or 13,
        TextColor3 = Theme.TabText,
        TextXAlignment = iconOnly and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
    }, { corner(8), padding(0, 0, iconOnly and 0 or 14, 0) })

    tab.Stroke = stroke(Theme.AccentLight, 1, 0.65)
    tab.Stroke.Parent = tab.TabButton

    tab.Indicator = create("Frame", {
        Parent = tab.TabButton,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, iconOnly and 3 or -8, 0.5, 0),
        Size = UDim2.fromOffset(3, 0),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
    }, { corner(2) })

    tab.Page = create("ScrollingFrame", {
        Parent = Pages,
        Visible = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Accent,
    }, {
        create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }),
        padding(2, 10, 2, 10),
    })

    -- touch screens fire MouseEnter on tap without a matching MouseLeave, so no hover there
    if not IsTouch then
        tab.TabButton.MouseEnter:Connect(function()
            if ActiveTab ~= tab then tween(tab.TabButton, 0.15, { BackgroundColor3 = Theme.PanelHover, BackgroundTransparency = 0.1 }) end
        end)
        tab.TabButton.MouseLeave:Connect(function()
            if ActiveTab ~= tab then tween(tab.TabButton, 0.15, { BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.35 }) end
        end)
    end
    tab.TabButton.MouseButton1Click:Connect(function() selectTab(tab) end)

    table.insert(Tabs, tab)
    if not ActiveTab then selectTab(tab) end
    return tab
end

-- ========================= ELEMENTS =========================
local function nextOrder(tab)
    tab.Order = tab.Order + 1
    return tab.Order
end

local function baseElement(tab, height)
    return create("Frame", {
        Parent = tab.Page,
        LayoutOrder = nextOrder(tab),
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.25,
    }, { corner(8), stroke(Theme.Stroke, 1, 0.55) })
end

local function clickArea(parent, text)
    return create("TextButton", {
        Parent = parent,
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        Text = text,
        Font = Enum.Font.GothamMedium,
        TextSize = UISize.Text,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, { padding(0, 0, 12, 12) })
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- PC: highlight on hover. Touch: highlight while the finger is down.
local function addHover(trigger, target)
    if IsTouch then
        trigger.InputBegan:Connect(function(input)
            if isPress(input) then tween(target, 0.08, { BackgroundColor3 = Theme.PanelHover }) end
        end)
        trigger.InputEnded:Connect(function(input)
            if isPress(input) then tween(target, 0.25, { BackgroundColor3 = Theme.Panel }) end
        end)
        return
    end
    trigger.MouseEnter:Connect(function() tween(target, 0.15, { BackgroundColor3 = Theme.PanelHover }) end)
    trigger.MouseLeave:Connect(function() tween(target, 0.15, { BackgroundColor3 = Theme.Panel }) end)
end

function TabMethods:Section(text)
    create("TextLabel", {
        Parent = self.Page,
        LayoutOrder = nextOrder(self),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.AccentLight,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Bottom,
    })
end

-- a dropdown: a field you tap to open a scrollable list under it. Returns a
-- group that takes the same elements as a tab (group:Button(...),
-- group:Label(...)) plus group:Option(text, callback) for compact list items.
-- It remembers whether you left it open. group.SetTitle(text) changes the field.
function TabMethods:Dropdown(title, defaultOpen)
    local key = "▾ " .. title
    local open = savedValue(self, key)
    if open == nil then open = defaultOpen == true end
    local maxHeight = IsTouch and 230 or 260

    local field = baseElement(self, UISize.Row) -- looks like every other button
    local btn = clickArea(field, title)
    -- the same "›" as buttons, turned to point down (closed) or up (open)
    local chevron = create("TextLabel", {
        Parent = btn,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Text = "›",
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = Theme.AccentLight,
        Rotation = 90,
    })
    addHover(btn, field)

    local list = create("ScrollingFrame", {
        Name = "DropdownList",
        Parent = self.Page,
        LayoutOrder = nextOrder(self),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = Theme.Field,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
    }, { corner(8), stroke(Theme.Stroke, 1, 0.4), padding(6, 6, 6, 10) })
    local layout = create("UIListLayout", { Parent = list, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
    local group = setmetatable({ Order = 0, Name = self.Name .. "/" .. title, Page = list }, TabMethods)

    -- the list grows with what's in it, up to maxHeight, then scrolls
    local function fit()
        local ok, size = pcall(function() return layout.AbsoluteContentSize end)
        local h = (ok and size and size.Y or 0) + 12
        list.CanvasSize = UDim2.new(0, 0, 0, h)
        list.Size = UDim2.new(1, 0, 0, math.min(h, maxHeight))
    end
    pcall(function() layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit) end)
    fit()

    -- scrolling inside the list never scrolls the page behind it: the page
    -- is held still while your finger / mouse is on the list
    local page = self.Page
    local holding = false
    local function hold(on)
        if holding == on then return end
        holding = on
        pcall(function() page.ScrollingEnabled = not on end)
    end
    local function pointerOnList()
        local ok, inside = pcall(function()
            -- (the menu ignores the top bar inset, so both are screen coordinates)
            local m = UserInputService:GetMouseLocation()
            local p, size = list.AbsolutePosition, list.AbsoluteSize
            local x, y = m.X, m.Y
            return list.Visible and x >= p.X and x <= p.X + size.X and y >= p.Y and y <= p.Y + size.Y
        end)
        return ok and inside
    end
    list.MouseEnter:Connect(function() if not IsTouch then hold(true) end end)
    list.MouseLeave:Connect(function() hold(false) end)
    list.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then hold(true) end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then hold(false) end
    end)
    -- safety net: MouseLeave can be missed (tab switched, list closed)
    task.spawn(function()
        while Alive do
            task.wait(0.4)
            if holding and not IsTouch and not pointerOnList() then hold(false) end
        end
    end)

    local function render()
        list.Visible = open
        tween(chevron, 0.15, { Rotation = open and -90 or 90 })
        if not open then hold(false) end
    end
    render()
    btn.MouseButton1Click:Connect(function()
        open = not open
        render()
        storeValue(self, key, open)
    end)

    -- a compact item in the list
    function group:Option(text, callback)
        local item = create("TextButton", {
            Parent = list,
            LayoutOrder = nextOrder(group),
            Size = UDim2.new(1, -6, 0, IsTouch and 38 or 34),
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 0.4,
            AutoButtonColor = false,
            Text = text,
            Font = Enum.Font.GothamMedium,
            TextSize = UISize.Text,
            TextColor3 = Theme.TabText,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, { corner(6), padding(0, 0, 10, 10) })
        local function hover(on)
            tween(item, 0.12, { BackgroundColor3 = on and Theme.AccentDark or Theme.Panel, BackgroundTransparency = on and 0.2 or 0.4 })
        end
        if IsTouch then
            item.InputBegan:Connect(function(input) if isPress(input) then hover(true) end end)
            item.InputEnded:Connect(function(input) if isPress(input) then hover(false) end end)
        else
            item.MouseEnter:Connect(function() hover(true) end)
            item.MouseLeave:Connect(function() hover(false) end)
        end
        item.MouseButton1Click:Connect(function()
            if callback then task.spawn(callback) end
        end)
        return item
    end

    function group.SetTitle(text) btn.Text = text end
    function group.IsOpen() return open end
    return group
end

function TabMethods:Label(text)
    local f = baseElement(self, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    return create("TextLabel", {
        Parent = f,
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        RichText = true,
        TextWrapped = true,
        Text = text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, { padding(10, 10, 12, 12) })
end

function TabMethods:Button(text, callback)
    local f = baseElement(self, UISize.Row)
    local btn = clickArea(f, text)
    create("TextLabel", {
        Parent = btn,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Text = "›",
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = Theme.AccentLight,
    })
    addHover(btn, f)
    btn.MouseButton1Click:Connect(function()
        tween(f, 0.08, { BackgroundColor3 = Theme.AccentDark }).Completed:Connect(function()
            tween(f, 0.25, { BackgroundColor3 = Theme.PanelHover })
        end)
        if callback then task.spawn(callback) end
    end)
    return btn
end

function TabMethods:Toggle(text, default, callback)
    local state = default and true or false
    local saved = savedValue(self, text)
    if type(saved) == "boolean" and saved ~= state then
        state = saved
        -- run it once the rest of the menu exists
        if callback then task.defer(callback, state) end
    end
    local f = baseElement(self, UISize.Row)
    local btn = clickArea(f, text)
    addHover(btn, f)

    local switch = create("Frame", {
        Parent = btn,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(UISize.SwitchW, UISize.SwitchH),
        BackgroundColor3 = state and Theme.Accent or Theme.Field,
    }, { round(), stroke(Theme.Stroke, 1, 0.3) })

    local onPos, offPos = UDim2.new(1, -(UISize.Knob + 2), 0.5, 0), UDim2.new(0, 2, 0.5, 0)
    local knob = create("Frame", {
        Parent = switch,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = state and onPos or offPos,
        Size = UDim2.fromOffset(UISize.Knob, UISize.Knob),
        BackgroundColor3 = Theme.Text,
    }, { round() })

    -- other controls (like the on-screen buttons) that mirror this toggle
    local listeners = {}

    local function set(value, silent)
        state = value and true or false
        storeValue(self, text, state)
        tween(switch, 0.2, { BackgroundColor3 = state and Theme.Accent or Theme.Field })
        tween(knob, 0.25, { Position = state and onPos or offPos }, Enum.EasingStyle.Back)
        for _, listener in ipairs(listeners) do task.spawn(listener, state) end
        if callback and not silent then task.spawn(callback, state) end
    end

    btn.MouseButton1Click:Connect(function() set(not state) end)
    local original = default and true or false
    table.insert(DefaultResetters, function()
        if state ~= original then set(original) end
    end)
    return {
        Set = set,
        Get = function() return state end,
        OnChanged = function(listener) table.insert(listeners, listener) end,
    }
end

function TabMethods:Slider(text, min, max, default, callback)
    local value = math.clamp(default or min, min, max)
    local original = value
    local saved = savedValue(self, text)
    if type(saved) == "number" and math.clamp(math.floor(saved + 0.5), min, max) ~= value then
        value = math.clamp(math.floor(saved + 0.5), min, max)
        if callback then task.defer(callback, value) end
    end
    local f = baseElement(self, UISize.Slider)

    create("TextLabel", {
        Parent = f, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -80, 0, 16),
        Text = text, Font = Enum.Font.GothamMedium, TextSize = UISize.Text,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local valueLabel = create("TextLabel", {
        Parent = f, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
        Size = UDim2.fromOffset(60, 16),
        Text = tostring(value), Font = Enum.Font.GothamBold, TextSize = UISize.Text,
        TextColor3 = Theme.AccentLight, TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- touch screens get - / + buttons on each side, since a thin bar is hard
    -- to set exactly with a finger
    local stepW = IsTouch and 34 or 0
    local sideGap = IsTouch and stepW + 20 or 12
    local trackY = IsTouch and 40 or 38

    -- tall invisible hit area so the bar is easy to grab; the thin track sits inside it
    local bar = create("TextButton", {
        Parent = f, AutoButtonColor = false, Text = "",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, sideGap, 0, trackY), Size = UDim2.new(1, -sideGap * 2, 0, IsTouch and 30 or 20),
    })
    local trackFrame = create("Frame", {
        Parent = bar, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, IsTouch and 8 or 6),
        BackgroundColor3 = Theme.Field,
    }, { round() })
    local fill = create("Frame", {
        Parent = trackFrame, BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, { round(), gradient(Theme.AccentDark, Theme.AccentLight) })
    local knob = create("Frame", {
        Parent = trackFrame, AnchorPoint = Vector2.new(0.5, 0.5),
        Size = IsTouch and UDim2.fromOffset(20, 20) or UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Text,
    }, { round(), stroke(Theme.Accent, 2) })

    local function render(animated)
        local p = (value - min) / (max - min)
        valueLabel.Text = tostring(value)
        if animated then
            tween(fill, 0.08, { Size = UDim2.fromScale(p, 1) })
            tween(knob, 0.08, { Position = UDim2.fromScale(p, 0.5) })
        else
            fill.Size = UDim2.fromScale(p, 1)
            knob.Position = UDim2.fromScale(p, 0.5)
        end
    end
    render(false)

    local function set(newValue, silent)
        newValue = math.clamp(math.floor(newValue + 0.5), min, max)
        local changed = newValue ~= value
        value = newValue
        if changed then storeValue(self, text, value) end
        render(true)
        if changed and callback and not silent then task.spawn(callback, value) end
    end

    local dragging = false
    local function fromX(x)
        local p = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        set(min + (max - min) * p)
    end

    bar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            fromX(input.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if isPress(input) then
            dragging = false
        end
    end))

    if IsTouch then
        -- a round step for this range: 1, 2, 5, 10, 25, 50 or 100
        local step = 1
        for _, s in ipairs({ 2, 5, 10, 25, 50, 100 }) do
            if s <= (max - min) / 40 then step = s end
        end

        local function stepButton(label, anchorX, x, delta)
            local b = create("TextButton", {
                Parent = f, AutoButtonColor = false,
                AnchorPoint = Vector2.new(anchorX, 0.5),
                Position = UDim2.new(anchorX, x, 0, trackY),
                Size = UDim2.fromOffset(stepW, 30),
                BackgroundColor3 = Theme.Field,
                Text = label, Font = Enum.Font.GothamBold, TextSize = 18,
                TextColor3 = Theme.AccentLight,
            }, { corner(8), stroke(Theme.Stroke, 1, 0.4) })

            -- tap = one step, hold = keep stepping
            local presses = 0
            local function release()
                tween(b, 0.2, { BackgroundColor3 = Theme.Field })
            end
            b.InputBegan:Connect(function(input)
                if not isPress(input) then return end
                presses += 1
                local id = presses
                set(value + delta * step)
                tween(b, 0.08, { BackgroundColor3 = Theme.AccentDark })
                task.delay(0.4, function()
                    local function held()
                        return presses == id and Alive and input.UserInputState ~= Enum.UserInputState.End
                            and input.UserInputState ~= Enum.UserInputState.Cancel
                    end
                    while held() do
                        set(value + delta * step)
                        task.wait(0.07)
                    end
                end)
            end)
            b.InputEnded:Connect(function(input)
                if isPress(input) then
                    presses += 1
                    release()
                end
            end)
        end
        stepButton("−", 0, 12, -1)
        stepButton("+", 1, -12, 1)
    end

    table.insert(DefaultResetters, function() set(original) end)
    return { Set = set, Get = function() return value end }
end

function TabMethods:Keybind(text, default, onChanged)
    if IsTouch then return { Get = function() return default end } end -- no keyboard on touch screens
    local current = default
    local saved = savedValue(self, text)
    local ok, savedKey = pcall(function() return Enum.KeyCode[saved] end)
    if type(saved) == "string" and ok and savedKey and savedKey ~= current then
        current = savedKey
        if onChanged then task.defer(onChanged, current) end
    end
    local f = baseElement(self, 40)

    create("TextLabel", {
        Parent = f, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0),
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    })

    local boxStroke = stroke(Theme.Accent, 1, 0.4)
    local box = create("TextButton", {
        Parent = f,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Field,
        Text = current.Name,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.AccentLight,
    }, {
        corner(6), boxStroke, padding(0, 0, 12, 12),
        create("UISizeConstraint", { MinSize = Vector2.new(90, 26) }),
    })

    local function reset()
        box.Text = current.Name
        tween(box, 0.2, { BackgroundColor3 = Theme.Field, TextColor3 = Theme.AccentLight })
        tween(boxStroke, 0.2, { Transparency = 0.4 })
    end

    box.MouseButton1Click:Connect(function()
        if PendingBind then return end
        box.Text = "⌛ Press a key..."
        tween(box, 0.2, { BackgroundColor3 = Theme.Accent, TextColor3 = Theme.Text })
        tween(boxStroke, 0.2, { Transparency = 0 })
        PendingBind = {
            Set = function(key)
                current = key
                storeValue(self, text, key.Name)
                reset()
                if onChanged then onChanged(key) end
            end,
            Cancel = reset,
        }
    end)

    table.insert(DefaultResetters, function()
        if current == default then return end
        current = default
        reset()
        if onChanged then onChanged(default) end
    end)
    return { Get = function() return current end }
end

-- ========================= PLAYER FEATURES =========================
local function getCharacter() return LocalPlayer.Character end
local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local Player = {
    WalkEnabled = false, WalkSpeed = 16,
    JumpEnabled = false, JumpPower = 50,
    InfJump = false,
    Noclip = false,
    Flying = false, FlySpeed = 80,
}

local Defaults = { WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = true }
do
    local hum = getHumanoid()
    if hum then
        Defaults.WalkSpeed = hum.WalkSpeed
        Defaults.JumpPower = hum.JumpPower
        Defaults.JumpHeight = hum.JumpHeight
        Defaults.UseJumpPower = hum.UseJumpPower
    end
end

local function restoreWalk()
    local hum = getHumanoid()
    if hum then hum.WalkSpeed = Defaults.WalkSpeed end
end

local function restoreJump()
    local hum = getHumanoid()
    if hum then
        hum.UseJumpPower = Defaults.UseJumpPower
        hum.JumpPower = Defaults.JumpPower
        hum.JumpHeight = Defaults.JumpHeight
    end
end

-- keep WalkSpeed / JumpPower applied even if the game resets them
track(RunService.Heartbeat:Connect(function()
    local hum = getHumanoid()
    if not hum then return end
    if Player.WalkEnabled and not Player.PauseWalk and hum.WalkSpeed ~= Player.WalkSpeed then
        hum.WalkSpeed = Player.WalkSpeed
    end
    if Player.JumpEnabled then
        if not hum.UseJumpPower then hum.UseJumpPower = true end
        if hum.JumpPower ~= Player.JumpPower then hum.JumpPower = Player.JumpPower end
    end
end))

-- infinite jump
track(UserInputService.JumpRequest:Connect(function()
    if not Player.InfJump then return end
    local hum = getHumanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

-- noclip
local noclipParts = {}
track(RunService.Stepped:Connect(function()
    if not Player.Noclip then return end
    local char = getCharacter()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            noclipParts[part] = true
            part.CanCollide = false
        end
    end
end))

local function setNoclip(on)
    Player.Noclip = on
    if not on then
        for part in pairs(noclipParts) do
            if part and part.Parent then part.CanCollide = true end
        end
        table.clear(noclipParts)
    end
end

-- fly: physics based like most Roblox fly scripts. A LinearVelocity moves
-- the character (eases in and out instead of jumping) and an AlignOrientation
-- turns it toward the camera with a slight lean in the direction you move.
local flyHold

local function stopFly()
    Player.Flying = false
    if flyHold then
        for _, o in ipairs(flyHold.Parts) do pcall(function() o:Destroy() end) end
        flyHold = nil
    end
    local hum, root = getHumanoid(), getRoot()
    if hum then hum.PlatformStand = false end
    if root then root.AssemblyLinearVelocity = Vector3.zero end
end

local function startFly()
    local root, hum = getRoot(), getHumanoid()
    if not root or not hum then return false end
    stopFly()
    Player.Flying = true

    local att = create("Attachment", { Name = "SmurfyFly", Parent = root })
    local move = create("LinearVelocity", {
        Parent = root,
        Attachment0 = att,
        MaxForce = math.huge,
        VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        VectorVelocity = Vector3.zero,
    })
    local turn = create("AlignOrientation", {
        Parent = root,
        Attachment0 = att,
        Mode = Enum.OrientationAlignmentMode.OneAttachment,
        MaxTorque = math.huge,
        Responsiveness = 25,
        CFrame = root.CFrame.Rotation,
    })
    flyHold = { Parts = { att, move, turn }, Move = move, Turn = turn, Velocity = Vector3.zero }
    hum.PlatformStand = true -- no walking / falling animations fighting the flight
    return true
end

-- The move stick / thumbstick, read from Roblox's own control module. While
-- flying the character is PlatformStand, and then Humanoid.MoveDirection
-- stays zero, so it can't be used for steering on touch screens / gamepads.
-- Runs in its own thread because it calls game code (see the notify queue).
Mobile.MoveVector = Vector3.zero
Mobile.JumpHeld = false
task.spawn(function()
    local ok, controls = pcall(function()
        local playerModule = LocalPlayer:WaitForChild("PlayerScripts", 10):WaitForChild("PlayerModule", 10)
        return require(playerModule):GetControls()
    end)
    if not ok or type(controls) ~= "table" then return end
    track(RunService.RenderStepped:Connect(function()
        if not Player.Flying then return end
        local okMove, move = pcall(controls.GetMoveVector, controls)
        Mobile.MoveVector = okMove and typeof(move) == "Vector3" and move or Vector3.zero
        -- the touch jump button, so holding jump flies up
        local held = false
        pcall(function()
            local active, touchJump = controls.activeController, controls.touchJumpController
            held = (active and active.GetIsJumping and active:GetIsJumping())
                or (touchJump and touchJump.GetIsJumping and touchJump:GetIsJumping()) or false
        end)
        Mobile.JumpHeld = held and true or false
    end))
end)

track(RunService.RenderStepped:Connect(function(dt)
    if not Player.Flying or not flyHold then return end
    local root, hum, cam = getRoot(), getHumanoid(), workspace.CurrentCamera
    if not root or not hum or not cam or not flyHold.Move.Parent then return end

    local camCF = cam.CFrame
    local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
    flatLook = flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
    local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)

    local dir, vertical = Vector3.zero, 0
    if not IsTouch and not UserInputService:GetFocusedTextBox() then
        local down = function(k) return UserInputService:IsKeyDown(k) end
        if down(Enum.KeyCode.W) then dir += camCF.LookVector end
        if down(Enum.KeyCode.S) then dir -= camCF.LookVector end
        if down(Enum.KeyCode.D) then dir += camCF.RightVector end
        if down(Enum.KeyCode.A) then dir -= camCF.RightVector end
        if down(Enum.KeyCode.Space) then vertical += 1 end
        if down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.LeftShift) then vertical -= 1 end
    end

    -- mobile / gamepad: the move stick, relative to the camera (X = right, -Z = forward)
    local stick = Mobile.MoveVector
    if dir.Magnitude == 0 and stick.Magnitude > 0.05 then
        dir = camCF.LookVector * -stick.Z + camCF.RightVector * stick.X
    elseif dir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
        local md = hum.MoveDirection
        dir = camCF.LookVector * md:Dot(flatLook) + camCF.RightVector * md:Dot(flatRight)
    end

    -- touch: the on-screen Up / Down buttons, and holding Roblox's jump button flies up
    if IsTouch then
        if Mobile.FlyUp or Mobile.JumpHeld or hum.Jump then vertical += 1 end
        if Mobile.FlyDown then vertical -= 1 end
    end
    dir += Vector3.yAxis * math.clamp(vertical, -1, 1)
    if dir.Magnitude > 0 then dir = dir.Unit end

    -- ease toward the target speed (smooth start and stop)
    local target = dir * Player.FlySpeed
    flyHold.Velocity = flyHold.Velocity:Lerp(target, math.min(1, dt * 8))
    flyHold.Move.VectorVelocity = flyHold.Velocity

    -- face the camera, leaning a little into the movement
    local speed = math.max(Player.FlySpeed, 1)
    local forward = math.clamp(flyHold.Velocity:Dot(flatLook) / speed, -1, 1)
    local side = math.clamp(flyHold.Velocity:Dot(flatRight) / speed, -1, 1)
    flyHold.Turn.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
        * CFrame.Angles(-math.rad(18) * forward, 0, -math.rad(12) * side)
    root.AssemblyAngularVelocity = Vector3.zero
end))

track(LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(noclipParts)
    if Player.Flying then
        flyHold = nil
        char:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.3)
        if Player.Flying then startFly() end
    end
end))

-- ========================= GAME ENGINE (Break & Steal an Egg) =========================
-- How the game works (from its client scripts):
--   * Eggs are parts tagged "BreakableEgg" under workspace.Build.ZoneBuilds.ZoneN.Eggs,
--     each inside a model named "<n>: <Type> Egg". Attributes: Health, MaxHealth,
--     Broken / Hatching / Despawning.
--   * Hitting: hold the "Pickaxe" tool and fire ReplicatedStorage.EggHitRequest(egg, hitId)
--     at most once per swing cooldown, from within 8 studs of the egg's surface.
--   * A broken egg drops an animal (a Model tagged "AnimalPickup" in workspace.AnimalPickups).
--     Its "StealPrompt" is moved by the game onto a "PromptAnchor" part in workspace.
--   * You carry animals (LocalPlayer CarryCount / SatchelCapacity) and they bank when
--     you reach your plot's Hitbox or the SafeZone. Banked animals are Tools tagged
--     "AnimalTool"; PlaceAnimalRemote(tool, position, seq) puts one in your pen.
--   * Your plot: the child of workspace.Plots whose OwnerUserId is yours.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function findPath(root, path)
    local node = root
    for _, name in ipairs(path) do
        node = node and node:FindFirstChild(name)
    end
    return node
end

local RarityOrder = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic",
    "Divine", "Cosmic", "Secret", "Celestial", "Inferno",
}
local RarityRank = {}
for i, name in ipairs(RarityOrder) do RarityRank[name] = i end
local RarityColors = {
    Common    = Color3.fromRGB(185, 192, 205),
    Uncommon  = Color3.fromRGB(90, 220, 110),
    Rare      = Color3.fromRGB(70, 150, 255),
    Epic      = Color3.fromRGB(175, 95, 255),
    Legendary = Color3.fromRGB(255, 190, 60),
    Mythic    = Color3.fromRGB(255, 85, 120),
    Divine    = Color3.fromRGB(255, 240, 140),
    Cosmic    = Color3.fromRGB(120, 110, 255),
    Secret    = Color3.fromRGB(40, 40, 40),
    Celestial = Color3.fromRGB(90, 240, 225),
    Inferno   = Color3.fromRGB(255, 110, 40),
}

-- helpers live on this table (the main chunk is near Luau's 200 local limit)
local Game = { Mods = {}, HitId = 0, PlaceSeq = 0 }

Game.Supported = workspace:FindFirstChild("Plots") ~= nil
    and ReplicatedStorage:FindFirstChild("EggHitRequest") ~= nil

function Game.Attr(inst, name)
    local ok, value = pcall(function() return inst:GetAttribute(name) end)
    if ok then return value end
    return nil
end

function Game.Num(inst, name, default)
    local value = Game.Attr(inst, name)
    if type(value) == "number" then return value end
    return default
end

function Game.Tagged(tag)
    local ok, list = pcall(function()
        return game:GetService("CollectionService"):GetTagged(tag)
    end)
    return ok and type(list) == "table" and list or {}
end

function Game.HasTag(inst, tag)
    local ok, has = pcall(function()
        return game:GetService("CollectionService"):HasTag(inst, tag)
    end)
    return ok and has == true
end

function Game.Remote(name)
    local r = ReplicatedStorage:FindFirstChild(name)
    if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then return r end
    return nil
end

function Game.Fire(name, ...)
    local r = Game.Remote(name)
    if not r or not r:IsA("RemoteEvent") then return false end
    local args = table.pack(...)
    return pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
end

function Game.Cash() return Game.Num(LocalPlayer, "Cash", 0) end

function Game.Short(n)
    n = n or 0
    for _, unit in ipairs({ { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if n >= unit[1] then return string.format("%.1f%s", n / unit[1], unit[2]) end
    end
    return tostring(math.floor(n))
end

-- the game's own data modules (pure tables). Loaded in their own thread:
-- game code never runs in a thread that touches the menu.
task.spawn(function()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local function req(root, path)
        local module = root and findPath(root, path)
        if not module or not module:IsA("ModuleScript") then return nil end
        local ok, result = pcall(require, module)
        return ok and type(result) == "table" and result or nil
    end
    Game.Mods.Pickaxe = req(shared, { "PickaxeConfig" })
    Game.Mods.Trails = req(shared, { "TrailsConfig" })
    Game.Mods.PlotUpgrade = req(shared, { "PlotUpgradeConfig" })
    Game.Mods.Treadmill = req(shared, { "TreadmillUpgradeConfig" })
    Game.Mods.RobuxShop = req(shared, { "RobuxShopConfig" })
    Game.Mods.EggRewards = req(shared, { "EggRewards" })
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    Game.Mods.LocalHits = req(scripts, { "Client", "Controllers", "EggLocalHits" })
end)

---------------------------------------------------------------- places
function Game.MyPlot()
    local plots = workspace:FindFirstChild("Plots")
    for _, plot in ipairs(plots and plots:GetChildren() or {}) do
        if Game.Attr(plot, "OwnerUserId") == LocalPlayer.UserId then return plot end
    end
    return nil
end

function Game.PlotHitbox()
    local plot = Game.MyPlot()
    local hitbox = plot and plot:FindFirstChild("Hitbox")
    return hitbox and hitbox:IsA("BasePart") and hitbox or nil
end

-- inside a part (the game's own check, with 2 studs of slack up and down)
function Game.InPart(part, pos)
    local rel = part.CFrame:PointToObjectSpace(pos)
    local half = part.Size * 0.5
    return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 2 and math.abs(rel.Z) <= half.Z
end

-- the ground under a point (or nil)
function Game.Ground(pos, ignore)
    local ok, hit = pcall(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local skip = { LocalPlayer.Character }
        if ignore then table.insert(skip, ignore) end
        params.FilterDescendantsInstances = skip
        return workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), params)
    end)
    return ok and hit and hit.Position or nil
end

-- where you stand at home: the plot's spawn point (else the middle of the plot)
local function plotCFrame()
    local plot = Game.MyPlot()
    if not plot then return nil end
    local spawn = plot:FindFirstChild("SpawnPoint")
    if spawn and spawn:IsA("BasePart") then
        return CFrame.new(spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
    end
    local hitbox = Game.PlotHitbox()
    if not hitbox then return nil end
    local ground = Game.Ground(hitbox.Position, plot)
    return CFrame.new((ground or hitbox.Position) + Vector3.new(0, 3, 0))
end

function Game.SafeZone()
    local part = findPath(workspace, { "Build", "ZoneHitboxes", "SafeZone" })
    return part and part:IsA("BasePart") and part or nil
end

function Game.InSafeZone()
    local part, root = Game.SafeZone(), getRoot()
    return part ~= nil and root ~= nil and Game.InPart(part, root.Position)
end

-- a spot to stand in zone n: next to one of its eggs, else the middle of its floor
function Game.ZoneSpot(n)
    local folder = findPath(workspace, { "Build", "ZoneBuilds", "Zone" .. n, "Eggs" })
    for _, egg in ipairs(folder and folder:GetDescendants() or {}) do
        if egg:IsA("BasePart") and egg.Name == "Egg" then
            return egg.Position + Vector3.new(egg.Size.X / 2 + 4, 0, 0)
        end
    end
    local hitbox = findPath(workspace, { "Build", "ZoneHitboxes", tostring(n) })
    if hitbox and hitbox:IsA("BasePart") then
        local ground = Game.Ground(Vector3.new(hitbox.Position.X, hitbox.Position.Y + hitbox.Size.Y / 2, hitbox.Position.Z))
        return ground and ground + Vector3.new(0, 3, 0) or hitbox.Position
    end
    return nil
end

-- which zone a position is in (1-9) from the zone hitboxes
function Game.ZoneAt(pos)
    local folder = findPath(workspace, { "Build", "ZoneHitboxes" })
    for i = 1, 9 do
        local part = folder and folder:FindFirstChild(tostring(i))
        if part and part:IsA("BasePart") and Game.InPart(part, pos) then return i end
    end
    return nil
end

function Game.Treadmill()
    local plot = Game.MyPlot()
    for _, child in ipairs(plot and plot:GetChildren() or {}) do
        if child:IsA("Model") and string.find(child.Name, "Treadmill", 1, true) then return child end
    end
    return nil
end

---------------------------------------------------------------- eggs
function Game.EggLive(egg)
    return egg ~= nil and egg.Parent ~= nil and not Game.Attr(egg, "Broken")
        and not Game.Attr(egg, "Hatching") and not Game.Attr(egg, "Despawning")
end

-- type ("Rock Egg") and zone number of an egg part
function Game.EggInfo(egg)
    local model = egg.Parent
    local name = model and model.Name or "Egg"
    name = string.gsub(name, "^%d+:%s*", "")
    if name == "Egg" or name == "" then name = Game.Attr(egg, "EggType") or "Egg" end
    local zone = nil
    local node = egg.Parent
    while node and node ~= workspace do
        local n = string.match(node.Name, "^Zone(%d)$")
        if n then zone = tonumber(n) break end
        node = node.Parent
    end
    return name, zone
end

function Game.Eggs()
    local list = {}
    for _, egg in ipairs(Game.Tagged("BreakableEgg")) do
        if egg:IsA("BasePart") and Game.EggLive(egg) then table.insert(list, egg) end
    end
    return list
end

-- damage per hit and seconds per swing, the way the game works them out
function Game.Damage(egg)
    local fixed = Game.Num(egg, "FixedDamage", 0)
    if fixed > 0 then return fixed end
    local tier = Game.Num(LocalPlayer, "PickaxeTier", 1)
    local mod = Game.Mods.Pickaxe
    if mod and mod.GetDamage then
        local ok, dmg = pcall(mod.GetDamage, tier)
        if ok and type(dmg) == "number" then return dmg end
    end
    return nil
end

function Game.SwingCooldown()
    local base = Game.Mods.Pickaxe and Game.Mods.Pickaxe.SwingCooldown or 0.5
    local mult = 1
    local shop = Game.Mods.RobuxShop
    if shop and shop.SwingMultiplierFor then
        local ok, m = pcall(shop.SwingMultiplierFor, LocalPlayer)
        if ok and type(m) == "number" and m > 0 then mult = m end
    end
    return base / mult
end

-- seconds to break an egg with your pickaxe (nil if unknown)
function Game.SecondsToBreak(egg)
    local dmg = Game.Damage(egg)
    if not dmg or dmg <= 0 then return nil end
    local hits = math.ceil(Game.Num(egg, "Health", 1) / dmg)
    return hits * Game.SwingCooldown()
end

function Game.Pickaxe()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local tool = char and char:FindFirstChild("Pickaxe")
    if tool and tool:IsA("Tool") then return tool, true end
    tool = backpack and backpack:FindFirstChild("Pickaxe")
    if tool and tool:IsA("Tool") then return tool, false end
    return nil, false
end

function Game.EquipPickaxe()
    local tool, held = Game.Pickaxe()
    if held then return true end
    local hum = getHumanoid()
    if tool and hum then pcall(function() hum:EquipTool(tool) end) end
    return tool ~= nil
end

function Game.Hit(egg)
    local remote = Game.Remote("EggHitRequest")
    if not remote then return false end
    local id
    local hits = Game.Mods.LocalHits
    if hits and hits.Announce then
        local ok, result = pcall(hits.Announce, egg, Game.Damage(egg) or 1)
        if ok and type(result) == "number" then id = result end
    end
    if not id then
        Game.HitId += 1
        id = Game.HitId
    end
    return pcall(function() remote:FireServer(egg, id) end)
end

---------------------------------------------------------------- animals
function Game.AnimalName(model)
    local name = Game.Attr(model, "AnimalName")
    return type(name) == "string" and name ~= "" and name or model.Name
end

function Game.Rarity(inst)
    local rarity = Game.Attr(inst, "Rarity")
    if type(rarity) == "string" and RarityRank[rarity] then return rarity end
    local mod = Game.Mods.EggRewards
    if mod and mod.RarityOf then
        local ok, r = pcall(mod.RarityOf, Game.AnimalName(inst))
        if ok and type(r) == "string" then return r end
    end
    return "Common"
end

function Game.Pickups()
    local list, seen = {}, {}
    local function add(model)
        if model:IsA("Model") and model.Parent and not seen[model] and not Game.Attr(model, "Despawning") then
            seen[model] = true
            table.insert(list, model)
        end
    end
    for _, model in ipairs(Game.Tagged("AnimalPickup")) do add(model) end
    local folder = workspace:FindFirstChild("AnimalPickups")
    for _, model in ipairs(folder and folder:GetChildren() or {}) do add(model) end
    return list
end

function Game.Reserved(inst)
    local id = Game.Attr(inst, "ReservedUserId")
    return type(id) == "number" and id ~= LocalPlayer.UserId
end

-- the StealPrompt for an animal: inside it, or on the anchor part the game
-- moved it to (the anchor sits on the animal's surface)
function Game.PromptFor(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and not Game.Reserved(d) then return d end
    end
    local ok, pivot = pcall(model.GetPivot, model)
    if not ok then return nil end
    local best, bestDist = nil, 20
    for _, anchor in ipairs(workspace:GetChildren()) do
        if anchor.Name == "PromptAnchor" and anchor:IsA("BasePart") then
            local prompt = anchor:FindFirstChild("StealPrompt")
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled and not Game.Reserved(prompt) then
                local dist = (anchor.Position - pivot.Position).Magnitude
                if dist < bestDist then best, bestDist = prompt, dist end
            end
        end
    end
    return best
end

function Game.FirePrompt(prompt)
    if type(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    return pcall(function()
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0) + 0.1)
        prompt:InputHoldEnd()
    end)
end

function Game.Carrying() return Game.Num(LocalPlayer, "CarryCount", 0) end
function Game.Capacity() return math.max(Game.Num(LocalPlayer, "SatchelCapacity", 1), 1) end

-- banked animals in your backpack / hands
function Game.AnimalTools()
    local list = {}
    for _, holder in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        for _, tool in ipairs(holder and holder:GetChildren() or {}) do
            if tool:IsA("Tool") and (Game.HasTag(tool, "AnimalTool") or Game.Attr(tool, "AnimalName") ~= nil) then
                table.insert(list, tool)
            end
        end
    end
    return list
end

function Game.PlotSpace()
    local plot = Game.MyPlot()
    if not plot then return 0 end
    local placed = Game.Num(plot, "AnimalsPlaced", 0)
    local max = Game.Num(plot, "MaxAnimals", nil)
    if not max then
        local mod = Game.Mods.PlotUpgrade
        local ok, cap = pcall(function() return mod.Capacity(Game.Num(plot, "PlotLevel", 1)) end)
        max = ok and type(cap) == "number" and cap or placed + 1
    end
    return math.max(max - placed, 0)
end

---------------------------------------------------------------- farm
local Farm = {
    Enabled = false,
    DoBreak = true, DoGrab = true, DoBank = true, DoPlace = true,
    Zones = {},             -- [n] = true: only these zones (none picked = any zone)
    Target = "Nearest",     -- Nearest / Weakest / Best zone
    MaxSeconds = 60,        -- skip eggs that take longer than this to break
    MinRarity = 1,          -- only grab animals at least this rare
    Smooth = false, Speed = 300,
    Status = "💤 Idle",
    Broken = 0, Banked = 0, Placed = 0, Grabbed = 0,
    SessionStart = nil,
    Token = 0,
    Skip = {},              -- eggs / animals that didn't work, until a time
    PlaceRetryAt = 0,
}

local function setStatus(text) Farm.Status = text end

-- move to a spot: teleport, or fly there at Farm.Speed
function Farm.MoveTo(pos, token)
    local root = getRoot()
    if not root then return false end
    if not Farm.Smooth or (pos - root.Position).Magnitude < 12 then
        root.CFrame = CFrame.new(pos)
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    local p = root.Position
    while Alive and Farm.Token == token and root.Parent and (pos - p).Magnitude > 1 do
        local dt = RunService.Heartbeat:Wait()
        p += (pos - p).Unit * math.min(Farm.Speed * math.min(dt, 0.1), (pos - p).Magnitude)
        root.CFrame = CFrame.new(p)
        root.AssemblyLinearVelocity = Vector3.zero
    end
    return Farm.Token == token and root.Parent ~= nil
end

-- stand next to an egg, facing it, close enough to hit
function Farm.StandAt(egg, token)
    local root = getRoot()
    if not root then return false end
    local radius = math.max(egg.Size.X, egg.Size.Z) / 2
    local flat = Vector3.new(root.Position.X - egg.Position.X, 0, root.Position.Z - egg.Position.Z)
    local dir = flat.Magnitude > 0.5 and flat.Unit or Vector3.new(1, 0, 0)
    local spot = egg.Position + dir * (radius + 2.5)
    spot = Vector3.new(spot.X, egg.Position.Y - egg.Size.Y / 2 + 3, spot.Z)
    if not Farm.MoveTo(spot, token) then return false end
    root.CFrame = CFrame.lookAt(spot, Vector3.new(egg.Position.X, spot.Y, egg.Position.Z))
    return true
end

function Farm.Skipped(inst)
    local untilTime = Farm.Skip[inst]
    if untilTime and os.clock() < untilTime then return true end
    Farm.Skip[inst] = nil
    return false
end

-- the egg to break next
function Farm.PickEgg()
    local root = getRoot()
    if not root then return nil end
    local anyZone = next(Farm.Zones) == nil
    local best, bestScore
    for _, egg in ipairs(Game.Eggs()) do
        local _, zone = Game.EggInfo(egg)
        if (anyZone or (zone and Farm.Zones[zone])) and not Farm.Skipped(egg) then
            local secs = Game.SecondsToBreak(egg)
            if not secs or secs <= Farm.MaxSeconds then
                local dist = (egg.Position - root.Position).Magnitude
                local score
                if Farm.Target == "Weakest" then
                    score = Game.Num(egg, "Health", 0) * 1e6 + dist
                elseif Farm.Target == "Best zone" then
                    score = -(zone or 0) * 1e7 + dist
                else
                    score = dist
                end
                if not bestScore or score < bestScore then best, bestScore = egg, score end
            end
        end
    end
    return best
end

-- the animal to grab next (rarest first, then nearest)
function Farm.PickAnimal()
    local root = getRoot()
    if not root then return nil end
    local best, bestRank, bestDist
    for _, model in ipairs(Game.Pickups()) do
        if not Game.Reserved(model) and not Farm.Skipped(model) then
            local rank = RarityRank[Game.Rarity(model)] or 1
            local ok, pivot = pcall(model.GetPivot, model)
            if ok and rank >= Farm.MinRarity then
                local dist = (pivot.Position - root.Position).Magnitude
                if not best or rank > bestRank or (rank == bestRank and dist < bestDist) then
                    best, bestRank, bestDist = model, rank, dist
                end
            end
        end
    end
    return best
end

function Farm.Grab(model, token)
    local ok, pivot = pcall(model.GetPivot, model)
    if not ok then return false end
    setStatus("🐾 Grabbing " .. Game.AnimalName(model))
    local before = Game.Carrying()
    if not Farm.MoveTo(pivot.Position + Vector3.new(0, 2, 3), token) then return false end
    task.wait(0.25) -- let the game's prompt anchor catch up
    for _ = 1, 4 do
        if Farm.Token ~= token or not model.Parent then break end
        local prompt = Game.PromptFor(model)
        if prompt then Game.FirePrompt(prompt) end
        local t = os.clock()
        while os.clock() - t < 0.8 and Game.Carrying() <= before and model.Parent do task.wait(0.1) end
        if Game.Carrying() > before or not model.Parent then break end
    end
    if Game.Carrying() > before then
        Farm.Grabbed += 1
        return true
    end
    Farm.Skip[model] = os.clock() + 15
    return false
end

function Farm.GoHome(token)
    local home = plotCFrame()
    if not home then
        local safe = Game.SafeZone()
        if not safe then return false end
        home = CFrame.new((Game.Ground(safe.Position) or safe.Position) + Vector3.new(0, 3, 0))
    end
    local carrying = Game.Carrying()
    setStatus("🏠 Bringing " .. carrying .. " animal" .. (carrying == 1 and "" or "s") .. " home")
    if not Farm.MoveTo(home.Position, token) then return false end
    local t = os.clock()
    while Farm.Token == token and Game.Carrying() > 0 and os.clock() - t < 5 do task.wait(0.2) end
    local banked = carrying - Game.Carrying()
    if banked > 0 then Farm.Banked += banked end
    return Game.Carrying() == 0
end

-- put banked animals in the pen (best first) while there's room
function Farm.PlaceAll(token)
    local hitbox = Game.PlotHitbox()
    if not hitbox then return 0 end
    local tools = Game.AnimalTools()
    if #tools == 0 or Game.PlotSpace() <= 0 then return 0 end
    table.sort(tools, function(a, b)
        return (RarityRank[Game.Rarity(a)] or 0) > (RarityRank[Game.Rarity(b)] or 0)
    end)
    local root = getRoot()
    if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(hitbox.Position.X, 0, hitbox.Position.Z)).Magnitude > 40 then
        local home = plotCFrame()
        if home then Farm.MoveTo(home.Position, token) end
    end
    local remote = Game.Remote("PlaceAnimalRemote")
    local hum = getHumanoid()
    local placed = 0
    for _, tool in ipairs(tools) do
        if Farm.Token ~= token or Game.PlotSpace() <= 0 or not remote or not hum then break end
        setStatus("📦 Placing " .. Game.AnimalName(tool))
        local before = Game.PlotSpace()
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.2)
        -- a random spot on the plot's floor, away from the edges
        local x = (math.random() - 0.5) * hitbox.Size.X * 0.6
        local z = (math.random() - 0.5) * hitbox.Size.Z * 0.6
        local spot = hitbox.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
        local ground = Game.Ground(spot, Game.MyPlot())
        spot = ground or Vector3.new(spot.X, hitbox.Position.Y - hitbox.Size.Y / 2, spot.Z)
        Game.PlaceSeq += 1
        pcall(function() remote:FireServer(tool, spot, Game.PlaceSeq) end)
        local t = os.clock()
        while os.clock() - t < 1.5 and tool.Parent and Game.PlotSpace() >= before do task.wait(0.1) end
        if Game.PlotSpace() < before or not tool.Parent then
            placed += 1
            Farm.Placed += 1
        end
    end
    pcall(function() hum:UnequipTools() end)
    return placed
end

function Farm.BreakEgg(egg, token)
    local name = Game.EggInfo(egg)
    if not Farm.StandAt(egg, token) then return false end
    if not Game.EquipPickaxe() then
        setStatus("⚠️ No pickaxe in your backpack")
        task.wait(1)
        return false
    end
    task.wait(0.15)
    local started = os.clock()
    local lastHealth, lastChange = Game.Num(egg, "Health", 0), os.clock()
    local cooldown = Game.SwingCooldown() * 1.05
    while Farm.Token == token and Farm.DoBreak and Game.EggLive(egg) do
        local root = getRoot()
        if not root then break end
        -- something pushed you away: step back next to it
        local flat = Vector3.new(root.Position.X - egg.Position.X, 0, root.Position.Z - egg.Position.Z)
        if flat.Magnitude > math.max(egg.Size.X, egg.Size.Z) / 2 + 5 then Farm.StandAt(egg, token) end
        Game.EquipPickaxe()
        Game.Hit(egg)
        local hp, max = Game.Num(egg, "Health", 0), Game.Num(egg, "MaxHealth", 0)
        setStatus(string.format("🥚 Breaking %s  %s", name, max > 0 and string.format("%d%%", math.floor(hp / max * 100 + 0.5)) or ""))
        if hp ~= lastHealth then lastHealth, lastChange = hp, os.clock() end
        -- no damage for a while (out of range, someone else's, ...): try another egg
        if os.clock() - lastChange > 6 then
            Farm.Skip[egg] = os.clock() + 30
            return false
        end
        if os.clock() - started > Farm.MaxSeconds + 15 then
            Farm.Skip[egg] = os.clock() + 60
            return false
        end
        -- carrying is full or a better animal just dropped: stop and deal with it
        if Farm.DoGrab and Game.Carrying() < Game.Capacity() and Farm.PickAnimal() then return true end
        task.wait(cooldown)
    end
    if not Game.EggLive(egg) and Farm.Token == token then
        Farm.Broken += 1
        task.wait(0.6) -- the animal pops out
    end
    return true
end

function Farm.Step(token)
    if not getRoot() then
        setStatus("⏳ Waiting for your character")
        task.wait(1)
        return
    end
    local carrying, capacity = Game.Carrying(), Game.Capacity()

    -- 1. full (or nothing else to grab while carrying): bring them home
    if Farm.DoBank and carrying > 0 and (carrying >= capacity or not (Farm.DoGrab and Farm.PickAnimal())) then
        if not Farm.GoHome(token) then
            setStatus("⚠️ Animals didn't bank, retrying")
            task.wait(1)
        end
        return
    end

    -- 2. animals in the backpack and room in the pen: place them
    if Farm.DoPlace and os.clock() >= Farm.PlaceRetryAt and #Game.AnimalTools() > 0 and Game.PlotSpace() > 0 then
        -- nothing placed (the game refused): don't fly home for it again right away
        if Farm.PlaceAll(token) == 0 then Farm.PlaceRetryAt = os.clock() + 30 end
        if not Farm.DoBreak and not Farm.DoGrab then
            task.wait(1)
            return
        end
    end

    -- 3. grab an animal lying around
    if Farm.DoGrab and carrying < capacity then
        local model = Farm.PickAnimal()
        if model then
            Farm.Grab(model, token)
            return
        end
    end

    -- 4. break an egg
    if Farm.DoBreak then
        local egg = Farm.PickEgg()
        if egg then
            Farm.BreakEgg(egg, token)
            return
        end
        setStatus("🔎 No eggs to break right now")
    else
        setStatus("💤 Nothing to do")
    end
    task.wait(1)
end

function Farm.Start()
    if Farm.Enabled then return end
    Farm.Enabled = true
    Farm.Token += 1
    local token = Farm.Token
    Farm.SessionStart = Farm.SessionStart or os.clock()
    task.spawn(function()
        while Alive and Farm.Enabled and Farm.Token == token do
            local ok, err = pcall(Farm.Step, token)
            if not ok then
                warn("[Smurfy's] farm: " .. tostring(err))
                setStatus("⚠️ " .. tostring(err):sub(1, 60))
                task.wait(1)
            end
            task.wait()
        end
    end)
end

function Farm.Stop()
    Farm.Enabled = false
    Farm.Token += 1
    Farm.Status = "💤 Idle"
end

---------------------------------------------------------------- auto features
local Auto = {
    Pickaxe = false, Trail = false, Plot = false, Treadmill = false,
    Rewards = false, AntiAfk = true,
}

-- a comma list attribute ("1,2,5") -> { [1] = true, ... }
function Game.OwnedSet(attr)
    local set = {}
    local value = Game.Attr(LocalPlayer, attr)
    if type(value) == "string" then
        for piece in string.gmatch(value, "[^,]+") do
            local n = tonumber(piece)
            if n then set[n] = true end
        end
    end
    return set
end

-- buy the next pickaxe you can afford, then hold it
function Game.BuyPickaxe()
    local mod = Game.Mods.Pickaxe
    if not mod or type(mod.Tiers) ~= "table" then return false end
    local owned = Game.OwnedSet("OwnedPickaxes")
    local current = Game.Num(LocalPlayer, "PickaxeTier", 1)
    owned[current] = true
    local best = 1
    for tier in pairs(owned) do if tier > best then best = tier end end
    local nextTier = mod.Tiers[best + 1]
    if nextTier and type(nextTier.Price) == "number" and Game.Cash() >= nextTier.Price then
        Game.Fire("PickaxeShopRequest", "Buy", best + 1)
        task.wait(0.5)
        Game.Fire("PickaxeShopRequest", "Equip", best + 1)
        notify("⛏️ New pickaxe", nextTier.Name or ("Tier " .. (best + 1)), 3)
        return true
    elseif best > current then
        Game.Fire("PickaxeShopRequest", "Equip", best)
    end
    return false
end

function Game.BuyTrail()
    local mod = Game.Mods.Trails
    if not mod or type(mod.Trails) ~= "table" then return false end
    local owned = Game.OwnedSet("OwnedTrails")
    local best
    for _, trail in ipairs(mod.Trails) do
        if owned[trail.Id] and (not best or trail.Price > best.Price) then best = trail end
    end
    for _, trail in ipairs(mod.Trails) do
        if not owned[trail.Id] and (not best or trail.Price > best.Price) then
            if Game.Cash() >= trail.Price then
                Game.Fire("TrailShopRequest", "Buy", trail.Id)
                task.wait(0.5)
                Game.Fire("TrailShopRequest", "Equip", trail.Id)
                notify("✨ New trail", trail.Name or "Trail", 3)
                return true
            end
            break
        end
    end
    if best and Game.Num(LocalPlayer, "EquippedTrail", 0) ~= best.Id then
        Game.Fire("TrailShopRequest", "Equip", best.Id)
    end
    return false
end

function Game.UpgradePlot()
    local plot, mod = Game.MyPlot(), Game.Mods.PlotUpgrade
    if not plot or not mod or not mod.UpgradeCost then return false end
    local ok, cost = pcall(mod.UpgradeCost, Game.Num(plot, "PlotLevel", 1))
    if ok and type(cost) == "number" and Game.Cash() >= cost then
        return Game.Fire("UpgradePlotRequest")
    end
    return false
end

function Game.UpgradeTreadmill()
    local plot, mod = Game.MyPlot(), Game.Mods.Treadmill
    if not plot then return false end
    if Game.Attr(plot, "TreadmillUnlocked") ~= true then
        if Game.Cash() >= 100 then return Game.Fire("UnlockTreadmillRequest") end
        return false
    end
    if not mod or not mod.UpgradeCost then return false end
    local ok, cost = pcall(mod.UpgradeCost, Game.Num(plot, "TreadmillLevel", 1))
    if ok and type(cost) == "number" and Game.Cash() >= cost then
        return Game.Fire("UpgradeTreadmillRequest")
    end
    return false
end

function Game.ClaimRewards()
    Game.Fire("OfflineRewardRemote", "Claim")
    Game.Fire("GroupRewardRemote", "Claim")
    Game.Fire("IndexRemote", "ClaimAll", nil)
end

-- sell backpack animals at or below a rarity (the game's Sell button)
function Game.SellUpTo(maxRank)
    local remote = Game.Remote("BackpackSellRemote")
    if not remote or not remote:IsA("RemoteFunction") then return 0 end
    local list = {}
    for _, tool in ipairs(Game.AnimalTools()) do
        if (RarityRank[Game.Rarity(tool)] or 1) <= maxRank then table.insert(list, tool) end
    end
    if #list == 0 then return 0 end
    local hum = getHumanoid()
    if hum then pcall(function() hum:UnequipTools() end) end
    local ok = pcall(function() remote:InvokeServer(list) end)
    return ok and #list or 0
end

isolate(function()
    -- shop / upgrades / rewards, checked every few seconds
    task.spawn(function()
        local nextRewards = 0
        while Alive do
            task.wait(3)
            if Auto.Pickaxe then pcall(Game.BuyPickaxe) end
            if Auto.Trail then pcall(Game.BuyTrail) end
            if Auto.Plot then pcall(Game.UpgradePlot) end
            if Auto.Treadmill then pcall(Game.UpgradeTreadmill) end
            if Auto.Rewards and os.clock() >= nextRewards then
                nextRewards = os.clock() + 60
                pcall(Game.ClaimRewards)
            end
        end
    end)

    -- anti afk
    local VirtualUser = game:GetService("VirtualUser")
    track(LocalPlayer.Idled:Connect(function()
        if not Auto.AntiAfk then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end)

-- ========================= OPEN / CLOSE / MINIMIZE =========================
local function setOpen(state)
    IsOpen = state
    if Mobile.OnOpenChanged then Mobile.OnOpenChanged(state) end
    if state then
        Holder.Visible = true
        tween(WindowScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        local t = tween(WindowScale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        t.Completed:Connect(function()
            if not IsOpen then Holder.Visible = false end
        end)
    end
end

-- ========================= DRAGGING (direct, 1:1 with the mouse) =========================
isolate(function()
do
    local dragging, dragStart, startPos = false, nil, nil

    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Vector2.new(Holder.Position.X.Offset, Holder.Position.Y.Offset)
        end
    end)

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local delta = input.Position - dragStart
        local screen = ScreenGui.AbsoluteSize
        if screen.X == 0 then screen = viewport() end
        local w = WINDOW_SIZE.X
        local h = Holder.Size.Y.Offset

        local x = clampNum(startPos.X + delta.X, w / 2, screen.X - w / 2)
        local y = clampNum(startPos.Y + delta.Y, 0, screen.Y - h)
        Holder.Position = UDim2.fromOffset(x, y)
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end
end)

-- ========================= OPEN BUTTON + TOUCH CONTROLS =========================
-- * a round "S" button that opens / closes the menu, with FPS and ping next
--   to it while the menu is minimized. Always on screen on touch screens;
--   on PC it only shows while the menu is minimized.
-- * clicking the logo in the top bar minimizes the menu
-- Touch screens only:
-- * on-screen buttons for features (turned on in the Buttons tab), like
--   Roblox's own jump button
-- * Up / Down buttons next to jump while flying
-- * an edit mode for dragging the buttons around (positions are saved)
isolate(function()
    local Saved = type(SavedSettings.ButtonPos) == "table" and SavedSettings.ButtonPos or {}
    SavedSettings.ButtonPos = Saved
    local Style = { Size = 1, Transparency = 0.25 }
    local QuickButtons = {} -- every on-screen button, by id
    Mobile.Editing = false

    local function screenSize()
        local size = ScreenGui.AbsoluteSize
        return size.X > 0 and size or viewport()
    end

    -- buttons are placed by their center, as a fraction of the screen, so
    -- they stay in the same spot when the screen size changes
    local function centerOf(frame)
        local screen, p = screenSize(), frame.Position
        return Vector2.new(p.X.Scale * screen.X + p.X.Offset, p.Y.Scale * screen.Y + p.Y.Offset)
    end

    local function placeAt(frame, center)
        local screen = screenSize()
        local half = frame.AbsoluteSize / 2
        local x = clampNum(center.X, half.X, screen.X - half.X)
        local y = clampNum(center.Y, half.Y, screen.Y - half.Y)
        frame.Position = UDim2.fromScale(x / screen.X, y / screen.Y)
    end

    local function savePosition(id, frame)
        local p = frame.Position
        Saved[id] = { p.X.Scale, p.Y.Scale }
        queueSave()
    end

    local function savedPosition(id)
        local s = Saved[id]
        if type(s) == "table" and tonumber(s[1]) and tonumber(s[2]) then
            local screen = screenSize()
            return Vector2.new(s[1] * screen.X, s[2] * screen.Y)
        end
        return nil
    end

    -- tap or drag. A press that moves more than a few pixels is a drag
    -- (when canDrag allows it), anything else is a tap.
    local function attachDrag(button, frame, id, canDrag, onTap, onPress, onRelease)
        button.InputBegan:Connect(function(input)
            if not isPress(input) then return end
            local isTouch = input.UserInputType == Enum.UserInputType.Touch
            local startPos, startCenter = input.Position, centerOf(frame)
            local dragging = false
            if onPress then onPress() end

            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(move)
                if isTouch and move ~= input then return end
                if not isTouch and move.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                local delta = move.Position - startPos
                if not dragging and (delta.Magnitude < 10 or not canDrag()) then return end
                dragging = true
                placeAt(frame, startCenter + Vector2.new(delta.X, delta.Y))
            end)
            endConn = UserInputService.InputEnded:Connect(function(ended)
                if isTouch and ended ~= input then return end
                if not isTouch and ended.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                moveConn:Disconnect()
                endConn:Disconnect()
                if onRelease then onRelease() end
                if dragging then
                    savePosition(id, frame)
                elseif onTap then
                    onTap()
                end
            end)
            track(moveConn)
            track(endConn)
        end)
    end

    -- ---------- open button ----------
    local OPEN_SIZE = 46
    local openRing = stroke(Color3.new(1, 1, 1), 2, 0)
    local openRingGradient = create("UIGradient", {
        Parent = openRing,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.AccentDark),
            ColorSequenceKeypoint.new(0.5, Theme.Text),
            ColorSequenceKeypoint.new(1, Theme.AccentDark),
        }),
    })
    local openHolder = create("Frame", {
        Name = "OpenButton",
        Parent = ScreenGui,
        Visible = IsTouch,
        ZIndex = 10, -- above the window, notifications and on-screen buttons
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(OPEN_SIZE, OPEN_SIZE),
        BackgroundTransparency = 1,
    })
    local openScale = create("UIScale", { Parent = openHolder })
    local openButton = create("TextButton", {
        Parent = openHolder,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Text = "",
    }, {
        round(),
        openRing,
        create("UIGradient", {
            Rotation = 135,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentLight),
                ColorSequenceKeypoint.new(0.45, Theme.Accent),
                ColorSequenceKeypoint.new(1, Theme.BgDeep),
            }),
        }),
    })
    local openShadow = create("TextLabel", {
        Parent = openButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 2),
        Text = "S", Font = Enum.Font.FredokaOne, TextSize = 26,
        TextColor3 = Theme.BgDeep, TextTransparency = 0.35,
    })
    local openLabel = create("TextLabel", {
        Parent = openButton, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "S", Font = Enum.Font.FredokaOne, TextSize = 26,
        TextColor3 = Theme.Text,
    })

    -- default spot: just right of Roblox's top-left buttons, a little lower
    -- than them so it doesn't look squeezed into Roblox's bar
    local OPEN_DROP = 16
    local function defaultOpenCenter()
        local ok, rect = pcall(function() return GuiService.TopbarInset end)
        if ok and typeof(rect) == "Rect" and rect.Width > 0 and rect.Height > 0 then
            return Vector2.new(rect.Min.X + OPEN_SIZE / 2 + 6, rect.Min.Y + rect.Height / 2 + OPEN_DROP)
        end
        local inset = topInset()
        return Vector2.new(150, math.max(inset / 2, OPEN_SIZE / 2 + 4) + OPEN_DROP)
    end

    local function bounce(scale)
        tween(scale, 0.08, { Scale = 0.88 }).Completed:Connect(function()
            tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
        end)
    end

    -- FPS / ping pill beside the S, shown while the menu is minimized
    local openStats = create("TextLabel", {
        Parent = openHolder,
        Visible = false,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(1, 8, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 26),
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.25,
        RichText = true,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.Text,
    }, { round(), padding(0, 0, 11, 11), stroke(Theme.Accent, 1, 0.5) })
    table.insert(Perf.Labels, openStats)

    -- farm pill under the S while auto farm runs and the menu is minimized
    local eggPillStroke = stroke(Theme.Accent, 1, 0.5)
    local eggPill = create("TextLabel", {
        Parent = openHolder,
        Visible = false,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0, 0, 1, 8),
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.25,
        RichText = true,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, { corner(10), padding(6, 6, 11, 11), eggPillStroke })
    local nextPillUpdate = 0

    -- PC: the S is only there while minimized (Settings can turn it off)
    Mobile.ShowMinimized = true

    -- touch: the S turns into an X while the menu is open
    function Mobile.OnOpenChanged(open)
        if open and Mobile.Editing then Mobile.SetEditing(false) end
        openHolder.Visible = IsTouch or (not open and Mobile.ShowMinimized)
        openStats.Visible = not open
        openLabel.Text = open and "✕" or "S"
        openShadow.Text = openLabel.Text
        openLabel.TextSize = open and 22 or 26
        openShadow.TextSize = openLabel.TextSize
    end

    attachDrag(openButton, openHolder, "Open", function() return true end, function()
        bounce(openScale)
        setOpen(not IsOpen)
    end)

    -- clicking the logo in the top bar minimizes the menu
    local toldHowToReopen = false
    create("TextButton", {
        Parent = Logo,
        ZIndex = 3,
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        Text = "",
    }).MouseButton1Click:Connect(function()
        setOpen(false)
        if not IsTouch and not toldHowToReopen then
            toldHowToReopen = true
            notify("➖ Menu minimized", (Mobile.ShowMinimized and "Click the S button or press " or "Press ")
                .. Binds.Menu.Name .. " to open it again.")
        end
    end)

    -- keep the S on screen, and the stats on whichever side has room
    local function updateOpenButton()
        local now = os.clock()
        openRingGradient.Rotation = (now * 90) % 360
        local onRight = centerOf(openHolder).X > screenSize().X / 2
        if openStats.Visible then
            openStats.AnchorPoint = onRight and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
            openStats.Position = onRight and UDim2.new(0, -8, 0.5, 0) or UDim2.new(1, 8, 0.5, 0)
        end

        eggPill.Visible = not IsOpen and Farm.Enabled
        if eggPill.Visible and now >= nextPillUpdate then
            nextPillUpdate = now + 0.25
            eggPill.AnchorPoint = onRight and Vector2.new(1, 0) or Vector2.new(0, 0)
            eggPill.Position = onRight and UDim2.new(1, 0, 1, 8) or UDim2.new(0, 0, 1, 8)
            eggPill.Text = string.format("🥚 %d broken · 🐾 %d banked\n<font transparency=\"0.25\">%s</font>",
                Farm.Broken, Farm.Banked, Farm.Status)
            local alert = string.find(Farm.Status, "⚠️", 1, true) ~= nil
            eggPillStroke.Color = alert and Color3.fromRGB(255, 90, 90) or Theme.Accent
            eggPillStroke.Transparency = alert and 0 or 0.5
        end
    end
    local function placeOpenButton()
        placeAt(openHolder, savedPosition("Open") or defaultOpenCenter())
    end

    -- minimize button in the top right of the window. Drawn (a bar on a glass
    -- tile) instead of a text symbol, so it looks the same on every device.
    do
        local size = IsTouch and 30 or 26
        local minimize = create("TextButton", {
            Name = "Minimize",
            Parent = TopBar,
            ZIndex = 4,
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.85,
            Text = "",
        }, { corner(8), stroke(Color3.new(1, 1, 1), 1, 0.7) })
        local minimizeScale = create("UIScale", { Parent = minimize })
        create("Frame", {
            Parent = minimize,
            ZIndex = 5,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(math.floor(size * 0.42), 3),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }, { round() })
        if not IsTouch then
            minimize.MouseEnter:Connect(function() tween(minimize, 0.15, { BackgroundTransparency = 0.7 }) end)
            minimize.MouseLeave:Connect(function() tween(minimize, 0.15, { BackgroundTransparency = 0.85 }) end)
            Perf.Row.Position = UDim2.new(1, -(size + 18), 0.5, 0) -- the FPS / key pills sit left of it
        end
        minimize.MouseButton1Click:Connect(function()
            bounce(minimizeScale)
            setOpen(false)
        end)
    end

    if not IsTouch then
        track(RunService.Heartbeat:Connect(updateOpenButton))
        track(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            placeAt(openHolder, centerOf(openHolder))
        end))
        placeOpenButton()
        task.defer(placeOpenButton)
        return
    end


    -- ---------- on-screen buttons ----------
    local BASE_SIZE = 56

    local function makeQuickButton(id, icon, label, hold)
        local frame = create("Frame", {
            Name = "Quick_" .. id,
            Parent = ScreenGui,
            ZIndex = 0, -- behind the menu window, so it never covers the menu
            Visible = false,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(BASE_SIZE, BASE_SIZE),
            BackgroundTransparency = 1,
        })
        local scale = create("UIScale", { Parent = frame })
        local ring = stroke(Theme.AccentLight, 1.5, 0.35)
        local button = create("TextButton", {
            Parent = frame,
            AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.BgDeep,
            BackgroundTransparency = Style.Transparency,
            Text = "",
        }, { round(), ring })
        local iconLabel = create("TextLabel", {
            Parent = button, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
            Size = UDim2.fromScale(1, 0.5),
            Text = icon, TextScaled = true, Font = Enum.Font.GothamBold,
            TextColor3 = Theme.Text,
        }, { create("UITextSizeConstraint", { MaxTextSize = 22 }) })
        local nameLabel = create("TextLabel", {
            Parent = button, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
            Size = UDim2.fromScale(0.9, 0.24),
            Text = label, TextScaled = true, Font = Enum.Font.GothamBold,
            TextColor3 = Theme.Text,
        }, { create("UITextSizeConstraint", { MaxTextSize = 10 }) })

        local q = { Id = id, Frame = frame, Button = button, On = false, Shown = false, Phase = math.random() * 6 }

        function q.Render()
            tween(button, 0.15, {
                BackgroundColor3 = q.On and Theme.Accent or Theme.BgDeep,
                BackgroundTransparency = q.On and math.min(Style.Transparency, 0.15) or Style.Transparency,
            })
            tween(ring, 0.15, {
                Color = (q.On or Mobile.Editing) and Theme.Text or Theme.AccentLight,
                Transparency = (q.On or Mobile.Editing) and 0.1 or 0.35,
                Thickness = Mobile.Editing and 2.5 or 1.5,
            })
            local textFade = Style.Transparency * 0.4
            iconLabel.TextTransparency, nameLabel.TextTransparency = textFade, textFade
        end

        function q.ApplyStyle()
            frame.Size = UDim2.fromOffset(BASE_SIZE * Style.Size, BASE_SIZE * Style.Size)
            q.Render()
        end

        function q.Refresh()
            -- edit mode also shows Up / Down so they can be placed without flying
            local visible = q.Shown or (Mobile.Editing and hold == true)
            if visible ~= frame.Visible then
                frame.Visible = visible
                if visible then
                    scale.Scale = 0.5
                    tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
                end
            end
            if not visible and q.OnRelease then q.OnRelease() end
            if not visible or not Mobile.Editing then frame.Rotation = 0 end
            q.Render()
        end

        function q.SetShown(shown)
            q.Shown = shown and true or false
            q.Refresh()
        end

        local function editing() return Mobile.Editing end
        if hold then
            -- held buttons (fly Up / Down) are on while the finger is down
            attachDrag(button, frame, id, editing, nil, function()
                if Mobile.Editing then return end
                q.On = true
                q.Render()
                if q.OnPress then q.OnPress() end
            end, function()
                if q.On then
                    q.On = false
                    q.Render()
                end
                if q.OnRelease then q.OnRelease() end
            end)
        else
            attachDrag(button, frame, id, editing, function()
                if Mobile.Editing then return end
                bounce(scale)
                if q.OnTap then q.OnTap() end
            end)
        end

        QuickButtons[id] = q
        q.ApplyStyle()
        return q
    end

    -- ---------- default layout ----------
    -- feature buttons go in a column down the right edge (a second column
    -- if needed), clear of Roblox's jump button; Up / Down sit next to jump
    local Order = { "Fly", "Noclip", "InfJump", "Speed", "AutoEggs" }

    local function jumpButtonArea(screen)
        -- where Roblox puts its touch jump button (center, size)
        if math.min(screen.X, screen.Y) <= 500 then
            return Vector2.new(screen.X - 60, screen.Y - 55), 70
        end
        return Vector2.new(screen.X - 110, screen.Y - 150), 120
    end

    local function defaultCenter(id)
        local screen = screenSize()
        local jump, jumpSize = jumpButtonArea(screen)
        local size = BASE_SIZE * Style.Size
        if id == "FlyUp" then
            return Vector2.new(jump.X, jump.Y - jumpSize / 2 - size / 2 - 10)
        elseif id == "FlyDown" then
            return Vector2.new(jump.X - jumpSize / 2 - size / 2 - 10, jump.Y)
        end
        local index = table.find(Order, id) or #Order
        local gap = size + 10
        local top = topInset() + size / 2 + 12
        local bottom = jump.Y - jumpSize / 2 - size - 30 -- leave room for the Up button
        local perColumn = math.max(1, math.floor((bottom - top) / gap) + 1)
        local column = math.floor((index - 1) / perColumn)
        local row = (index - 1) % perColumn
        return Vector2.new(screen.X - size / 2 - 14 - column * gap, top + row * gap)
    end

    local function placeButton(id, frame)
        placeAt(frame, savedPosition(id) or defaultCenter(id))
    end

    function Mobile.ResetPositions()
        table.clear(Saved)
        queueSave()
        placeAt(openHolder, defaultOpenCenter())
        for id, q in pairs(QuickButtons) do placeAt(q.Frame, defaultCenter(id)) end
    end

    function Mobile.SetStyle(size, transparency)
        if size then Style.Size = size end
        if transparency then Style.Transparency = transparency end
        for _, q in pairs(QuickButtons) do q.ApplyStyle() end
    end

    -- feature buttons, made from the targets the tabs registered
    function Mobile.AddFeatureButton(target)
        local q = makeQuickButton(target.Id, target.Icon, target.Label, false)
        q.On = target.Toggle.Get()
        q.OnTap = function() target.Toggle.Set(not target.Toggle.Get()) end
        target.Toggle.OnChanged(function(state)
            q.On = state
            q.Render()
        end)
        placeButton(target.Id, q.Frame)
        return q
    end

    -- fly Up / Down: only shown while flying (or while editing the layout)
    local flyUp = makeQuickButton("FlyUp", "⬆️", "Up", true)
    flyUp.OnPress = function() Mobile.FlyUp = true end
    flyUp.OnRelease = function() Mobile.FlyUp = false end
    local flyDown = makeQuickButton("FlyDown", "⬇️", "Down", true)
    flyDown.OnPress = function() Mobile.FlyDown = true end
    flyDown.OnRelease = function() Mobile.FlyDown = false end
    placeButton("FlyUp", flyUp.Frame)
    placeButton("FlyDown", flyDown.Frame)

    -- ---------- edit layout mode ----------
    local editBar = create("Frame", {
        Name = "EditBar",
        Parent = ScreenGui,
        ZIndex = 11,
        Visible = false,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, topInset() + 8),
        Size = UDim2.fromOffset(0, 44),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.BgDeep,
        BackgroundTransparency = 0.1,
    }, {
        corner(12),
        stroke(Theme.Accent, 1.5, 0.2),
        padding(6, 6, 14, 6),
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 12),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    create("TextLabel", {
        Parent = editBar, LayoutOrder = 1, BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
        Text = "✏️ Drag the buttons where you want them",
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.Text,
    })
    local doneButton = create("TextButton", {
        Parent = editBar, LayoutOrder = 2,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(84, 32),
        BackgroundColor3 = Theme.Accent,
        Text = "✅ Done",
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Theme.Text,
    }, { corner(9) })

    function Mobile.SetEditing(on)
        if Mobile.Editing == on then return end
        Mobile.Editing = on
        editBar.Visible = on
        if on and IsOpen then setOpen(false) end
        for _, q in pairs(QuickButtons) do q.Refresh() end
    end

    doneButton.MouseButton1Click:Connect(function()
        Mobile.SetEditing(false)
        setOpen(true)
        notify("✅ Layout saved", "Your buttons will stay where you put them.")
    end)

    -- ---------- every frame ----------
    track(RunService.Heartbeat:Connect(function()
        local t = os.clock()
        updateOpenButton()
        -- Up / Down follow the fly toggle
        local flying = Player.Flying
        if flyUp.Shown ~= flying then
            flyUp.SetShown(flying)
            flyDown.SetShown(flying)
        end
        -- buttons wiggle while they can be moved
        if Mobile.Editing then
            for _, q in pairs(QuickButtons) do
                if q.Frame.Visible then q.Frame.Rotation = math.sin(t * 14 + q.Phase) * 3 end
            end
        end
    end))

    -- ---------- screen size changes (rotation, resizing the emulator) ----------
    track(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local screen = screenSize()
        WINDOW_SIZE = windowSizeFor(screen)
        Holder.Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y)
        local pos = Holder.Position
        Holder.Position = UDim2.fromOffset(
            clampNum(pos.X.Offset, WINDOW_SIZE.X / 2, screen.X - WINDOW_SIZE.X / 2),
            clampNum(pos.Y.Offset, 0, screen.Y - WINDOW_SIZE.Y)
        )
        placeAt(openHolder, centerOf(openHolder))
        for _, q in pairs(QuickButtons) do placeAt(q.Frame, centerOf(q.Frame)) end
    end))

    -- AbsoluteSize is ready on the next frame; place the open button then
    placeOpenButton()
    task.defer(function()
        placeOpenButton()
        for id, q in pairs(QuickButtons) do placeButton(id, q.Frame) end
    end)
end)

-- ========================= KEY HANDLING =========================
-- PC only: touch screens use the open button and on-screen buttons instead
if not IsTouch then track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if PendingBind then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local bind = PendingBind
            PendingBind = nil
            if input.KeyCode == Enum.KeyCode.Escape then
                bind.Cancel()
            else
                bind.Set(input.KeyCode)
            end
        end
        return
    end

    if gameProcessed or UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == Binds.Menu then
        setOpen(not IsOpen)
    elseif input.KeyCode == Binds.Fly and flyToggle then
        flyToggle.Set(not flyToggle.Get())
    end
end)) end

-- extra cleanup registered by the ESP / World tabs
local UnloadHooks = {}

local function unload()
    Alive = false
    for _, hook in ipairs(UnloadHooks) do pcall(hook) end
    for key, value in pairs(Auto) do
        if type(value) == "boolean" then Auto[key] = false end
    end
    Farm.Stop()
    stopFly()
    setNoclip(false)
    if Player.WalkEnabled then
        Player.WalkEnabled = false
        restoreWalk()
    end
    if Player.JumpEnabled then
        Player.JumpEnabled = false
        restoreJump()
    end
    Player.InfJump = false
    Mobile.FlyUp, Mobile.FlyDown = false, false
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    ScreenGui:Destroy()
    if GlobalEnv.SmurfysUnload == unload then GlobalEnv.SmurfysUnload = nil end
end
GlobalEnv.SmurfysUnload = unload

-- ========================= BUILD TABS =========================
-- a broken section is skipped (and reported) instead of stopping the menu from opening
local function safeSection(name, build)
    local ok, err = pcall(build)
    if not ok then
        warn("[Smurfy's] " .. name .. " failed to load: " .. tostring(err))
        notify("⚠️ " .. name .. " failed to load", tostring(err), 8)
    end
end

local Home      = createTab("Home", "🏠", "Overview of your session")
local PlayerTab = createTab("Player", "👤", "Movement, flight and character tweaks")
local TeleportTab = createTab("Teleport", "📍", "Zones, your base and saved spots")
local FarmTab   = createTab("Farm", "🥚", "Break eggs, grab animals, bring them home")
local BaseTab   = createTab("Base", "🏡", "Your pen, selling and upgrades")
local AutoTab   = createTab("Auto", "🤖", "Shop, upgrades and rewards on their own")
local EspTab    = createTab("ESP", "👁️", "See eggs, animals, guards and players")
local ButtonsTab = IsTouch and createTab("Buttons", "📲", "On-screen buttons, like Roblox's jump button")
local Settings  = createTab("Settings", "⚙️", IsTouch and "Device and interface options" or "Keybinds and interface options")

-- 🏠 Home: welcome screen
local keyHint
isolate(function()
do
    local hero = create("Frame", {
        Parent = Home.Page,
        LayoutOrder = nextOrder(Home),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.08,
    }, {
        corner(12),
        stroke(Theme.AccentLight, 1, 0.6),
        create("UIGradient", {
            Rotation = 120,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentDark),
                ColorSequenceKeypoint.new(0.6, Theme.BgMid),
                ColorSequenceKeypoint.new(1, Theme.BgDeep),
            }),
        }),
        create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
        padding(20, 20, 20, 20),
    })

    local function heroText(order, props)
        props.Parent = hero
        props.LayoutOrder = order
        props.BackgroundTransparency = 1
        props.Size = UDim2.new(1, 0, 0, 0)
        props.AutomaticSize = Enum.AutomaticSize.Y
        props.TextWrapped = true
        props.RichText = true
        props.TextXAlignment = Enum.TextXAlignment.Left
        return create("TextLabel", props)
    end

    local title = heroText(2, {
        Text = "Hey, " .. LocalPlayer.DisplayName .. " 👋",
        Font = Enum.Font.GothamBlack,
        TextSize = 26,
        TextColor3 = Theme.Text,
    })
    create("UIGradient", {
        Parent = title,
        Rotation = 90,
        Color = ColorSequence.new(Theme.Text, Theme.AccentLight),
    })

    heroText(3, {
        Text = "Pick a tab on the left to get started.",
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Theme.SubText,
    })

    -- Discord button (gradient lives on the frame so the text stays white)
    local discord = create("Frame", {
        Parent = hero,
        LayoutOrder = 5,
        Size = UDim2.fromOffset(210, 40),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, {
        corner(10),
        stroke(Theme.Text, 1, 0.75),
        create("UIGradient", {
            Rotation = 0,
            Color = ColorSequence.new(Color3.fromRGB(88, 101, 242), Theme.Accent),
        }),
    })
    local discordScale = create("UIScale", { Parent = discord })
    local discordBtn = create("TextButton", {
        Parent = discord,
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        Text = "💬  Join our Discord",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.Text,
    })
    if not IsTouch then
        discordBtn.MouseEnter:Connect(function() tween(discordScale, 0.15, { Scale = 1.04 }) end)
        discordBtn.MouseLeave:Connect(function() tween(discordScale, 0.15, { Scale = 1 }) end)
    end
    discordBtn.MouseButton1Click:Connect(function()
        tween(discordScale, 0.08, { Scale = 0.96 }).Completed:Connect(function()
            tween(discordScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
        end)
        if CONFIG.DiscordLink == "" then
            notify("💬 Discord", "The Discord invite hasn't been added yet.")
        elseif type(setclipboard) == "function" then
            setclipboard(CONFIG.DiscordLink)
            notify("💬 Invite copied", "Paste it in your browser to join.")
        else
            notify("💬 Discord", CONFIG.DiscordLink, 6)
        end
    end)

    keyHint = heroText(6, {
        Text = IsTouch and "📲 Tap the round <b>S</b> button to open and close the menu"
            or ("⌨️ <b>" .. Binds.Menu.Name .. "</b> opens and closes the menu"),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.SubText,
    })
end
end)
-- 🏠 Home: session stats
safeSection("Home stats", function()
    local grid = create("Frame", {
        Parent = Home.Page,
        LayoutOrder = nextOrder(Home),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, {
        create("UIGridLayout", {
            CellSize = UDim2.new(0.5, -4, 0, 62),
            CellPadding = UDim2.fromOffset(8, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local function statTile(order, icon, label)
        local tile = create("Frame", {
            Parent = grid,
            LayoutOrder = order,
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 0.25,
        }, { corner(10), stroke(Theme.Stroke, 1, 0.55) })
        create("TextLabel", {
            Parent = tile,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.fromOffset(34, 34),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.75,
            Text = icon,
            TextSize = 17,
        }, { corner(9) })
        local value = create("TextLabel", {
            Parent = tile,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(56, 11),
            Size = UDim2.new(1, -64, 0, 22),
            Text = "-",
            Font = Enum.Font.GothamBlack,
            TextSize = 18,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        create("TextLabel", {
            Parent = tile,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(56, 34),
            Size = UDim2.new(1, -64, 0, 16),
            Text = label,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        return value
    end

    local sessionValue = statTile(1, "⏱️", "Session time")
    local eggsValue    = statTile(2, "🥚", "Eggs broken")
    local animalsValue = statTile(3, "🐾", "Animals banked")
    local cashValue    = statTile(4, "💰", "Cash per hour")

    local started = os.clock()
    local elapsed = 0
    local earned, lastCash = 0, Game.Cash()

    track(RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 1 then return end
        elapsed = 0

        -- earnings only count money coming in (buying doesn't lower it)
        local cash = Game.Cash()
        if cash > lastCash then earned += cash - lastCash end
        lastCash = cash

        if not Holder.Visible or ActiveTab ~= Home then return end
        local secs = math.max(math.floor(os.clock() - started), 1)
        sessionValue.Text = string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60)
        eggsValue.Text = tostring(Farm.Broken)
        animalsValue.Text = tostring(Farm.Banked)
        local perSecond = Game.Num(LocalPlayer, "CashPerSecond", nil)
        if perSecond and perSecond > 0 then
            cashValue.Text = "$" .. Game.Short(perSecond * 3600)
        else
            cashValue.Text = secs >= 30 and ("$" .. Game.Short(earned / secs * 3600)) or "Measuring..."
        end
    end))
end)

-- 👤 Player
PlayerTab:Section("🏃 Movement")
local wsToggle = PlayerTab:Toggle("WalkSpeed", false, function(on)
    Player.WalkEnabled = on
    if not on then restoreWalk() end
end)
PlayerTab:Slider("⚡ Speed", 16, 250, 16, function(v) Player.WalkSpeed = v end)

local jpToggle = PlayerTab:Toggle("🦘 JumpPower", false, function(on)
    Player.JumpEnabled = on
    if not on then restoreJump() end
end)
PlayerTab:Slider("⬆️ Jump strength", 50, 300, 50, function(v) Player.JumpPower = v end)

local infToggle = PlayerTab:Toggle("♾️ Infinite jump", false, function(on) Player.InfJump = on end)

PlayerTab:Section("🕊️ Flight")
flyToggle = PlayerTab:Toggle("Fly", false, function(on)
    if on then
        if not startFly() then
            flyToggle.Set(false, true)
            notify("⚠️ Can't fly yet", "Your character hasn't loaded.")
        end
    else
        stopFly()
    end
end)
if not IsTouch then
    PlayerTab:Keybind("⌨️ Fly keybind", Binds.Fly, function(key)
        Binds.Fly = key
        notify("✅ Keybind updated", "Fly key is now " .. key.Name .. ".")
    end)
end
PlayerTab:Slider("💨 Fly speed", 16, 5000, 80, function(v) Player.FlySpeed = v end)

PlayerTab:Section("👻 Character")
local noclipToggle = PlayerTab:Toggle("Noclip", false, setNoclip)

-- features that can have an on-screen button (Buttons tab, touch screens)
table.insert(Mobile.Targets, { Id = "Fly", Icon = "🕊️", Label = "Fly", Toggle = flyToggle, Default = true })
table.insert(Mobile.Targets, { Id = "Noclip", Icon = "👻", Label = "Noclip", Toggle = noclipToggle })
table.insert(Mobile.Targets, { Id = "InfJump", Icon = "♾️", Label = "Inf jump", Toggle = infToggle })
table.insert(Mobile.Targets, { Id = "Speed", Icon = "⚡", Label = "Speed", Toggle = wsToggle })

PlayerTab:Button("↩️ Reset all player settings", function()
    wsToggle.Set(false)
    jpToggle.Set(false)
    infToggle.Set(false)
    flyToggle.Set(false)
    noclipToggle.Set(false)
    notify("↩️ Reset", "Player settings are back to default.")
end)

-- 📍 Teleport: saved spots (per game, kept between sessions)
isolate(function()
    local MAX_SPOTS = 30
    local key = tostring(game.PlaceId)
    if type(SavedSettings.Spots) ~= "table" then SavedSettings.Spots = {} end
    local spots = {}
    for _, s in ipairs(type(SavedSettings.Spots[key]) == "table" and SavedSettings.Spots[key] or {}) do
        if type(s) == "table" and type(s.Name) == "string" and tonumber(s.X) and tonumber(s.Y) and tonumber(s.Z) then
            table.insert(spots, { Name = s.Name, X = tonumber(s.X), Y = tonumber(s.Y), Z = tonumber(s.Z) })
        end
    end
    local function persist()
        SavedSettings.Spots[key] = spots
        saveSettings()
    end

    local Travel = { Smooth = false, Speed = 300, Token = 0, Back = nil }

    -- teleport (or fly smoothly) to pos; remembers where you were for "Back"
    local refreshBack
    local function goTo(pos, label)
        local root = getRoot()
        if not root then return notify("📍 Can't teleport", "Your character hasn't loaded.") end
        if Farm.Enabled then return notify("📍 Auto farm is on", "Stop it first, it's moving you around.") end
        Travel.Back = root.Position
        refreshBack()
        Travel.Token += 1
        local token = Travel.Token
        local goal = pos + Vector3.new(0, 3, 0)
        if not Travel.Smooth then
            root.CFrame = CFrame.new(goal)
            root.AssemblyLinearVelocity = Vector3.zero
            notify("📍 " .. label, "Teleported.", 2)
            return
        end
        notify("✈️ " .. label, "Flying there...", 2)
        task.spawn(function()
            local p = root.Position
            while Alive and Travel.Token == token and root.Parent and (goal - p).Magnitude > 1 do
                local dt = RunService.Heartbeat:Wait()
                p += (goal - p).Unit * math.min(Travel.Speed * math.min(dt, 0.1), (goal - p).Magnitude)
                root.CFrame = CFrame.new(p)
                root.AssemblyLinearVelocity = Vector3.zero
            end
            if Travel.Token == token and root.Parent then root.CFrame = CFrame.new(goal) end
        end)
    end

    -- ---------- save ----------
    TeleportTab:Section("➕ Save a spot")
    local nameRow = create("Frame", {
        Parent = TeleportTab.Page, LayoutOrder = nextOrder(TeleportTab),
        Size = UDim2.new(1, 0, 0, UISize.Row), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.25,
    }, { corner(8), stroke(Theme.Stroke, 1, 0.55) })
    local nameBox = create("TextBox", {
        Parent = nameRow, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
        Text = "", PlaceholderText = "✏️ Name (optional), e.g. Zone 5 eggs", PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = false, Font = Enum.Font.GothamMedium, TextSize = UISize.Text,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local function typedName()
        local text = (nameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        return text ~= "" and text:sub(1, 30) or nil
    end

    local rebuild
    TeleportTab:Button("📍 Save where I'm standing", function()
        local root = getRoot()
        if not root then return notify("📍 Can't save", "Your character hasn't loaded.") end
        if #spots >= MAX_SPOTS then return notify("📍 List is full", "Delete a spot first (max " .. MAX_SPOTS .. ").") end
        local name = typedName()
        if not name then
            local n = #spots + 1
            local taken = {}
            for _, s in ipairs(spots) do taken[s.Name] = true end
            while taken["Spot " .. n] do n += 1 end
            name = "Spot " .. n
        end
        local p = root.Position
        table.insert(spots, { Name = name, X = math.floor(p.X * 10) / 10, Y = math.floor(p.Y * 10) / 10, Z = math.floor(p.Z * 10) / 10 })
        nameBox.Text = ""
        persist()
        rebuild()
        notify("📍 Saved " .. name, "Find it under Your spots.", 2)
    end)

    -- ---------- quick ----------
    TeleportTab:Section("🧭 Quick")
    TeleportTab:Button("🏡 My base", function()
        local home = plotCFrame()
        if not home then return notify("🏡 No base found", "This game has no base of yours.") end
        goTo(home.Position - Vector3.new(0, 3, 0), "My base")
    end)
    local backButton = TeleportTab:Button("↩️ Back to where I was", function()
        if not Travel.Back then return notify("↩️ Nothing to go back to", "Teleport somewhere first.") end
        goTo(Travel.Back - Vector3.new(0, 3, 0), "Back")
    end)
    function refreshBack()
        backButton.Text = Travel.Back and "↩️ Back to where I was" or "↩️ Back to where I was (teleport first)"
    end
    refreshBack()

    if Game.Supported then
        TeleportTab:Button("🛡️ Safe zone", function()
            local safe = Game.SafeZone()
            if not safe then return notify("🛡️ Safe zone", "Can't find it right now.", 3) end
            local ground = Game.Ground(safe.Position, safe)
            goTo(ground or safe.Position, "Safe zone")
        end)
        TeleportTab:Button("🏃 My treadmill", function()
            local treadmill = Game.Treadmill()
            if not treadmill then return notify("🏃 No treadmill", "Unlock it in your base first.", 3) end
            goTo(treadmill:GetPivot().Position + Vector3.new(0, 2, 0), "Treadmill")
        end)
        local zoneNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic", "Secret" }
        local zoneGroup = TeleportTab:Dropdown("🗺️ Zones", false)
        for i, rarity in ipairs(zoneNames) do
            zoneGroup:Option("Zone " .. i .. " · " .. rarity, function()
                local spot = Game.ZoneSpot(i)
                if not spot then return notify("🗺️ Zone " .. i, "Can't find it right now.", 3) end
                goTo(spot, "Zone " .. i)
            end)
        end
    end

    -- ---------- your spots ----------
    local spotsGroup = TeleportTab:Dropdown("⭐ Your spots", true)
    local emptyLabel = spotsGroup:Label("No spots yet. Stand somewhere and tap Save.")
    local list = create("Frame", {
        Parent = spotsGroup.Page, LayoutOrder = nextOrder(spotsGroup),
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    }, { create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
    local distanceLabels = {}

    local function smallButton(parent, text, width, color, x)
        local b = create("TextButton", {
            Parent = parent, AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0),
            Size = UDim2.fromOffset(width, IsTouch and 32 or 28),
            BackgroundColor3 = color, Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Theme.Text,
        }, { corner(7) })
        return b
    end

    function rebuild()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        table.clear(distanceLabels)
        spotsGroup.SetTitle("⭐ Your spots (" .. #spots .. ")")
        emptyLabel.Text = #spots == 0 and "No spots yet. Stand somewhere and tap Save."
            or "Type a name above and tap ✏️ to rename a spot. 🗑 twice to delete."
        for i, spot in ipairs(spots) do
            local row = create("Frame", {
                Parent = list, LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, IsTouch and 52 or 46),
                BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.25,
            }, { corner(8), stroke(Theme.Stroke, 1, 0.55) })
            create("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 18),
                Text = "📍 " .. spot.Name, Font = Enum.Font.GothamBold, TextSize = 13,
                TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            })
            distanceLabels[i] = create("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -170, 0, 14),
                Text = "", Font = Enum.Font.Gotham, TextSize = 11,
                TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
            })

            local go = smallButton(row, "Go", 52, Theme.Accent, -84)
            go.MouseButton1Click:Connect(function()
                goTo(Vector3.new(spot.X, spot.Y, spot.Z), spot.Name)
            end)

            local rename = smallButton(row, "✏️", 32, Theme.Field, -46)
            rename.MouseButton1Click:Connect(function()
                local name = typedName()
                if not name then return notify("✏️ Rename", "Type the new name in the box at the top first.", 3) end
                spot.Name = name
                nameBox.Text = ""
                persist()
                rebuild()
            end)

            local armed = 0
            local delete = smallButton(row, "🗑", 32, Theme.Field, -8)
            delete.MouseButton1Click:Connect(function()
                if os.clock() > armed then
                    armed = os.clock() + 3
                    delete.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
                    delete.Text = "?"
                    task.delay(3, function()
                        if delete.Parent and os.clock() > armed then
                            delete.BackgroundColor3 = Theme.Field
                            delete.Text = "🗑"
                        end
                    end)
                    return
                end
                table.remove(spots, i)
                persist()
                rebuild()
                notify("🗑 Deleted " .. spot.Name, "", 2)
            end)
        end
    end
    rebuild()

    -- live distances while the tab is open
    local nextUpdate = 0
    track(RunService.Heartbeat:Connect(function()
        if os.clock() < nextUpdate or not Holder.Visible or ActiveTab ~= TeleportTab then return end
        nextUpdate = os.clock() + 0.5
        local root = getRoot()
        for i, label in pairs(distanceLabels) do
            local spot = spots[i]
            if spot then
                label.Text = root and string.format("%d studs away", (Vector3.new(spot.X, spot.Y, spot.Z) - root.Position).Magnitude)
                    or string.format("%d, %d, %d", spot.X, spot.Y, spot.Z)
            end
        end
    end))

    -- ---------- how to travel ----------
    TeleportTab:Section("⚙️ How to travel")
    TeleportTab:Toggle("✈️ Fly there smoothly instead of teleporting", false, function(on) Travel.Smooth = on end)
    TeleportTab:Slider("🚀 Fly-there speed", 50, 2000, Travel.Speed, function(v) Travel.Speed = v end)
end)

-- 🥚 Farm
isolate(function()
if not Game.Supported then
    FarmTab:Section("⚠️ Not available here")
    FarmTab:Label("This tab works in Break & Steal an Egg. The Player, Teleport and Settings tabs work everywhere.")
else
    FarmTab:Section("🤖 Auto farm")
    local statusLabel = FarmTab:Label("💤 Idle")
    local farmToggle = FarmTab:Toggle("▶ Auto farm", false, function(on)
        if on then Farm.Start() else Farm.Stop() end
    end)
    table.insert(Mobile.Targets, { Id = "Farm", Icon = "🥚", Label = "Farm", Toggle = farmToggle })
    Mobile.FarmToggle = farmToggle

    -- live status while the tab is open
    local nextUpdate = 0
    track(RunService.Heartbeat:Connect(function()
        if os.clock() < nextUpdate or not Holder.Visible or ActiveTab ~= FarmTab then return end
        nextUpdate = os.clock() + 0.3
        local hours = Farm.SessionStart and (os.clock() - Farm.SessionStart) / 3600 or 0
        statusLabel.Text = string.format(
            "<b>%s</b>\n🥚 %d broken  ·  🐾 %d grabbed  ·  🏠 %d banked  ·  📦 %d placed\n🎒 Carrying %d / %d%s",
            Farm.Enabled and Farm.Status or "💤 Idle",
            Farm.Broken, Farm.Grabbed, Farm.Banked, Farm.Placed,
            Game.Carrying(), Game.Capacity(),
            hours > 0.02 and string.format("  ·  %d eggs / hour", math.floor(Farm.Broken / hours + 0.5)) or "")
    end))

    FarmTab:Section("✅ What it does")
    FarmTab:Toggle("⛏️ Break eggs", Farm.DoBreak, function(on) Farm.DoBreak = on end)
    FarmTab:Toggle("🐾 Grab animals that drop", Farm.DoGrab, function(on) Farm.DoGrab = on end)
    FarmTab:Toggle("🏠 Bring them home when full", Farm.DoBank, function(on) Farm.DoBank = on end)
    FarmTab:Toggle("📦 Place them in your pen", Farm.DoPlace, function(on) Farm.DoPlace = on end)

    FarmTab:Section("🎯 Which eggs")
    local zoneNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Cosmic", "Secret" }
    local zoneGroup = FarmTab:Dropdown("🗺️ Zones (none on = any zone)", false)
    for i, rarity in ipairs(zoneNames) do
        zoneGroup:Toggle("Zone " .. i .. " · " .. rarity, false, function(on) Farm.Zones[i] = on or nil end)
    end

    local targets = { "Nearest", "Weakest", "Best zone" }
    local savedTarget = savedValue(FarmTab, "Target")
    if type(savedTarget) == "string" and table.find(targets, savedTarget) then Farm.Target = savedTarget end
    local targetGroup = FarmTab:Dropdown("🎯 Pick eggs: " .. Farm.Target, false)
    for _, name in ipairs(targets) do
        targetGroup:Option(name, function()
            Farm.Target = name
            storeValue(FarmTab, "Target", name)
            targetGroup.SetTitle("🎯 Pick eggs: " .. name)
        end)
    end
    table.insert(DefaultResetters, function()
        Farm.Target = "Nearest"
        targetGroup.SetTitle("🎯 Pick eggs: Nearest")
    end)
    FarmTab:Slider("⏱️ Skip eggs slower than (seconds)", 5, 600, Farm.MaxSeconds, function(v) Farm.MaxSeconds = v end)
    FarmTab:Label("Eggs your pickaxe would take longer than this to break are skipped. Upgrade your pickaxe to break bigger eggs.")

    FarmTab:Section("🐾 Which animals")
    local savedRarity = savedValue(FarmTab, "MinRarity")
    if type(savedRarity) == "number" and RarityOrder[savedRarity] then Farm.MinRarity = savedRarity end
    local rarityGroup = FarmTab:Dropdown("💎 Grab at least: " .. RarityOrder[Farm.MinRarity], false)
    for i, rarity in ipairs(RarityOrder) do
        rarityGroup:Option(rarity, function()
            Farm.MinRarity = i
            storeValue(FarmTab, "MinRarity", i)
            rarityGroup.SetTitle("💎 Grab at least: " .. rarity)
        end)
    end
    table.insert(DefaultResetters, function()
        Farm.MinRarity = 1
        rarityGroup.SetTitle("💎 Grab at least: Common")
    end)
    FarmTab:Label("Rarest animals are grabbed first. Animals saved for another player are left alone.")

    FarmTab:Section("🚀 Travel")
    FarmTab:Toggle("✈️ Fly instead of teleporting", false, function(on) Farm.Smooth = on end)
    FarmTab:Slider("💨 Fly speed", 50, 1000, Farm.Speed, function(v) Farm.Speed = v end)

    FarmTab:Section("🛠️ Do it once")
    local function once(fn)
        if Farm.Enabled then return notify("🤖 Auto farm is on", "Stop it first.") end
        Farm.Token += 1
        local ok, err = pcall(fn, Farm.Token)
        if not ok then notify("⚠️ Didn't work", tostring(err), 4) end
    end
    FarmTab:Button("⛏️ Break the nearest egg", function()
        once(function(token)
            local saved = Farm.Target
            Farm.Target = "Nearest"
            local egg = Farm.PickEgg()
            Farm.Target = saved
            if not egg then return notify("🥚 No egg found", "None in your zones that you can break in time.") end
            local wasBreaking = Farm.DoBreak
            Farm.DoBreak = true
            Farm.BreakEgg(egg, token)
            Farm.DoBreak = wasBreaking
            notify("🥚 Done", Game.EggLive(egg) and "Stopped before it broke." or "Egg broken!", 2)
        end)
    end)
    FarmTab:Button("🐾 Grab the best animal", function()
        once(function(token)
            local model = Farm.PickAnimal()
            if not model then return notify("🐾 No animal found", "Nothing to grab right now.") end
            notify("🐾 " .. Game.AnimalName(model), Farm.Grab(model, token) and "Grabbed!" or "Couldn't grab it.", 2)
        end)
    end)
    FarmTab:Button("🏠 Bring my animals home", function()
        once(function(token)
            if Game.Carrying() == 0 then return notify("🏠 Not carrying anything", "") end
            notify("🏠 Home", Farm.GoHome(token) and "Animals banked." or "They didn't bank. Try again.", 3)
        end)
    end)
end
end)

-- 🏡 Base
isolate(function()
if not Game.Supported then
    BaseTab:Section("⚠️ Not available here")
    BaseTab:Label("This tab works in Break & Steal an Egg.")
else
    BaseTab:Section("📦 Pen")
    local penLabel = BaseTab:Label("-")
    local nextUpdate = 0
    track(RunService.Heartbeat:Connect(function()
        if os.clock() < nextUpdate or not Holder.Visible or ActiveTab ~= BaseTab then return end
        nextUpdate = os.clock() + 0.5
        local plot = Game.MyPlot()
        if not plot then
            penLabel.Text = "No base found yet."
            return
        end
        penLabel.Text = string.format("🐾 %d placed  ·  %d free spots\n🎒 %d animals in your backpack\n💰 $%s  (+$%s/s)",
            Game.Num(plot, "AnimalsPlaced", 0), Game.PlotSpace(), #Game.AnimalTools(),
            Game.Short(Game.Cash()), Game.Short(Game.Num(LocalPlayer, "CashPerSecond", 0)))
    end))
    BaseTab:Button("📦 Place my animals now", function()
        if Farm.Enabled then return notify("🤖 Auto farm is on", "It places them for you.") end
        if #Game.AnimalTools() == 0 then return notify("📦 Nothing to place", "Your backpack has no animals.") end
        if Game.PlotSpace() <= 0 then return notify("📦 Pen is full", "Upgrade your base or sell some animals.") end
        Farm.Token += 1
        local n = Farm.PlaceAll(Farm.Token)
        notify("📦 Placed " .. n, n > 0 and "In your pen." or "The game didn't accept them. Stand in your base and try again.", 3)
    end)
    BaseTab:Button("⭐ Equip best animals", function()
        notify("⭐ Equip best", Game.Fire("PetsInventoryRemote", "EquipBest", nil) and "Sent." or "Not available.", 2)
    end)

    BaseTab:Section("💰 Sell")
    local sellUpTo = 2
    local savedSell = savedValue(BaseTab, "SellUpTo")
    if type(savedSell) == "number" and RarityOrder[savedSell] then sellUpTo = savedSell end
    local sellGroup = BaseTab:Dropdown("💰 Sell up to: " .. RarityOrder[sellUpTo], false)
    for i, rarity in ipairs(RarityOrder) do
        sellGroup:Option(rarity, function()
            sellUpTo = i
            storeValue(BaseTab, "SellUpTo", i)
            sellGroup.SetTitle("💰 Sell up to: " .. rarity)
        end)
    end
    local armed = 0
    BaseTab:Button("💰 Sell backpack animals", function()
        if os.clock() > armed then
            armed = os.clock() + 4
            return notify("💰 Sure?", (IsTouch and "Tap" or "Click") .. " again to sell every backpack animal up to "
                .. RarityOrder[sellUpTo] .. ". Placed animals are kept.", 4)
        end
        armed = 0
        local n = Game.SellUpTo(sellUpTo)
        notify("💰 Sold " .. n, n > 0 and "animals." or "Nothing matched.", 3)
    end)

    BaseTab:Section("⬆️ Upgrades")
    BaseTab:Button("🏡 Upgrade base (more pen space)", function()
        notify("🏡 Upgrade base", Game.UpgradePlot() and "Upgraded!" or "Not enough cash yet.", 2)
    end)
    BaseTab:Button("🏃 Upgrade treadmill", function()
        notify("🏃 Treadmill", Game.UpgradeTreadmill() and "Upgraded!" or "Not enough cash yet.", 2)
    end)
    BaseTab:Button("⛏️ Buy next pickaxe", function()
        if not Game.BuyPickaxe() then notify("⛏️ Pickaxe", "Not enough cash for the next one yet.", 2) end
    end)
    BaseTab:Button("✨ Buy next trail", function()
        if not Game.BuyTrail() then notify("✨ Trail", "Not enough cash for the next one yet.", 2) end
    end)
end
end)

-- 🤖 Auto
isolate(function()
if not Game.Supported then
    AutoTab:Section("⚠️ Not available here")
    AutoTab:Label("This tab works in Break & Steal an Egg.")
else
    AutoTab:Section("🛒 Shop")
    AutoTab:Toggle("⛏️ Auto buy better pickaxes", false, function(on) Auto.Pickaxe = on end)
    AutoTab:Toggle("✨ Auto buy faster trails", false, function(on) Auto.Trail = on end)
    AutoTab:Section("⬆️ Upgrades")
    AutoTab:Toggle("🏡 Auto upgrade base", false, function(on) Auto.Plot = on end)
    AutoTab:Toggle("🏃 Auto upgrade treadmill", false, function(on) Auto.Treadmill = on end)
    AutoTab:Section("🎁 Rewards")
    AutoTab:Toggle("🎁 Auto claim rewards", false, function(on) Auto.Rewards = on end)
    AutoTab:Label("Offline cash, group reward and index rewards, checked every minute.")
    AutoTab:Label("Each one buys as soon as you have the cash. Checked every 3 seconds.")
end
end)


-- 👁️ ESP
safeSection("ESP", function()
    local ESP = {
        Players = false, Eggs = false, Animals = false, Guards = false,
        Chams = true, Names = true, Distance = true,
        MaxDistance = 3000,
    }
    local MAX_CHAMS = 30 -- Roblox only draws 31 Highlights at once
    local PLAYER_COLOR = Color3.fromRGB(255, 110, 80)

    -- billboards and highlights live next to the menu, not inside it
    local container = create("Folder", { Name = "SmurfysESP" })
    pcall(function()
        local parent = ScreenGui.Parent
        local old = parent:FindFirstChild(container.Name)
        if old then old:Destroy() end
        container.Parent = parent
    end)
    table.insert(UnloadHooks, function() container:Destroy() end)

    local entries = {} -- [Model] = entry

    local function newEntry(target, color)
        local highlight = create("Highlight", {
            Parent = container,
            Adornee = target,
            Enabled = false,
            FillColor = color,
            FillTransparency = 0.65,
            OutlineColor = color,
            OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        })

        local billboard = create("BillboardGui", {
            Parent = container,
            Enabled = false,
            AlwaysOnTop = true,
            LightInfluence = 0,
            ClipsDescendants = false,
            Size = UDim2.fromOffset(220, 48),
            StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
        })
        local pill = create("Frame", {
            Parent = billboard,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            BackgroundColor3 = Theme.BgDeep,
            BackgroundTransparency = 0.2,
        }, {
            corner(8),
            padding(4, 4, 8, 10),
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, 7),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        })
        local pillStroke = stroke(color, 1.5, 0.15)
        pillStroke.Parent = pill
        local dot = create("Frame", {
            Parent = pill,
            LayoutOrder = 1,
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = color,
        }, { round() })
        local textColumn = create("Frame", {
            Parent = pill,
            LayoutOrder = 2,
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
        }, {
            create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
        })
        local nameLabel = create("TextLabel", {
            Parent = textColumn,
            LayoutOrder = 1,
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Color3.new(1, 1, 1),
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        local infoLabel = create("TextLabel", {
            Parent = textColumn,
            LayoutOrder = 2,
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = Color3.fromRGB(190, 200, 225),
            TextXAlignment = Enum.TextXAlignment.Left,
        })

        return {
            Highlight = highlight, Billboard = billboard, Stroke = pillStroke,
            Dot = dot, Name = nameLabel, Info = infoLabel, Color = color,
        }
    end

    local function setColor(e, color)
        if e.Color == color then return end
        e.Color = color
        e.Highlight.FillColor = color
        e.Highlight.OutlineColor = color
        e.Stroke.Color = color
        e.Dot.BackgroundColor3 = color
    end

    local function removeEntry(key)
        local e = entries[key]
        if not e then return end
        entries[key] = nil
        e.Highlight:Destroy()
        e.Billboard:Destroy()
    end

    local function infoText(first, dist)
        local parts = {}
        if ESP.Names and first then table.insert(parts, first) end
        if ESP.Distance then table.insert(parts, string.format("%dm", math.floor(dist + 0.5))) end
        return table.concat(parts, "  •  ")
    end

    local function update()
        local root = getRoot()
        local cam = workspace.CurrentCamera
        local origin = (root and root.Position) or (cam and cam.CFrame.Position)
        if not origin then return end

        local seen, shown = {}, {}

        if ESP.Players then
            for _, plr in ipairs(Players:GetPlayers()) do
                local char = plr ~= LocalPlayer and plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local part = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
                if hum and part and part:IsA("BasePart") and hum.Health > 0 then
                    local dist = (part.Position - origin).Magnitude
                    if dist <= ESP.MaxDistance then
                        local e = entries[char]
                        if not e then
                            e = newEntry(char, PLAYER_COLOR)
                            e.Billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
                            entries[char] = e
                        end
                        e.Billboard.Adornee = part
                        e.Name.Text = plr.DisplayName == plr.Name and plr.Name
                            or (plr.DisplayName .. "  <font transparency=\"0.4\">@" .. plr.Name .. "</font>")
                        e.Name.RichText = true
                        e.Info.Text = infoText(string.format("❤ %d", math.floor(hum.Health + 0.5)), dist)
                        seen[char] = true
                        table.insert(shown, { e, dist })
                    end
                end
            end
        end

        -- one billboard + highlight per thing, keyed by the instance
        local function show(key, adornee, pos, color, name, info, offset)
            local dist = (pos - origin).Magnitude
            if dist > ESP.MaxDistance then return end
            local e = entries[key]
            if not e then
                e = newEntry(adornee, color)
                e.Billboard.Adornee = adornee
                e.Billboard.StudsOffsetWorldSpace = Vector3.new(0, offset or 3, 0)
                entries[key] = e
            end
            setColor(e, color)
            e.Name.Text = name
            e.Info.Text = infoText(info, dist)
            seen[key] = true
            table.insert(shown, { e, dist })
        end

        if ESP.Eggs then
            for _, egg in ipairs(Game.Eggs()) do
                local name, zone = Game.EggInfo(egg)
                local hp, max = Game.Num(egg, "Health", 0), Game.Num(egg, "MaxHealth", 0)
                local secs = Game.SecondsToBreak(egg)
                local color = RarityColors[RarityOrder[zone or 1]] or RarityColors.Common
                show(egg, egg, egg.Position, color, name,
                    string.format("❤ %s%s", Game.Short(hp), secs and string.format(" · %ds", math.ceil(secs)) or "")
                        .. (max > 0 and hp < max and string.format(" (%d%%)", math.floor(hp / max * 100)) or ""),
                    egg.Size.Y / 2 + 1)
            end
        end

        if ESP.Animals then
            local now = workspace:GetServerTimeNow()
            for _, model in ipairs(Game.Pickups()) do
                local ok, pivot = pcall(model.GetPivot, model)
                if ok then
                    local rarity = Game.Rarity(model)
                    local despawn = Game.Num(model, "DespawnAtServerTime", nil)
                    local extra = despawn and string.format(" · %ds", math.max(math.floor(despawn - now), 0)) or ""
                    if Game.Reserved(model) then extra = extra .. " · reserved" end
                    show(model, model, pivot.Position, RarityColors[rarity] or RarityColors.Common,
                        Game.AnimalName(model), rarity .. extra, 3)
                end
            end
        end

        if ESP.Guards then
            for _, guard in ipairs(Game.Tagged("ZoneGuard")) do
                local ok, pivot = pcall(guard.GetPivot, guard)
                if ok and guard.Parent then
                    local state = Game.Attr(guard, "ChaseState")
                    show(guard, guard, pivot.Position, Color3.fromRGB(255, 70, 70), "🛡️ " .. guard.Name,
                        type(state) == "string" and state or "Guard", 5)
                end
            end
        end

        for key in pairs(entries) do
            if not seen[key] then removeEntry(key) end
        end

        -- chams go to the nearest things first
        table.sort(shown, function(a, b) return a[2] < b[2] end)
        for i, item in ipairs(shown) do
            local e = item[1]
            e.Highlight.Enabled = ESP.Chams and i <= MAX_CHAMS
            e.Name.Visible = ESP.Names
            e.Info.Visible = e.Info.Text ~= ""
            e.Billboard.Enabled = ESP.Names or ESP.Distance
        end
    end

    local elapsed = 0
    track(RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed < 0.1 then return end
        elapsed = 0
        pcall(update)
    end))

    EspTab:Section("👁️ Show")
    EspTab:Toggle("🧍 Players", false, function(on) ESP.Players = on end)
    EspTab:Toggle("🥚 Eggs (type, health, time to break)", false, function(on) ESP.Eggs = on end)
    EspTab:Toggle("🐾 Animals to grab", false, function(on) ESP.Animals = on end)
    EspTab:Toggle("🛡️ Guards", false, function(on) ESP.Guards = on end)

    EspTab:Section("🎨 Style")
    EspTab:Toggle("✨ Chams", ESP.Chams, function(on) ESP.Chams = on end)
    EspTab:Toggle("🏷️ Names / type", ESP.Names, function(on) ESP.Names = on end)
    EspTab:Toggle("📏 Distance", ESP.Distance, function(on) ESP.Distance = on end)
    EspTab:Slider("📡 Max distance", 50, 3000, ESP.MaxDistance, function(v) ESP.MaxDistance = v end)
end)

-- 💡 Lighting (on the ESP tab)
safeSection("Lighting", function()
    local Lighting = game:GetService("Lighting")

    ------------------------------------------------ lighting overrides
    -- the game's day/night cycle keeps changing lighting, so overrides are
    -- re-applied every frame while on and put back exactly when turned off
    local enforced, original = {}, {}
    local function override(props, on)
        for prop, value in pairs(props) do
            if on then
                if original[prop] == nil then original[prop] = Lighting[prop] end
                enforced[prop] = value
                pcall(function() Lighting[prop] = value end)
            elseif enforced[prop] ~= nil then
                enforced[prop] = nil
                local old = original[prop]
                original[prop] = nil
                pcall(function() Lighting[prop] = old end)
            end
        end
    end
    track(RunService.Heartbeat:Connect(function()
        for prop, value in pairs(enforced) do
            if Lighting[prop] ~= value then Lighting[prop] = value end
        end
    end))

    local FULLBRIGHT = {
        Brightness = 2,
        Ambient = Color3.fromRGB(178, 178, 178),
        OutdoorAmbient = Color3.fromRGB(178, 178, 178),
        ExposureCompensation = 0,
    }
    local NO_SHADOWS = { GlobalShadows = false }
    local NO_FOG = { FogStart = 0, FogEnd = 1e6 }
    table.insert(UnloadHooks, function()
        override(FULLBRIGHT, false)
        override(NO_SHADOWS, false)
        override(NO_FOG, false)
    end)

    EspTab:Section("💡 Lighting")
    EspTab:Toggle("☀️ Fullbright", false, function(on) override(FULLBRIGHT, on) end)
    EspTab:Toggle("🌑 No shadows", false, function(on) override(NO_SHADOWS, on) end)
    EspTab:Toggle("🌫️ No fog", false, function(on) override(NO_FOG, on) end)
end)

-- 📲 Buttons (touch screens only)
if ButtonsTab then
    safeSection("Buttons", function()
        ButtonsTab:Section("📲 Show on screen")
        for _, target in ipairs(Mobile.Targets) do
            local q = Mobile.AddFeatureButton(target)
            local show = ButtonsTab:Toggle(target.Icon .. " " .. target.Label .. " button", target.Default == true, q.SetShown)
            q.SetShown(show.Get())
        end

        ButtonsTab:Section("✏️ Layout")
        ButtonsTab:Button("✏️ Move buttons", function() Mobile.SetEditing(true) end)
        ButtonsTab:Slider("📏 Button size (%)", 70, 150, 100, function(v) Mobile.SetStyle(v / 100, nil) end)
        ButtonsTab:Slider("🔍 Button see-through (%)", 0, 80, 25, function(v) Mobile.SetStyle(nil, v / 100) end)
        ButtonsTab:Button("↩️ Reset button positions", function()
            Mobile.ResetPositions()
            notify("↩️ Positions reset", "Every button is back in its starting spot.")
        end)
    end)
end

-- ⚙️ Settings
if not IsTouch then
    Settings:Section("⌨️ Keybinds")
    Settings:Keybind("🔑 Open / close menu", Binds.Menu, function(key)
        Binds.Menu = key
        KeyPill.Text = "⌨️ " .. key.Name
        keyHint.Text = "⌨️ <b>" .. key.Name .. "</b> opens and closes the menu"
        notify("✅ Keybind updated", "Menu key is now " .. key.Name .. ".")
    end)
end

if not IsTouch then
    Settings:Toggle("🔵 S button while minimized", true, function(on)
        Mobile.ShowMinimized = on
        Mobile.OnOpenChanged(IsOpen)
    end)
end

-- 📱 Device: force a layout when the automatic one is wrong
Settings:Section("📱 Device")
do
    local modes = { "Auto", "PC", "Tablet", "Phone" }
    local detected = detectDevice()
    local chosen = DeviceMode
    local function text()
        return "📱 Layout: " .. chosen .. (chosen == "Auto" and (" (" .. detected .. ")") or "")
    end
    local layoutButton
    layoutButton = Settings:Button(text(), function()
        chosen = modes[(table.find(modes, chosen) or 1) % #modes + 1]
        layoutButton.Text = text()
        SavedSettings.DeviceMode = chosen ~= "Auto" and chosen or nil
        saveSettings()
        local wanted = chosen == "Auto" and detected or chosen
        if wanted == Device then
            notify("📱 Layout: " .. chosen, "That's the layout you're using now.")
        else
            notify("📱 Layout: " .. chosen, "Run the script again to switch to the " .. wanted .. " layout.", 5)
        end
    end)
    Settings:Label("Using the <b>" .. Device .. "</b> layout. Tap above to change it if it looks wrong on your device.")
end

-- 🎨 Themes
local applyThemeByName
isolate(function()
do
    local Themes = {
        { Name = "Ocean", Icon = "🌊", Colors = ThemeDefaults },
        { Name = "Nebula", Icon = "🔮", Colors = {
            BgDeep = Color3.fromRGB(9, 5, 20),       BgMid = Color3.fromRGB(26, 13, 50),
            BgBlue = Color3.fromRGB(90, 40, 165),    Sidebar = Color3.fromRGB(8, 4, 18),
            Panel = Color3.fromRGB(25, 15, 45),      PanelHover = Color3.fromRGB(42, 27, 76),
            Field = Color3.fromRGB(14, 8, 29),       Accent = Color3.fromRGB(150, 90, 255),
            AccentLight = Color3.fromRGB(205, 170, 255), AccentDark = Color3.fromRGB(86, 40, 178),
            Text = Color3.fromRGB(255, 255, 255),    SubText = Color3.fromRGB(182, 166, 212),
            TabText = Color3.fromRGB(232, 222, 250), Stroke = Color3.fromRGB(82, 58, 140),
        } },
        { Name = "Emerald", Icon = "🍀", Colors = {
            BgDeep = Color3.fromRGB(3, 14, 11),      BgMid = Color3.fromRGB(7, 33, 27),
            BgBlue = Color3.fromRGB(14, 102, 74),    Sidebar = Color3.fromRGB(3, 12, 9),
            Panel = Color3.fromRGB(11, 31, 25),      PanelHover = Color3.fromRGB(19, 50, 40),
            Field = Color3.fromRGB(5, 19, 15),       Accent = Color3.fromRGB(36, 200, 132),
            AccentLight = Color3.fromRGB(135, 240, 192), AccentDark = Color3.fromRGB(16, 118, 80),
            Text = Color3.fromRGB(255, 255, 255),    SubText = Color3.fromRGB(150, 200, 182),
            TabText = Color3.fromRGB(214, 245, 232), Stroke = Color3.fromRGB(38, 96, 76),
        } },
    }

    local NoThemeRoots = {}
    local currentTheme = "Ocean"

    local function colorKey(c)
        return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end

    -- recolors every element that uses a theme color, then updates Theme so
    -- anything created or animated later uses the new colors too
    local function applyTheme(colors)
        local remap = {}
        for key, newColor in pairs(colors) do
            if Theme[key] then remap[colorKey(Theme[key])] = newColor end
        end
        local function swap(c) return remap[colorKey(c)] end

        local skip = {}
        for _, rootObj in ipairs(NoThemeRoots) do
            skip[rootObj] = true
            for _, d in ipairs(rootObj:GetDescendants()) do skip[d] = true end
        end

        for _, obj in ipairs(ScreenGui:GetDescendants()) do
            if not skip[obj] then
                pcall(function()
                    if obj:IsA("GuiObject") then
                        local n = swap(obj.BackgroundColor3)
                        if n then obj.BackgroundColor3 = n end
                        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                            n = swap(obj.TextColor3)
                            if n then obj.TextColor3 = n end
                        end
                        if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                            n = swap(obj.ImageColor3)
                            if n then obj.ImageColor3 = n end
                        end
                        if obj:IsA("ScrollingFrame") then
                            n = swap(obj.ScrollBarImageColor3)
                            if n then obj.ScrollBarImageColor3 = n end
                        end
                    elseif obj:IsA("UIStroke") then
                        local n = swap(obj.Color)
                        if n then obj.Color = n end
                    elseif obj:IsA("UIGradient") then
                        local points, changed = {}, false
                        for i, kp in ipairs(obj.Color.Keypoints) do
                            local n = swap(kp.Value)
                            if n then changed = true end
                            points[i] = ColorSequenceKeypoint.new(kp.Time, n or kp.Value)
                        end
                        if changed then obj.Color = ColorSequence.new(points) end
                    end
                end)
            end
        end

        for key, c in pairs(colors) do Theme[key] = c end
    end

    Settings:Section("🎨 Theme")
    local row = create("Frame", {
        Parent = Settings.Page,
        LayoutOrder = nextOrder(Settings),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 46),
    }, {
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local tiles = {}
    local function refreshTiles()
        for name, t in pairs(tiles) do
            local on = name == currentTheme
            t.Stroke.Thickness = on and 2 or 1
            t.Stroke.Transparency = on and 0 or 0.7
        end
    end

    function applyThemeByName(name)
        if name == currentTheme then return end
        for _, theme in ipairs(Themes) do
            if theme.Name == name then
                applyTheme(theme.Colors)
                currentTheme = name
                refreshTiles()
                SavedSettings.Theme = name
                saveSettings()
                return
            end
        end
    end

    for i, theme in ipairs(Themes) do
        local tileStroke = stroke(Color3.new(1, 1, 1), 1, 0.7)
        local tile = create("Frame", {
            Parent = row,
            LayoutOrder = i,
            Size = UDim2.new(1 / 3, -4, 1, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
        }, {
            corner(9),
            tileStroke,
            create("UIGradient", {
                Rotation = 135,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, theme.Colors.BgMid),
                    ColorSequenceKeypoint.new(1, theme.Colors.Accent),
                }),
            }),
        })
        local button = create("TextButton", {
            Parent = tile,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1),
            Text = theme.Icon .. "  " .. theme.Name,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Color3.new(1, 1, 1),
        })
        local tileScale = create("UIScale", { Parent = tile })
        if not IsTouch then
            button.MouseEnter:Connect(function() tween(tileScale, 0.15, { Scale = 1.03 }) end)
            button.MouseLeave:Connect(function() tween(tileScale, 0.15, { Scale = 1 }) end)
        end
        button.MouseButton1Click:Connect(function() applyThemeByName(theme.Name) end)

        tiles[theme.Name] = { Stroke = tileStroke }
        table.insert(NoThemeRoots, tile)
    end
    refreshTiles()
end
end)

Settings:Section("🎨 Interface")
Settings:Toggle("🔔 Notifications", true, function(on) NotifsOn = on end)
Settings:Toggle("🌟 Background stars", true, function(on)
    EffectsOn = on
    StarLayer.Visible = on
end)

-- 🔋 Battery saver: after a while with no input the 3D view turns off and
-- the frame rate drops, behind a dark screen with the farm's status.
-- Any tap / click / key wakes it up.
Settings:Section("🔋 Battery saver")
isolate(function()
    local Saver = { Enabled = false, AfterSeconds = 120, Active = false, LastInput = os.clock() }

    local overlay = create("TextButton", {
        Name = "BatterySaver",
        Parent = ScreenGui,
        ZIndex = 50, -- above everything, including the S button
        Visible = false,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        Text = "",
    })
    local info = create("TextLabel", {
        Parent = overlay,
        ZIndex = 51,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.9, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        RichText = true,
        TextWrapped = true,
        Text = "",
        Font = Enum.Font.GothamMedium,
        TextSize = 15,
        TextColor3 = Color3.fromRGB(150, 160, 180),
    })

    local savedCap
    local function setRendering(on)
        pcall(function() RunService:Set3dRenderingEnabled(on) end)
        if type(setfpscap) ~= "function" then return end
        if on then
            pcall(setfpscap, savedCap or 60)
        else
            if type(getfpscap) == "function" then
                local ok, cap = pcall(getfpscap)
                savedCap = ok and tonumber(cap) or nil
            end
            pcall(setfpscap, 15)
        end
    end

    local function sleep()
        if Saver.Active then return end
        Saver.Active = true
        overlay.Visible = true
        setRendering(false)
    end

    local function wake()
        Saver.LastInput = os.clock()
        if not Saver.Active then return end
        Saver.Active = false
        overlay.Visible = false
        setRendering(true)
    end

    -- real input only (the anti-AFK's fake right click must not wake it)
    local wakeTypes = {
        [Enum.UserInputType.Touch] = true,
        [Enum.UserInputType.MouseButton1] = true,
        [Enum.UserInputType.Keyboard] = true,
        [Enum.UserInputType.MouseWheel] = true,
        [Enum.UserInputType.Gamepad1] = true,
    }
    track(UserInputService.InputBegan:Connect(function(input)
        if wakeTypes[input.UserInputType] then wake() end
    end))
    overlay.MouseButton1Click:Connect(wake)

    local nextCheck = 0
    track(RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now < nextCheck then return end
        nextCheck = now + 1
        if Saver.Active then
            local lines = { "🔋 <b>Battery saver</b>" }
            if Farm.Enabled then
                table.insert(lines, Farm.Status)
                local hours = Farm.SessionStart and (now - Farm.SessionStart) / 3600 or 0
                table.insert(lines, string.format("🥚 %d eggs broken · 🐾 %d banked%s", Farm.Broken, Farm.Banked,
                    hours > 0.01 and string.format(" · %d eggs per hour", math.floor(Farm.Broken / hours + 0.5)) or ""))
            end
            table.insert(lines, "\n<font size=\"12\">" .. (IsTouch and "Tap" or "Click") .. " anywhere to wake up</font>")
            info.Text = table.concat(lines, "\n")
        elseif Saver.Enabled and now - Saver.LastInput >= Saver.AfterSeconds then
            sleep()
        end
    end))

    Settings:Toggle("🔋 Dark screen when AFK", false, function(on)
        Saver.Enabled = on
        Saver.LastInput = os.clock()
        if not on then wake() end
    end)
    Settings:Slider("⏱️ AFK after (seconds)", 30, 600, Saver.AfterSeconds, function(v)
        Saver.AfterSeconds = v
    end)
    Settings:Button("🌙 Turn it on now", function()
        task.delay(0.3, sleep) -- after the tap that pressed this, so it doesn't wake right away
    end)
    Settings:Label("Turns off the 3D view and lowers the frame rate to save battery and heat. Auto farm keeps running.")
    table.insert(UnloadHooks, function() if Saver.Active then setRendering(true) end end)
end)

Settings:Section("🛡️ Protection")
Settings:Toggle("💤 Anti AFK", true, function(on) Auto.AntiAfk = on end)

Settings:Section("🌐 Server")
safeSection("Server hop", function()
    local TeleportService = game:GetService("TeleportService")
    track(TeleportService.TeleportInitFailed:Connect(function(player, _, message)
        if player == LocalPlayer then notify("🔀 Server hop failed", tostring(message), 5) end
    end))

    Settings:Button("🔀 Server hop", function()
        notify("🔀 Server hop", "Looking for another server...")
        local servers, cursor = {}, nil
        for _ = 1, 3 do
            local url = string.format(
                "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true%s",
                game.PlaceId, cursor and ("&cursor=" .. cursor) or ""
            )
            local ok, data = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)
            if not ok or type(data) ~= "table" or type(data.data) ~= "table" then break end
            for _, server in ipairs(data.data) do
                local playing, max = tonumber(server.playing), tonumber(server.maxPlayers)
                if server.id ~= game.JobId and playing and max and playing < max then
                    table.insert(servers, server.id)
                end
            end
            if #servers > 0 or type(data.nextPageCursor) ~= "string" then break end
            cursor = data.nextPageCursor
        end

        local ok = false
        if #servers > 0 then
            ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(#servers)], LocalPlayer)
            end)
        end
        -- couldn't list servers: let Roblox pick one
        if not ok then
            ok = pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        end
        notify("🔀 Server hop", ok and "Joining another server..." or "Couldn't start the teleport.")
    end)
end)

Settings:Section("⚠️ Danger zone")
do
    local armedUntil = 0
    Settings:Button("🔄 Restore defaults", function()
        -- two clicks, so it can't happen by accident
        if os.clock() > armedUntil then
            armedUntil = os.clock() + 4
            notify("🔄 Restore defaults?", IsTouch and "Tap again to reset every toggle, slider, button and the theme."
                or "Click again to reset every toggle, slider, keybind and the theme.", 4)
            return
        end
        armedUntil = 0
        for _, resetToDefault in ipairs(DefaultResetters) do pcall(resetToDefault) end
        if applyThemeByName then applyThemeByName("Ocean") end
        Farm.Stop()
        if Mobile.ResetPositions then Mobile.ResetPositions() end
        SavedSettings.Values = {}
        SavedSettings.Theme = nil
        saveSettings()
        notify("🔄 Defaults restored", "Everything is back to how it started.")
    end)
end
Settings:Button("🗑️ Unload UI", unload)

-- ========================= START =========================
if type(SavedSettings.Theme) == "string" then applyThemeByName(SavedSettings.Theme) end
setOpen(true)
notify("💙 Smurfy's loaded", IsTouch and "Tap the round S button to open and close the menu."
    or ("Press " .. Binds.Menu.Name .. " to toggle the menu."))

-- ========================= DISCORD INVITE (first launch only) =========================
-- A small card asking people to join. It never blocks the menu, and once
-- it's answered it doesn't show again.
if CONFIG.DiscordLink ~= "" and not SavedSettings.DiscordPrompted then isolate(function()
    local function remember()
        SavedSettings.DiscordPrompted = true
        saveSettings()
    end

    local card = create("Frame", {
        Name = "DiscordInvite",
        Parent = ScreenGui,
        ZIndex = 12, -- above the window and the S button
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(IsTouch and 280 or 310, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, {
        corner(14),
        stroke(Theme.AccentLight, 1.5, 0.3),
        create("UIGradient", {
            Rotation = 120,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentDark),
                ColorSequenceKeypoint.new(0.6, Theme.BgMid),
                ColorSequenceKeypoint.new(1, Theme.BgDeep),
            }),
        }),
        create("UIListLayout", {
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
        padding(18, 16, 18, 18),
    })
    local cardScale = create("UIScale", { Parent = card, Scale = 0.6 })

    create("TextLabel", {
        Parent = card, LayoutOrder = 1, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24),
        Text = "💬 Join our Discord!", Font = Enum.Font.GothamBlack, TextSize = 19,
        TextColor3 = Theme.Text,
    })
    create("TextLabel", {
        Parent = card, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        Text = "Get updates, new features and help first. You can join any time from the Home tab too.",
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.SubText,
    })

    local row = create("Frame", {
        Parent = card, LayoutOrder = 3, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, IsTouch and 40 or 36),
    }, {
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local function close()
        remember()
        local t = tween(cardScale, 0.2, { Scale = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        t.Completed:Connect(function() card:Destroy() end)
    end

    local function cardButton(order, text, primary, onClick)
        local b = create("TextButton", {
            Parent = row, LayoutOrder = order,
            AutoButtonColor = false,
            Size = UDim2.new(0.5, -4, 1, 0),
            BackgroundColor3 = primary and Color3.fromRGB(88, 101, 242) or Theme.Panel,
            Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
            TextColor3 = Theme.Text,
        }, { corner(9), stroke(Theme.Text, 1, primary and 0.6 or 0.85) })
        b.MouseButton1Click:Connect(onClick)
    end

    cardButton(1, "📋 Copy invite", true, function()
        close()
        if type(setclipboard) == "function" then
            pcall(setclipboard, CONFIG.DiscordLink)
            notify("💬 Invite copied", "Paste it in your browser or Discord to join.", 5)
        else
            notify("💬 Discord", CONFIG.DiscordLink, 8)
        end
        -- PC: also ask the Discord app (if it's open) to show the invite
        local httpRequest = request or http_request or (syn and syn.request)
        if not IsTouch and type(httpRequest) == "function" then
            task.spawn(pcall, httpRequest, {
                Url = "http://127.0.0.1:6463/rpc?v=1",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json", Origin = "https://discord.com" },
                Body = HttpService:JSONEncode({
                    cmd = "INVITE_BROWSER",
                    nonce = HttpService:GenerateGUID(false),
                    args = { code = string.match(CONFIG.DiscordLink, "([%w%-]+)/?$") },
                }),
            })
        end
    end)
    cardButton(2, "Maybe later", false, close)

    tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end) end

