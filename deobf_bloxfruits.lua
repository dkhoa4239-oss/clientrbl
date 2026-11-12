--[[
================================================================
  UTILITY MENU V1 - Claude
----------------------------------------------------------------
  THAY ĐỔI:
    - Gộp "Fix Lag (cực mạnh)" + "Fix Lag Farm (siêu mạnh)" thành
      1 toggle duy nhất "Fix Lag (siêu mạnh)":
        * xoá mọi texture bề mặt: Decal/Texture/SurfaceAppearance,
          MaterialVariant, MeshPart.TextureID, SpecialMesh.TextureId,
          quần áo nhân vật (Shirt/Pants/ShirtGraphic)
        * xoá bầu trời: ẩn Sky/Clouds/Atmosphere, thay bằng Sky trống
          (không skybox, không mặt trời/trăng/sao)
        * bề mặt công trình kiểu CHẾ ĐỘ NHANH: SmoothPlastic phẳng,
          giữ màu gốc; nước = 1 màu xanh đặc, không sóng
        * xoá mọi hiệu ứng: particle (kể cả :Emit của skill),
          trail/beam/smoke/fire/sparkles, explosion, đèn, post-effect,
          highlight, selection, billboard, surfacegui, part Neon/ForceField
        * hạ chất lượng đồ hoạ + Lighting.Technology (nếu được phép)
        * lọc theo ClassName, quét lại theo lô -> không giật khung hình
    - Bảo vệ loot/rương + ESP khỏi bị ảnh hưởng
    - Nút D: dời lên góc phải trên, giữ và kéo để di chuyển tự do
================================================================
--]]

local LOOT_NAME_FILTER = { "rương", "ruong", "chest", "treasure" }
local function nameMatchesLootFilter(name)
    local n = string.lower(name)
    for _, k in ipairs(LOOT_NAME_FILTER) do
        if n:find(k, 1, true) then return true end
    end
    return false
end
local function hasInteraction(inst)
    if not inst or not inst.Parent then return false end
    return inst:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
        or inst:FindFirstChildWhichIsA("ClickDetector", true) ~= nil
end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting          = game:GetService("Lighting")
local MaterialService   = game:GetService("MaterialService")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

local ItemFinder -- forward declare

local CONFIG = {
    GuiName         = "UtilityMenuGui",
    ToggleKey       = Enum.KeyCode.RightShift,
    WalkSpeed       = { Min = 1, Max = 500, Default = 16 },
    Jump            = { Min = 1, Max = 500, Default = 50 },
    FarmHeight      = { Min = 3, Max = 30, Default = 8 },
    FarmDistance    = { Min = 3, Max = 25, Default = 8 },
    AttackDistance  = 12,
    AttackSettle    = 0.25,
    MoveMode        = "Align",
    StopDistanceLoot = 2,
    RetargetInterval = 0.2,
    TeleportThreshold = 60,
    EnemyTag            = "FarmableEnemy",
    FallbackEnemyFolder = "Enemies",
    ESP = {
        Color = Color3.fromRGB(0, 200, 255),
        ShowName = true, ShowHealth = true, ShowDistance = true,
        SameTeamOnly = false, UpdateInterval = 0.5,
    },
    ItemESP = {
        FillColor = Color3.fromRGB(255, 200, 0),
        OutlineColor = Color3.fromRGB(255, 255, 255),
        UpdateInterval = 0.3,
    },
    NotifyDuration = 2.5,
}

do
    local old = PlayerGui:FindFirstChild(CONFIG.GuiName)
    if old then old:Destroy() end
end

local function getCharacter() return LocalPlayer.Character end
local function getHumanoid()
    local c = getCharacter()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
local function getHRP()
    local c = getCharacter()
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end
local function isAlive()
    local h = getHumanoid()
    return h ~= nil and h.Health > 0
end
local function normalizeName(n) return (n:gsub("%s*%(%d+%)%s*$", "")) end
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ============================================================
-- NOTIFY
-- ============================================================
local NotifyContainer
local function notify(text, isError)
    if not NotifyContainer or not NotifyContainer.Parent then return end
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = isError and Color3.fromRGB(180,60,60) or Color3.fromRGB(40,45,55)
    frame.BackgroundTransparency = 0.1
    frame.Size = UDim2.new(0, 240, 0, 30)
    frame.AutomaticSize = Enum.AutomaticSize.X
    frame.Position = UDim2.new(0.5, 0, 0, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BorderSizePixel = 0
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = frame
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1,-16,1,0); l.Position = UDim2.new(0,8,0,0)
    l.Font = Enum.Font.GothamMedium; l.TextSize = 12
    l.TextColor3 = Color3.new(1,1,1); l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text; l.Parent = frame
    frame.Parent = NotifyContainer
    task.spawn(function()
        task.wait(CONFIG.NotifyDuration)
        if frame.Parent then
            TweenService:Create(frame, TweenInfo.new(0.3), {BackgroundTransparency=1}):Play()
            TweenService:Create(l, TweenInfo.new(0.3), {TextTransparency=1}):Play()
            task.wait(0.35); frame:Destroy()
        end
    end)
    for _, o in ipairs(NotifyContainer:GetChildren()) do
        if o:IsA("Frame") and o ~= frame then
            local y = o.Position.Y.Offset
            TweenService:Create(o, TweenInfo.new(0.2),
                {Position = UDim2.new(0.5,0,0,y-38)}):Play()
        end
    end
end

-- ============================================================
-- NOCLIP
-- ============================================================
local NoclipManager = { _refCount=0, _active=false, _saved={}, _conns={} }
function NoclipManager:_applyToChar(char, restore)
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            if restore then
                local s = self._saved[d]
                if s then
                    d.CanCollide = s.collide
                    d.Massless   = s.massless
                    self._saved[d] = nil
                end
            else
                if self._saved[d] == nil then
                    self._saved[d] = { collide=d.CanCollide, massless=d.Massless }
                end
                d.CanCollide = false; d.Massless = true
            end
        end
    end
end
function NoclipManager:_start()
    if self._active then return end
    self._active = true
    self:_applyToChar(getCharacter(), false)
    table.insert(self._conns, RunService.Heartbeat:Connect(function()
        if not self._active then return end
        local char = getCharacter(); if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and (d.CanCollide or not d.Massless) then
                if self._saved[d] == nil then
                    self._saved[d] = { collide=d.CanCollide, massless=d.Massless }
                end
                d.CanCollide = false; d.Massless = true
            end
        end
    end))
    table.insert(self._conns, LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.1)
        if self._active then self:_applyToChar(char, false) end
    end))
end
function NoclipManager:_stop()
    if not self._active then return end
    self._active = false
    self:_applyToChar(getCharacter(), true)
    for _, c in ipairs(self._conns) do c:Disconnect() end
    self._conns = {}; self._saved = {}
end
function NoclipManager:acquire()
    self._refCount += 1
    if self._refCount == 1 then self:_start() end
end
function NoclipManager:release()
    self._refCount = math.max(0, self._refCount-1)
    if self._refCount == 0 then self:_stop() end
end

-- ============================================================
-- BẢO VỆ CHUNG
-- ============================================================
local PROTECT_KEYWORDS = {
    "rương","ruong","chest","treasure","fruit","devil",
    "loot","drop","item","spawn","baseplate",
}
local function isProtectedFromFixLag(inst)
    if not inst or not inst.Parent then return true end
    if inst.Name == "UtilityESP" then return true end
    local myChar = LocalPlayer.Character
    if myChar and (inst == myChar or inst:IsDescendantOf(myChar)) then return true end
    if ItemFinder then
        if ItemFinder.espObjects and ItemFinder.espObjects[inst] then return true end
        local parent = inst.Parent
        for _ = 1, 3 do
            if not parent then break end
            if ItemFinder.espObjects and ItemFinder.espObjects[parent] then return true end
            if ItemFinder.Discovered and ItemFinder.Discovered[parent] then return true end
            parent = parent.Parent
        end
    end
    local n = string.lower(inst.Name)
    for _, k in ipairs(PROTECT_KEYWORDS) do
        if n:find(k, 1, true) then return true end
    end
    if inst:FindFirstChildWhichIsA("ProximityPrompt", false) then return true end
    if inst:FindFirstChildWhichIsA("ClickDetector", false) then return true end
    return false
end

-- ============================================================
-- FIX LAG (SIÊU MẠNH) — kiểu CHẾ ĐỘ NHANH
--  - Bề mặt công trình: SmoothPlastic phẳng, GIỮ màu gốc, xoá mọi texture
--    (Decal/Texture/SurfaceAppearance/MaterialVariant/MeshPart.TextureID/
--    SpecialMesh.TextureId/quần áo), không bóng đổ, không phản chiếu
--  - Xoá bầu trời: ẩn Sky/Clouds/Atmosphere, thay bằng Sky trống
--  - Xoá MỌI hiệu ứng: particle (kể cả hiệu ứng skill bắn bằng :Emit),
--    trail/beam/smoke/fire/sparkles/explosion, đèn, post-effect, highlight,
--    selection, billboard/surfacegui, part hiệu ứng Neon/ForceField
--  - Tắt bóng + ánh sáng môi trường, hạ chất lượng đồ hoạ, nước phẳng
--  - Lọc theo ClassName, quét lại theo lô, dọn instance đã bị huỷ
-- ============================================================
local SKY_BLUE = Color3.fromRGB(70, 130, 180)
local FIXLAG_BATCH  = 1500 -- số instance xử lý mỗi frame khi quét
local FIXLAG_RESCAN = 5    -- giây nghỉ giữa 2 lượt quét lại

