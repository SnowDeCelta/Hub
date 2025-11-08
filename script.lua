local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local C = {
    Title = "Infinity Hub",
    SubTitle = "Anime Fight",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    MinimizeKey = Enum.KeyCode.LeftAlt,
    WORLDS = {"Leaf Village", "Dragon Town", "Slayer Village"},
    BOSS_WORLD = "Leaf Village",
    BOSS_NAMES = {"KesameAkat", "ItacheAkat"},
    RAID_ENTRY_MINUTES = {0, 30},
    RAID_ENTRY_SECOND = 31,
    TELEPORT_OFFSET = CFrame.new(0, 0, -8),
    FARM_DISTANCE_THRESHOLD = 80,
    BOSS_CHECK_INTERVAL = 30,
}
local Window = Fluent:CreateWindow(C)
local Services = {Players = game:GetService("Players"), ReplicatedStorage = game:GetService("ReplicatedStorage"), Workspace = workspace}
local player = Services.Players.LocalPlayer
local Bridge = Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bridge")
local state = {world = nil, mob = nil, returnWorld = nil, savedPos = nil, diffByName = {}, toggles = {}, exitWave = nil, exitedTrial = false, inTrialWait = false, exitTowerWave = nil, exitedTower = false, triedEnterTower = false}
local function getHRP() return (player.Character or player.CharacterAdded:Wait()):FindFirstChild("HumanoidRootPart") end
local function getPart(model)
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildOfClass("BasePart") end
end
local function tpTo(targetPart)
    local hrp = getHRP()
    if hrp and targetPart then hrp.CFrame = targetPart.CFrame * C.TELEPORT_OFFSET end
end
local function maintainDist(targetPart)
    local hrp = getHRP()
    if hrp and targetPart and (hrp.Position - targetPart.Position).Magnitude > C.FARM_DISTANCE_THRESHOLD then
        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, -5)
    end
end
local function getEnemy(world, diff)
    local folder = Services.Workspace.Server.Enemies:FindFirstChild(world)
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if e:GetAttribute("Difficult") == diff and (e:GetAttribute("Health") or 1) > 0 then return e end
        end
    end
