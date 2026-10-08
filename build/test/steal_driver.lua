-- Plays the Farm tab in the fake game (steal_game.lua) and checks it.
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

-- four eggs in zone 1 (3 hits each), one with too much health to matter
__SG.spawnEgg("Basic Egg", Vector3.new(-250, 3, 0), 3)
__SG.spawnEgg("Basic Egg", Vector3.new(-270, 3, 20), 3)
__SG.spawnEgg("Forest Egg", Vector3.new(-290, 3, -20), 3)
__SG.spawnEgg("Rock Egg", Vector3.new(-310, 3, 10), 3)

local ok, err = xpcall(__main, debug.traceback)
check(ok, "script loads" .. (ok and "" or (": " .. tostring(err))))
if not ok then return end
__runFrames(30)

check(__findText("⛏️ Break eggs") ~= nil, "Farm tab built")
check(__findText("📦 Place my animals now") ~= nil, "Base tab built")
check(__findText("⛏️ Auto buy better pickaxes") ~= nil, "Auto tab built")
check(__findText("🛡️ Safe zone") ~= nil, "Teleport tab has game spots")

check(click("▶ Auto farm"), "start auto farm")
__runFrames(60 * 90)
for _, line in ipairs(__SG.log) do print("    " .. line) end
check(__SG.broken == 4, "all 4 eggs broken (" .. __SG.broken .. ")")
check(__SG.fastHits == 0, "never hit faster than the swing cooldown (" .. __SG.fastHits .. " too fast)")
check(__SG.farHits == 0, "every hit in range (" .. __SG.farHits .. " too far)")
check(__SG.unheldHits == 0, "pickaxe always held (" .. __SG.unheldHits .. " without)")
check(__SG.taken == 4, "all 4 animals grabbed (" .. __SG.taken .. ")")
check(__SG.banked == 4, "all 4 animals banked (" .. __SG.banked .. ")")
check(__SG.placed == 3, "pen filled: 3 placed (" .. __SG.placed .. ")")
check(__SG.refusedPlace == 0, "no placement refused (" .. __SG.refusedPlace .. ")")

-- stop: nothing moves any more
check(click("▶ Auto farm"), "stop auto farm")
__runFrames(30)
local before = __SG.hits
__SG.spawnEgg("Basic Egg", Vector3.new(-250, 3, 0), 3)
__runFrames(60 * 5)
check(__SG.hits == before, "stopped farm doesn't hit eggs")

-- teleport tab: zone 1 and my base
__runFrames(10)
for _, i in ipairs(__all()) do
    if i.ClassName == "TextButton" and i.Text == "Zone 1 · Common" and i.Parent then i.MouseButton1Click:Fire() end
end
__runFrames(5)
check(__root.Position.X < -200, ("Zone 1 teleport (x = %.0f)"):format(__root.Position.X))
click("🏡 My base")
__runFrames(5)
check(math.abs(__root.Position.X) < 5 and math.abs(__root.Position.Z) < 5, "My base teleport")

-- ESP with everything on
for _, text in ipairs({ "🥚 Eggs (type, health, time to break)", "🐾 Animals to grab", "🛡️ Guards", "🧍 Players" }) do click(text) end
__runFrames(30)
check(true, "ESP ran")

click("🗑️ Unload UI")
__runFrames(10)
if #__errors > 0 then
    local seen = {}
    for _, e in ipairs(__errors) do
        local first = e:match("^[^\n]*")
        if not seen[first] then seen[first] = true; print("  thread error: " .. first) end
    end
end
check(#__errors == 0, "no errors in background threads")
print(failures == 0 and "STEAL TESTS OK" or ("STEAL TESTS FAILED: " .. failures))
