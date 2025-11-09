local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
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
    TELEPORT_OFFSET = CFrame.new(0, 5, -8),
    FARM_DISTANCE_THRESHOLD = 80,
    BOSS_CHECK_INTERVAL = 30,
}
local Window = WindUI:CreateWindow({
    Title = C.Title,
    Icon = "settings",
    Author = "Infinity Hub",
    Folder = "InfinityHub",
    Size = C.Size,
    KeySystem = false
})
Window:SetToggleKey(Enum.KeyCode.LeftAlt)
Window:EditOpenButton({
    Title = "Open Infinity Hub",
    Icon = "sword",
    CornerRadius = UDim.new(0,16),
    StrokeThickness = 2,
    Color = ColorSequence.new( -- gradient
        Color3.fromHex("FF0F7B"),
        Color3.fromHex("F89B29")
    ),
    OnlyMobile = false,
    Enabled = true,
    Draggable = true,
})
local Services = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Workspace = workspace
}
local player = Services.Players.LocalPlayer
local Bridge = Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bridge")
local state = {
    world = nil,
    mob = nil,
    returnWorld = nil,
    savedPos = nil,
    diffByName = {},
    toggles = {},
    exitWave = nil,
    exitedTrial = false,
    inTrialWait = false,
    exitTowerWave = nil,
    exitedTower = false,
    triedEnterTower = false
}
-- Helper Functions
local function getHRP()
    return (player.Character or player.CharacterAdded:Wait()):FindFirstChild("HumanoidRootPart")
end
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
        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 5, -5)
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
local function updateMobDD(worldName, dropdown)
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
            if mobByDiff[key] then
                table.insert(values, mobByDiff[key])
                state.diffByName[mobByDiff[key]] = key
            end
        end
    end
    dropdown:Refresh(#values > 0 and values or {"No Mobs"})
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
    return state.world and state.mob and getEnemy(state.world, state.diffByName[state.mob]) or nil
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
local function getWave(guiPath)
    local value = player.PlayerGui.UI.HUD[guiPath].Frame.Wave.Value
    return value and value:IsA("TextLabel") and tonumber(value.Text) or 0
end
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
local function farmLoop(key, getTarget, isBoss)
    task.spawn(function()
        while state.toggles[key] do
            local hrp = getHRP()
            if not hrp then task.wait(0.1) continue end
            local mob = getTarget()
            while state.toggles[key] and not mob do task.wait(0.7) mob = getTarget() end
            if not state.toggles[key] then break end
            local mobPart = getPart(mob)
            if not mobPart then task.wait(0.1) continue end
            tpTo(mobPart)
            task.wait(0.07)
            while state.toggles[key] and mob and mob.Parent and (mob:GetAttribute("Health") or 1) > 0 do
                maintainDist(getPart(mob))
                task.wait(0.07)
            end
            task.wait(0.4)
            if isBoss and state.toggles[key] then
                local currentTime = tick()
                if (currentTime - (state.lastBossCheck or 0) < C.BOSS_CHECK_INTERVAL) then
                    task.wait(C.BOSS_CHECK_INTERVAL - (currentTime - (state.lastBossCheck or 0)))
                end
                state.lastBossCheck = currentTime
            end
        end
    end)
end
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
            local desc
            if gamemode == "Trial" then
                local min, sec = timeToNext()
                desc = string.format("Wave: %s | Status: %s\nNext Entry: %02d:%02d", tostring(currentWave), inMode, min, sec)
            else
                desc = string.format("Wave: %s | Status: %s", tostring(currentWave), inMode)
            end
            para:SetDesc(desc)
            if inMode:find("In ") then _G[exitFlag] = false end
            if state.toggles[toggleKey] and state[exitKey] and currentWave == state[exitKey] and currentWave > 0 and not _G[exitFlag] and inMode:find("In ") then
                Bridge:FireServer("Gamemodes", gamemode, "Leave")
                _G[exitFlag] = true
                if returnAfterExit then returnSaved() end
                if gamemode == "Tower" then task.wait(2.5) state.triedEnterTower = false end
            end
            task.wait(0.3)
        end
    end)