-- Gỡ khỏi cây (trả lại khi tắt)
local FIXLAG_HIDE = {
    Sky = true, Clouds = true, Atmosphere = true,
    SurfaceAppearance = true, MaterialVariant = true,
}
local OFF = { Enabled = false }
-- ClassName -> { thuộc tính = giá trị }
local FIXLAG_RULES = {
    -- Lifetime 0 + trong suốt: chặn cả hạt bắn bằng :Emit() (Enabled=false không chặn được)
    ParticleEmitter = { Enabled = false, Lifetime = NumberRange.new(0),
        Transparency = NumberSequence.new(1) },
    Trail = OFF, Beam = OFF, Smoke = OFF, Fire = OFF, Sparkles = OFF,
    PointLight = OFF, SpotLight = OFF, SurfaceLight = OFF,
    BloomEffect = OFF, BlurEffect = OFF, SunRaysEffect = OFF,
    ColorCorrectionEffect = OFF, DepthOfFieldEffect = OFF,
    Highlight = OFF, BillboardGui = OFF, SurfaceGui = OFF,
    Explosion = { Visible = false },
    SelectionBox = { Visible = false }, SelectionSphere = { Visible = false },
    Decal = { Transparency = 1 }, Texture = { Transparency = 1 },
    SpecialMesh = { TextureId = "" },
    Shirt = { ShirtTemplate = "" }, Pants = { PantsTemplate = "" },
    ShirtGraphic = { Graphic = "" },
    Sound = { Volume = 0 },
    Humanoid = { DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None },
}
-- Part không va chạm làm bằng các vật liệu này gần như luôn là hiệu ứng
local FIXLAG_VFX_MATERIAL = {
    [Enum.Material.Neon] = true, [Enum.Material.ForceField] = true,
}
local FIXLAG_LIGHTING = {
    FogColor = SKY_BLUE, FogStart = 5000, FogEnd = 8000,
    GlobalShadows = false, ShadowSoftness = 0,
    EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0,
    Brightness = 2, ClockTime = 14, GeographicLatitude = 0,
    ExposureCompensation = 0,
}
local FIXLAG_TERRAIN = {
    WaterColor = SKY_BLUE, WaterWaveSize = 0, WaterTransparency = 0,
    WaterReflectance = 0, Decoration = false,
}

local FixLag = { enabled=false, gen=0, saved={}, env={}, hidden={}, conns={}, blankSky=nil }

local function getProp(inst, prop) return inst[prop] end
local function setProp(inst, prop, val) inst[prop] = val end
-- Executor: thuộc tính bị khoá (Technology, QualityLevel...) đi qua get/sethiddenproperty
local function tryGet(inst, prop)
    local ok, val = pcall(getProp, inst, prop)
    if not ok and gethiddenproperty then ok, val = pcall(gethiddenproperty, inst, prop) end
    return ok, val
end
local function trySet(inst, prop, val)
    if not pcall(setProp, inst, prop, val) and sethiddenproperty then
        pcall(sethiddenproperty, inst, prop, val)
    end
end
local function remember(store, inst, prop, newVal)
    local ok, cur = tryGet(inst, prop)
    if not ok or cur == newVal then return end
    local e = store[inst]
    if not e then e = {}; store[inst] = e end
    if e[prop] == nil then e[prop] = cur end
    trySet(inst, prop, newVal)
end
local function restoreStore(store)
    for inst, props in pairs(store) do
        for prop, val in pairs(props) do trySet(inst, prop, val) end
    end
end
local function makeBlankSky()
    local sky = Instance.new("Sky")
    sky.Name = "FixLagSky"
    for _, face in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
        sky["Skybox" .. face] = ""
    end
    sky.SunTextureId = ""; sky.MoonTextureId = ""
    sky.CelestialBodiesShown = false; sky.StarCount = 0
    return sky
end

function FixLag:_hide(inst)
    if self.hidden[inst] then return end
    local parent = inst.Parent
    if pcall(setProp, inst, "Parent", nil) then self.hidden[inst] = parent end
end
function FixLag:_simplifyPart(part)
    local e = self.saved[part]
    local mat = (e and e.Material) or part.Material
    if FIXLAG_VFX_MATERIAL[mat] and not part.CanCollide then
        remember(self.saved, part, "LocalTransparencyModifier", 1)
    end
    remember(self.saved, part, "Material", Enum.Material.SmoothPlastic)
    remember(self.saved, part, "MaterialVariant", "")
    remember(self.saved, part, "CastShadow", false)
    remember(self.saved, part, "Reflectance", 0)
    if part:IsA("MeshPart") then remember(self.saved, part, "TextureID", "") end
end
function FixLag:_process(inst)
    local cls = inst.ClassName
    local rule = FIXLAG_RULES[cls]
    local isPart = not rule and cls ~= "Terrain" and inst:IsA("BasePart")
    if not (rule or isPart or FIXLAG_HIDE[cls] or cls == "Accessory"
        or cls == "Hat" or cls == "AnimationController") then return end
    if inst == self.blankSky or isProtectedFromFixLag(inst) then return end
    if isPart then
        self:_simplifyPart(inst)
    elseif rule then
        for prop, val in pairs(rule) do remember(self.saved, inst, prop, val) end
        if cls == "ParticleEmitter" or cls == "Trail" then pcall(inst.Clear, inst) end
    elseif FIXLAG_HIDE[cls] then
        self:_hide(inst)
    elseif cls == "AnimationController" then
        local animator = inst:FindFirstChildOfClass("Animator")
        if animator then
            for _, a in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function() a:Stop(0) end)
            end
        end
    else
        local h = inst:FindFirstChild("Handle")
        if h then remember(self.saved, h, "Transparency", 1) end
    end
end
function FixLag:_applyTo(container)
    for _, d in ipairs(container:GetDescendants()) do
        self:_process(d)
    end
end
-- Bỏ instance đã bị game huỷ (hiệu ứng skill...) để bộ nhớ không phình
function FixLag:_prune()
    for inst in pairs(self.saved) do
        if inst.Parent == nil then self.saved[inst] = nil end
    end
    for inst, parent in pairs(self.hidden) do
        if parent.Parent == nil then self.hidden[inst] = nil end
    end
end
function FixLag:_rescanLoop(gen)
    while self.enabled and self.gen == gen do
        for i, d in ipairs(workspace:GetDescendants()) do
            if not self.enabled or self.gen ~= gen then return end
            self:_process(d)
            if i % FIXLAG_BATCH == 0 then task.wait() end
        end
        self:_prune()
        task.wait(FIXLAG_RESCAN)
    end
end
function FixLag:start()
    if self.enabled then return end
    self.enabled = true
    self.gen += 1
    self.saved = {}; self.env = {}; self.hidden = {}
    self:_applyTo(Lighting)
    self:_applyTo(MaterialService)
    self.blankSky = makeBlankSky()
    self.blankSky.Parent = Lighting
    for k, v in pairs(FIXLAG_LIGHTING) do remember(self.env, Lighting, k, v) end
    for k, v in pairs(FIXLAG_TERRAIN) do remember(self.env, workspace.Terrain, k, v) end
    pcall(function()
        remember(self.env, Lighting, "Technology", Enum.Technology.Compatibility)
    end)
    pcall(function()
        remember(self.env, UserSettings():GetService("UserGameSettings"),
            "SavedQualityLevel", Enum.SavedQualitySetting.QualityLevel1)
    end)
    pcall(function()
        remember(self.env, settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01)
    end)
    table.insert(self.conns, workspace.DescendantAdded:Connect(function(d)
        if self.enabled then self:_process(d) end
    end))
    table.insert(self.conns, Lighting.DescendantAdded:Connect(function(d)
        if self.enabled then self:_process(d) end
    end))
    task.spawn(self._rescanLoop, self, self.gen)
end
function FixLag:stop()
    if not self.enabled then return end
    self.enabled = false
    for _, c in ipairs(self.conns) do c:Disconnect() end
    self.conns = {}
    restoreStore(self.saved); restoreStore(self.env)
    self.saved = {}; self.env = {}
    if self.blankSky then self.blankSky:Destroy(); self.blankSky = nil end
    for inst, parent in pairs(self.hidden) do pcall(setProp, inst, "Parent", parent) end
    self.hidden = {}
end

-- ============================================================
-- FULL BRIGHT
-- ============================================================
local FullBright = { enabled=false, originals=nil, conn=nil }
local FB_VALUES = {
    Brightness = 2, Ambient = Color3.fromRGB(180,180,180),
    OutdoorAmbient = Color3.fromRGB(180,180,180),
    ExposureCompensation = 0.2, GlobalShadows = false,
    EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.6,
}
function FullBright:start()
    if self.enabled then return end
    self.enabled = true
    self.originals = {}
    for k in pairs(FB_VALUES) do self.originals[k] = Lighting[k] end
    for k, v in pairs(FB_VALUES) do pcall(function() Lighting[k] = v end) end
    self.conn = Lighting:GetPropertyChangedSignal("Brightness"):Connect(function()
        if self.enabled and Lighting.Brightness ~= FB_VALUES.Brightness then
            Lighting.Brightness = FB_VALUES.Brightness
        end
    end)
end
function FullBright:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.conn then self.conn:Disconnect(); self.conn = nil end
    if self.originals then
        for k, v in pairs(self.originals) do pcall(function() Lighting[k] = v end) end
        self.originals = nil
    end
end

