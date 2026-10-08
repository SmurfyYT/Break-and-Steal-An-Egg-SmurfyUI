-- Runs SmurfySimple.lua (Movement Lab) against the fake server in fake_game.lua.
local failures = 0
local function check(cond, what)
    print((cond and "  PASS  " or "  FAIL  ") .. what)
    if not cond then failures += 1 end
end
local function page(name)
    for _, i in ipairs(__all()) do
        if i.ClassName == "ScrollingFrame" and i.Name == name and i.Parent then return i end
    end
end
local function clickIn(pageName, text)
    local p = page(pageName)
    for _, i in ipairs(p and p:GetChildren() or {}) do
        if i.ClassName == "TextButton" and type(i.Text) == "string" and i.Text:sub(1, #text) == text then
            i.MouseButton1Click:Fire()
            __runFrames(2)
            return true
        end
    end
    print("  !! no button on " .. pageName .. ": " .. text)
    return false
end
local function results(pageName)
    local out = {}
    for _, i in ipairs(page(pageName):GetChildren()) do
        if i.ClassName == "TextLabel" and i.Font == Enum.Font.Code then table.insert(out, i.Text) end
    end
    return table.concat(out, "\n")
end
local function plain(t) return (t:gsub("<[^>]+>", "")) end
-- run until the page says Done (or time runs out)
local function waitDone(pageName, seconds)
    for _ = 1, seconds * 10 do
        __runFrames(6)
        if results(pageName):find("Done%.") then return true end
    end
    return false
end
local function line(pageName, prefix)
    for l in plain(results(pageName)):gmatch("[^\n]+") do
        if l:find(prefix, 1, true) then return l end
    end
    return ""
end

local ok, err = xpcall(__main, debug.traceback)
check(ok, "script loads" .. (ok and "" or (": " .. tostring(err))))
if not ok then return end
__runFrames(30)

for _, name in ipairs({ "Main", "Snap", "Ladder", "Methods", "Warmup", "Glide", "Endure", "Under" }) do
    check(page(name) ~= nil, "tab: " .. name)
end
for _, i in ipairs(__all()) do
    if i.ClassName == "TextButton" and i.Parent and type(i.Text) == "string" and (i.Text:find("Auto farm") or i.Text:find("Zone:")) then
        check(false, "old farm button still there: " .. i.Text)
    end
end
check(clickIn("Main", "Restore settings") and true, "Main has Restore settings")

-- Remotes: spy sees the game's own sends and the server's messages, and never sends anything
check(page("Remotes") ~= nil, "tab: Remotes")
clickIn("Remotes", "Spy on remotes")
local infoOk = false
for _, i in ipairs(page("Remotes"):GetChildren()) do
    if i.ClassName == "TextLabel" and type(i.Text) == "string" and i.Text:find("both ways") then infoOk = true end
end
check(infoOk, "spy watches both ways when hookmetamethod exists")
local calls = __SG.serverCalls
__SG.remotes.EggHitRequest:FireServer(__SG.remotes.EggHitRequest, 3)
__SG.remotes.EggHitRequest:FireServer(__SG.remotes.EggHitRequest, 4)
__SG.remotes.Notify.OnClientEvent:Fire("You stole an egg!", { Kind = "Info" })
__runFrames(30)
local spyText = results("Remotes")
check(spyText:find("→ EggHitRequest ×2", 1, true) ~= nil, "sent remote listed with its count")
check(spyText:find("(EggHitRequest, 4)", 1, true) ~= nil, "...and its last arguments")
check(spyText:find("← Notify ×1", 1, true) ~= nil, "received remote listed")
check(spyText:find('"You stole an egg!"', 1, true) ~= nil, "...with its arguments")
check(__SG.serverCalls == calls + 2, "the game's own sends still reach the server (spy passes them on)")
clickIn("Remotes", "Copy list")
check((__SG.clipboard() or ""):find("OUT EggHitRequest x2", 1, true) ~= nil, "copy list puts it on the clipboard")
clickIn("Remotes", "List every remote")
check(results("Remotes"):find("4 remotes", 1, true) ~= nil and results("Remotes"):find("F BackpackSellRemote", 1, true) ~= nil, "lists every remote in the game")
clickIn("Remotes", "Spy on remotes") -- off
__SG.remotes.EggHitRequest:FireServer(__SG.remotes.EggHitRequest, 5)
__runFrames(30)
check(results("Remotes"):find("×3", 1, true) == nil, "spy off: nothing more logged")

-- Snap: quick check (plain 50 studs) gets pulled back, and the watcher sees the pull
clickIn("Snap", "Quick check")
check(waitDone("Snap", 20), "snap quick check finishes")
check(line("Snap", "Plain TP 50"):find("BACK") ~= nil, "plain TP 50 studs: pulled back -> " .. line("Snap", "Plain TP 50"))
check(line("Snap", "Seen:"):match("Seen: (%d+)") ~= "0", "the watcher listed the pull back (" .. line("Snap", "Seen:") .. ")")

-- Ladder: 10 ok, 25+ pulled back (fake server limit: 20 studs a frame)
clickIn("Ladder", "Run ladder")
check(waitDone("Ladder", 120), "ladder finishes")
print(plain(results("Ladder")))
check(line("Ladder", "   10 studs"):find("ok") ~= nil, "ladder 10: ok")
for _, d in ipairs({ 25, 50, 100, 250, 500, 1000 }) do
    check(line("Ladder", ("%5d studs"):format(d)):find("BACK") ~= nil, ("ladder %d: BACK"):format(d))
end

-- Methods
clickIn("Methods", "Run showdown")
check(waitDone("Methods", 240), "showdown finishes")
print(plain(results("Methods")))
for _, d in ipairs({ 50, 250, 1000 }) do
    local cells = {}
    for c in line("Methods", ("%5d "):format(d)):gmatch("%S+") do table.insert(cells, c) end
    check(cells[2] == "BACK" and cells[3] == "ok" and cells[4] == "ok" and cells[5] == "ok",
        ("showdown row %d: Plain BACK, Ghost/Fling/Glide ok (%s)"):format(d, table.concat(cells, " ")))
end

-- Warmup: none and 1 frame fail, 0.05 s is the shortest that works
clickIn("Warmup", "Run warmup test")
check(waitDone("Warmup", 240), "warmup test finishes")
print(plain(results("Warmup")))
check(line("Warmup", "none"):find("0/2") ~= nil, "warmup none: 0/2")
check(line("Warmup", "1 frame"):find("0/2") ~= nil, "warmup 1 frame: 0/2")
check(line("Warmup", "0.05 s"):find("2/2") ~= nil, "warmup 0.05 s: 2/2")
check(line("Warmup", "Best:"):find("0.05") ~= nil, "best warmup picked: 0.05 s")
local warmupButtonOk = false
for _, i in ipairs(page("Warmup"):GetChildren()) do
    if i.ClassName == "TextButton" and i.Text == "Current warmup: 0.05 s" then warmupButtonOk = true end
end
check(warmupButtonOk, "warmup setting now 0.05 s")

-- Glide: up to 1000/s ok (fake limit 1200/s)
clickIn("Glide", "Run glide test")
check(waitDone("Glide", 120), "glide test finishes")
print(plain(results("Glide")))
check(line("Glide", "Fastest ok:"):find("1000") ~= nil, "fastest glide: 1000 studs/s")
check(line("Glide", " 3000/s"):find("BACK") ~= nil, "3000/s pulled back")

-- Endure: dies after 40 s hidden
clickIn("Endure", "Run endurance")
check(waitDone("Endure", 200), "endurance finishes")
print(plain(results("Endure")))
for _, s in ipairs({ " 5 s", "15 s", "30 s" }) do check(line("Endure", s):find("ok") ~= nil, "endure" .. s .. ": ok") end
check(line("Endure", "60 s"):find("DIED") ~= nil, "endure 60 s: DIED")

-- Under: default run works, never below the kill height margin
local minY = math.huge
local rsSig = __Signal
local conn = game:GetService("RunService").Heartbeat:Connect(function() minY = math.min(minY, __root.Position.Y) end)
clickIn("Under", "Run once")
check(waitDone("Under", 60), "under route finishes")
print(plain(results("Under")))
check(line("Under", "50 under"):find("ok") ~= nil, "under route (50 under, 250 studs, 300/s): ok")
check(minY < -40 and minY > -450, ("went under the floor but above the kill height (lowest y %.0f)"):format(minY))
conn:Disconnect()

-- Stop works mid-test and another test can start
clickIn("Ladder", "Run ladder")
__runFrames(60)
clickIn("Ladder", "Stop")
__runFrames(30)
check(plain(results("Ladder")):find("Stopped") ~= nil, "stop shows Stopped")
clickIn("Snap", "Quick check")
check(waitDone("Snap", 20), "a new test runs after Stop")

-- Restore settings: warmup back to 0.15 s
clickIn("Main", "Restore settings")
__runFrames(5)
local restored = false
for _, i in ipairs(page("Warmup"):GetChildren()) do
    if i.ClassName == "TextButton" and i.Text == "Current warmup: 0.15 s" then restored = true end
end
check(restored, "restore settings resets the warmup")

clickIn("Main", "Unload")
__runFrames(30)
local gone = true
for _, i in ipairs(__all()) do if i.Name == "SmurfySimple" and i.Parent then gone = false end end
check(gone, "unload removes the UI")
local hf = __SG.hiddenFrames
__runFrames(30)
check(__SG.hiddenFrames == hf, "nothing hidden after unload")
local before = __SG.serverCalls
__SG.remotes.EggHitRequest:FireServer(__SG.remotes.EggHitRequest, 6)
check(__SG.serverCalls == before + 1, "after unload remotes still work (hook removed)")

if #__errors > 0 then
    local seen = {}
    for _, e in ipairs(__errors) do
        local first = e:match("^[^\n]*")
        if not seen[first] then seen[first] = true; print("  thread error: " .. first) end
    end
end
check(#__errors == 0, "no errors in background threads")
print(failures == 0 and "ALL TESTS OK" or ("TESTS FAILED: " .. failures))
