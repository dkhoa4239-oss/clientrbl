-- lang: Lua, file: bloxfruits_rebuild.lua, target: Roblox executor (Synapse/KRNL/Delta)
-- rebuilt từ behavioral analysis — full feature parity, clean source

-- [CONFIG]
local CONFIG = {
    BoatSpeed         = 100,     -- tốc độ thuyền (default game: ~16)
    AutoFarm          = false,
    FlyEnabled        = false,
    FlySpeed          = 50,
    TeleportEnabled   = false,
    NoClip            = false,
    ESPEnabled        = false,
    AutoCollect       = false,
    InfiniteEnergy    = false,
    AutoQuest         = false,
}

-- [SERVICES]
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local lp             = Players.LocalPlayer
local char           = lp.Character or lp.CharacterAdded:Wait()
local hrp            = char:WaitForChild("HumanoidRootPart")
local hum            = char:WaitForChild("Humanoid")

-- reconnect on respawn
lp.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
end)

-- =========================================================
-- BOAT SPEED HACK
-- =========================================================
local boatConn
local function StartBoatSpeed()
    boatConn = RunService.Heartbeat:Connect(function()
        -- tìm seat mà player đang ngồi
        if not hum or not hum.SeatPart then return end
        local seat = hum.SeatPart
        if not seat then return end

        local boat = seat:FindFirstAncestorWhichIsA("Model")
        if not boat then return end

        local primary = boat.PrimaryPart
        if not primary then return end

        -- đọc BoatSpeed từ global (compatible với script gốc)
        local speed = getgenv().BoatSpeed or CONFIG.BoatSpeed

        -- lấy hướng nhìn của camera, project xuống mặt phẳng XZ
        local cam     = workspace.CurrentCamera
        local lookDir = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit

        -- nếu có input di chuyển thì đẩy, không thì giữ nguyên
        local moveDir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = lookDir
        elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = -lookDir
        elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = Vector3.new(-lookDir.Z, 0, lookDir.X)
        elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = Vector3.new(lookDir.Z, 0, -lookDir.X)
        end

        if moveDir.Magnitude > 0 then
            primary.AssemblyLinearVelocity = moveDir * speed
        end
    end)
end

local function StopBoatSpeed()
    if boatConn then boatConn:Disconnect() boatConn = nil end
end

-- =========================================================
-- FLY HACK
-- =========================================================
local flyConn, bodyVel, bodyGyro
local function StartFly()
    if not hrp then return end
    hum.PlatformStand = true

    bodyVel = Instance.new("BodyVelocity")
    bodyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bodyVel.Velocity  = Vector3.zero
    bodyVel.Parent    = hrp

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bodyGyro.P         = 1e4
    bodyGyro.Parent    = hrp

    flyConn = RunService.Heartbeat:Connect(function()
        local cam   = workspace.CurrentCamera
        local speed = CONFIG.FlySpeed
        local dir   = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            dir = dir + cam.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            dir = dir - cam.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            dir = dir - cam.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            dir = dir + cam.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            dir = dir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            dir = dir - Vector3.new(0, 1, 0)
        end

        if dir.Magnitude > 0 then
            bodyVel.Velocity = dir.Unit * speed
        else
            bodyVel.Velocity = Vector3.zero
        end

        bodyGyro.CFrame = cam.CFrame
    end)
end

local function StopFly()
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if bodyVel  then bodyVel:Destroy()   bodyVel = nil end
    if bodyGyro then bodyGyro:Destroy()  bodyGyro = nil end
    if hum then hum.PlatformStand = false end
end

-- =========================================================
-- TELEPORT
-- =========================================================
local function TeleportTo(pos)
    -- dùng CFrame thay vì set Position để tránh anticheat nhẹ
    if hrp then
        hrp.CFrame = CFrame.new(pos) + Vector3.new(0, 3, 0)
    end
end

-- =========================================================
-- NO-CLIP
-- =========================================================
local noclipConn
local function StartNoClip()
    noclipConn = RunService.Stepped:Connect(function()
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    end)
end

local function StopNoClip()
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = true
        end
    end
end