-- ============================================================
-- SPEED WALK
-- ============================================================
local SpeedWalk = { enabled=false, value=CONFIG.WalkSpeed.Default, original=nil, conns={}, propConn=nil }
local function speedHook(hum)
    if SpeedWalk.propConn then SpeedWalk.propConn:Disconnect() end
    SpeedWalk.propConn = nil
    if not hum then return end
    SpeedWalk.propConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if SpeedWalk.enabled and hum.WalkSpeed ~= SpeedWalk.value then
            hum.WalkSpeed = SpeedWalk.value
        end
    end)
end
function SpeedWalk:start()
    if self.enabled then return end
    self.enabled = true
    local h = getHumanoid()
    if h then
        self.original = h.WalkSpeed
        h.WalkSpeed = self.value
        speedHook(h)
    end
    table.insert(self.conns, RunService.PreSimulation:Connect(function()
        if not self.enabled then return end
        local hum = getHumanoid()
        if not hum or hum.Health <= 0 then return end
        if hum.WalkSpeed ~= self.value then hum.WalkSpeed = self.value end
    end))
    table.insert(self.conns, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.2)
        if not self.enabled then return end
        local hum = getHumanoid()
        if hum then
            if self.original == nil then self.original = hum.WalkSpeed end
            hum.WalkSpeed = self.value
            speedHook(hum)
        end
    end))
end
function SpeedWalk:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.propConn then self.propConn:Disconnect(); self.propConn = nil end
    for _, c in ipairs(self.conns) do c:Disconnect() end
    self.conns = {}
    local hum = getHumanoid()
    if hum then hum.WalkSpeed = self.original or CONFIG.WalkSpeed.Default end
    self.original = nil
end
function SpeedWalk:set(v)
    self.value = clamp(tonumber(v) or self.value, CONFIG.WalkSpeed.Min, CONFIG.WalkSpeed.Max)
    if self.enabled then
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = self.value end
    end
end

-- ============================================================
-- HIGH JUMP
-- ============================================================
local HighJump = { enabled=false, value=CONFIG.Jump.Default, mode="JumpPower", original=nil, conn=nil, heartbeat=nil }
local function detectJumpMode(h)
    if not h then return "JumpPower" end
    return h.UseJumpPower and "JumpPower" or "JumpHeight"
end
local function applyJump()
    local h = getHumanoid(); if not h then return end
    if HighJump.mode == "JumpPower" then
        h.UseJumpPower = true; h.JumpPower = HighJump.value
    else
        h.UseJumpPower = false; h.JumpHeight = HighJump.value
    end
end
function HighJump:start()
    if self.enabled then return end
    self.enabled = true
    local h = getHumanoid()
    if h then
        self.mode = detectJumpMode(h)
        self.original = (self.mode == "JumpPower") and h.JumpPower or h.JumpHeight
    end
    applyJump()
    self.heartbeat = RunService.PreSimulation:Connect(function()
        if not self.enabled then return end
        local hum = getHumanoid()
        if not hum or hum.Health <= 0 then return end
        if self.mode == "JumpPower" then
            hum.UseJumpPower = true; hum.JumpPower = self.value
        else
            hum.UseJumpPower = false; hum.JumpHeight = self.value
        end
    end)
    self.conn = LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.2)
        if not self.enabled then return end
        local hum = getHumanoid()
        if hum then
            self.mode = detectJumpMode(hum)
            if self.original == nil then
                self.original = (self.mode=="JumpPower") and hum.JumpPower or hum.JumpHeight
            end
            applyJump()
        end
    end)
end
function HighJump:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.heartbeat then self.heartbeat:Disconnect(); self.heartbeat = nil end
    if self.conn then self.conn:Disconnect(); self.conn = nil end
    local hum = getHumanoid()
    if hum then
        local o = self.original or CONFIG.Jump.Default
        if self.mode == "JumpPower" then hum.UseJumpPower=true; hum.JumpPower=o
        else hum.UseJumpPower=false; hum.JumpHeight=o end
    end
    self.original = nil
end
function HighJump:set(v)
    self.value = clamp(tonumber(v) or self.value, CONFIG.Jump.Min, CONFIG.Jump.Max)
    if self.enabled then applyJump() end
end

-- ============================================================
-- ATTACK
-- ============================================================
local AttackState = {
    cooldown = 0.15, maxDistance = CONFIG.AttackDistance,
    settleTime = CONFIG.AttackSettle, lastAttackAt = 0, debug = false,
}
local function attackTarget(target)
    if not target or not target.Parent then return false end
    local hrp = getHRP(); if not hrp then return false end
    local enemyRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if not enemyRoot then return false end
    local dist = (hrp.Position - enemyRoot.Position).Magnitude
    if dist > AttackState.maxDistance then return false end
    local now = os.clock()
    if now - AttackState.lastAttackAt < AttackState.cooldown then return false end
    AttackState.lastAttackAt = now
    if AttackState.debug then
        print(string.format("[Attack] HIT %s — dist=%.1f", target.Name, dist))
    end
    return true
end

-- ============================================================
-- ITEM FINDER
-- ============================================================
ItemFinder = {
    enabled = false, espEnabled = false,
    Discovered = {}, espObjects = {},
    scanConn = nil, removeConn = nil, Blacklist = {},
    KEYWORDS = { "chest", "fruit", "devil", "treasure", "loot", "rương", "ruong" },
    IGNORE = {
        "door","gate","shop","sign","teleport","elevator","button",
        "lever","npc","dialog","bank","atm","vehicle","baseplate",
        "spawnlocation","camera","light","humanoid","head","torso",
        "effect","sound","guiparent","hint","label","frame","ui",
        "gui","text","mesh","union","tool","weapon","sword",
    },
}
local function _l(s) return string.lower(s) end
local function _kw(name, list)
    local n = _l(name)
    for _, k in ipairs(list) do
        if n:find(k, 1, true) then return true end
    end
    return false
end
local function isPlayerModel(inst)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == inst then return true end
    end
    return false
end
function ItemFinder:isCollectible(inst)
    if not inst or not inst.Parent then return false, nil end
    if isPlayerModel(inst) then return false, nil end
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false, nil end
    if _kw(inst.Name, self.IGNORE) then return false, nil end
    local hasPrompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    local hasClick  = inst:FindFirstChildWhichIsA("ClickDetector", true)
    if hasPrompt then return true, "prompt" end
    if hasClick  then return true, "click" end
    if _kw(inst.Name, self.KEYWORDS) then return true, "name" end
    return false, nil
end
function ItemFinder:isBlacklisted(inst)
    local exp = self.Blacklist[inst]
    if not exp then return false end
    if os.clock() > exp then self.Blacklist[inst] = nil; return false end
    return true
end
function ItemFinder:addBlacklist(inst, seconds)
    self.Blacklist[inst] = os.clock() + (seconds or 8)
end
function ItemFinder:addESP(inst)
    if self.espObjects[inst] then return end
    local base = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart")
    if not base then return end
    local hl = Instance.new("Highlight")
    hl.Name = "ItemESP"
    hl.FillColor = CONFIG.ItemESP.FillColor
    hl.OutlineColor = CONFIG.ItemESP.OutlineColor
    hl.FillTransparency = 0.6; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = inst; hl.Parent = inst
    local bb = Instance.new("BillboardGui")
    bb.Name = "ItemESP"; bb.Size = UDim2.new(0, 130, 0, 32)
    bb.StudsOffset = Vector3.new(0, 2.5, 0); bb.AlwaysOnTop = true
    bb.Adornee = base; bb.Parent = base
    local bg = Instance.new("Frame")
    bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bg.BackgroundTransparency = 0.35
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BorderSizePixel = 0; bg.Parent = bb
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 5); bc.Parent = bg
    local nameL = Instance.new("TextLabel")
    nameL.BackgroundTransparency = 1
    nameL.Size = UDim2.new(1, -8, 0, 16)
    nameL.Position = UDim2.new(0, 4, 0, 1)
    nameL.Font = Enum.Font.GothamBold; nameL.TextSize = 11
    nameL.TextColor3 = Color3.fromRGB(255, 220, 100)
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Text = normalizeName(inst.Name); nameL.Parent = bg
    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency = 1
    distL.Size = UDim2.new(1, -8, 0, 12)
    distL.Position = UDim2.new(0, 4, 0, 17)
    distL.Font = Enum.Font.Gotham; distL.TextSize = 10
    distL.TextColor3 = Color3.fromRGB(220, 220, 220)
    distL.TextXAlignment = Enum.TextXAlignment.Left
    distL.Text = "..."; distL.Parent = bg
    self.espObjects[inst] = { hl = hl, bb = bb, distL = distL }
end
function ItemFinder:removeESP(inst)
    local e = self.espObjects[inst]
    if not e then return end
    if e.hl then e.hl:Destroy() end
    if e.bb then e.bb:Destroy() end
    self.espObjects[inst] = nil
end
function ItemFinder:register(inst, kind)
    if self.Discovered[inst] then return end
    self.Discovered[inst] = { key = normalizeName(inst.Name), kind = kind }
    if self.espEnabled then self:addESP(inst) end
end
function ItemFinder:unregister(inst)
    self.Discovered[inst] = nil
    self:removeESP(inst)
end
function ItemFinder:scanNode(inst)
    local ok, kind = self:isCollectible(inst)
    if ok then self:register(inst, kind) end
end
function ItemFinder:scanAll()
    for _, d in ipairs(workspace:GetDescendants()) do
        self:scanNode(d)
    end
end
function ItemFinder:start()
    if self.enabled then return end
    self.enabled = true
    self:scanAll()
    self.scanConn = workspace.DescendantAdded:Connect(function(d)
        if not self.enabled then return end
        task.defer(function()
            if d and d.Parent then self:scanNode(d) end
        end)
    end)
    self.removeConn = workspace.DescendantRemoving:Connect(function(d)
        if self.Discovered[d] then self:unregister(d) end
    end)
