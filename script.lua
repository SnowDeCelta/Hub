local Library = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local SaveManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/SaveManager.luau"))()
local InterfaceManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()
local Window = Library:CreateWindow{
    Title = "Infinity Hub",
    SubTitle = "Anime Fight",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    MinSize = Vector2.new(470, 380),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftAlt
}
local Tabs = {
    Farm = Window:CreateTab{Title = "Farm", Icon = "sword"},
    Stars = Window:CreateTab{Title = "Stars", Icon = "star"},
    Trial = Window:CreateTab{Title = "Trial", Icon = "shield"},
    Tower = Window:CreateTab{Title = "Tower", Icon = "building"},
    Gacha = Window:CreateTab{Title = "Gacha", Icon = "star"},
    Events = Window:CreateTab{Title = "Events", Icon = "zap"},
    Misc = Window:CreateTab{Title = "Misc", Icon = "wand"},
    Settings = Window:CreateTab{Title = "Settings", Icon = "settings"}
}
local Options = Library.Options
local Services = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Workspace = workspace
}
local player = Services.Players.LocalPlayer
local Bridge = Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bridge")
local state = {
    world = nil, mob = nil, returnWorld = nil, savedPos = nil,
    diffByName = {}, toggles = {}, exitWave = nil, inTrialWait = false,
    exitTowerWave = nil, triedEnterTower = false, gachaType = nil,
    meteorCount = 0, lastMeteorTime = 0, meteorRainActive = false,
    inTowerWait = false
}
local C = {
    WORLDS = {"Leaf Village", "Dragon Town", "Slayer Village", "Pirate Island"},
    BOSS_WORLD = "Leaf Village",
    BOSS_NAMES = {"KesameAkat", "ItacheAkat"},
    RAID_ENTRY_MINUTES = {0, 30},
    RAID_ENTRY_SECOND = 31,
    TELEPORT_OFFSET = CFrame.new(0, 5, -8),
    FARM_DISTANCE_THRESHOLD = 80,
    METEOR_TELEPORT_OFFSET = CFrame.new(0, 5, -3),
    CHEST_TELEPORT_OFFSET = CFrame.new(0, 5, -3)
}
local CHEST_NAMES = {"Daily", "Group", "Time", "VIP"}
local function getHRP() return (player.Character or player.CharacterAdded:Wait()):FindFirstChild("HumanoidRootPart") end
local function getPart(model)
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildOfClass("BasePart") end
end
local function tpTo(targetPart, offset)
    local hrp = getHRP()
    if hrp and targetPart then hrp.CFrame = targetPart.CFrame * (offset or C.TELEPORT_OFFSET) end
end
local function maintainDist(targetPart)
    local hrp = getHRP()
    if hrp and targetPart and (hrp.Position - targetPart.Position).Magnitude > C.FARM_DISTANCE_THRESHOLD then
        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 5, -5)
    end
end
local function getMeteor()
    local success, folder = pcall(function() return Services.Workspace:WaitForChild("Server"):WaitForChild("GameEvent"):WaitForChild("Meteors"):WaitForChild("Spawned") end)
    if success and folder then for _, m in ipairs(folder:GetChildren()) do if m and m.Parent and m:IsA("Model") then return m end end end
    return nil
end
local function getEnemy(world, diff)
    local folder = Services.Workspace.Server.Enemies:FindFirstChild(world)
    if folder then for _, e in ipairs(folder:GetChildren()) do if e:GetAttribute("Difficult") == diff and (e:GetAttribute("Health") or 1) > 0 then return e end end end