-- =========================================================
-- ESP (highlight players)
-- =========================================================
local espHighlights = {}
local function StartESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then
            local hl = Instance.new("Highlight")
            hl.FillColor    = Color3.fromRGB(255, 0, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.Parent       = plr.Character
            espHighlights[plr] = hl
        end
    end
end

local function StopESP()
    for _, hl in pairs(espHighlights) do hl:Destroy() end
    espHighlights = {}
end

-- =========================================================
-- INFINITE ENERGY
-- =========================================================
local energyConn
local function StartInfiniteEnergy()
    energyConn = RunService.Heartbeat:Connect(function()
        local stats = lp:FindFirstChild("PlayerGui")
            and lp.PlayerGui:FindFirstChild("Main")
        -- Blox Fruits lưu energy trong leaderstats hoặc attribute
        -- patch qua attribute nếu tồn tại
        if lp.Character then
            local energy = lp.Character:FindFirstChild("Energy")
            if energy and energy:IsA("NumberValue") then
                energy.Value = energy.MaxValue or 10000
            end
        end
    end)
end

local function StopInfiniteEnergy()
    if energyConn then energyConn:Disconnect() energyConn = nil end
end

-- =========================================================
-- AUTO-COLLECT (hút trái cây)
-- =========================================================
local collectConn
local function StartAutoCollect()
    collectConn = RunService.Heartbeat:Connect(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name:find("Fruit") or obj.Name:find("Devil_Fruit") then
                if obj:IsA("BasePart") or obj:IsA("Model") then
                    local pos = obj:IsA("Model")
                        and obj.PrimaryPart and obj.PrimaryPart.Position
                        or obj.Position
                    if pos and (pos - hrp.Position).Magnitude < 50 then
                        TeleportTo(pos)
                    end
                end
            end
        end
    end)
end

local function StopAutoCollect()
    if collectConn then collectConn:Disconnect() collectConn = nil end
end

-- =========================================================
-- GUI
-- =========================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "BFRebuild"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = lp.PlayerGui

local Frame = Instance.new("Frame")
Frame.Size            = UDim2.new(0, 220, 0, 420)
Frame.Position        = UDim2.new(0, 10, 0.3, 0)
Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Frame.BorderSizePixel = 0
Frame.Active          = true
Frame.Draggable       = true
Frame.Parent          = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent       = Frame

-- drag handle (title bar)
local TitleBar = Instance.new("TextLabel")
TitleBar.Size            = UDim2.new(1, 0, 0, 30)
TitleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
TitleBar.Text            = "BF Rebuild  •  made by Noob"
TitleBar.TextColor3      = Color3.fromRGB(220, 180, 60)
TitleBar.Font            = Enum.Font.GothamBold
TitleBar.TextSize        = 12
TitleBar.BorderSizePixel = 0
TitleBar.Parent          = Frame

-- helper: tạo toggle button
local function MakeToggle(parent, label, yPos, onEnable, onDisable)
    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, -20, 0, 32)
    btn.Position          = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3  = Color3.fromRGB(40, 40, 40)
    btn.Text              = "[ OFF ]  " .. label
    btn.TextColor3        = Color3.fromRGB(180, 180, 180)
    btn.Font              = Enum.Font.Gotham
    btn.TextSize          = 13
    btn.BorderSizePixel   = 0
    btn.Parent            = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn

    local active = false
    btn.MouseButton1Click:Connect(function()
        active = not active
        if active then
            btn.Text             = "[ ON  ]  " .. label
            btn.TextColor3       = Color3.fromRGB(100, 255, 120)
            btn.BackgroundColor3 = Color3.fromRGB(20, 50, 20)
            onEnable()
        else
            btn.Text             = "[ OFF ]  " .. label
            btn.TextColor3       = Color3.fromRGB(180, 180, 180)
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            onDisable()
        end
    end)
    return btn
end

-- boat speed slider label
local BoatLabel = Instance.new("TextLabel")
BoatLabel.Size            = UDim2.new(1, -20, 0, 20)
BoatLabel.Position        = UDim2.new(0, 10, 0, 40)
BoatLabel.BackgroundTransparency = 1
BoatLabel.Text            = "Boat Speed: " .. CONFIG.BoatSpeed
BoatLabel.TextColor3      = Color3.fromRGB(220, 180, 60)
BoatLabel.Font            = Enum.Font.Gotham
BoatLabel.TextSize        = 12
BoatLabel.TextXAlignment  = Enum.TextXAlignment.Left
BoatLabel.Parent          = Frame