end
function ItemFinder:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.scanConn then self.scanConn:Disconnect(); self.scanConn = nil end
    if self.removeConn then self.removeConn:Disconnect(); self.removeConn = nil end
    for inst in pairs(self.Discovered) do self:unregister(inst) end
    self.Discovered = {}; self.Blacklist = {}
end
function ItemFinder:setESP(on)
    self.espEnabled = on
    for inst in pairs(self.Discovered) do
        if on then self:addESP(inst) else self:removeESP(inst) end
    end
end
function ItemFinder:getPosition(inst)
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        local r = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
        return r and r.Position or nil
    end
    return nil
end
function ItemFinder:collect(inst)
    if not inst or not inst.Parent then return false end
    local p = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    if p then
        pcall(function()
            p.MaxActivationDistance = math.huge
            p.RequiresLineOfSight = false
            p.Enabled = true
        end)
        pcall(function()
            p:InputHoldBegin()
            local holdDur = p.HoldDuration or 0.2
            task.delay(holdDur + 0.15, function()
                pcall(function() p:InputHoldEnd() end)
            end)
        end)
        return true
    end
    local cd = inst:FindFirstChildWhichIsA("ClickDetector", true)
    if cd then
        pcall(function()
            cd.MaxActivationDistance = math.huge
            cd:Click(LocalPlayer)
        end)
        pcall(function()
            if fireclickdetector then fireclickdetector(cd) end
        end)
        return true
    end
    if inst:IsA("BasePart") or inst:FindFirstChildWhichIsA("BasePart") then
        return true
    end
    return false
end
function ItemFinder:updateDistanceLabels()
    if not self.espEnabled then return end
    local myHrp = getHRP(); if not myHrp then return end
    for inst, e in pairs(self.espObjects) do
        if e.distL and inst.Parent then
            local pos = self:getPosition(inst)
            if pos then
                e.distL.Text = string.format("%d studs",
                    math.floor((pos - myHrp.Position).Magnitude))
            end
        end
    end
end

-- ============================================================
-- AUTO FARM
-- ============================================================
local AutoFarm = {
    enabled=false, selectedType=nil, target=nil, conn=nil,
    noclipHeld=false, status="Tắt",
    findCache=nil, findTimer=0, savedState=nil,
    height = CONFIG.FarmHeight.Default,
    distance = CONFIG.FarmDistance.Default,
    settleStart = nil, targetChanged = nil,
}
local MOVER_NAMES = {
    "AutoFarmAlignPos","AutoFarmAlignOri",
    "AutoFarmHover","AutoFarmGyro","AutoFarmRootAtt",
}
local function destroyMovers(hrp)
    if not hrp then return end
    for _, n in ipairs(MOVER_NAMES) do
        local m = hrp:FindFirstChild(n)
        if m then m:Destroy() end
    end
end
local function getAllEnemies()
    local list = {}
    for _, inst in ipairs(CollectionService:GetTagged(CONFIG.EnemyTag)) do
        if inst:IsA("Model") then table.insert(list, inst)
        elseif inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Model") then
            table.insert(list, inst.Parent) end
    end
    if #list == 0 then
        local folder = workspace:FindFirstChild(CONFIG.FallbackEnemyFolder)
        if folder then
            for _, inst in ipairs(folder:GetChildren()) do
                if inst:IsA("Model") then table.insert(list, inst) end
            end
        end
    end
    return list
end
local function getEnemyTypes()
    local set = {}
    for _, m in ipairs(getAllEnemies()) do set[normalizeName(m.Name)] = true end
    local arr = {}
    for k in pairs(set) do table.insert(arr, k) end
    table.sort(arr); return arr
end
local function isEnemyAlive(m)
    if not m or not m.Parent then return false end
    local h = m:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end
local function findNearestEnemy(typeName)
    local hrp = getHRP(); if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, m in ipairs(getAllEnemies()) do
        if isEnemyAlive(m) and normalizeName(m.Name) == typeName then
            local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if root then
                local d = (root.Position - hrp.Position).Magnitude
                if d < bestDist then
                    bestDist = d; best = { model=m, root=root }
                end
            end
        end
    end
    return best
end
local function autoFarmSetup()
    local hum = getHumanoid(); local hrp = getHRP()
    if not hum or not hrp then return end
    AutoFarm.savedState = {
        anchored = hrp.Anchored, platformStand = hum.PlatformStand,
        autoRotate = hum.AutoRotate, walkSpeed = hum.WalkSpeed,
        jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight,
        useJumpPower = hum.UseJumpPower,
    }
    destroyMovers(hrp)
    local mode = CONFIG.MoveMode
    if mode == "Anchored" then
        hrp.Anchored = true; hum.PlatformStand = true; hum.AutoRotate = false
        hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
    elseif mode == "Align" then
        hrp.Anchored = false; hum.PlatformStand = true; hum.AutoRotate = false
        hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
        local att = hrp:FindFirstChild("AutoFarmRootAtt")
        if not att then
            att = Instance.new("Attachment"); att.Name = "AutoFarmRootAtt"; att.Parent = hrp
        end
        local ap = Instance.new("AlignPosition")
        ap.Name = "AutoFarmAlignPos"
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment
        ap.Attachment0 = att; ap.MaxForce = 1e6; ap.MaxVelocity = math.huge
        ap.Responsiveness = 25; ap.Position = hrp.Position
        ap.ApplyAtCenterOfMass = false; ap.Parent = hrp
        local ao = Instance.new("AlignOrientation")
        ao.Name = "AutoFarmAlignOri"
        ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
        ao.Attachment0 = att; ao.MaxTorque = 1e6; ao.MaxAngularVelocity = math.huge
        ao.Responsiveness = 25; ao.CFrame = hrp.CFrame; ao.Parent = hrp
    elseif mode == "Ground" then
        hrp.Anchored = false; hum.PlatformStand = false; hum.AutoRotate = true
        hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
    end
end
local function autoFarmRestore()
    local s = AutoFarm.savedState
    if not s then return end
    local hum = getHumanoid(); local hrp = getHRP()
    if hrp then destroyMovers(hrp); hrp.Anchored = s.anchored end
    if hum then
        hum.PlatformStand = s.platformStand; hum.AutoRotate = s.autoRotate
        hum.WalkSpeed = s.walkSpeed; hum.JumpPower = s.jumpPower
        hum.JumpHeight = s.jumpHeight; hum.UseJumpPower = s.useJumpPower
    end
    AutoFarm.savedState = nil
end
local function autoFarmMove(dt, hrp, enemyPos)
    local mode = CONFIG.MoveMode
    if mode == "Align" then
        local ap = hrp:FindFirstChild("AutoFarmAlignPos")
        local ao = hrp:FindFirstChild("AutoFarmAlignOri")
        local standPos = enemyPos + Vector3.new(0, AutoFarm.height, 0)
        if ap then ap.Position = standPos end
        if ao then ao.CFrame = CFrame.lookAt(standPos, enemyPos) end
    elseif mode == "Ground" then
        local currentPos = hrp.Position
        local dirXZ = Vector3.new(currentPos.X - enemyPos.X, 0, currentPos.Z - enemyPos.Z)
        if dirXZ.Magnitude < 0.01 then dirXZ = Vector3.new(0,0,-1) end
        local goalPos = enemyPos + dirXZ.Unit * AutoFarm.distance
        goalPos = Vector3.new(goalPos.X, currentPos.Y, goalPos.Z)
        local delta = goalPos - currentPos
        if delta.Magnitude > 0.3 then
            hrp.CFrame = CFrame.lookAt(currentPos + delta * math.min(1, dt*14), enemyPos)
        else
            hrp.CFrame = CFrame.lookAt(currentPos, enemyPos)
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
    else
        local currentPos = hrp.Position
        local standPos = enemyPos + Vector3.new(0, AutoFarm.height, 0)
        local dist = (standPos - currentPos).Magnitude
        local newPos
        if dist > 0.3 then
            newPos = currentPos:Lerp(standPos, math.min(1, dt * 14))
        else newPos = standPos end
        hrp.CFrame = CFrame.lookAt(newPos, enemyPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end
local function autoFarmStep(dt)
    if not AutoFarm.enabled then return end
    if not isAlive() then return end
    if not AutoFarm.selectedType then AutoFarm.status = "Chưa chọn quái"; return end
    local hrp = getHRP(); if not hrp then return end
    AutoFarm.findTimer += dt
    if not AutoFarm.findCache or AutoFarm.findTimer > CONFIG.RetargetInterval then
        AutoFarm.findCache = findNearestEnemy(AutoFarm.selectedType)
        AutoFarm.findTimer = 0
    end
    local found = AutoFarm.findCache
    if not found or not isEnemyAlive(found.model) then
        AutoFarm.target = nil; AutoFarm.findCache = nil
        AutoFarm.settleStart = nil; AutoFarm.targetChanged = nil
        AutoFarm.status = "Chờ quái"; return
    end
    AutoFarm.target = found.model
    local enemyPos = found.root.Position
    autoFarmMove(dt, hrp, enemyPos)
    if AutoFarm.targetChanged ~= found.model then
        AutoFarm.targetChanged = found.model
        AutoFarm.settleStart   = os.clock()
    end
    local settleElapsed = os.clock() - (AutoFarm.settleStart or 0)
    local settled = settleElapsed >= AttackState.settleTime
    local realDist = (hrp.Position - enemyPos).Magnitude
    if settled then
        if attackTarget(found.model) then
            AutoFarm.status = string.format("Đánh %s", found.model.Name)
        else
            AutoFarm.status = string.format("Chờ (%.1f)", realDist)
        end
    else
        AutoFarm.status = string.format("Ổn định %.1fs", settleElapsed)
    end
end
function AutoFarm:start()
    if self.enabled then return end
    self.enabled = true
    self.findTimer = 0; self.findCache = nil
    self.settleStart = nil; self.targetChanged = nil
    if not self.noclipHeld then NoclipManager:acquire(); self.noclipHeld = true end
    autoFarmSetup()
    self.conn = RunService.RenderStepped:Connect(function(dt) autoFarmStep(dt) end)
    self._respawnConns = self._respawnConns or {}
    table.insert(self._respawnConns, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.3)
        if self.enabled then
            autoFarmSetup(); self.settleStart = nil; self.targetChanged = nil
        end
    end))