end
local function updateMobDD(worldName, dropdown)
    local mobByDiff, values = {}, {}
    local worldFolder = Services.Workspace.Server.Enemies:FindFirstChild(worldName)
    state.diffByName = {}
    state.mob = nil
    if worldFolder then
        for _, enemy in ipairs(worldFolder:GetChildren()) do
            local diff = enemy:GetAttribute("Difficult")
            if diff and not mobByDiff[diff] and table.find({"Easy","Medium","Hard","Insane","Boss"}, diff) then mobByDiff[diff] = enemy.Name end
        end
        for _, key in ipairs({"Easy","Medium","Hard","Insane","Boss"}) do
            if mobByDiff[key] then table.insert(values, mobByDiff[key]) state.diffByName[mobByDiff[key]] = key end
        end
    end
    if #values > 0 then dropdown:SetValues(values) dropdown:SetValue(nil) else dropdown:SetValues({"No Mobs"}) dropdown:SetValue("No Mobs") end
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
local function getSelMob() return state.world and state.mob and getEnemy(state.world, state.diffByName[state.mob]) or nil end
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
    if folder then for _, name in ipairs(C.BOSS_NAMES) do local boss = folder:FindFirstChild(name) if boss and (boss:GetAttribute("Health") or 1) > 0 then table.insert(bosses, boss) end end end
    return bosses
