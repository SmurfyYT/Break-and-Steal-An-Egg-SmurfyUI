-- Steps run by build/test/run.sh after loading a build in the fake Roblox:
-- open button, on-screen buttons, edit mode, Discord card, logo minimize,
-- fly with the thumbstick, restore defaults, unload.
local ok, err = xpcall(__main, debug.traceback)
if not ok then print("LOAD FAILED: " .. tostring(err)) return end
print("loaded")
__runFrames(5)

local function touch(x, y) return { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(x or 10, y or 10, 0), UserInputState = Enum.UserInputState.Begin } end
local function tap(button)
    local i = touch()
    button.InputBegan:Fire(i)
    i.UserInputState = Enum.UserInputState.End
    __UIS.InputEnded:Fire(i, false)
    button.InputEnded:Fire(i)
    button.MouseButton1Click:Fire()
    __runFrames(2)
end
local function click(text)
    local b = __findText(text)
    if not b then print("  !! no button: " .. text) return end
    b.MouseButton1Click:Fire()
    __runFrames(2)
    print("  clicked " .. text)
end

local openFrame = __find("OpenButton")
if __DEVICE__ == "phone" then
    assert(openFrame, "no open button")
    local p = openFrame.Position
    print(("  open button at %.2f, %.2f (scale)"):format(p.X.Scale, p.Y.Scale))
    local btn = openFrame.__children[2] or openFrame.__children[1]
    for _, c in ipairs(openFrame.__children) do if c.ClassName == "TextButton" then btn = c end end
    tap(btn); print("  tapped open button (close)")
    tap(btn); print("  tapped open button (open)")
    -- drag the open button
    local i = touch(100, 30)
    btn.InputBegan:Fire(i)
    __UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(160, 90, 0) }, false)
    i.Position = Vector3.new(160, 90, 0)
    __UIS.InputChanged:Fire(i, false)
    __UIS.InputEnded:Fire(i, false)
    p = openFrame.Position
    print(("  after drag open button at %.3f, %.3f"):format(p.X.Scale, p.Y.Scale))

    local fly = __find("Quick_Fly")
    assert(fly, "no fly quick button")
    print("  fly button visible:", fly.Visible)
    for _, c in ipairs(fly.__children) do if c.ClassName == "TextButton" then tap(c) end end
    print("  tapped fly quick button")
    for _, id in ipairs({ "Quick_Noclip", "Quick_InfJump", "Quick_Speed", "Quick_FlyUp", "Quick_FlyDown" }) do
        local f = __find(id)
        print("  " .. id, f and f.Visible, f and ("%.2f,%.2f"):format(f.Position.X.Scale, f.Position.Y.Scale))
    end
    click("✏️ Move buttons")
    print("  editing; FlyUp visible:", __find("Quick_FlyUp").Visible, "edit bar:", __find("EditBar").Visible)
    click("✅ Done")
    print("  done; FlyUp visible:", __find("Quick_FlyUp").Visible, "edit bar:", __find("EditBar").Visible)
    local plus = __findText("+")
    local before = 0
    tap(plus); print("  tapped +")
    click("↩️ Reset button positions")
    __find("Minimize").MouseButton1Click:Fire(); __runFrames(2); print("  clicked minimize")
end
-- discord card
print("  invite card shown:", __find("DiscordInvite") ~= nil)
local copy = __findText("📋 Copy invite")
if copy then copy.MouseButton1Click:Fire(); __runFrames(3); print("  copied invite; card parent:", __find("DiscordInvite").Parent) end
-- logo minimizes, S + stats show
do
    local ob = __find("OpenButton")
    local logoBtn
    for _, inst in ipairs(__all()) do
        if inst.ClassName == "TextButton" and inst.Text == "" and inst.Parent and inst.Parent.Size and inst.Parent.Size.X.Offset == 30 then logoBtn = inst end
    end
    print("  before logo click: S visible", ob.Visible)
    logoBtn.MouseButton1Click:Fire()
    __runFrames(40)
    local stats
    for _, c in ipairs(ob.__children) do if c.ClassName == "TextLabel" and tostring(c.Text):find("FPS") then stats = c end end
    print("  after logo click: S visible", ob.Visible, "stats:", stats and stats.Visible, stats and stats.Text)
    assert(ob.Visible and stats and stats.Visible, "after minimizing, the S button and FPS pill should show")
    local p = ob.Position
    print(("  S at %.0f, %.0f px"):format(p.X.Scale * (__DEVICE__ == "phone" and 800 or 1600), p.Y.Scale * (__DEVICE__ == "phone" and 360 or 900)))
end
-- minimize button (top right of the window)
do
    local minimize = __find("Minimize")
    assert(minimize, "no minimize button")
    minimize.MouseButton1Click:Fire()
    __runFrames(30)
    print("  minimize -> window visible:", __find("Holder").Visible, "S button:", __find("OpenButton").Visible)
    assert(__find("OpenButton").Visible, "S button should show after minimizing")