end
-- UI Tabs
local Tabs = {
    Farm = Window:Tab({Title = "Farm", Icon = "sword", Locked = false}),
    Stars = Window:Tab({Title = "Stars", Icon = "star", Locked = false}),
    Trial = Window:Tab({Title = "Trial", Icon = "shield", Locked = false}),
    Tower = Window:Tab({Title = "Tower", Icon = "building", Locked = false}),
    Misc = Window:Tab({Title = "Misc", Icon = "wand", Locked = false}),
    Settings = Window:Tab({Title = "Settings", Icon = "settings", Locked = false})
}
Tabs.Farm:Select()
-- Farm Tab
local WorldDD = Tabs.Farm:Dropdown({
    Title = "Select World",
    Desc = "Choose world to farm.",
    Values = C.WORLDS,
    Callback = function(Option)
        state.world = Option
        updateMobDD(Option, MobDropdown)
    end
})
local MobDropdown = Tabs.Farm:Dropdown({
    Title = "Select Mob",
    Desc = "Select mob type to target.",
    Values = {"No Mobs"},
    Callback = function(Option)
        state.mob = (Option ~= "No Mobs") and Option or nil
    end
})
local RefreshMobButton = Tabs.Farm:Button({
    Title = "Refresh Mobs",
    Desc = "Refreshes the mob list for the selected world.",
    Callback = function()
        if not state.world then
            WindUI:Notify({Title = "No World Selected", Content = "Please select a world first!", Duration = 3, Icon = "settings"})
            return
        end
        updateMobDD(state.world, MobDropdown)
        MobDropdown:SetValue(nil)
        WindUI:Notify({Title = "Mobs Refreshed", Content = "Mob list updated for " .. state.world, Duration = 2, Icon = "settings"})
    end
})
local AutoFarmToggle = Tabs.Farm:Toggle({
    Title = "Auto Farm",
    Desc = "Teleports to and farms selected mob.",
    Value = false,
    Callback = function(Value)
        state.toggles.AutoFarm = Value
        if Value then
            if not state.world or not state.mob or state.mob == "No Mobs" then
                WindUI:Notify({Title = "Missing Selection", Content = "Please select a world and a mob first!", Duration = 4, Icon = "settings"})
                state.toggles.AutoFarm = false
                AutoFarmToggle:Set(false)
                return
            end
            Bridge:FireServer("General", "Teleport", "Teleport", state.world)
            task.wait(0.5)
            farmLoop("AutoFarm", getSelMob)
        end
    end
})
-- Stars Tab
local AutoHatchNToggle = Tabs.Stars:Toggle({
    Title = "Auto Hatch Normal",
    Desc = "Hatches stars at normal speed.",
    Value = false,
    Callback = function(Value)
        state.toggles.AutoHatchN = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoHatchN do
                    Bridge:FireServer("General", "Star", "Open")
                    task.wait(1.4)
                end
            end)
        end
    end
})
local AutoHatchFToggle = Tabs.Stars:Toggle({
    Title = "Auto Hatch Fast",
    Desc = "Rapidly hatches stars.",
    Value = false,
    Callback = function(Value)
        state.toggles.AutoHatchF = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoHatchF do
                    Bridge:FireServer("General", "Star", "Open")
                    task.wait(0.05)
                end
            end)
        end
    end
})
-- Trial Tab
local AutoTrialToggle = Tabs.Trial:Toggle({
    Title = "Enter Trial",
    Desc = "Joins Trial raids at scheduled times (00:31 and 30:31).",
    Value = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitWave or state.exitWave <= 0) then
            WindUI:Notify({Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Enter Trial!", Duration = 4, Icon = "settings"})
            AutoTrialToggle:Set(false)
            return
        end
        state.toggles.AutoTrial = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoTrial do
                    if state.toggles.AutoTower or getGamemodeMob("Tower") then task.wait(0.1) continue end
                    local t = os.date("*t")
                    if t.sec == C.RAID_ENTRY_SECOND and table.find(C.RAID_ENTRY_MINUTES, t.min) then
                        Bridge:FireServer("Gamemodes", "Trial", "Join")
                        state.inTrialWait = true
                        task.wait(30)
                        state.inTrialWait = false
                        task.wait(2)
                    end
                    task.wait(0.3)
                end
            end)
        end
    end
})
local AutoFarmTrialToggle = Tabs.Trial:Toggle({
    Title = "Auto Farm Trial",
    Desc = "Farms enemies in Trial raids.",
    Value = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitWave or state.exitWave <= 0) then
            WindUI:Notify({Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Auto Farm Trial!", Duration = 4, Icon = "settings"})
            AutoFarmTrialToggle:Set(false)
            return
        end
        state.toggles.AutoFarmTrial = Value
        if Value then farmLoop("AutoFarmTrial", function() return getGamemodeMob("Trial") end) end
    end
})
local ExitWaveInput = Tabs.Trial:Input({
    Title = "Exit at Wave",
    Desc = "Exits Trial after this wave.",
    Value = "",
    Placeholder = "Enter wave number",
    Callback = function(Text) state.exitWave = tonumber(Text) end
})
local TrialStatusPara = Tabs.Trial:Paragraph({
    Title = "Trial Status",
    Desc = "Current wave and status. Calculating..."
})
_G.exitedTrial = false
monitorGamemode("Trial", TrialStatusPara, function() return getWave("Trial") end, function() return getGamemodeMob("Trial") end, "AutoTrial", "exitWave", "exitedTrial", true)
-- Tower Tab
local AutoTowerToggle = Tabs.Tower:Toggle({
    Title = "Enter Tower",
    Desc = "Starts and enters Tower challenges.",
    Value = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitTowerWave or state.exitTowerWave <= 0) then
            WindUI:Notify({Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Enter Tower!", Duration = 4, Icon = "settings"})
            AutoTowerToggle:Set(false)
            return
        end
        state.toggles.AutoTower = Value
        if not Value then state.triedEnterTower = false return end
        task.spawn(function()
            while state.toggles.AutoTower do
                if not getGamemodeMob("Tower") and not state.triedEnterTower then
                    Bridge:FireServer("Gamemodes", "Tower", "Start")
                    state.triedEnterTower = true
                    task.wait(2)
                end
                task.wait(0.3)
            end
        end)
    end
})
local AutoFarmTowerToggle = Tabs.Tower:Toggle({
    Title = "Auto Farm Tower",
    Desc = "Farms enemies in Tower challenges.",
    Value = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitTowerWave or state.exitTowerWave <= 0) then
            WindUI:Notify({Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Auto Farm Tower!", Duration = 4, Icon = "settings"})
            AutoFarmTowerToggle:Set(false)
            return
        end
        state.toggles.AutoFarmTower = Value
        if Value then farmLoop("AutoFarmTower", function() return getGamemodeMob("Tower") end) end
    end
})
local ExitTowerWaveInput = Tabs.Tower:Input({
    Title = "Exit at Wave",
    Desc = "Exits Tower after this wave.",
    Value = "",
    Placeholder = "Enter wave number",
    Callback = function(Text) state.exitTowerWave = tonumber(Text) end
})
local TowerPara = Tabs.Tower:Paragraph({
    Title = "Status",
    Desc = "Current wave and status inside Tower. Calculating..."
})
_G.exitedTower = false
monitorGamemode("Tower", TowerPara, function() return getWave("Tower") end, function() return getGamemodeMob("Tower") end, "AutoTower", "exitTowerWave", "exitedTower", true)
-- Misc Tab
local AutoBossToggle = Tabs.Misc:Toggle({
    Title = "Auto Farm Boss",
    Desc = "Farms bosses and returns to saved spot.",
    Value = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos) then
            WindUI:Notify({Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Auto Farm Boss!", Duration = 4, Icon = "settings"})
            AutoBossToggle:Set(false)
            return
        end
        state.toggles.AutoBoss = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoBoss do
                    if state.toggles.AutoTower or getGamemodeMob("Trial") or getGamemodeMob("Tower") or state.inTrialWait then task.wait(0.1) continue end
                    local hrp = getHRP()
                    if not hrp then task.wait(0.1) continue end
                    local bosses = getBosses()
                    if #bosses == 0 then task.wait(0.1) continue end
                    Bridge:FireServer("General", "Teleport", "Teleport", C.BOSS_WORLD)
                    task.wait(1.5)
                    local firstBossPart = getPart(bosses[1])
                    if firstBossPart then tpTo(firstBossPart) task.wait(0.07) end
                    while state.toggles.AutoBoss and #getBosses() > 0 do
                        if state.toggles.AutoTower or getGamemodeMob("Trial") or getGamemodeMob("Tower") or state.inTrialWait then break end
                        local targetBoss = getBosses()[1]
                        if targetBoss and targetBoss.Parent and (targetBoss:GetAttribute("Health") or 1) > 0 then
                            maintainDist(getPart(targetBoss))
                        end
                        task.wait(0.07)
                    end
                    if state.toggles.AutoBoss then returnSaved() task.wait(0.07) end
                    task.wait(0.4)
                end
            end)
        end
    end
})
local BossPara = Tabs.Misc:Paragraph({
    Title = "Boss Status",
    Desc = "Monitors spawned bosses. Checking..."
})
local ReturnWorldDD = Tabs.Misc:Dropdown({
    Title = "Return World",
    Desc = "World to return to after bosses or raids.",
    Values = C.WORLDS,
    Callback = function(Option) state.returnWorld = Option end
})
local SavePosButton = Tabs.Misc:Button({
    Title = "Save Position",
    Desc = "Saves current position for auto-return.",
    Callback = function()
        if not state.returnWorld then
            WindUI:Notify({Title = "Missing Return World", Content = "Please select a 'Return World' first to save position!", Duration = 4, Icon = "settings"})
            return
        end
        local hrp = getHRP()
        if hrp then
            state.savedPos = hrp.CFrame
            WindUI:Notify({Title = "Position Saved", Content = "Your current position has been saved to return to: " .. state.returnWorld, Duration = 3, Icon = "settings"})
        end
    end
})
-- Monitoring
task.spawn(function()
    while true do
        local bosses = getBosses()
        local bossNames = {}
        for _, boss in ipairs(bosses) do table.insert(bossNames, boss.Name) end
        BossPara:SetDesc(string.format("Bosses Spawned: %s\nList: %s", #bosses > 0 and "Yes" or "No", #bossNames > 0 and table.concat(bossNames, ", ") or "None"))
        task.wait(0.3)
    end
end)
