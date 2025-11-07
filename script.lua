local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local C = {
    Title = "Infinity Hub", SubTitle = "Anime Fight", TabWidth = 160, Size = UDim2.fromOffset(580, 460), MinimizeKey = Enum.KeyCode.LeftAlt,
    WORLDS = {"Leaf Village", "Dragon Town", "Slayer Village"}, BOSS_WORLD = "Leaf Village", BOSS_NAMES = {"KesameAkat", "ItacheAkat"},
    RAID_ENTRY_MINUTES = {0, 30}, RAID_ENTRY_SECOND = 31,
    TELEPORT_OFFSET = CFrame.new(0, 5, -8), FARM_DISTANCE_THRESHOLD = 80, BOSS_CHECK_INTERVAL = 30,
}
local Window = Fluent:CreateWindow(C)
local Services = {Players = game:GetService("Players"), ReplicatedStorage = game:GetService("ReplicatedStorage"), Workspace = workspace}
local player = Services.Players.LocalPlayer
local Bridge = Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bridge")
local state = {selectedWorld = nil, selectedMob = nil, returnWorld = nil, savedPosition = nil, difficultyByName = {}, toggles = {}, exitWave = nil, hasExitedTrial = false}
local MobDropdown, AutoTrialToggleRef, AutoFarmBossToggleRef

local function getHRP() return (player.Character or player.CharacterAdded:Wait()):FindFirstChild("HumanoidRootPart") end
local function getPart(model)
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildOfClass("BasePart") end
end
local function teleportToTarget(targetPart)
    local hrp = getHRP()
    if hrp and targetPart then hrp.CFrame = targetPart.CFrame * C.TELEPORT_OFFSET end
end
local function maintainDistance(targetPart)
    local hrp = getHRP()
    if hrp and targetPart and (hrp.Position - targetPart.Position).Magnitude > C.FARM_DISTANCE_THRESHOLD then
        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 3, -5)
    end
end
local function getEnemy(world, difficulty)
    local folder = Services.Workspace.Server.Enemies:FindFirstChild(world)
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if e:GetAttribute("Difficult") == difficulty and (e:GetAttribute("Health") or 1) > 0 then return e end
        end
    end