end
local function updateMobDD(worldName)
    local mobByDiff, values = {}, {}
    local worldFolder = Services.Workspace.Server.Enemies:FindFirstChild(worldName)
    state.diffByName = {}
    if worldFolder then
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local diff = enemy:GetAttribute("Difficult")
            if diff and not mobByDiff[diff] and table.find({"Easy","Medium","Hard","Insane","Boss"}, diff) then
                mobByDiff[diff] = enemy.Name
            end
        end
        for _, key in ipairs({"Easy","Medium","Hard","Insane","Boss"}) do
            if mobByDiff[key] then table.insert(values, mobByDiff[key]); state.diffByName[mobByDiff[key]] = key end
        end
    end
    MobDropdown:SetValues(#values > 0 and values or {"No Mobs"})
    state.mob = nil
end
local function timeToNext()
    local seconds = os.date("*t").min * 60 + os.date("*t").sec
    local remaining = math.huge
    for _, targetMin in ipairs(C.RAID_ENTRY_MINUTES) do
        local diff = (targetMin * 60 + C.RAID_ENTRY_SECOND) - seconds
        if diff <= 0 then diff = 3600 + diff end
        remaining = math.min(remaining, diff)
    end
    return math.floor(remaining / 60), remaining % 60
end
local function getSelMob()
    if state.world and state.mob then return getEnemy(state.world, state.diffByName[state.mob]) end
end
local function getGamemodeMob(gamemode)
    local hrp = getHRP()
    if not hrp then return end
    local folder = Services.Workspace.Server.Gamemodes[gamemode].Enemies
    if not folder then return end
    local nearestMob, nearestDistSq = nil, C.FARM_DISTANCE_THRESHOLD^2
    for _, e in ipairs(folder:GetChildren()) do
        if (e:GetAttribute("Health") or 1) > 0 then
            local mobPart = getPart(e)
            if mobPart then
                local distSq = (hrp.Position - mobPart.Position).Magnitude^2
                if distSq < nearestDistSq then nearestDistSq, nearestMob = distSq, e end
            end
        end
    end
    return nearestMob
end
local function getRaidMob() return getGamemodeMob("Trial") end
local function getTowerMob() return getGamemodeMob("Tower") end
local function getBosses()
    local bosses = {}
    local folder = Services.Workspace.Server.Enemies:FindFirstChild(C.BOSS_WORLD)
    if folder then
        for _, name in ipairs(C.BOSS_NAMES) do
            local boss = folder:FindFirstChild(name)
            if boss and (boss:GetAttribute("Health") or 1) > 0 then table.insert(bosses, boss) end
        end
    end
    return bosses
end
local function farmLoop(key, getTarget)
    task.spawn(function()
        while state.toggles[key] do
            local hrp = getHRP()
            if not hrp then task.wait(0.25); continue end
            local mob = getTarget()
            while state.toggles[key] and not mob do task.wait(0.5); mob = getTarget() end
            if not state.toggles[key] then break end
            local mobPart = getPart(mob)
            if not mobPart then task.wait(0.25); continue end
            tpTo(mobPart)
            task.wait(0.1)
            while state.toggles[key] and mob and mob.Parent and (mob:GetAttribute("Health") or 1) > 0 do
                maintainDist(getPart(mob))
                task.wait(0.1)
            end
            task.wait(0.1)
        end
    end)
end
local function getWave(guiPath)
    local value = player.PlayerGui.UI.HUD[guiPath].Frame.Wave.Value
    return value and value:IsA("TextLabel") and tonumber(value.Text) or 0
end
local function getTrialWave() return getWave("Trial") end
local function getTowerWave() return getWave("Tower") end
local function returnSaved()
    if state.returnWorld and state.savedPos then
        Bridge:FireServer("General", "Teleport", "Teleport", state.returnWorld)
        task.wait(1.5)
        local hrp = getHRP()
        if hrp then hrp.CFrame = state.savedPos end
    end
end
local function monitorGamemode(gamemode, para, getWaveFunc, getMobFunc, toggleKey, exitKey, exitFlag, returnAfterExit)
    task.spawn(function()
        while true do
            local currentWave = getWaveFunc()
            local inMode = getMobFunc() and ("In " .. gamemode) or ("Not in " .. gamemode)
            para:SetDesc(string.format("Current Wave: %s\nStatus: %s", tostring(currentWave), inMode))
            if inMode:find("In ") then _G[exitFlag] = false end
            if state.toggles[toggleKey] and state[exitKey] and currentWave == state[exitKey] and currentWave > 0 and not _G[exitFlag] and inMode:find("In ") then
                Bridge:FireServer("Gamemodes", gamemode, "Leave")
                _G[exitFlag] = true
                if returnAfterExit then returnSaved() end
                if gamemode == "Tower" then task.wait(2.5); state.triedEnterTower = false end
            end
            task.wait(0.5)
        end
    end)
end
local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "sword"}),
    Stars = Window:AddTab({Title = "Stars", Icon = "star"}),
    Trial = Window:AddTab({Title = "Trial", Icon = "shield"}),
    Tower = Window:AddTab({Title = "Tower", Icon = "building"}),
    Misc = Window:AddTab({Title = "Misc", Icon = "wand"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
}
Window:SelectTab(1)
-- Farm Tab
Tabs.Farm:AddDropdown("WorldDD", { Title = "Select World", Values = C.WORLDS, Callback = function(v) state.world = v; updateMobDD(v) end })
MobDropdown = Tabs.Farm:AddDropdown("MobDD", { Title = "Select Mob", Values = {"No Mobs"}, Callback = function(v) state.mob = (v ~= "No Mobs") and v or nil end })
Tabs.Farm:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false, Callback = function(v)
    state.toggles.AutoFarm = v;
    if v then
        if not state.world then
            Fluent:Notify({Title = "Missing World", Content = "Please select a world first!", Duration = 4})
            state.toggles.AutoFarm = false
            return
        end
        Bridge:FireServer("General", "Teleport", "Teleport", state.world)
        task.wait(1.5)
        farmLoop("AutoFarm", getSelMob)
    end
end })
-- Stars Tab
Tabs.Stars:AddToggle("AutoHatchN", { Title = "Auto Hatch Normal", Default = false, Callback = function(v)
    state.toggles.AutoHatchN = v
    if v then
        task.spawn(function()
            while state.toggles.AutoHatchN do
                Bridge:FireServer("General", "Star", "Open");
                task.wait(1.4)
            end
        end)
    end
end })
Tabs.Stars:AddToggle("AutoHatchF", { Title = "Auto Hatch Fast", Default = false, Callback = function(v)
    state.toggles.AutoHatchF = v
    if v then
        task.spawn(function()
            while state.toggles.AutoHatchF do
                Bridge:FireServer("General", "Star", "Open");
                task.wait(0.05)
            end
        end)
    end
end })
-- Trial Tab
local function trialCallback(v, ref)
    state.toggles.AutoTrial = v
    if v then
        if not state.returnWorld or not state.savedPos then
            state.toggles.AutoTrial = false
            if ref then ref:SetValue(false) end
            Fluent:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Enter Trial!", Duration = 4})
            return
        end
        task.spawn(function()
            while state.toggles.AutoTrial do
                if state.toggles.AutoTower or getTowerMob() then task.wait(0.1); continue end
                local t = os.date("*t")
                if t.sec == C.RAID_ENTRY_SECOND and table.find(C.RAID_ENTRY_MINUTES, t.min) then
                    Bridge:FireServer("Gamemodes", "Trial", "Join")
                    state.inTrialWait = true
                    task.wait(30)
                    state.inTrialWait = false
                    task.wait(2)
                end
                task.wait(0.5)
            end
        end)
    end
