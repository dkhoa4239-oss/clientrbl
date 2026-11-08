-- lang: Luau, file: BloxFruits_RealKid.lua
-- target: Roblox Blox Fruits, executor: Delta X / any UNC-compatible
-- remotes sourced from Luraph v15.1 static analysis

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local lp     = Players.LocalPlayer
local char   = lp.Character or lp.CharacterAdded:Wait()
local root   = char:WaitForChild("HumanoidRootPart")
local hum    = char:WaitForChild("Humanoid")

-- ================================================================
-- CONFIG
-- ================================================================
local Config = {
    AutoFarm        = false,
    BossFarm        = false,
    SeaBeastFarm    = false,
    AutoChest       = false,
    AutoFruit       = false,
    AutoRaid        = false,
    AutoLever       = false,
    NoClip          = false,
    AutoTP          = false,
    FarmRange       = 55,
    FarmDelay       = 0.08,
    SelectedBoss    = "Leviathan",
}

-- ================================================================
-- UTILS
-- ================================================================
local function getRoot(char2)
    return char2 and char2:FindFirstChild("HumanoidRootPart")
end

local function isAlive(char2)
    local h = char2 and char2:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function tpTo(pos)
    if root then
        root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
end

local function safeCall(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[BF] " .. tostring(err)) end
end

-- ================================================================
-- REMOTE HELPERS
-- ================================================================
local function getRemote(name)
    -- trường hợp remote nằm trong ReplicatedStorage hoặc workspace
    local rs = game:GetService("ReplicatedStorage")
    local r  = rs:FindFirstChild(name, true)
           or workspace:FindFirstChild(name, true)
    return r
end

local function fireRemote(name, ...)
    local r = getRemote(name)
    if r and r:IsA("RemoteEvent") then
        r:FireServer(...)
    elseif r and r:IsA("RemoteFunction") then
        r:InvokeServer(...)
    end
end

-- ================================================================
-- AUTO FARM (mob attack via RegisterHit)
-- ================================================================
local function getNearestMob(range)
    local nearest, nearDist = nil, range or math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        -- skip players, only NPCs
    end
    -- scan workspace NPCs
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= char then
            local h2  = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart")
            if h2 and hrp and h2.Health > 0 then
                local d = (hrp.Position - root.Position).Magnitude
                if d < nearDist then
                    nearDist = d
                    nearest  = obj
                end
            end
        end
    end
    return nearest, nearDist
end

local function doAutoFarm()
    if not Config.AutoFarm then return end
    local target, dist = getNearestMob(Config.FarmRange * 3)
    if not target then return end

    local hrp = target:FindFirstChild("HumanoidRootPart")
    if hrp then
        -- teleport sát target
        tpTo(hrp.Position)
        task.wait(0.05)
        -- fire RegisterHit
        safeCall(function()
            fireRemote("RE/RegisterAttack", 0)
            fireRemote("RE/RegisterHit")
            -- fallback: FindFirstChild path
            local rh = workspace:FindFirstChild("Enemies", true)
            if rh then
                local re = rh:FindFirstChild("RegisterHit", true)
                if re then re:FireServer(target, char) end
            end
        end)
    end
end

-- ================================================================
-- BOSS FARM
-- ================================================================
local BossNames = {
    "Leviathan", "leviathan",
    "Dragonstorm",
    "Rip_indra", "Indra",
    "CipherToken", "Soul Reaper",
    "Cake Queen", "Island Empress",
    "Longma", "Gavina",
    "Corrupted King",
    "Order", "Cursed Captain",
    "Bobby", "Yeti",
}

local SegmentNames = {
    ["Leviathan Segment"]    = true,
    ["Liberator of the Sky"] = true,
    ["Shadow Sovereign"]     = true,
}

local function findBoss()
    for _, name in ipairs(BossNames) do
        local b = workspace:FindFirstChild(name)
                or workspace:FindFirstChild(name, true)
        if b and b:IsA("Model") then
            local hrp = b:FindFirstChild("HumanoidRootPart")
            local h2  = b:FindFirstChildOfClass("Humanoid")
            if hrp and h2 and h2.Health > 0 then
                return b, hrp
            end
            -- check segments (Leviathan)
            for _, seg in ipairs(b:GetChildren()) do
                if SegmentNames[seg.Name] then
                    local sHRP = seg:FindFirstChild("HumanoidRootPart")
                    local sH   = seg:FindFirstChildOfClass("Humanoid")
                    if sHRP and sH and sH.Health > 0 then
                        return seg, sHRP
                    end
                end
            end
        end
    end
    return nil, nil
end

local function doBossFarm()
    if not Config.BossFarm then return end
    local boss, bHRP = findBoss()
    if not boss or not bHRP then return end

    local dist = (bHRP.Position - root.Position).Magnitude
    if dist > 10 then
        tpTo(bHRP.Position)
        task.wait(0.08)
    end

    safeCall(function()
        -- disable hitbox
        for _, p in ipairs(boss:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
        fireRemote("RE/RegisterAttack", 0)
        fireRemote("RE/RegisterHit")
    end)
end

-- ================================================================
-- SEA BEAST FARM
-- ================================================================
local function doSeaBeastFarm()
    if not Config.SeaBeastFarm then return end
    local folder = workspace:FindFirstChild("SeaBeasts")
                or workspace:FindFirstChild("SeaBeast", true)
    if not folder then return end

    local nearest, nearDist = nil, math.huge
    for _, beast in ipairs(folder:GetChildren()) do
        local hrp = beast:FindFirstChild("HumanoidRootPart")
        local h2  = beast:FindFirstChildOfClass("Humanoid")
        if hrp and h2 and h2.Health > 0 then
            local d = (hrp.Position - root.Position).Magnitude
            if d < nearDist then
                nearDist = d
                nearest  = beast
            end
        end
    end

    if nearest then
        local bHRP = nearest:FindFirstChild("HumanoidRootPart")
        tpTo(bHRP.Position)
        task.wait(0.08)
        safeCall(function()
            fireRemote("RE/RegisterAttack", 0)
            fireRemote("RE/RegisterHit")
        end)
    end
end

-- ================================================================
-- AUTO CHEST
-- ================================================================
local function doAutoChest()
    if not Config.AutoChest then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("chest") and obj:IsA("Model") then
            local part = obj:FindFirstChildOfClass("BasePart")
            if part then
                tpTo(part.Position)
                task.wait(0.1)
                -- proximity prompt / touch
                local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                if pp then
                    fireproximityprompt(pp)
                end
            end
        end
    end
end

-- ================================================================
-- AUTO FRUIT
-- ================================================================
local function doAutoFruit()
    if not Config.AutoFruit then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Blox Fruit" or obj.Name:find("Fruit") then
            local part = obj:FindFirstChildOfClass("BasePart")
                      or (obj:IsA("BasePart") and obj)
            if part then
                tpTo(part.Position)
                task.wait(0.1)
                local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                        or part:FindFirstChildOfClass("ProximityPrompt")
                if pp then
                    safeCall(function() fireproximityprompt(pp) end)
                end
            end
        end
    end
end

-- ================================================================
-- NO CLIP
-- ================================================================
RunService.Stepped:Connect(function()
    if not Config.NoClip then return end
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
end)

-- ================================================================
-- CHARACTER REFRESH
-- ================================================================
lp.CharacterAdded:Connect(function(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
end)

-- ================================================================
-- MAIN LOOP
-- ================================================================
task.spawn(function()
    while task.wait(Config.FarmDelay) do
        if not char or not root then continue end
        if hum and hum.Health <= 0 then continue end

        doAutoFarm()
        doBossFarm()
        doSeaBeastFarm()
        doAutoChest()
        doAutoFruit()
    end
end)

-- ================================================================
-- GUI
-- ================================================================
local gui = Instance.new("ScreenGui")
gui.Name           = "BF_RealKid"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = gethui and gethui() or lp.PlayerGui

local main = Instance.new("Frame")
main.Size            = UDim2.new(0, 220, 0, 320)
main.Position        = UDim2.new(0, 10, 0.3, 0)
main.BackgroundColor3= Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.Active          = true
main.Draggable       = true
main.Parent          = gui

-- rounded corner
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = main

-- title bar
local title = Instance.new("TextLabel")
title.Size              = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3  = Color3.fromRGB(90, 40, 200)
title.BorderSizePixel   = 0
title.Text              = "BF RealKid  •  Delta X"
title.TextColor3        = Color3.new(1,1,1)
title.TextSize          = 13
title.Font              = Enum.Font.GothamBold
title.Parent            = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = title

-- toggle builder
local yOff = 38
local function makeToggle(label, configKey)
    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.new(1, -16, 0, 28)
    btn.Position        = UDim2.new(0, 8, 0, yOff)
    btn.BackgroundColor3= Color3.fromRGB(30, 30, 40)
    btn.BorderSizePixel = 0
    btn.TextColor3      = Color3.fromRGB(180, 180, 200)
    btn.TextSize        = 12
    btn.Font            = Enum.Font.Gotham
    btn.Text            = "[ OFF ]  " .. label
    btn.TextXAlignment  = Enum.TextXAlignment.Left
    btn.Parent          = main
    yOff += 32

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 5)
    bc.Parent = btn

    btn.MouseButton1Click:Connect(function()
        Config[configKey] = not Config[configKey]
        if Config[configKey] then
            btn.Text             = "[ ON  ]  " .. label
            btn.BackgroundColor3 = Color3.fromRGB(50, 25, 100)
            btn.TextColor3       = Color3.fromRGB(180, 120, 255)
        else
            btn.Text             = "[ OFF ]  " .. label
            btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
            btn.TextColor3       = Color3.fromRGB(180, 180, 200)
        end
    end)
end

makeToggle("Auto Farm Mob",   "AutoFarm")
makeToggle("Boss Farm",       "BossFarm")
makeToggle("Sea Beast Farm",  "SeaBeastFarm")
makeToggle("Auto Chest",      "AutoChest")
makeToggle("Auto Fruit",      "AutoFruit")
makeToggle("Auto Raid",       "AutoRaid")
makeToggle("Auto Lever",      "AutoLever")
makeToggle("No Clip",         "NoClip")

-- resize main to fit
main.Size = UDim2.new(0, 220, 0, yOff + 10)

print("[BF RealKid] loaded — Delta X OK")