end
function AutoFarm:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.conn then self.conn:Disconnect(); self.conn = nil end
    if self._respawnConns then
        for _, c in ipairs(self._respawnConns) do c:Disconnect() end
        self._respawnConns = nil
    end
    self.settleStart = nil; self.targetChanged = nil
    autoFarmRestore()
    self.target = nil; self.findCache = nil; self.status = "Tắt"
    if self.noclipHeld then NoclipManager:release(); self.noclipHeld = false end
end
function AutoFarm:setHeight(v)
    self.height = clamp(tonumber(v) or self.height, CONFIG.FarmHeight.Min, CONFIG.FarmHeight.Max)
end
function AutoFarm:setDistance(v)
    self.distance = clamp(tonumber(v) or self.distance, CONFIG.FarmDistance.Min, CONFIG.FarmDistance.Max)
end
function AutoFarm:restartMover()
    if not self.enabled then return end
    autoFarmRestore(); autoFarmSetup()
    self.settleStart = nil; self.targetChanged = nil
end

-- ============================================================
-- AUTO LOOT v6 — Sweep bounds cố định
-- ============================================================
local AutoLoot = {
    enabled=false, target=nil, conn=nil,
    noclipHeld=false, status="Tắt",
    findCache=nil, findTimer=0, savedState=nil,
    failCount = 0, lastAttempt = 0,
    arrivedAt = nil, lastTarget = nil,
    sweepQueue = nil, sweepIdx = 0, sweepWaitUntil = 0,
    lastChestFoundAt = 0,
    SWEEP_BOUNDS = 5000,
    SWEEP_CELL = 500,
    SWEEP_PAUSE = 0.45,
    SWEEP_Y = 120,
    SWEEP_COOLDOWN = 1.5,
    SWEEP_MAX_WP = 600,
}
local function buildSweepQueue()
    local hrp = getHRP()
    local px, pz = 0, 0
    if hrp then px, pz = hrp.Position.X, hrp.Position.Z end
    local B = AutoLoot.SWEEP_BOUNDS
    local minX, maxX = px - B, px + B
    local minZ, maxZ = pz - B, pz + B
    local queue = {}
    local cell = AutoLoot.SWEEP_CELL
    local y = AutoLoot.SWEEP_Y
    for x = minX, maxX, cell do
        for z = minZ, maxZ, cell do
            table.insert(queue, Vector3.new(x, y, z))
        end
    end
    table.sort(queue, function(a, b)
        local da = (a.X - px)^2 + (a.Z - pz)^2
        local db = (b.X - px)^2 + (b.Z - pz)^2
        return da < db
    end)
    if #queue > AutoLoot.SWEEP_MAX_WP then
        local trimmed = {}
        for i = 1, AutoLoot.SWEEP_MAX_WP do trimmed[i] = queue[i] end
        queue = trimmed
    end
    print(string.format("[Sweep] Bounds %d studs, cell %d → %d waypoint",
        B*2, cell, #queue))
    return queue
end
local function findAllLoot()
    local list = {}
    for inst in pairs(ItemFinder.Discovered) do
        if inst.Parent
           and not ItemFinder:isBlacklisted(inst)
           and nameMatchesLootFilter(inst.Name) then
            table.insert(list, inst)
        end
    end
    return list
end
local function findNearestLoot()
    local hrp = getHRP(); if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, inst in ipairs(findAllLoot()) do
        local pos = ItemFinder:getPosition(inst)
        if pos then
            local d = (pos - hrp.Position).Magnitude
            if d < bestDist then
                bestDist = d; best = { inst = inst, pos = pos }
            end
        end
    end
    return best
end
local function autoLootSetup()
    local hum = getHumanoid(); local hrp = getHRP()
    if not hum or not hrp then return end
    AutoLoot.savedState = {
        anchored=hrp.Anchored, platformStand=hum.PlatformStand,
        autoRotate=hum.AutoRotate, walkSpeed=hum.WalkSpeed,
        jumpPower=hum.JumpPower, jumpHeight=hum.JumpHeight,
        useJumpPower=hum.UseJumpPower,
    }
    hrp.Anchored = false
    hum.PlatformStand = true
    hum.AutoRotate = false
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    hum.JumpHeight = 0
end
local function autoLootRestore()
    local s = AutoLoot.savedState
    if not s then return end
    local hum = getHumanoid(); local hrp = getHRP()
    if hrp then hrp.Anchored = s.anchored end
    if hum then
        hum.PlatformStand = s.platformStand
        hum.AutoRotate    = s.autoRotate
        hum.WalkSpeed     = s.walkSpeed
        hum.JumpPower     = s.jumpPower or hum.JumpPower
        hum.JumpHeight    = s.jumpHeight or hum.JumpHeight
        hum.UseJumpPower  = s.useJumpPower
    end
    AutoLoot.savedState = nil
end
local function moveToLoot(hrp, itemPos, dt)
    local currentPos = hrp.Position
    local dist = (itemPos - currentPos).Magnitude
    local dirXZ = Vector3.new(currentPos.X - itemPos.X, 0, currentPos.Z - itemPos.Z)
    if dirXZ.Magnitude < 0.01 then dirXZ = Vector3.new(0, 0, -1) end
    local standPos = itemPos + dirXZ.Unit * CONFIG.StopDistanceLoot
    if dist > CONFIG.TeleportThreshold then
        hrp.CFrame = CFrame.lookAt(standPos, itemPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    else
        local alpha = math.min(1, dt * 10)
        local newPos = currentPos:Lerp(standPos, alpha)
        hrp.CFrame = CFrame.lookAt(newPos, itemPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    return dist
end
local function doSweep(hrp)
    local now = os.clock()
    if not AutoLoot.sweepQueue or #AutoLoot.sweepQueue == 0 then
        AutoLoot.sweepQueue = buildSweepQueue()
        AutoLoot.sweepIdx = 1
        AutoLoot.sweepWaitUntil = 0
        if #AutoLoot.sweepQueue == 0 then
            AutoLoot.status = "Sweep queue rỗng"
            return
        end
    end
    if AutoLoot.sweepIdx > #AutoLoot.sweepQueue then
        AutoLoot.sweepIdx = 1
    end
    if now < AutoLoot.sweepWaitUntil then
        AutoLoot.status = string.format("Chờ load %d/%d",
            AutoLoot.sweepIdx, #AutoLoot.sweepQueue)
        return
    end
    local wp = AutoLoot.sweepQueue[AutoLoot.sweepIdx]
    hrp.CFrame = CFrame.new(wp)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    AutoLoot.sweepIdx += 1
    AutoLoot.sweepWaitUntil = now + AutoLoot.SWEEP_PAUSE
    task.defer(function()
        if not AutoLoot.enabled then return end
        ItemFinder:scanAll()
        AutoLoot.findCache = nil
    end)
    AutoLoot.status = string.format("Quét map %d/%d",
        AutoLoot.sweepIdx - 1, #AutoLoot.sweepQueue)
end
local function autoLootStep(dt)
    if not AutoLoot.enabled then return end
    if not isAlive() then return end
    local hrp = getHRP(); if not hrp then return end
    AutoLoot.findTimer += dt
    local needRetarget = (not AutoLoot.findCache)
        or (not AutoLoot.findCache.inst.Parent)
        or (not hasInteraction(AutoLoot.findCache.inst))
        or AutoLoot.findTimer > CONFIG.RetargetInterval
    if needRetarget then
        AutoLoot.findCache = findNearestLoot()
        AutoLoot.findTimer = 0
    end
    local found = AutoLoot.findCache
    if not found or not found.inst.Parent then
        AutoLoot.target = nil; AutoLoot.findCache = nil
        AutoLoot.failCount = 0
        AutoLoot.arrivedAt = nil
        local now = os.clock()
        if now - AutoLoot.lastChestFoundAt > AutoLoot.SWEEP_COOLDOWN then
            doSweep(hrp)
        else
            AutoLoot.status = "Chờ rương..."
        end
        return
    end
    AutoLoot.lastChestFoundAt = os.clock()
    if AutoLoot.lastTarget ~= found.inst then
        AutoLoot.lastTarget = found.inst
        AutoLoot.target = found.inst
        AutoLoot.failCount = 0
        AutoLoot.lastAttempt = 0
        AutoLoot.arrivedAt = nil
    end
    local itemPos = ItemFinder:getPosition(found.inst) or found.pos
    local dist = moveToLoot(hrp, itemPos, dt)
    if dist <= CONFIG.StopDistanceLoot + 1.5 then
        if not AutoLoot.arrivedAt then
            AutoLoot.arrivedAt = os.clock()
        end
        if os.clock() - AutoLoot.arrivedAt > 0.15 then
            local now = os.clock()
            if now - AutoLoot.lastAttempt > 0.4 then
                AutoLoot.lastAttempt = now
                ItemFinder:collect(found.inst)
                AutoLoot.failCount += 1
                if AutoLoot.failCount >= 5 then
                    ItemFinder:addBlacklist(found.inst, 8)
                    AutoLoot.findCache = nil
                    AutoLoot.target = nil
                    AutoLoot.lastTarget = nil
                    AutoLoot.failCount = 0
                    AutoLoot.arrivedAt = nil
                    AutoLoot.status = "Skip " .. found.inst.Name
                    return
                end
            end
            AutoLoot.status = string.format("Nhặt %s (lần %d)",
                found.inst.Name, AutoLoot.failCount)
        else
            AutoLoot.status = "Chuẩn bị..."
        end
    else
        AutoLoot.arrivedAt = nil
        AutoLoot.status = string.format("→ %s (%.0f)", found.inst.Name, dist)
    end
end
function AutoLoot:start()
    if self.enabled then return end
    self.enabled = true
    self.findTimer = 0; self.findCache = nil
    self.failCount = 0; self.lastAttempt = 0
    self.arrivedAt = nil; self.lastTarget = nil
    self.sweepQueue = nil; self.sweepIdx = 0; self.sweepWaitUntil = 0
    if not ItemFinder.enabled then ItemFinder:start() end
    ItemFinder:scanAll()
    self.lastChestFoundAt = os.clock()
    local count = 0
    for _ in pairs(ItemFinder.Discovered) do count += 1 end
    print(string.format("[AutoLoot v6] Đã scan %d item trong workspace", count))
    if not self.noclipHeld then NoclipManager:acquire(); self.noclipHeld = true end
    autoLootSetup()
    self.conn = RunService.RenderStepped:Connect(function(dt) autoLootStep(dt) end)
    self._respawnConns = self._respawnConns or {}
    table.insert(self._respawnConns, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.3)
        if self.enabled then autoLootSetup() end
    end))
end
function AutoLoot:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.conn then self.conn:Disconnect(); self.conn = nil end
    if self._respawnConns then
        for _, c in ipairs(self._respawnConns) do c:Disconnect() end
        self._respawnConns = nil
    end
    autoLootRestore()
    self.target=nil; self.findCache=nil; self.status="Tắt"
    self.failCount = 0; self.lastAttempt = 0
    self.arrivedAt = nil; self.lastTarget = nil
    self.sweepQueue = nil; self.sweepIdx = 0; self.sweepWaitUntil = 0
    if self.noclipHeld then NoclipManager:release(); self.noclipHeld = false end
end

-- ============================================================
-- PLAYER ESP
-- ============================================================
local ESP = { enabled=false, entries={}, loopConn=nil, playerConns={} }
local function clearEspEntry(plr)
    local e = ESP.entries[plr]; if not e then return end
    if e.highlight then e.highlight:Destroy() end
    if e.billboard then e.billboard:Destroy() end
    for _, c in ipairs(e.conns) do c:Disconnect() end
    ESP.entries[plr] = nil
end
local function refreshEspFor(plr)
    if plr == LocalPlayer then return end
    clearEspEntry(plr)
    if not ESP.enabled then return end
    if CONFIG.ESP.SameTeamOnly and plr.Team ~= nil and plr.Team == LocalPlayer.Team then return end
    local char = plr.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local hl = Instance.new("Highlight")
    hl.Name = "UtilityESP"
    hl.FillColor = CONFIG.ESP.Color; hl.OutlineColor = CONFIG.ESP.Color
    hl.FillTransparency = 0.7; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char; hl.Parent = char
    local head = char:FindFirstChild("Head") or char:FindFirstChildWhichIsA("BasePart")
    if not head then hl:Destroy() return end
    local bb = Instance.new("BillboardGui")
    bb.Name="UtilityESP"; bb.Size=UDim2.new(0,140,0,42)
    bb.StudsOffset=Vector3.new(0,2.5,0); bb.AlwaysOnTop=true
    bb.Adornee=head; bb.Parent=head
    local bg = Instance.new("Frame")
    bg.BackgroundColor3=Color3.fromRGB(0,0,0); bg.BackgroundTransparency=0.4
    bg.Size=UDim2.new(1,0,1,0); bg.BorderSizePixel=0; bg.Parent=bb
    local bgc = Instance.new("UICorner"); bgc.CornerRadius=UDim.new(0,6); bgc.Parent=bg
    local nameL = Instance.new("TextLabel")
    nameL.BackgroundTransparency=1
    nameL.Size=UDim2.new(1,-8,0,16); nameL.Position=UDim2.new(0,4,0,2)
    nameL.Font=Enum.Font.GothamBold; nameL.TextSize=12
    nameL.TextColor3=Color3.new(1,1,1)
    nameL.TextXAlignment=Enum.TextXAlignment.Left
    nameL.Text = CONFIG.ESP.ShowName and plr.Name or ""
    nameL.Visible = CONFIG.ESP.ShowName; nameL.Parent=bg
    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency=1
    distL.Size=UDim2.new(0,50,0,16); distL.Position=UDim2.new(1,-54,0,2)
    distL.Font=Enum.Font.Gotham; distL.TextSize=11
    distL.TextColor3=Color3.fromRGB(220,220,220)
    distL.TextXAlignment=Enum.TextXAlignment.Right
    distL.Text="0"; distL.Visible=CONFIG.ESP.ShowDistance; distL.Parent=bg
    local hpB = Instance.new("Frame")
    hpB.BackgroundColor3=Color3.fromRGB(30,30,30); hpB.BorderSizePixel=0
    hpB.Size=UDim2.new(1,-8,0,6); hpB.Position=UDim2.new(0,4,1,-10)
    hpB.Visible=CONFIG.ESP.ShowHealth; hpB.Parent=bg
    local hbc=Instance.new("UICorner"); hbc.CornerRadius=UDim.new(0,3); hbc.Parent=hpB
    local hpF = Instance.new("Frame")
    hpF.BackgroundColor3=Color3.fromRGB(80,200,90); hpF.BorderSizePixel=0
    hpF.Size=UDim2.new(1,0,1,0); hpF.Parent=hpB
    local hfc=Instance.new("UICorner"); hfc.CornerRadius=UDim.new(0,3); hfc.Parent=hpF
    local conns = {}
    table.insert(conns, hum.HealthChanged:Connect(function(h)
        local mx = hum.MaxHealth
        if mx > 0 then
            hpF.Size = UDim2.new(math.clamp(h/mx,0,1),0,1,0)
            hpF.BackgroundColor3 = Color3.fromRGB(
                math.floor(255*(1-h/mx)), math.floor(255*(h/mx)), 80)
        end
    end))
    if hum.MaxHealth > 0 then
        hpF.Size = UDim2.new(math.clamp(hum.Health/hum.MaxHealth,0,1),0,1,0)
    end
    ESP.entries[plr] = { highlight=hl, billboard=bb, distLabel=distL, conns=conns }
end
local function espDistanceLoop()
    if not ESP.enabled then return end
    local myHrp = getHRP(); if not myHrp then return end
    for plr, e in pairs(ESP.entries) do
        if e.distLabel and plr.Character then
            local root = plr.Character:FindFirstChild("HumanoidRootPart")
            if root then
                e.distLabel.Text = string.format("%d",
                    math.floor((root.Position - myHrp.Position).Magnitude))
            end
        end
    end
end
function ESP:start()
    if self.enabled then return end
    self.enabled = true
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then refreshEspFor(plr) end
    end
    table.insert(self.playerConns, Players.PlayerAdded:Connect(function(plr)
        local c1 = plr.CharacterAdded:Connect(function() refreshEspFor(plr) end)
        local c2 = plr.CharacterRemoving:Connect(function() clearEspEntry(plr) end)
        table.insert(self.playerConns, c1); table.insert(self.playerConns, c2)
        refreshEspFor(plr)
    end))
    table.insert(self.playerConns, Players.PlayerRemoving:Connect(function(plr)
        clearEspEntry(plr)
    end))
    table.insert(self.playerConns, LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.2)
        if self.enabled then
            for _, plr in ipairs(Players:GetPlayers()) do refreshEspFor(plr) end
        end
    end))
    self.loopConn = RunService.Heartbeat:Connect(function()
        self._last = self._last or 0
        if os.clock() - self._last < CONFIG.ESP.UpdateInterval then return end
        self._last = os.clock(); espDistanceLoop()
    end)
end
function ESP:stop()
    if not self.enabled then return end
    self.enabled = false
    if self.loopConn then self.loopConn:Disconnect(); self.loopConn = nil end
    for _, c in ipairs(self.playerConns) do c:Disconnect() end
    self.playerConns = {}
    for plr in pairs(self.entries) do clearEspEntry(plr) end
    self.entries = {}
end

-- ============================================================
-- UI HELPERS
-- ============================================================
local UI = {}
function UI.corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6); c.Parent = inst; return c
end
function UI.makeButton(parent, text, size, pos)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = true
    b.BackgroundColor3 = Color3.fromRGB(45,50,65)
    b.BorderSizePixel = 0
    b.Text = text; b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamMedium; b.TextSize = 12
    b.Size = size; b.Position = pos; b.Parent = parent
    UI.corner(b, 5); return b
end
function UI.makeSection(parent, title)
    local h = Instance.new("Frame")
    h.BackgroundColor3 = Color3.fromRGB(30,34,44)
    h.BorderSizePixel = 0
    h.Size = UDim2.new(1,-6,0,0)
    h.AutomaticSize = Enum.AutomaticSize.Y
    h.Position = UDim2.new(0,3,0,0)
    h.Parent = parent
    UI.corner(h, 6)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0,6); p.PaddingBottom = UDim.new(0,6)
    p.PaddingLeft = UDim.new(0,6); p.PaddingRight = UDim.new(0,6)
    p.Parent = h
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0,4); l.Parent = h
    if title then
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1,0,0,16)
        lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 11
        lbl.TextColor3 = Color3.fromRGB(180,200,255)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = title; lbl.LayoutOrder = -1; lbl.Parent = h
    end
    return h