end
local function updateMobDropdown(worldName)
    local mobByDifficulty, values = {}, {}
    local worldFolder = Services.Workspace.Server.Enemies:FindFirstChild(worldName)
    state.difficultyByName = {}
    if worldFolder then
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local diff = enemy:GetAttribute("Difficult")
            if diff and not mobByDifficulty[diff] and table.find({"Easy","Medium","Hard","Insane","Boss"}, diff) then
                mobByDifficulty[diff] = enemy.Name
            end
        end
        for _, key in ipairs({"Easy","Medium","Hard","Insane","Boss"}) do
            if mobByDifficulty[key] then table.insert(values, mobByDifficulty[key]); state.difficultyByName[mobByDifficulty[key]] = key end
        end
    end
    MobDropdown:SetValues(#values > 0 and values or {"No Mobs"})
    state.selectedMob = nil
end
local function getTimeUntilNextEntry()
    local seconds = os.date("*t").min * 60 + os.date("*t").sec
    local remaining = math.huge
    for _, targetMin in ipairs(C.RAID_ENTRY_MINUTES) do
        local diff = (targetMin * 60 + C.RAID_ENTRY_SECOND) - seconds
        if diff <= 0 then diff = 3600 + diff end
        remaining = math.min(remaining, diff)
    end
    return math.floor(remaining / 60), remaining % 60
end
local function getSelectedMobTarget()
    if state.selectedWorld and state.selectedMob then
        return getEnemy(state.selectedWorld, state.difficultyByName[state.selectedMob])
    end
end
local function getRaidMobTarget()
    local hrp = getHRP()
    if not hrp then return end
    local trialFolder = Services.Workspace.Server.Gamemodes.Trial.Enemies
    if not trialFolder then return end
    local nearestMob, nearestDistanceSq = nil, C.FARM_DISTANCE_THRESHOLD^2
    for _, e in ipairs(trialFolder:GetChildren()) do
        if (e:GetAttribute("Health") or 1) > 0 then
            local mobPart = getPart(e)
            if mobPart then
                local distanceSq = (hrp.Position - mobPart.Position).Magnitude^2
                if distanceSq < nearestDistanceSq then nearestDistanceSq, nearestMob = distanceSq, e end
            end
        end
    end
    return nearestMob
end
local function getBossesTarget()
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
local function startFarmLoop(autoKey, getTargetFunc)
    task.spawn(function()
        while state.toggles[autoKey] do
            local hrp = getHRP()
            if not hrp then task.wait(0.25); continue end
            local mob = getTargetFunc()
            while state.toggles[autoKey] and not mob do task.wait(0.5); mob = getTargetFunc() end
            if not state.toggles[autoKey] then break end
            local mobPart = getPart(mob)
            if not mobPart then task.wait(0.25); continue end
            teleportToTarget(mobPart)
            task.wait(0.1)
            while state.toggles[autoKey] and mob and mob.Parent and (mob:GetAttribute("Health") or 1) > 0 do
                maintainDistance(getPart(mob))
                task.wait(0.1)
            end
            task.wait(0.1)
        end
    end)
end
local function getCurrentWave()
    local value = player.PlayerGui.UI.HUD.Trial.Frame.Wave.Value
    return value and value:IsA("TextLabel") and tonumber(value.Text) or 0
end
local function returnToSaved()
    if state.returnWorld and state.savedPosition then
        Bridge:FireServer("General", "Teleport", "Teleport", state.returnWorld)
        task.wait(1.5)
        local hrp = getHRP()
        if hrp then hrp.CFrame = state.savedPosition end
    end
end

local Tabs = {
    Farm = Window:AddTab({Title = "Farm", Icon = "sword"}),
    Stars = Window:AddTab({Title = "Stars", Icon = "star"}),
    Trial = Window:AddTab({Title = "Trial", Icon = "shield"}),
    Misc = Window:AddTab({Title = "Misc", Icon = "wand"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"})
}
Window:SelectTab(1)

-- Farm Tab
Tabs.Farm:AddDropdown("WorldDropdown", {
    Title = "Select World",
    Values = C.WORLDS,
    Callback = function(v) state.selectedWorld = v; updateMobDropdown(v) end
})
MobDropdown = Tabs.Farm:AddDropdown("MobDropdown", {
    Title = "Select Mob",
    Values = {"No Mobs"},
    Callback = function(v) state.selectedMob = (v ~= "No Mobs") and v or nil end
})
Tabs.Farm:AddToggle("AutoFarmToggle", {
    Title = "Auto Farm",
    Default = false,
    Callback = function(v) state.toggles.AutoFarm = v; if v then startFarmLoop("AutoFarm", getSelectedMobTarget) end end
})

-- Stars Tab
Tabs.Stars:AddToggle("AutoHatchToggle", {
    Title = "Auto Hatch Stars",
    Default = false,
    Callback = function(v)
        state.toggles.AutoHatch = v
        if v then task.spawn(function() while state.toggles.AutoHatch do Bridge:FireServer("General", "Star", "Open"); task.wait(0.05) end end) end
    end
})

-- Trial Tab
AutoTrialToggleRef = Tabs.Trial:AddToggle("AutoTrialToggle", {
    Title = "Enter Trial",
    Default = false,
    Callback = function(v)
        state.toggles.AutoTrial = v
        if v then
            if not state.returnWorld or not state.savedPosition then
                state.toggles.AutoTrial = false
                AutoTrialToggleRef:SetValue(false)
                Fluent:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Enter Trial!", Duration = 4})
                return
            end
            task.spawn(function()
                while state.toggles.AutoTrial do
                    local t = os.date("*t")
                    if t.sec == C.RAID_ENTRY_SECOND and table.find(C.RAID_ENTRY_MINUTES, t.min) then
                        Bridge:FireServer("Gamemodes", "Trial", "Join"); task.wait(2)
                    end
                    task.wait(0.5)
                end
            end)
        end
    end
})
Tabs.Trial:AddToggle("AutoFarmTrialToggle", {
    Title = "Auto Farm Trial",
    Default = false,
    Callback = function(v) state.toggles.AutoFarmTrial = v; if v then startFarmLoop("AutoFarmTrial", getRaidMobTarget) end end
})
Tabs.Trial:AddInput("ExitWaveInput", {
    Title = "Exit at Wave",
    Numeric = true,
    Callback = function(v) state.exitWave = tonumber(v) end
})
local TimerParagraph = Tabs.Trial:AddParagraph({Title = "Next Entry", Content = "Calculating..."})
task.spawn(function()
    while true do
        local min, sec = getTimeUntilNextEntry()
        local currentWave = getCurrentWave()
        local waveText = tostring(currentWave)
        local inTrial = getRaidMobTarget() and "In Trial" or "Not in Trial"
        TimerParagraph:SetDesc(string.format("Time remaining: %02d:%02d\nCurrent Wave: %s\nStatus: %s", min, sec, waveText, inTrial))
        if inTrial == "In Trial" then
            state.hasExitedTrial = false
        end
        if state.toggles.AutoTrial and state.exitWave and currentWave == state.exitWave and currentWave > 0 and not state.hasExitedTrial and inTrial == "In Trial" then
            Bridge:FireServer("Gamemodes", "Trial", "Leave")
            state.hasExitedTrial = true
            returnToSaved()
        end
        task.wait(2)
    end
end)

-- Misc Tab
AutoFarmBossToggleRef = Tabs.Misc:AddToggle("AutoFarmBossToggle", {
    Title = "Auto Farm Boss",
    Default = false,
    Callback = function(v)
        state.toggles.AutoFarmBoss = v
        if v then
            if not state.returnWorld or not state.savedPosition then
                state.toggles.AutoFarmBoss = false
                AutoFarmBossToggleRef:SetValue(false)
                Fluent:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Auto Farm Boss!", Duration = 4})
                return
            end
            task.spawn(function()
                while state.toggles.AutoFarmBoss do
                    if getRaidMobTarget() then task.wait(0.1); continue end
                    local hrp = getHRP()
                    if not hrp then task.wait(0.25); continue end
                    local currentTime, bosses = tick(), getBossesTarget()
                    local hasBosses = #bosses > 0
                    if not hasBosses and (currentTime - (state.lastBossCheck or 0) < C.BOSS_CHECK_INTERVAL) then
                        task.wait(C.BOSS_CHECK_INTERVAL - (currentTime - (state.lastBossCheck or 0)))
                        bosses = getBossesTarget(); hasBosses = #bosses > 0
                    end
                    state.lastBossCheck = tick()
                    if not hasBosses then task.wait(0.1); continue end
                    Bridge:FireServer("General", "Teleport", "Teleport", C.BOSS_WORLD); task.wait(1.5)
                    local firstBossPart = getPart(bosses[1])
                    if firstBossPart then teleportToTarget(firstBossPart); task.wait(0.1) end
                    while state.toggles.AutoFarmBoss and #getBossesTarget() > 0 do
                        if getRaidMobTarget() then break end
                        local targetBoss = getBossesTarget()[1]
                        if targetBoss and targetBoss.Parent and (targetBoss:GetAttribute("Health") or 1) > 0 then
                            maintainDistance(getPart(targetBoss))
                        end
                        task.wait(0.1)
                    end
                    if state.toggles.AutoFarmBoss then
                        returnToSaved()
                        task.wait(0.1)
                    end
                    task.wait(0.1)
                end
            end)
        end
    end
})
local BossStatusParagraph = Tabs.Misc:AddParagraph({Title = "Boss Status", Content = "Checking..."})
local AutoReturnSection = Tabs.Misc:AddSection("Auto Return")
AutoReturnSection:AddDropdown("ReturnWorldDropdown", {
    Title = "Return World",
    Values = C.WORLDS,
    Callback = function(v) state.returnWorld = v end
})
AutoReturnSection:AddButton({
    Title = "Save Position",
    Description = "Save your current position to return to after Auto Boss Farm.",
    Callback = function()
        if not state.returnWorld then
            Fluent:Notify({Title = "Missing Return World", Content = "Please select a 'Return World' first to save position!", Duration = 4})
            return
        end
        local hrp = getHRP()
        if hrp then
            state.savedPosition = hrp.CFrame
            Fluent:Notify({Title = "Position Saved", Content = "Your current position has been saved to return to: " .. state.returnWorld, Duration = 3})
        end
    end
})

-- Settings Tab
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
SaveManager:SetLibrary(Fluent)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

task.spawn(function()
    while true do
        local bosses = getBossesTarget()
        local hasBosses = #bosses > 0
        local bossNames = {}
        for _, boss in ipairs(bosses) do
            table.insert(bossNames, boss.Name)
        end
        local bossList = #bossNames > 0 and table.concat(bossNames, ", ") or "None"
        BossStatusParagraph:SetDesc(string.format("Bosses Spawned: %s\nSpawned Bosses: %s", hasBosses and "Yes" or "No", bossList))
        task.wait(2)
    end
end)

updateMobDropdown(nil)
