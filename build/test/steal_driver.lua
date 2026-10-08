-- Plays auto steal and the base automation in the fake game (steal_game.lua).
-- With __NO_MODULES the script can't use the game's modules and must fall
-- back to the remotes.
local failures = 0
local MODULES = not __NO_MODULES
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
local function near(pos, r)
    return ((__root.Position - pos) * Vector3.new(1, 0, 1)).Magnitude < (r or 5)
end

-- eggs out before the script loads
local beetle = __SG.spawnEgg("Petal Beetle", 150, 20) -- the tutorial egg (needs the slot key)
local gecko = __SG.spawnEgg("Prism Gecko", 250, -30)  -- Mythic
local owl = __SG.spawnEgg("Frost Owl", 480, 10)       -- Snow needs 1M speed, you have 5K

local ok, err = xpcall(__main, debug.traceback)
check(ok, "script loads" .. (ok and "" or (": " .. tostring(err))))
if not ok then return end
__runFrames(30)
check(__findText("▶  Start auto steal") ~= nil, "Steal tab built")
check(__findText("Forest  ·  ⚡ 10") ~= nil and __findText("Snow  ·  ⚡ 1M") ~= nil, "area toggles with the speed needed")
-- open the Steal tab (phones show icons only)
if not __findText("🥚") or not click("🥚") then click("🥚   Steal") end
__runFrames(60 * 5)
check(labelHas("^2$"), "2 eggs you can steal (Snow is too hard)")
check(labelHas("Eggs in the areas %(3%)"), "egg list shows the 3 eggs")
if MODULES then check(labelHas("Prism Gecko  ·  Mythic  ·  Forest"), "egg list shows pet, rarity and area") end

-- 1. steals the two Forest eggs, skips Snow, brings them home, then trains
check(click("▶  Start auto steal"), "Start button")
__runFrames(60 * 15)
check(__SG.delivered == 2, "2 eggs brought home (" .. __SG.delivered .. ")")
if MODULES then check(__SG.stolen[1] == "Prism Gecko", "rarest egg first (" .. tostring(__SG.stolen[1]) .. ")") end
check(not __SG.eggOut(beetle), "the tutorial egg (slot key) was stolen too")
check(__SG.eggOut(owl), "Snow egg left alone (not enough speed)")
check(labelHas("waiting for eggs"), "then it waits for more")
local speedBefore = __SG.speed.Value
__runFrames(60 * 3)
check(near(__SG.treadmill, 4) and __SG.speed.Value > speedBefore, "trains on the treadmill while waiting")
check(#__SG.backpack:GetChildren() == 2, "2 egg tools in the backpack")

-- 2. new egg appears: it goes and gets it
__SG.spawnEgg("Moss Toad", 180, 50)
__runFrames(60 * 8)
check(__SG.delivered == 3, "new egg stolen too (" .. __SG.delivered .. ")")

-- 3. "only areas my speed is high enough for" off: Snow egg gets stolen
click("🛡️ Only areas my Speed is high enough for")
__runFrames(60 * 8)
check(__SG.delivered == 4 and not __SG.eggOut(owl), "Snow egg stolen once allowed (" .. __SG.delivered .. ")")

-- 4. stop
check(click("■  Stop auto steal"), "Stop button")
__runFrames(30)
check(labelHas("Idle"), "status idle after stop")
check(near(__SG.home, 25), "stop leaves you at your base (home or treadmill)")

-- 5. area filter: Forest off -> a Forest egg is ignored
click("Forest  ·  ⚡ 10")
local forestEgg = __SG.spawnEgg("Petal Beetle", 160, -10)
click("▶  Start auto steal")
__runFrames(60 * 6)
check(__SG.eggOut(forestEgg) and __SG.delivered == 4, "Forest egg ignored when Forest is off")
click("■  Stop auto steal")
click("Forest  ·  ⚡ 10")

-- 6. lowest rarity: Mythic+ ignores a Common egg
if MODULES then
    click("⭐ Lowest rarity: Any")
    click("Mythic and better")
    check(labelHas("Lowest rarity: Mythic%+"), "rarity filter set")
    click("▶  Start auto steal")
    __runFrames(60 * 6)
    check(__SG.eggOut(forestEgg) and __SG.delivered == 4, "Common egg ignored with Mythic+")
    click("■  Stop auto steal")
    click("⭐ Lowest rarity: Mythic+")
    click("Any rarity")
end

-- 7. fly home instead of teleporting
click("✈️ Fly home instead of teleporting")
click("▶  Start auto steal")
__runFrames(60 * 15)
check(__SG.delivered == 5, "egg brought home by flying (" .. __SG.delivered .. ")")
click("■  Stop auto steal")
click("✈️ Fly home instead of teleporting")

-- 8. base: place the egg tools, hatch them when grown, collect, equip best
click("🥚 Auto place stolen eggs in my pen")
__runFrames(60 * 6)
check(__SG.placed == 5, "5 eggs placed in the pen (" .. __SG.placed .. ")")
check(#__SG.backpack:GetChildren() == 0, "no egg tools left")
if MODULES then
    click("🐣 Auto hatch grown eggs")
    __runFrames(60 * 25)
    check(__SG.hatched == 5, "5 eggs hatched once grown (" .. __SG.hatched .. ")")
    click("🐣 Auto hatch grown eggs")
end
click("💰 Auto collect away earnings")
click("⭐ Auto equip best pets")
__runFrames(60 * 3)
check(__SG.collected >= 1 and __SG.woreBest >= 1, "away earnings collected and best pets equipped")
click("💰 Auto collect away earnings")
click("⭐ Auto equip best pets")
click("🥚 Auto place stolen eggs in my pen")

-- 9. treadmill on its own
click("🏃 Stand on my treadmill (train Speed)")
__runFrames(60 * 3)
check(near(__SG.treadmill, 4), "stands on the treadmill")
click("🏃 Stand on my treadmill (train Speed)")
__runFrames(60 * 2)

-- 10. guard chase: warns and (when on) takes you home
click("🏃 Teleport home when a guard chases me")
__root.CFrame = CFrame.new(Vector3.new(200, 5, 0))
__runFrames(5)
__SG.guards.Forest:SetAttribute("TargetPlayer", "Tester")
__runFrames(30)
check(near(__SG.home), "guard chase -> teleported home")
check(labelHas("Guard chasing you"), "guard chase notification")
__SG.guards.Forest:SetAttribute("TargetPlayer", "")

-- 11. teleports: my plot, an area
__root.CFrame = CFrame.new(Vector3.new(300, 5, 0))
click("🏡 My plot")
check(near(__SG.home), "Teleport > My plot")
click("Snow  ·  ⚡ 1M speed")
check(math.abs(__root.Position.X - 410) < 2, "Teleport > Snow area (" .. math.floor(__root.Position.X) .. ")")

-- 12. ESP for eggs and guards builds without errors
__SG.spawnEgg("Prism Gecko", 190, 40)
click("🥚 Eggs (colored by rarity)")
click("🛡️ Guards (red when awake)")
__runFrames(60 * 4)
local billboards = 0
for _, i in ipairs(__all()) do
    if i.ClassName == "BillboardGui" and i.Parent and i.Parent.Name == "SmurfysESP" and i.Enabled ~= false then billboards += 1 end
end
check(billboards >= 3, "ESP billboards for eggs + guards (" .. billboards .. ")")

-- 13. debug report
click("📋 Copy debug report")
check(labelHas("Report"), "debug report done")

-- unload while auto steal runs
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