end
local AutoTrialRef = Tabs.Trial:AddToggle("AutoTrial", { Title = "Enter Trial", Default = false, Callback = function(v) trialCallback(v, AutoTrialRef) end })
-- Trial Tab continued
Tabs.Trial:AddToggle("AutoFarmTrial", { Title = "Auto Farm Trial", Default = false, Callback = function(v)
    state.toggles.AutoFarmTrial = v;
    if v then farmLoop("AutoFarmTrial", getRaidMob) end
end })
Tabs.Trial:AddInput("ExitWave", { Title = "Exit at Wave", Numeric = true, Callback = function(v) state.exitWave = tonumber(v) end })
local TimerPara = Tabs.Trial:AddParagraph({Title = "Next Entry", Content = "Calculating..."})
task.spawn(function()
    while true do
        local min, sec = timeToNext()
        TimerPara:SetDesc(string.format("Time remaining: %02d:%02d", min, sec))
        task.wait(0.5)
    end
end)
_G.exitedTrial = false
monitorGamemode("Trial", TimerPara, getTrialWave, getRaidMob, "AutoTrial", "exitWave", "exitedTrial", true)
-- Tower Tab
local function towerCallback(v, ref)
    state.toggles.AutoTower = v
    if not v then
        state.triedEnterTower = false
        return
    end
    if v then
        if not state.returnWorld or not state.savedPos then
            state.toggles.AutoTower = false
            if ref then ref:SetValue(false) end
            Fluent:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Enter Tower!", Duration = 4})
            return
        end
        task.spawn(function()
            while state.toggles.AutoTower do
                local inTower = getTowerMob() ~= nil
                if not inTower and not state.triedEnterTower then
                    Bridge:FireServer("Gamemodes", "Tower", "Start")
                    state.triedEnterTower = true
                    task.wait(2)
                end
                task.wait(0.5)
            end
        end)
    end