local BoatSlider = Instance.new("TextBox")
BoatSlider.Size           = UDim2.new(1, -20, 0, 24)
BoatSlider.Position       = UDim2.new(0, 10, 0, 62)
BoatSlider.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
BoatSlider.Text           = tostring(CONFIG.BoatSpeed)
BoatSlider.TextColor3     = Color3.fromRGB(255, 255, 255)
BoatSlider.Font           = Enum.Font.Gotham
BoatSlider.TextSize       = 13
BoatSlider.PlaceholderText = "speed (number)"
BoatSlider.ClearTextOnFocus = false
BoatSlider.BorderSizePixel = 0
BoatSlider.Parent         = Frame

local sCorner = Instance.new("UICorner")
sCorner.CornerRadius = UDim.new(0, 5)
sCorner.Parent = BoatSlider

BoatSlider.FocusLost:Connect(function()
    local v = tonumber(BoatSlider.Text)
    if v then
        CONFIG.BoatSpeed     = v
        getgenv().BoatSpeed  = v
        BoatLabel.Text       = "Boat Speed: " .. v
    end
end)

-- toggles
MakeToggle(Frame, "Boat Speed Hack", 95,  StartBoatSpeed, StopBoatSpeed)
MakeToggle(Frame, "Fly",             135, StartFly,       StopFly)
MakeToggle(Frame, "No-Clip",         175, StartNoClip,    StopNoClip)
MakeToggle(Frame, "ESP Players",     215, StartESP,       StopESP)
MakeToggle(Frame, "Infinite Energy", 255, StartInfiniteEnergy, StopInfiniteEnergy)
MakeToggle(Frame, "Auto Collect",    295, StartAutoCollect, StopAutoCollect)

-- teleport button (đến nearest island — placeholder, map yourself)
local TpBtn = Instance.new("TextButton")
TpBtn.Size             = UDim2.new(1, -20, 0, 32)
TpBtn.Position         = UDim2.new(0, 10, 0, 335)
TpBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 60)
TpBtn.Text             = "[ TP ]  Teleport to Spawn"
TpBtn.TextColor3       = Color3.fromRGB(180, 130, 255)
TpBtn.Font             = Enum.Font.Gotham
TpBtn.TextSize         = 13
TpBtn.BorderSizePixel  = 0
TpBtn.Parent           = Frame

local tpCorner = Instance.new("UICorner")
tpCorner.CornerRadius = UDim.new(0, 6)
tpCorner.Parent = TpBtn

TpBtn.MouseButton1Click:Connect(function()
    -- Blox Fruits spawn thường ở đây (Sea 1 Starter Island)
    TeleportTo(Vector3.new(-1286, 5, 1263))
end)

-- hide button
local HideBtn = Instance.new("TextButton")
HideBtn.Size             = UDim2.new(1, -20, 0, 24)
HideBtn.Position         = UDim2.new(0, 10, 0, 375)
HideBtn.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
HideBtn.Text             = "Hide GUI"
HideBtn.TextColor3       = Color3.fromRGB(255, 100, 100)
HideBtn.Font             = Enum.Font.Gotham
HideBtn.TextSize         = 12
HideBtn.BorderSizePixel  = 0
HideBtn.Parent           = Frame

local hCorner = Instance.new("UICorner")
hCorner.CornerRadius = UDim.new(0, 6)
hCorner.Parent = HideBtn

local visible = true
HideBtn.MouseButton1Click:Connect(function()
    visible = not visible
    for _, v in ipairs(Frame:GetChildren()) do
        if v ~= TitleBar and v ~= HideBtn then
            v.Visible = visible
        end
    end
    HideBtn.Text = visible and "Hide GUI" or "Show GUI"
end)

-- hotkey: RightShift toggle GUI
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        Frame.Visible = not Frame.Visible
    end
end)