end
function UI.makeToggle(parent, text, default, callback)
    local row = Instance.new("Frame")
    row.BackgroundTransparency=1; row.Size=UDim2.new(1,0,0,22); row.Parent=parent
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency=1
    lbl.Size=UDim2.new(1,-50,1,0)
    lbl.Font=Enum.Font.Gotham; lbl.TextSize=12
    lbl.TextColor3=Color3.fromRGB(230,230,230)
    lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.Text=text; lbl.Parent=row
    local sw = Instance.new("TextButton")
    sw.Size=UDim2.new(0,38,0,18); sw.Position=UDim2.new(1,-38,0.5,-9)
    sw.BackgroundColor3 = default and Color3.fromRGB(70,180,90) or Color3.fromRGB(60,60,70)
    sw.Text=""; sw.BorderSizePixel=0; sw.AutoButtonColor=false; sw.Parent=row
    UI.corner(sw, 9)
    local dot = Instance.new("Frame")
    dot.Size=UDim2.new(0,14,0,14)
    dot.Position = default and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
    dot.BackgroundColor3=Color3.new(1,1,1); dot.BorderSizePixel=0
    dot.Parent=sw; UI.corner(dot, 7)
    local state = default
    local function set(v, fire)
        state = v
        sw.BackgroundColor3 = v and Color3.fromRGB(70,180,90) or Color3.fromRGB(60,60,70)
        local goal = v and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
        TweenService:Create(dot, TweenInfo.new(0.15), {Position=goal}):Play()
        if fire then callback(v) end
    end
    sw.MouseButton1Click:Connect(function() set(not state, true) end)
    return { set=function(v) set(v,false) end, row=row }