end

-- saved teleport spots
do
    local root = __root
    local function box()
        for _, i in ipairs(__all()) do if i.ClassName == "TextBox" then return i end end
    end
    local function rows() -- one Go button per listed spot
        local n = 0
        for _, i in ipairs(__all()) do
            if i.ClassName == "TextButton" and i.Text == "Go" and i.Parent and i.Parent.Parent then n += 1 end
        end
        return n
    end
    local function pressExact(text)
        for _, i in ipairs(__all()) do
            if i.ClassName == "TextButton" and i.Text == text and i.Parent then i.MouseButton1Click:Fire(); __runFrames(2); return true end
        end
        error("no button " .. text)
    end
    root.CFrame = CFrame.new(Vector3.new(100, 10, -50))
    pressExact("📍 Save where I'm standing")
    root.CFrame = CFrame.new(Vector3.new(-300, 20, 80))
    box().Text = "Volcano"
    pressExact("📍 Save where I'm standing")
    print("  spots saved:", rows())
    assert(rows() == 2, "two spots should be listed")
    -- Go to the first spot (Spot 1 at 100,10,-50)
    local goButtons = {}
    for _, i in ipairs(__all()) do if i.ClassName == "TextButton" and i.Text == "Go" and i.Parent then table.insert(goButtons, i) end end
    goButtons[1].MouseButton1Click:Fire(); __runFrames(2)
    local p = root.Position
    print(("  Go -> %.0f, %.0f, %.0f"):format(p.X, p.Y, p.Z))
    assert(math.abs(p.X - 100) < 1 and math.abs(p.Z + 50) < 1, "Go should teleport to the spot")
    pressExact("↩️ Back to where I was"); __runFrames(2)
    p = root.Position
    assert(math.abs(p.X + 300) < 1, "Back should return to where you were")
    -- rename the first spot, then delete it (tap twice)
    box().Text = "Base corner"
    for _, i in ipairs(__all()) do if i.ClassName == "TextButton" and i.Text == "✏️" and i.Parent then i.MouseButton1Click:Fire(); break end end
    __runFrames(2)
    local renamed = false
    for _, i in ipairs(__all()) do if i.ClassName == "TextLabel" and i.Text == "📍 Base corner" and i.Parent then renamed = true end end
    assert(renamed, "rename should change the name")
    local del
    for _, i in ipairs(__all()) do if i.ClassName == "TextButton" and i.Text == "🗑" and i.Parent then del = i; break end end
    del.MouseButton1Click:Fire(); __runFrames(2)
    assert(rows() == 2, "one tap only arms delete")
    del.MouseButton1Click:Fire(); __runFrames(2)
    print("  spots after delete:", rows())
    assert(rows() == 1, "second tap deletes")
end

-- device switch
for _, inst in pairs({ __findText("📱 Layout: Auto (" .. (__DEVICE__ == "phone" and "Phone" or "PC") .. ")") }) do
    inst.MouseButton1Click:Fire(); __runFrames(2); print("  cycled layout ->", inst.Text)
end
-- fly with the stick pushed forward
do
    local flyT
    for _, inst in ipairs(__all()) do
        if inst.ClassName == "TextButton" and inst.Text == "Fly" then flyT = inst end
    end
    flyT.MouseButton1Click:Fire()
    __runFrames(30)
    local lv
    for _, c in ipairs(__root.__children) do if c.ClassName == "LinearVelocity" then lv = c end end
    local v = lv and lv.VectorVelocity
    print(("  FLY VELOCITY: %s"):format(v and ("%.1f, %.1f, %.1f"):format(v.X, v.Y, v.Z) or "none"))
    flyT.MouseButton1Click:Fire()
    __runFrames(2)
end
-- battery saver: turn on, then wake with a tap
do
    click("🌙 Turn it on now")
    __runFrames(70)
    local overlay = __find("BatterySaver")
    print("  Battery saver on:", overlay and overlay.Visible)
    __UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(5, 5, 0) }, false)
    __runFrames(2)
    print("  Battery saver after tap:", overlay and overlay.Visible)
    assert(overlay and overlay.Visible == false, "battery saver did not wake")
end
click("🔄 Restore defaults")
click("🔄 Restore defaults")
__runFrames(10)
click("🗑️ Unload UI")
print("unload hook cleared:", getgenv().SmurfysUnload == nil)
if #__errors > 0 then
    print("THREAD ERRORS: " .. #__errors)
    local seen = {}
    for _, e in ipairs(__errors) do
        local first = e:match("^[^\n]*")
        if not seen[first] then seen[first] = true; print("  " .. first) end
    end
    error("background threads hit errors")
end
print("DONE OK")