end
local function farmLoop(key, getTarget)
    task.spawn(function()
        while state.toggles[key] do
            if getMeteor() then
                task.wait(0.05)
            else
                local hrp = getHRP()
                if not hrp then
                    task.wait(0.05)
                else
                    local mob = getTarget()
                    while state.toggles[key] and not mob do task.wait(0.5) mob = getTarget() end
                    if not state.toggles[key] then break end
                    local mobPart = getPart(mob)
                    if not mobPart then
                        task.wait(0.05)
                    else
                        tpTo(mobPart)
                        task.wait(0.05)
                        while state.toggles[key] and mob and mob.Parent and (mob:GetAttribute("Health") or 1) > 0 do
                            if getMeteor() then break end
                            maintainDist(getPart(mob))
                            task.wait(0.05)
                        end
                        task.wait(0.2)
                    end
                end
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
            local min, sec = timeToNext()
            local desc = gamemode == "Trial" and string.format("Wave: %s | Status: %s\nNext Entry: %02d:%02d", tostring(currentWave), inMode, min, sec) or
                         string.format("Wave: %s | Status: %s", tostring(currentWave), inMode)
            para:SetValue(desc)
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
-- Farm Tab
local WorldDD = Tabs.Farm:CreateDropdown("WorldDD", {Title = "Select World", Values = C.WORLDS, Multi = false, Default = nil})
local MobDropdown = Tabs.Farm:CreateDropdown("MobDropdown", {Title = "Select Mob", Values = {"No Mobs"}, Multi = false, Default = nil})
WorldDD:OnChanged(function(Value) if Value and Value ~= "" then state.world = Value updateMobDD(Value, MobDropdown) end end)
MobDropdown:OnChanged(function(Value) if Value and Value ~= "" and Value ~= "No Mobs" then state.mob = Value else state.mob = nil end end)
local AutoFarmToggle = Tabs.Farm:CreateToggle("AutoFarmToggle", {
    Title = "Auto Farm",
    Default = false,
    Callback = function(Value)
        state.toggles.AutoFarm = Value
        if Value then
            if not state.world or not state.mob or state.mob == "No Mobs" then
                Library:Notify{Title = "Missing Selection", Content = "Please select a world and a mob first!", Duration = 4}
                state.toggles.AutoFarm = false Options.AutoFarmToggle:SetValue(false) return
            end
            Bridge:FireServer("General", "Teleport", "Teleport", state.world)
            task.wait(0.5)
            farmLoop("AutoFarm", getSelMob)
        end
    end
})
-- Stars Tab
local AutoHatchNToggle = Tabs.Stars:CreateToggle("AutoHatchNToggle", {
    Title = "Auto Hatch Normal",
    Default = false,
    Callback = function(Value)
        state.toggles.AutoHatchN = Value
        if Value then task.spawn(function() while state.toggles.AutoHatchN do Bridge:FireServer("General", "Star", "Open") task.wait(1.4) end end) end
    end
})
local AutoHatchFToggle = Tabs.Stars:CreateToggle("AutoHatchFToggle", {
    Title = "Auto Hatch Fast",
    Default = false,
    Callback = function(Value)
        state.toggles.AutoHatchF = Value
        if Value then task.spawn(function() while state.toggles.AutoHatchF do Bridge:FireServer("General", "Star", "Open") task.wait(0.05) end end) end
    end
})
-- Trial Tab
local AutoTrialToggle = Tabs.Trial:CreateToggle("AutoTrialToggle", {
    Title = "Enter Trial",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitWave or state.exitWave <= 0) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Enter Trial!", Duration = 4}
            Options.AutoTrialToggle:SetValue(false) return
        end
        state.toggles.AutoTrial = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoTrial do
                    if state.toggles.AutoTower or state.inTowerWait or getMeteor() or getGamemodeMob("Tower") then task.wait(0.1)
                    else
                        local t = os.date("*t")
                        if t.sec == C.RAID_ENTRY_SECOND and table.find(C.RAID_ENTRY_MINUTES, t.min) then
                            Bridge:FireServer("Gamemodes", "Trial", "Join")
                            state.inTrialWait = true
                            task.wait(30)
                            state.inTrialWait = false
                            task.wait(2)
                        end
                    end
                    task.wait(0.3)
                end
            end)
        end
    end
})
local AutoFarmTrialToggle = Tabs.Trial:CreateToggle("AutoFarmTrialToggle", {
    Title = "Auto Farm Trial",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitWave or state.exitWave <= 0) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Auto Farm Trial!", Duration = 4}
            Options.AutoFarmTrialToggle:SetValue(false) return
        end
        state.toggles.AutoFarmTrial = Value
        if Value then farmLoop("AutoFarmTrial", function() return getGamemodeMob("Trial") end) end
    end
})
local ExitWaveInput = Tabs.Trial:CreateInput("ExitWaveInput", {Title = "Exit at Wave", Default = "", Numeric = true, Finished = true, Callback = function(Value) state.exitWave = tonumber(Value) end})
local TrialStatusPara = Tabs.Trial:CreateParagraph("TrialStatusPara", {Title = "Trial Status", Content = "Current wave and status. Calculating..."})
_G.exitedTrial = false
monitorGamemode("Trial", Options.TrialStatusPara, function() return getWave("Trial") end, function() return getGamemodeMob("Trial") end, "AutoTrial", "exitWave", "exitedTrial", true)
-- Tower Tab
local AutoTowerToggle = Tabs.Tower:CreateToggle("AutoTowerToggle", {
    Title = "Enter Tower",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitTowerWave or state.exitTowerWave <= 0) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Enter Tower!", Duration = 4}
            Options.AutoTowerToggle:SetValue(false) return
        end
        state.toggles.AutoTower = Value
        if not Value then
            state.triedEnterTower = false
            state.inTowerWait = false
            return
        end
        task.spawn(function()
            while state.toggles.AutoTower do
                if getMeteor() then task.wait(0.1)
                else
                    if not getGamemodeMob("Tower") and not state.triedEnterTower then
                        Bridge:FireServer("Gamemodes", "Tower", "Start")
                        state.triedEnterTower = true
                        state.inTowerWait = true
                        task.wait(30)
                        state.inTowerWait = false
                        task.wait(2)
                    end
                end
                task.wait(0.3)
            end
        end)
    end
})
local AutoFarmTowerToggle = Tabs.Tower:CreateToggle("AutoFarmTowerToggle", {
    Title = "Auto Farm Tower",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos or not state.exitTowerWave or state.exitTowerWave <= 0) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World', 'Save Position' and set 'Exit at Wave' (>0) before enabling Auto Farm Tower!", Duration = 4}
            Options.AutoFarmTowerToggle:SetValue(false) return
        end
        state.toggles.AutoFarmTower = Value
        if Value then farmLoop("AutoFarmTower", function() return getGamemodeMob("Tower") end) end
    end
})
local ExitTowerWaveInput = Tabs.Tower:CreateInput("ExitTowerWaveInput", {Title = "Exit at Wave", Default = "", Numeric = true, Finished = true, Callback = function(Value) state.exitTowerWave = tonumber(Value) end})
local TowerPara = Tabs.Tower:CreateParagraph("TowerPara", {Title = "Status", Content = "Current wave and status inside Tower. Calculating..."})
_G.exitedTower = false
monitorGamemode("Tower", Options.TowerPara, function() return getWave("Tower") end, function() return getGamemodeMob("Tower") end, "AutoTower", "exitTowerWave", "exitedTower", true)
-- Gacha Tab
local GachaDD = Tabs.Gacha:CreateDropdown("GachaDD", {Title = "Select Gacha", Values = {"Clans", "Races", "Breathings", "Haki"}, Multi = false, Default = nil})
GachaDD:OnChanged(function(Value) if Value and Value ~= "" then state.gachaType = Value end end)
local AutoRerollToggle = Tabs.Gacha:CreateToggle("AutoRerollToggle", {
    Title = "Auto Reroll",
    Default = false,
    Callback = function(Value)
        state.toggles.AutoReroll = Value
        if Value then
            if not state.gachaType then
                Library:Notify{Title = "Missing Selection", Content = "Please select a gacha type first!", Duration = 4}
                state.toggles.AutoReroll = false Options.AutoRerollToggle:SetValue(false) return
            end
            task.spawn(function() while state.toggles.AutoReroll do Bridge:FireServer("General", state.gachaType, "Reroll") task.wait(1) end end)
        end
    end
})
-- Events Tab
local AutoBossToggle = Tabs.Events:CreateToggle("AutoBossToggle", {
    Title = "Auto Farm Boss",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Auto Farm Boss!", Duration = 4}
            Options.AutoBossToggle:SetValue(false) return
        end
        state.toggles.AutoBoss = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoBoss do
                    if getMeteor() or state.meteorRainActive or state.toggles.AutoTower or state.inTowerWait or getGamemodeMob("Trial") or getGamemodeMob("Tower") or state.inTrialWait then
                        task.wait(0.05)
                    else
                        local hrp = getHRP()
                        if not hrp then
                            task.wait(0.05)
                        else
                            local bosses = getBosses()
                            if #bosses == 0 then
                                task.wait(0.05)
                            else
                                Bridge:FireServer("General", "Teleport", "Teleport", C.BOSS_WORLD)
                                task.wait(1.5)
                                local firstBossPart = getPart(bosses[1])
                                if firstBossPart then tpTo(firstBossPart) task.wait(0.05) end
                                while state.toggles.AutoBoss and #getBosses() > 0 do
                                    if getMeteor() or state.meteorRainActive or state.toggles.AutoTower or state.inTowerWait or getGamemodeMob("Trial") or getGamemodeMob("Tower") or state.inTrialWait then break end
                                    local targetBoss = getBosses()[1]
                                    if targetBoss and targetBoss.Parent and (targetBoss:GetAttribute("Health") or 1) > 0 then maintainDist(getPart(targetBoss)) end
                                    task.wait(0.05)
                                end
                                if state.toggles.AutoBoss then returnSaved() task.wait(0.05) end
                                task.wait(0.2)
                            end
                        end
                    end
                end
            end)
        end
    end
})
local BossPara = Tabs.Events:CreateParagraph("BossPara", {Title = "Boss Status", Content = "Monitors spawned bosses. Checking..."})
local AutoMeteorToggle = Tabs.Events:CreateToggle("AutoMeteorToggle", {
    Title = "Auto Meteor",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos) then
            Library:Notify{Title = "Missing Setup", Content = "Please select 'Return World' and 'Save Position' before enabling Auto Meteor!", Duration = 4}
            Options.AutoMeteorToggle:SetValue(false) return
        end
        state.toggles.AutoMeteor = Value
        if Value then
            task.spawn(function()
                while state.toggles.AutoMeteor do
                    local meteor = getMeteor()
                    if meteor then
                        local currentTime = tick()
                        if currentTime - state.lastMeteorTime > 10 then
                            state.meteorCount = 1
                        else
                            state.meteorCount = state.meteorCount + 1
                        end
                        state.lastMeteorTime = currentTime
                       
                        if state.meteorCount >= 2 then
                            state.meteorRainActive = true
                        end
                       
                        local meteorPart = getPart(meteor)
                        local targetWorld = nil
                        local success, spawnsFolder = pcall(function() return Services.Workspace.Server.GameEvent.Meteors:WaitForChild("Spawns") end)
                        if success and spawnsFolder then
                            for _, spot in ipairs(spawnsFolder:GetChildren()) do
                                if spot:IsA("BasePart") and meteorPart and meteorPart.CFrame == spot.CFrame then
                                    targetWorld = spot.Name
                                    break
                                end
                            end
                        end
                        if targetWorld then
                            Bridge:FireServer("General", "Teleport", "Teleport", targetWorld)
                            task.wait(1.5)
                        end
                        if meteorPart then
                            tpTo(meteorPart, C.METEOR_TELEPORT_OFFSET)
                            task.wait(0.5)
                        end
                        local mesh = meteor:FindFirstChild("Mesh")
                        local prompt = mesh and mesh:FindFirstChild("Prompt")
                        if prompt and prompt:IsA("ProximityPrompt") then
                            local attempts = 0
                            while meteor and prompt and prompt.Parent and attempts < 10 do
                                fireproximityprompt(prompt)
                                attempts = attempts + 1
                                task.wait(0.1)
                            end
                        end
                        while getMeteor() do task.wait(0.05) end
                        returnSaved()
                    else
                        if state.meteorRainActive and tick() - state.lastMeteorTime > 60 then
                            state.meteorRainActive = false
                            state.meteorCount = 0
                        end
                    end
                    task.wait(0.5)
                end
            end)
        end
    end
})
local MeteorPara = Tabs.Events:CreateParagraph("MeteorPara", {Title = "Meteor Status", Content = "Monitors spawned meteors. Checking..."})
-- Misc Tab
local ReturnWorldDD = Tabs.Misc:CreateDropdown("ReturnWorldDD", {Title = "Return World", Values = C.WORLDS, Multi = false, Default = nil})
ReturnWorldDD:OnChanged(function(Value) if Value and Value ~= "" then state.returnWorld = Value end end)
local SavePosButton = Tabs.Misc:CreateButton{
    Title = "Save Position",
    Callback = function()
        if not state.returnWorld then
            Library:Notify{Title = "Missing Return World", Content = "Please select a 'Return World' first to save position!", Duration = 4}
            return
        end
        local hrp = getHRP()
        if hrp then
            state.savedPos = hrp.CFrame
            Library:Notify{Title = "Position Saved", Content = "Your current position has been saved to return to: " .. state.returnWorld, Duration = 3}
        end
    end
}
local ChestDropdown = Tabs.Misc:CreateDropdown("ChestDropdown", {Title = "Select Chests", Values = CHEST_NAMES, Multi = true, Default = {}})
local AutoClaimChestsToggle = Tabs.Misc:CreateToggle("AutoClaimChestsToggle", {
    Title = "Auto Claim Chests",
    Default = false,
    Callback = function(Value)
        if Value and (not state.returnWorld or not state.savedPos) then
            Library:Notify{
                Title = "Missing Setup",
                Content = "Please select 'Return World' and 'Save Position' before enabling Auto Claim Chests!",
                Duration = 4
            }
            Options.AutoClaimChestsToggle:SetValue(false)
            return
        end
       
        local valueDict = Options.ChestDropdown.Value or {}
       
        local selected = {}
        for key, enabled in pairs(valueDict) do
            if enabled then
                table.insert(selected, key)
            end
        end
       
        if Value and #selected == 0 then
            Library:Notify{
                Title = "Missing Selection",
                Content = "Please select at least one chest type!",
                Duration = 4
            }
            Options.AutoClaimChestsToggle:SetValue(false)
            return
        end
       
        state.toggles.AutoClaimChests = Value
       
        if Value then
            task.spawn(function()
                while state.toggles.AutoClaimChests do
                    local valueDict = Options.ChestDropdown.Value or {}
                    local selected = {}
                    for key, enabled in pairs(valueDict) do
                        if enabled then
                            table.insert(selected, key)
                        end
                    end
                   
                    if #selected == 0 then
                        task.wait(5)
                        continue
                    end
                   
                    local hasHigherPriority = false
                   
                    if state.toggles.AutoFarm then
                        hasHigherPriority = true
                    elseif state.meteorRainActive then
                        hasHigherPriority = true
                    elseif state.toggles.AutoTower or state.toggles.AutoFarmTower or state.inTowerWait or getGamemodeMob("Tower") then
                        hasHigherPriority = true
                    elseif state.toggles.AutoTrial or state.toggles.AutoFarmTrial or state.inTrialWait or getGamemodeMob("Trial") then
                        hasHigherPriority = true
                    elseif state.toggles.AutoBoss or #getBosses() > 0 then
                        hasHigherPriority = true
                    end
                   
                    if hasHigherPriority then
                        task.wait(2)
                        continue
                    end
                   
                    local chestsFolder = Services.Workspace.Server:FindFirstChild("Chests")
                   
                    if not chestsFolder then
                        task.wait(5)
                        continue
                    end
                   
                    local collectedAny = false
                   
                    for _, chestName in ipairs(selected) do
                        if not state.toggles.AutoClaimChests then break end
                       
                        local chest = chestsFolder:FindFirstChild(chestName)
                        if not chest then
                            continue
                        end
                       
                        local main = chest:FindFirstChild("main")
                        if not main then
                            continue
                        end
                       
                        local statusGui = main:FindFirstChild("BillboardGui")
                        local isReady = false
                       
                        if statusGui then
                            local statusFrame = statusGui:FindFirstChild("Frame")
                            if statusFrame then
                                local status = statusFrame:FindFirstChild("Status")
                                if status and status:IsA("TextLabel") then
                                    local statusText = status.Text
                                    isReady = (statusText == "READY")
                                end
                            end
                        end
                       
                        if not isReady then
                            continue
                        end
                       
                        local mainPart = getPart(main)
                        if mainPart then
                            tpTo(mainPart, C.CHEST_TELEPORT_OFFSET)
                            task.wait(0.5)
                           
                            local prompt = main:FindFirstChild("Prompt")
                            if prompt and prompt:IsA("ProximityPrompt") then
                                fireproximityprompt(prompt)
                                task.wait(0.1)
                                collectedAny = true
                            end
                        end
                    end
                   
                    if collectedAny then
                        returnSaved()
                        task.wait(1)
                    end
                   
                    task.wait(30)
                end
            end)
        end
    end
})
-- Status monitors
task.spawn(function()
    while true do
        local bosses = getBosses()
        local bossNames = {}
        for _, boss in ipairs(bosses) do table.insert(bossNames, boss.Name) end
       
        local atBoss = false
        local hrp = getHRP()
        if hrp and #bosses > 0 then
            for _, boss in ipairs(bosses) do
                local bossPart = getPart(boss)
                if bossPart then
                    local distance = (hrp.Position - bossPart.Position).Magnitude
                    if distance <= 100 then
                        atBoss = true
                        break
                    end
                end
            end
        end
       
        Options.BossPara:SetValue(string.format("Bosses Spawned: %s\nList: %s\nAt Boss: %s",
            #bosses > 0 and "Yes" or "No",
            #bossNames > 0 and table.concat(bossNames, ", ") or "None",
            atBoss and "Yes" or "No"
        ))
       
        local meteor = getMeteor()
        Options.MeteorPara:SetValue(string.format("Meteor Spawned: %s", meteor and "Yes" or "No"))
        task.wait(0.3)
    end
end)
-- Save/Load configuration
SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes{'ThemeManager_Section'}
InterfaceManager:SetFolder("InfinityHub")
SaveManager:SetFolder("InfinityHub/specific-game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)
Library:Notify{Title = "Infinity Hub", Content = "The script has been loaded.", Duration = 5}
SaveManager:LoadAutoloadConfig()