end
function UI.makeSlider(parent, text, min, max, default, callback, isFloat)
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency=1
    holder.Size=UDim2.new(1,0,0,38); holder.Parent=parent
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency=1
    lbl.Size=UDim2.new(0.6,0,0,14)
    lbl.Font=Enum.Font.Gotham; lbl.TextSize=11
    lbl.TextColor3=Color3.fromRGB(230,230,230)
    lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.Text=text; lbl.Parent=holder
    local input = Instance.new("TextBox")
    input.Size=UDim2.new(0,50,0,16); input.Position=UDim2.new(1,-50,0,0)
    input.BackgroundColor3=Color3.fromRGB(45,50,65); input.BorderSizePixel=0
    input.Font=Enum.Font.Gotham; input.TextSize=11
    input.TextColor3=Color3.new(1,1,1)
    input.Text = isFloat and string.format("%.2f", default) or tostring(default)
    input.ClearTextOnFocus=false
    input.Parent=holder; UI.corner(input, 3)
    local track = Instance.new("Frame")
    track.BackgroundColor3=Color3.fromRGB(50,55,70); track.BorderSizePixel=0
    track.Size=UDim2.new(1,0,0,6); track.Position=UDim2.new(0,0,0,24)
    track.Parent=holder; UI.corner(track, 3)
    local fill = Instance.new("Frame")
    fill.BackgroundColor3=Color3.fromRGB(90,150,240); fill.BorderSizePixel=0
    fill.Size=UDim2.new((default-min)/(max-min),0,1,0)
    fill.Parent=track; UI.corner(fill, 3)
    local knob = Instance.new("Frame")
    knob.BackgroundColor3=Color3.new(1,1,1); knob.BorderSizePixel=0
    knob.Size=UDim2.new(0,12,0,12); knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.new((default-min)/(max-min),0,0.5,0)
    knob.Parent=track; UI.corner(knob, 6)
    local value = default
    local function setValue(v, fire)
        v = clamp(tonumber(v) or value, min, max); value = v
        local a = (v-min)/(max-min)
        fill.Size = UDim2.new(a,0,1,0)
        knob.Position = UDim2.new(a,0,0.5,0)
        input.Text = isFloat and string.format("%.2f", v) or tostring(math.floor(v))
        if fire then callback(v) end
    end
    local dragging = false
    local function updateFromInput(pos)
        local rel = (pos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
        setValue(min + rel * (max-min), true)
    end
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; updateFromInput(i.Position)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(i.Position)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    input.FocusLost:Connect(function() setValue(tonumber(input.Text), true) end)
    return { setValue=setValue, row=holder, get=function() return value end }
end
local function makeDropdown(parent, text, multi, getItems, onChange)
    local row = Instance.new("Frame")
    row.BackgroundTransparency=1; row.Size=UDim2.new(1,0,0,26); row.Parent=parent
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency=1
    lbl.Size=UDim2.new(0.5,0,1,0)
    lbl.Font=Enum.Font.Gotham; lbl.TextSize=11
    lbl.TextColor3=Color3.fromRGB(230,230,230)
    lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.Text=text; lbl.Parent=row
    local btn = UI.makeButton(row, "Chọn...", UDim2.new(0.5,-4,1,0), UDim2.new(0.5,4,0,0))
    local selected, singleValue = {}, nil
    local panel
    local overlay = PlayerGui:FindFirstChild(CONFIG.GuiName)
    local function closePanel() if panel then panel:Destroy() panel=nil end end
    local function updateLabel()
        if multi then
            local c, first = 0, nil
            for k in pairs(selected) do c += 1; if not first then first = k end end
            if c == 0 then btn.Text = "Chọn..."
            elseif c == 1 then btn.Text = first
            else btn.Text = c .. " đã chọn" end
        else btn.Text = singleValue or "Chọn..." end
    end
    local function openPanel()
        closePanel()
        local pos = btn.AbsolutePosition
        panel = Instance.new("Frame")
        panel.BackgroundColor3=Color3.fromRGB(35,40,52); panel.BorderSizePixel=0
        panel.Size=UDim2.new(0,220,0,220)
        panel.Position=UDim2.new(0,pos.X,0,pos.Y + btn.AbsoluteSize.Y + 4)
        panel.ZIndex=20; panel.Parent=overlay
        UI.corner(panel, 6)
        local search = Instance.new("TextBox")
        search.Size=UDim2.new(1,-12,0,20); search.Position=UDim2.new(0,6,0,6)
        search.BackgroundColor3=Color3.fromRGB(25,30,40); search.BorderSizePixel=0
        search.Font=Enum.Font.Gotham; search.TextSize=11
        search.TextColor3=Color3.new(1,1,1); search.Text=""
        search.PlaceholderText="Tìm..."; search.ClearTextOnFocus=false
        search.Parent=panel; UI.corner(search, 3)
        local scroll = Instance.new("ScrollingFrame")
        scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
        scroll.Position=UDim2.new(0,6,0,32); scroll.Size=UDim2.new(1,-12,1,-40)
        scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.ScrollBarThickness=3
        scroll.Parent=panel
        local list = Instance.new("UIListLayout")
        list.Padding=UDim.new(0,2); list.Parent=scroll
        local function refresh()
            for _, c in ipairs(scroll:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            local q = search.Text:lower()
            for _, name in ipairs(getItems()) do
                if q == "" or name:lower():find(q,1,true) then
                    local item = Instance.new("TextButton")
                    item.BackgroundColor3 = (multi and selected[name] or singleValue == name)
                        and Color3.fromRGB(90,150,240) or Color3.fromRGB(45,50,65)
                    item.BorderSizePixel=0; item.Size=UDim2.new(1,0,0,22)
                    item.Font=Enum.Font.Gotham; item.TextSize=11
                    item.TextColor3=Color3.new(1,1,1)
                    item.TextXAlignment=Enum.TextXAlignment.Left
                    item.Text = "  " .. name
                    item.Parent=scroll; UI.corner(item, 3)
                    item.MouseButton1Click:Connect(function()
                        if multi then selected[name] = not selected[name] or nil
                        else
                            singleValue = name
                            selected = { [name] = true }
                            closePanel()
                        end
                        updateLabel(); onChange(selected, singleValue); refresh()
                    end)
                end
            end
            scroll.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y)
        end
        search:GetPropertyChangedSignal("Text"):Connect(refresh)
        refresh()
        local closeConn
        closeConn = UserInputService.InputBegan:Connect(function(i, gp)
            if gp then return end
            if panel and panel.Parent then
                local mx, my = i.Position.X, i.Position.Y
                local ap, az = panel.AbsolutePosition, panel.AbsoluteSize
                local inside = mx >= ap.X and mx <= ap.X + az.X
                           and my >= ap.Y and my <= ap.Y + az.Y
                local bp, bs = btn.AbsolutePosition, btn.AbsoluteSize
                local onBtn = mx >= bp.X and mx <= bp.X + bs.X
                          and my >= bp.Y and my <= bp.Y + bs.Y
                if not inside and not onBtn then
                    closePanel()
                    if closeConn then closeConn:Disconnect() end
                end
            end
        end)
    end
    btn.MouseButton1Click:Connect(function()
        if panel then closePanel() else openPanel() end
    end)
    updateLabel()
    return { row=row, getSelected=function() return selected, singleValue end,
             setLabel=function(s) singleValue=s; updateLabel() end }
end

-- ============================================================
-- BUILD UI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = CONFIG.GuiName
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = PlayerGui

NotifyContainer = Instance.new("Frame")
NotifyContainer.BackgroundTransparency = 1
NotifyContainer.Size = UDim2.new(1,0,0,240)
NotifyContainer.Position = UDim2.new(0,0,0,50)
NotifyContainer.Parent = screenGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0,44,0,44)
toggleBtn.Position = UDim2.new(1,-58,0,60)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40,90,180)
toggleBtn.Text = "D"; toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.Font = Enum.Font.GothamBlack; toggleBtn.TextSize = 22
toggleBtn.BorderSizePixel = 0; toggleBtn.Parent = screenGui
UI.corner(toggleBtn, 10)

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0,290,0,580)
main.Position = UDim2.new(0.5,-145,0.5,-290)
main.BackgroundColor3 = Color3.fromRGB(22,25,33)
main.BorderSizePixel = 0; main.Parent = screenGui
UI.corner(main, 10)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1,0,0,32)
titleBar.BackgroundColor3 = Color3.fromRGB(30,34,44)
titleBar.BorderSizePixel = 0; titleBar.Parent = main
UI.corner(titleBar, 10)
local titleLbl = Instance.new("TextLabel")
titleLbl.BackgroundTransparency = 1
titleLbl.Size = UDim2.new(1,-70,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 12
titleLbl.TextColor3 = Color3.fromRGB(200,215,255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "UTILITY MENU V1 - Claude"; titleLbl.Parent = titleBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0,22,0,22)
minimizeBtn.Position = UDim2.new(1,-50,0.5,-11)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
minimizeBtn.BorderSizePixel = 0; minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.new(1,1,1)
minimizeBtn.Font = Enum.Font.GothamBold; minimizeBtn.TextSize = 14
minimizeBtn.Parent = titleBar; UI.corner(minimizeBtn, 5)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0,22,0,22)
closeBtn.Position = UDim2.new(1,-26,0.5,-11)
closeBtn.BackgroundColor3 = Color3.fromRGB(180,60,60)
closeBtn.BorderSizePixel = 0; closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 11
closeBtn.Parent = titleBar; UI.corner(closeBtn, 5)

