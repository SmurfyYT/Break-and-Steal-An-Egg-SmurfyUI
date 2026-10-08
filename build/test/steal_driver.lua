-- Plays auto steal in the fake game (steal_game.lua) and checks it.
local failures = 0
local function check(cond, what)
    print((cond and "  PASS  " or "  FAIL  ") .. what)
    if not cond then failures += 1 end
end
local function click(text)
    local b = __findText(text)
    if not b then print("  !! no button: " .. text) return false end
    b.MouseButton1Click:Fire()
    __runFrames(2)
    return true
end
local function labelHas(pattern)
    for _, i in ipairs(__all()) do
        if (i.ClassName == "TextLabel" or i.ClassName == "TextButton") and type(i.Text) == "string" and i.Text:find(pattern) and i.Parent then
            return true
        end
    end
    return false
end
local function atHome()
    return ((__root.Position - __SG.home) * Vector3.new(1, 0, 1)).Magnitude < 5
end

-- eggs out before the script loads
__SG.spawnEgg("Petal Beetle", 150, 20)
__SG.spawnEgg("Prism Gecko", 250, -30, true) -- rare
local snowEgg = __SG.spawnEgg("Frost Owl", 480, 10) -- Snow needs 1M speed, you have 5K

local ok, err = xpcall(__main, debug.traceback)
check(ok, "script loads" .. (ok and "" or (": " .. tostring(err))))
if not ok then return end
__runFrames(30)
check(__findText("▶  Start auto steal") ~= nil, "Steal tab built")
check(labelHas("Eggs in the areas %(3%)"), "egg list shows the 3 eggs")
check(__findText("Forest  ·  ⚡ 10") ~= nil and __findText("Snow  ·  ⚡ 1M") ~= nil, "area toggles with the speed needed")
-- open the Steal tab (phones show icons only)
if not __findText("🥚") or not click("🥚") then click("🥚   Steal") end
__runFrames(150)
check(labelHas("^2$"), "2 eggs you can steal (Snow is too hard)")

-- 1. steals the two Forest eggs (rare first), skips Snow, brings them home
check(click("▶  Start auto steal"), "Start button")
__runFrames(60 * 15)
check(__SG.delivered == 2, "2 eggs brought home (" .. __SG.delivered .. ")")
check(__SG.stolen[1] == "Prism Gecko", "rare egg first (" .. tostring(__SG.stolen[1]) .. ")")
check(snowEgg.Parent ~= nil, "Snow egg left alone (not enough speed)")
check(labelHas("Waiting for eggs"), "then it waits for more")
check(atHome(), "waits at home")

-- 2. new egg appears: it goes and gets it
__SG.spawnEgg("Moss Toad", 180, 50)
__runFrames(60 * 8)
check(__SG.delivered == 3, "new egg stolen too (" .. __SG.delivered .. ")")

-- 3. turn off "only areas my speed is high enough for": Snow egg gets stolen
click("🛡️ Only areas my Speed is high enough for")
__runFrames(60 * 8)
check(__SG.delivered == 4 and snowEgg.Parent == nil, "Snow egg stolen once allowed (" .. __SG.delivered .. ")")

-- 4. stop
check(click("■  Stop auto steal"), "Stop button")
__runFrames(30)
check(labelHas("Idle"), "status idle after stop")

-- 5. area filter: Forest off -> a Forest egg is ignored
click("Forest  ·  ⚡ 10")
local forestEgg = __SG.spawnEgg("Petal Beetle", 160, -10)
click("▶  Start auto steal")
__runFrames(60 * 6)
check(forestEgg.Parent ~= nil and __SG.delivered == 4, "Forest egg ignored when Forest is off")
click("■  Stop auto steal")
click("Forest  ·  ⚡ 10")

-- 6. fly home instead of teleporting
click("✈️ Fly home instead of teleporting")
click("▶  Start auto steal")
__runFrames(60 * 15)
check(__SG.delivered == 5, "egg brought home by flying (" .. __SG.delivered .. ")")
click("■  Stop auto steal")
click("✈️ Fly home instead of teleporting")

-- 7. guard chase: warns and (when on) takes you home
click("🏃 Teleport home when a guard chases me")
__root.CFrame = CFrame.new(Vector3.new(200, 5, 0))
__runFrames(5)
__SG.guards.Forest:SetAttribute("TargetPlayer", "Tester")
__runFrames(30)
check(atHome(), "guard chase -> teleported home")
check(labelHas("Guard chasing you"), "guard chase notification")
__SG.guards.Forest:SetAttribute("TargetPlayer", "")

-- 8. teleports: my plot, an area
__root.CFrame = CFrame.new(Vector3.new(300, 5, 0))
click("🏡 My plot")
check(atHome(), "Teleport > My plot")
click("Snow  ·  ⚡ 1M speed")
check(math.abs(__root.Position.X - 410) < 2, "Teleport > Snow area (" .. math.floor(__root.Position.X) .. ")")

-- 9. ESP for eggs and guards builds without errors
__SG.spawnEgg("Moss Toad", 190, 40, true)
click("🥚 Eggs (⭐ rare in gold)")
click("🛡️ Guards (red when awake)")
__runFrames(30)
local billboards = 0
for _, i in ipairs(__all()) do
    if i.ClassName == "BillboardGui" and i.Parent and i.Parent.Name == "SmurfysESP" and i.Enabled ~= false then billboards += 1 end
end
check(billboards >= 3, "ESP billboards for eggs + guards (" .. billboards .. ")")

-- 10. debug report
click("📋 Copy debug report")
check(labelHas("Report"), "debug report done")

-- unload while auto steal runs: stops and goes home
__SG.spawnEgg("Petal Beetle", 140, 30)
click("▶  Start auto steal")
__runFrames(3)
click("🗑️ Unload UI")
__runFrames(60)
check(getgenv().SmurfysUnload == nil, "unloaded")

for _, line in ipairs(__SG.log) do print("    " .. line) end
if #__errors > 0 then
    print("THREAD ERRORS: " .. #__errors)
    for _, e in ipairs(__errors) do print("  " .. e:sub(1, 400)) end
    failures += 1
end
print(failures == 0 and "STEAL TESTS OK" or ("STEAL TESTS FAILED: " .. failures))
