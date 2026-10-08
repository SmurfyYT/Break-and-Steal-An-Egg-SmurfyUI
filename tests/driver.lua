-- Runs SmurfySimple.lua in the fake game and checks it.
local failures = 0
local function check(cond, what)
    print((cond and "  PASS  " or "  FAIL  ") .. what)
    if not cond then failures += 1 end
end
local function buttonStarting(text)
    for _, i in ipairs(__all()) do
        if i.ClassName == "TextButton" and i.Parent and type(i.Text) == "string" and i.Text:sub(1, #text) == text then return i end
    end
end
local function click(text)
    local b = buttonStarting(text)
    if not b then print("  !! no button: " .. text) return false end
    b.MouseButton1Click:Fire()
    __runFrames(2)
    return true
end

-- zone 1: three eggs (3 hits each); zone 2: one egg; a stray animal from someone else's egg
__SG.spawnEgg(1, "Forest Egg", Vector3.new(-250, 2.5, 0), 3)
__SG.spawnEgg(1, "Forest Egg", Vector3.new(-270, 2.5, 20), 3)
__SG.spawnEgg(1, "Rock Egg", Vector3.new(-290, 2.5, -20), 3)
__SG.dropAnimal(Vector3.new(-246, 2.5, 6), 999, "Stray")

local ok, err = xpcall(__main, debug.traceback)
check(ok, "script loads" .. (ok and "" or (": " .. tostring(err))))
if not ok then return end
__runFrames(30)
check(__SG.autoSwingOn() == false, "the game's Auto Swing is turned off on load")
__SG.autoSwing.SetOn(true)
__runFrames(5)
check(__SG.autoSwingOn() == false, "...and turned back off if something switches it on")

for _, text in ipairs({ "Restore settings", "Unload", "Auto farm (fling)", "Zone: ", "Fling power: ",
    "Fling in place", "Fling TP → nearest egg", "Fling TP → outside my plot" }) do
    check(buttonStarting(text) ~= nil, "button: " .. text)
end

-- manual: fling in place keeps you still
check(__inHitbox(__root.Position), "test starts on the plot")
click("Fling in place")
__runFrames(60 * 5) -- walks off the plot first
check(not __inHitbox(__root.Position), "fling in place walks off the plot first")
check((__SG.unflungJumps or 0) == 0, "...walking, not a visible step")
__SG.flungFrames = 0
local startPos = __root.Position
__runFrames(120)
check(__SG.flungFrames >= 100, "fling in place sends a flung character (" .. __SG.flungFrames .. " frames)")
check((__root.Position - startPos).Magnitude < 0.01, "fling in place: you stay still")
check(not __SG.notStillFrames, "velocity zeroed before every physics step")
click("Fling in place")
__runFrames(10)
local flungBefore = __SG.flungFrames
__runFrames(30)
check(__SG.flungFrames == flungBefore, "turning it off stops the fling")

-- manual: TP outside plot lands outside, unflung
click("Fling TP → outside my plot")
__runFrames(60)
check(not __inHitbox(__root.Position), ("outside-plot TP lands outside the hitbox (x=%.1f z=%.1f)"):format(__root.Position.X, __root.Position.Z))
check(math.abs(__root.Position.X) < 60 and math.abs(__root.Position.Z) < 60, "...and right next to it")
check(not __SG.lastFlung, "...and the fling is off after landing")

-- auto farm, zone 1
__SG.flungOnPlot = 0
__SG.expectWalkOut = true
click("Zone: ") -- Any -> 1
click("Auto farm (fling)")
__runFrames(60 * 120)
click("Auto farm (fling)")
__runFrames(30)
for _, line in ipairs(__SG.log) do print("    " .. line) end
check(__SG.broken == 3, "all 3 zone-1 eggs broken (" .. __SG.broken .. ")")
check((__SG.earlyHits or 0) == 0, "waits 1 second next to each egg before swinging (" .. (__SG.earlyHits or 0) .. " early hits)")
check((__SG.flungHits or 0) == 0, "mines without the fling (" .. (__SG.flungHits or 0) .. " flung hits)")
check((__SG.noWalkOutHits or 0) == 0, "walks out of dig reach and back before mining (" .. (__SG.noWalkOutHits or 0) .. " hits without)")
check((__SG.jumps or 0) >= 6, "trips happened as jumps (" .. (__SG.jumps or 0) .. ")")
check((__SG.unflungJumps or 0) == 0, "every jump is flung the frame before and the frame of it (" .. (__SG.unflungJumps or 0) .. " not)")
check((__SG.multiFrameTrips or 0) == 0, "each trip is a single-frame jump, no visible hops (" .. (__SG.multiFrameTrips or 0) .. ")")
check((__SG.maxSpeed or 0) >= 1e6, ("Max fling power by default (%.0f)"):format(__SG.maxSpeed or 0))
check(buttonStarting("Fling power: Max") ~= nil, "power button shows Max")
check(__SG.fastHits == 0, "never hit faster than the swing cooldown (" .. __SG.fastHits .. ")")
check(__SG.farHits == 0, "every hit in range (" .. __SG.farHits .. " too far)")
check(__SG.unheldHits == 0, "pickaxe always held (" .. __SG.unheldHits .. ")")
check(__SG.taken == 3, "waited out the hatch: all 3 animals grabbed (" .. __SG.taken .. ")")
local tookStray = false
for _, n in ipairs(__SG.takenNames or {}) do if n == "Stray" then tookStray = true end end
check(not tookStray, "grabbed the egg's own animal (HatchId), not the stray")
check(__SG.banked == 3, "all 3 banked (" .. __SG.banked .. ")")
check(__SG.flungOnPlot == 0, "never flung while on the plot (" .. __SG.flungOnPlot .. " frames)")
check(__SG.bankedWhileFlung == 0, "banking only happens after the fling stops")
check(__SG.carriedUnflungOutside == 0, "flung the whole way home while carrying (" .. __SG.carriedUnflungOutside .. " frames exposed)")
check(not __SG.lastFlung, "stopping the farm stops the fling")
check(__SG.autoSwingOn() == false, "Auto Swing still off after farming")

__SG.expectWalkOut = false
-- zone 2 egg isn't touched when zone 1 is selected
__SG.spawnEgg(2, "Swamp Egg", Vector3.new(-600, 2.5, 0), 3)
local hits = __SG.hits
click("Auto farm (fling)")
__runFrames(60 * 5)
check(__SG.hits == hits, "zone filter: zone 2 egg ignored while zone 1 is picked")
click("Stop everything")
__runFrames(10)

-- restore settings: zone back to Any
click("Restore settings")
__runFrames(5)
check(buttonStarting("Zone: Any") ~= nil, "restore settings resets the zone")

click("Unload")
__runFrames(30)
local gone = true
for _, i in ipairs(__all()) do if i.Name == "SmurfySimple" and i.Parent then gone = false end end
check(gone, "unload removes the UI")
local f = __SG.flungFrames
__runFrames(30)
check(__SG.flungFrames == f, "nothing runs after unload")

if #__errors > 0 then
    local seen = {}
    for _, e in ipairs(__errors) do
        local first = e:match("^[^\n]*")
        if not seen[first] then seen[first] = true; print("  thread error: " .. first) end
    end
end
check(#__errors == 0, "no errors in background threads")
print(failures == 0 and "ALL TESTS OK" or ("TESTS FAILED: " .. failures))