end
local AutoTowerRef = Tabs.Tower:AddToggle("AutoTower", { Title = "Enter Tower", Default = false, Callback = function(v) towerCallback(v, AutoTowerRef) end })
Tabs.Tower:AddToggle("AutoFarmTower", { Title = "Auto Farm Tower", Default = false, Callback = function(v)
    state.toggles.AutoFarmTower = v;
    if v then farmLoop("AutoFarmTower", getTowerMob) end
end })
Tabs.Tower:AddInput("ExitTowerWave", { Title = "Exit at Wave", Numeric = true, Callback = function(v) state.exitTowerWave = tonumber(v) end })
local TowerPara = Tabs.Tower:AddParagraph({Title = "Status", Content = "Calculating..."})
_G.exitedTower = false
monitorGamemode("Tower", TowerPara, getTowerWave, getTowerMob, "AutoTower", "exitTowerWave", "exitedTower", true)
-- Misc Tab
local function bossCallback(v, ref)
    state.toggles.AutoBoss = v
    if v then
        if not state.returnWorld or not state.savedPos then
            state.toggles.AutoBoss = false
            if ref then ref:SetValue(false) end
            Fluent:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Auto Farm Boss!", Duration = 4})
            return
        end
        task.spawn(function()
            while state.toggles.AutoBoss do
                if state.toggles.AutoTower or getRaidMob() or getTowerMob() or state.inTrialWait then task.wait(0.1); continue end
                local hrp = getHRP()
                if not hrp then task.wait(0.25); continue end
                local currentTime, bosses = tick(), getBosses()
                local hasBosses = #bosses > 0
                if not hasBosses and (currentTime - (state.lastBossCheck or 0) < C.BOSS_CHECK_INTERVAL) then
                    task.wait(C.BOSS_CHECK_INTERVAL - (currentTime - (state.lastBossCheck or 0)))
                    bosses = getBosses(); hasBosses = #bosses > 0
                end
                state.lastBossCheck = tick()
                if not hasBosses then task.wait(0.1); continue end
                Bridge:FireServer("General", "Teleport", "Teleport", C.BOSS_WORLD);
                task.wait(1.5)
                local firstBossPart = getPart(bosses[1])
                if firstBossPart then tpTo(firstBossPart); task.wait(0.1) end
                while state.toggles.AutoBoss and #getBosses() > 0 do
                    if state.toggles.AutoTower or getRaidMob() or getTowerMob() or state.inTrialWait then break end
                    local targetBoss = getBosses()[1]
                    if targetBoss and targetBoss.Parent and (targetBoss:GetAttribute("Health") or 1) > 0 then
                        maintainDist(getPart(targetBoss))
                    end
                    task.wait(0.1)
                end
                if state.toggles.AutoBoss then returnSaved() task.wait(0.1) end
                task.wait(0.1)
            end
        end)
    end
end
local AutoBossRef = Tabs.Misc:AddToggle("AutoBoss", { Title = "Auto Farm Boss", Default = false, Callback = function(v) bossCallback(v, AutoBossRef) end })
local BossPara = Tabs.Misc:AddParagraph({Title = "Boss Status", Content = "Checking..."})
local AutoRetSec = Tabs.Misc:AddSection("Auto Return")
AutoRetSec:AddDropdown("ReturnWorld", { Title = "Return World", Values = C.WORLDS, Callback = function(v) state.returnWorld = v end })
AutoRetSec:AddButton({ Title = "Save Position", Description = "Save your current position to return to after Auto Boss Farm.", Callback = function()
    if not state.returnWorld then
        Fluent:Notify({Title = "Missing Return World", Content = "Please select a 'Return World' first to save position!", Duration = 4})
        return
    end
    local hrp = getHRP()
    if hrp then
        state.savedPos = hrp.CFrame
        Fluent:Notify({Title = "Position Saved", Content = "Your current position has been saved to return to: " .. state.returnWorld, Duration = 3})
    end
end })
-- Settings Tab
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
SaveManager:SetLibrary(Fluent)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()
task.spawn(function()
    while true do
        local bosses = getBosses()
        local hasBosses = #bosses > 0
        local bossNames = {}
        for _, boss in ipairs(bosses) do table.insert(bossNames, boss.Name) end
        local bossList = #bossNames > 0 and table.concat(bossNames, ", ") or "None"
        BossPara:SetDesc(string.format("Bosses Spawned: %s\nSpawned Bosses: %s", hasBosses and "Yes" or "No", bossList))
        task.wait(0.5)
    end
end)
updateMobDD(nil)