local content = Instance.new("ScrollingFrame")
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Position = UDim2.new(0,0,0,36)
content.Size = UDim2.new(1,0,1,-40)
content.CanvasSize = UDim2.new(0,0,0,0)
content.ScrollBarThickness = 3
content.Parent = main
local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0,6); contentLayout.Parent = content
contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    content.CanvasSize = UDim2.new(0,0,0, contentLayout.AbsoluteContentSize.Y + 6)
end)

-- DI CHUYỂN
local secMove = UI.makeSection(content, "DI CHUYỂN")
UI.makeToggle(secMove, "Speed Walk", false, function(on)
    if on then SpeedWalk:start() else SpeedWalk:stop() end
end)
UI.makeSlider(secMove, "WalkSpeed", CONFIG.WalkSpeed.Min, CONFIG.WalkSpeed.Max,
    CONFIG.WalkSpeed.Default, function(v) SpeedWalk:set(v) end)
UI.makeToggle(secMove, "High Jump", false, function(on)
    if on then HighJump:start() else HighJump:stop() end
end)
UI.makeSlider(secMove, "Jump", CONFIG.Jump.Min, CONFIG.Jump.Max,
    CONFIG.Jump.Default, function(v) HighJump:set(v) end)
UI.makeToggle(secMove, "Noclip", false, function(on)
    if on then NoclipManager:acquire() else NoclipManager:release() end
end)

-- TỰ ĐỘNG
local secAuto = UI.makeSection(content, "TỰ ĐỘNG")
local farmToggle
farmToggle = UI.makeToggle(secAuto, "Auto Farm", false, function(on)
    if on then
        if AutoLoot.enabled then AutoLoot:stop(); if lootToggle then lootToggle.set(false) end end
        AutoFarm:start()
    else AutoFarm:stop() end
end)

makeDropdown(secAuto, "Loại quái", false, function()
    return getEnemyTypes()
end, function(_, single) AutoFarm.selectedType = single end)

UI.makeSlider(secAuto, "Độ cao farm", CONFIG.FarmHeight.Min, CONFIG.FarmHeight.Max,
    CONFIG.FarmHeight.Default, function(v) AutoFarm:setHeight(v) end)

local modeDropdown = makeDropdown(secAuto, "Mode bay", false, function()
    return { "Align", "Anchored", "Ground" }
end, function(_, single)
    if single == "Align" then CONFIG.MoveMode = "Align"
    elseif single == "Anchored" then CONFIG.MoveMode = "Anchored"
    elseif single == "Ground" then CONFIG.MoveMode = "Ground" end
    if AutoFarm.enabled then AutoFarm:restartMover() end
    notify("Mode: " .. CONFIG.MoveMode)
end)

local farmStatus = Instance.new("TextLabel")
farmStatus.BackgroundTransparency = 1
farmStatus.Size = UDim2.new(1,0,0,12)
farmStatus.Font = Enum.Font.Gotham; farmStatus.TextSize = 10
farmStatus.TextColor3 = Color3.fromRGB(180,200,255)
farmStatus.TextXAlignment = Enum.TextXAlignment.Left
farmStatus.Text = "Farm: Tắt"; farmStatus.Parent = secAuto

-- AUTO LOOT
local lootToggle
lootToggle = UI.makeToggle(secAuto, "Auto Loot Rương (sweep map)", false, function(on)
    if on then
        if AutoFarm.enabled then AutoFarm:stop(); if farmToggle then farmToggle.set(false) end end
        AutoLoot:start()
    else AutoLoot:stop() end
end)

UI.makeSlider(secAuto, "Bán kính sweep (x1000)", 1, 10, 5, function(v)
    AutoLoot.SWEEP_BOUNDS = v * 1000
    AutoLoot.sweepQueue = nil
    AutoLoot.sweepIdx = 0
    notify(string.format("Bán kính sweep: %d studs", v * 1000))
end)

local lootStatus = Instance.new("TextLabel")
lootStatus.BackgroundTransparency = 1
lootStatus.Size = UDim2.new(1,0,0,12)
lootStatus.Font = Enum.Font.Gotham; lootStatus.TextSize = 10
lootStatus.TextColor3 = Color3.fromRGB(180,200,255)
lootStatus.TextXAlignment = Enum.TextXAlignment.Left
lootStatus.Text = "Loot: Tắt"; lootStatus.Parent = secAuto

-- HÌNH ẢNH
local secVis = UI.makeSection(content, "HÌNH ẢNH")
UI.makeToggle(secVis, "Fix Lag (siêu mạnh)", false, function(on)
    if on then
        FixLag:start()
        notify("Fix Lag: BẬT — xoá texture, bầu trời, hiệu ứng")
    else
        FixLag:stop()
        notify("Fix Lag: TẮT")
    end
end)
UI.makeToggle(secVis, "Full Bright", false, function(on)
    if on then FullBright:start() else FullBright:stop() end
end)
UI.makeToggle(secVis, "ESP Vật phẩm", false, function(on)
    if not ItemFinder.enabled then ItemFinder:start() end
    ItemFinder:setESP(on)
    notify(on and "ESP item BẬT" or "ESP item TẮT")
end)
UI.makeToggle(secVis, "ESP Người chơi", false, function(on)
    if on then ESP:start() else ESP:stop() end
end)
UI.makeToggle(secVis, "ESP - chỉ khác đội", CONFIG.ESP.SameTeamOnly, function(on)
    CONFIG.ESP.SameTeamOnly = on
    if ESP.enabled then ESP:stop(); ESP:start() end
end)

-- UI logic
do
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end
minimizeBtn.MouseButton1Click:Connect(function()
    content.Visible = not content.Visible
    main.Size = content.Visible and UDim2.new(0,290,0,580) or UDim2.new(0,290,0,32)
    minimizeBtn.Text = content.Visible and "–" or "+"
end)
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
-- Nút D: chạm để mở/đóng menu, giữ và kéo để di chuyển tự do
do
    local dragInput, dragStart, startAbs, moved = nil, nil, nil, false
    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input; dragStart = input.Position
            startAbs = toggleBtn.AbsolutePosition; moved = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragInput then return end
        local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
            and dragInput.UserInputType == Enum.UserInputType.MouseButton1
        if input ~= dragInput and not isMouse then return end
        local d = input.Position - dragStart
        if not moved and d.Magnitude < 6 then return end
        moved = true
        local size, screen = toggleBtn.AbsoluteSize, screenGui.AbsoluteSize
        toggleBtn.Position = UDim2.fromOffset(
            clamp(startAbs.X + d.X, 0, screen.X - size.X),
            clamp(startAbs.Y + d.Y, 0, screen.Y - size.Y))
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragInput = nil
        end
    end)
    toggleBtn.MouseButton1Click:Connect(function()
        if moved then moved = false; return end
        main.Visible = not main.Visible
    end)
end
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CONFIG.ToggleKey then
        main.Visible = not main.Visible
    end
end)

task.spawn(function()
    while screenGui.Parent do
        farmStatus.Text = "Farm: " .. (AutoFarm.enabled and AutoFarm.status or "Tắt")
        lootStatus.Text = "Loot: " .. (AutoLoot.enabled and AutoLoot.status or "Tắt")
        ItemFinder:updateDistanceLabels()
        task.wait(CONFIG.ItemESP.UpdateInterval)
    end
end)

screenGui.Destroying:Connect(function()
    SpeedWalk:stop(); HighJump:stop()
    AutoFarm:stop(); AutoLoot:stop()
    ESP:stop(); FixLag:stop(); FullBright:stop()
    ItemFinder:stop()
    NoclipManager:release()
end)

modeDropdown.setLabel("Align")

notify("Menu V1 - Claude — Fix Lag siêu mạnh")
