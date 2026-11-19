-- ============================================================
-- KICIA MELEE v10 — Zero-Ping + Agresif Takip + Ragebot Filtreleri
-- fix.txt altyapısı (Trove, Signal) korundu
-- VOID bölümü değiştirilmedi — sadece atak/hədəf mantığı güçlendirildi
-- ============================================================
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local lp         = Players.LocalPlayer
local UIS        = game:GetService("UserInputService")

repeat task.wait() until game:IsLoaded() and lp.Character

-- ============================================================
-- Signal / Trove (değişmedi)
-- ============================================================
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _handlers = {} }, Signal) end
function Signal:Connect(fn)
    local h = { fn = fn, connected = true }
    table.insert(self._handlers, h)
    local sig = self
    return {
        Connected = true,
        Disconnect = function(c)
            if not h.connected then return end
            h.connected = false
            c.Connected = false
            local i = table.find(sig._handlers, h)
            if i then table.remove(sig._handlers, i) end
        end,
    }
end
function Signal:Fire(...)
    local list = table.clone(self._handlers)
    for _, h in ipairs(list) do
        if h.connected then task.spawn(h.fn, ...) end
    end
end
function Signal:Destroy() table.clear(self._handlers) end

local Trove = {}
Trove.__index = Trove
function Trove.new(name) return setmetatable({ _name = name, _items = {}, _cleaning = false }, Trove) end
local function cleanItem(o)
    local t = typeof(o)
    if t == "RBXScriptConnection" then pcall(function() o:Disconnect() end)
    elseif t == "Instance" then pcall(function() o:Destroy() end)
    elseif t == "thread" then pcall(task.cancel, o)
    elseif type(o) == "function" then pcall(o)
    elseif type(o) == "table" then
        local destroy = o.Destroy or o.Disconnect
        if type(destroy) == "function" then pcall(destroy, o) end
    end
end
function Trove:Add(o) table.insert(self._items, o); return o end
function Trove:Connect(sig, fn) return self:Add(sig:Connect(fn)) end
function Trove:Clean()
    if self._cleaning then return end
    self._cleaning = true
    local items = self._items
    self._items = {}
    for i = #items, 1, -1 do cleanItem(items[i]) end
    self._cleaning = false
end
Trove.Destroy = Trove.Clean

local MainTrove = Trove.new("KiciaMelee")

-- ============================================================
-- FAST FLAGS (değişmedi)
-- ============================================================
pcall(function()
    if setfflag then
        setfflag("DFIntS2PhysicsSenderRate", "240")
        setfflag("DFIntAssemblyHistoryBufferSize", "2147483648")
        setfflag("DFIntAssemblyHistorySkipSize", "0")
    end
end)

-- ============================================================
-- MODÜL YÜKLEMELERİ (değişmedi)
-- ============================================================
local EnumLibrary = require(RS.Modules.EnumLibrary)
local UseItem     = RS.Remotes.Replication.Fighter:WaitForChild("UseItem", 10)
local FC          = require(lp.PlayerScripts.Controllers:WaitForChild("FighterController", 30))
local function localFighter() return FC and FC.LocalFighter end

local CameraController
pcall(function()
    CameraController = require(lp.PlayerScripts.Controllers.CameraController)
end)

local setRotationFn = nil
if CameraController then
    pcall(function()
        local mt = getmetatable(CameraController)
        if mt and type(mt.__index) == "table" then
            setRotationFn = mt.__index.SetRotation
        end
    end)
end

local function applyCameraRotation(pitch, yaw)
    local rot = Vector2.new(pitch, yaw)
    if setRotationFn then
        pcall(function() coroutine.wrap(setRotationFn)(CameraController, rot) end)
    else
        pcall(function() CameraController.Rotation = rot end)
    end
end

local _to_enum = rawget(EnumLibrary, "_to_enum")
local function toEnum(name)
    if _to_enum then return _to_enum[name] end
    local ok, v = pcall(function() return EnumLibrary:ToEnum(name) end)
    if ok and v ~= nil then return v end
    return nil
end

local START_SHOOTING = toEnum("StartShooting")
local START_AIMING   = toEnum("StartAiming")
local ANIM_ATTACK    = toEnum("AttackAnimation1") or toEnum("Attack1")
local ANIM_HEAVY     = toEnum("HeavyAttackAnimation1") or toEnum("HeavyAttack1")

-- ============================================================
-- CONFIG (değişmedi, sadece TARGET_MODE ve PRIORITY eklendi)
-- ============================================================
local CONFIG = {
    ATTACK_DURATION  = 0.15,
    VOID_DURATION    = 0.34,
    FIRE_DELAY       = 0.01,
    KNIFE_COOLDOWN   = 0.75,
    MELEE_COOLDOWN   = 0.15,

    TP_BACK          = 2.0,
    TP_FRONT         = 2.0,
    TP_SIDE          = 2.0,
    RANGE            = math.huge,
    AIM_SMOOTHING    = 0,

    -- Zero-Ping
    PREDICTION_STRENGTH = 1.0,
    MAX_PING            = 0.3,

    -- Voidspam (DEĞİŞMEDİ)
    VOID_TRACK_RADIUS   = 5000,
    VOID_TP_PER_FRAME   = 100,
    VOID_MIN_Y          = 5000,
    VOID_MAX_Y          = 10000,

    BACKSTAB_SPEED      = 120,
    SMART_BACKSTAB      = true,

    -- YENİ: Hedef seçim parametreleri
    TARGET_MODE         = "Closest",  -- "Closest" | "LowestHealth"
    PRIORITY_VOIDED     = true,       -- void'deki hedeflere öncelik
    PRIORITY_ATTACKERS  = true,       -- silah tutanlara öncelik
    NEAR_OTHER_MATCH_R  = 1000,       -- başka maç yakınlık eşiği

    DEBUG = true,
}

-- ============================================================
-- FALLEN PARTS (değişmedi)
-- ============================================================
local function disableFallenParts()
    pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
end
disableFallenParts()
task.spawn(function()
    while true do task.wait(0.5) disableFallenParts() end
end)

-- ============================================================
-- FAST CFrame WRITE (değişmedi)
-- ============================================================
local _ni_cache = nil
local _ni_checked = false
local function getHRPNewIndex(hrp)
    if not _ni_checked then
        local mt = getrawmetatable(hrp)
        _ni_cache = mt and rawget(mt, "__newindex")
        _ni_checked = true
    end
    return _ni_cache
end

local V0 = Vector3.zero
local function fastSetCF(hrp, cf)
    local ni = getHRPNewIndex(hrp)
    if ni then
        pcall(ni, hrp, "AssemblyLinearVelocity", V0)
        pcall(ni, hrp, "AssemblyAngularVelocity", V0)
        pcall(ni, hrp, "CFrame", cf)
        pcall(ni, hrp, "AssemblyLinearVelocity", V0)
    else
        pcall(function()
            hrp.AssemblyLinearVelocity = V0
            hrp.AssemblyAngularVelocity = V0
            hrp.CFrame = cf
        end)
    end
    if sethiddenproperty then
        pcall(sethiddenproperty, hrp, "CFrame", cf)
        pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", V0)
    end
end

-- ============================================================
-- ENEMY TRACKER (değişmedi)
-- ============================================================
local enemyTrackers    = setmetatable({}, { __mode = "k" })
local enemyTrackerChar = setmetatable({}, { __mode = "k" })
local MAX_TRACK_SAMPLES = 8

local function updateEnemyTracker(plr)
    local char = plr.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local tracker = enemyTrackers[plr]
    if not tracker or enemyTrackerChar[plr] ~= char then
        tracker = { positions = {}, cframes = {}, times = {} }
        enemyTrackers[plr]  = tracker
        enemyTrackerChar[plr] = char
    end

    local now = workspace:GetServerTimeNow()
    table.insert(tracker.positions, root.Position)
    table.insert(tracker.cframes,   root.CFrame)
    table.insert(tracker.times,     now)

    while #tracker.positions > MAX_TRACK_SAMPLES do
        table.remove(tracker.positions, 1)
        table.remove(tracker.cframes,   1)
        table.remove(tracker.times,     1)
    end
end

-- ============================================================
-- PREDICTION (değişmedi)
-- ============================================================
local function getPredictedState(plr)
    local char = plr.Character
    local fbPos, fbCF = Vector3.zero, CFrame.new()
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then fbPos, fbCF = root.Position, root.CFrame end
    end

    local tracker = enemyTrackers[plr]
    if not tracker or #tracker.positions < 2 then
        return {
            Position = fbPos, CFrame = fbCF,
            Velocity = Vector3.zero, Speed = 0,
            PredictionTime = 0, Confidence = 0,
            RealPosition = fbPos, RealCFrame = fbCF,
        }
    end

    local n = #tracker.positions
    local totalW, sumVel = 0, Vector3.zero
    local velocities = {}

    for i = 2, n do
        local dt = tracker.times[i] - tracker.times[i - 1]
        if dt > 0.001 then
            local v = (tracker.positions[i] - tracker.positions[i - 1]) / dt
            table.insert(velocities, v)
            local w = i - 1
            sumVel  = sumVel + v * w
            totalW  = totalW + w
        end
    end

    local avgVel = totalW > 0 and (sumVel / totalW) or Vector3.zero

    local sigma = 0
    if #velocities >= 2 then
        local acc = 0
        for _, v in velocities do
            acc = acc + (v - avgVel).Magnitude ^ 2
        end
        sigma = math.sqrt(acc / #velocities)
    end

    local sampleConf   = math.clamp((n - 1) / 3, 0.35, 1)
    local varianceConf = math.clamp(1 - sigma / 80, 0.30, 1)
    local confidence   = sampleConf * varianceConf

    local lastPos, lastCF, lastT = tracker.positions[n], tracker.cframes[n], tracker.times[n]
    local sampleAge = math.max(0, workspace:GetServerTimeNow() - lastT)

    local rawPing = lp:GetNetworkPing()
    local rtt = rawPing > 1 and (rawPing / 1000) or rawPing

    local rawPredTime = (rtt + sampleAge) * CONFIG.PREDICTION_STRENGTH * confidence
    local predictionTime = math.clamp(rawPredTime, 0, CONFIG.MAX_PING)

    local predictedPos = lastPos + avgVel * predictionTime
    local horizVel     = Vector3.new(avgVel.X, 0, avgVel.Z)

    return {
        Position        = predictedPos,
        CFrame          = lastCF,
        Velocity        = avgVel,
        Speed           = horizVel.Magnitude,
        PredictionTime  = predictionTime,
        Confidence      = confidence,
        RealPosition    = lastPos,
        RealCFrame      = lastCF,
    }
end

-- ============================================================
-- YENİ: RAGEBOT'DAN ALINAN FİLTRELEME HELPERLARI
-- ============================================================
local function getRoot(char)
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Silah ismi (ViewModels üzerinden)
local function scanWeapon(plr)
    local vms = workspace:FindFirstChild("ViewModels")
    if not vms then return "" end
    for _, model in ipairs(vms:GetChildren()) do
        if model:IsA("Model") then
            local sp = model.Name:find(" - ", 1, true)
            if sp and model.Name:sub(1, sp-1) == plr.Name then
                return model.Name:sub(sp+3):lower()
            end
        end
    end
    return ""
end

local function isKatana(plr) return scanWeapon(plr):find("katana", 1, true) ~= nil end

-- Invincible: attachment + particle kontrolü
local function isInvincible(plr)
    local char = plr and plr.Character
    local root = getRoot(char)
    if not root then return true end
    for _, obj in ipairs(root:GetChildren()) do
        if obj:IsA("Attachment") and obj.Name == "Attachment" then return true end
    end
    return char:FindFirstChild("InvincibilityParticles", true) ~= nil
end

-- Başka maçtaki oyuncular yakınsa hedef alma
local function isNearOtherMatch(pos, ignore)
    if typeof(pos) ~= "Vector3" then return false end
    local myEnv = lp:GetAttribute("EnvironmentID")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr ~= ignore and plr:GetAttribute("EnvironmentID") ~= myEnv then
            local r = getRoot(plr.Character)
            if r and (r.Position - pos).Magnitude <= CONFIG.NEAR_OTHER_MATCH_R then
                return true
            end
        end
    end
    return false
end

-- Shooting range / firing range tespit
local function isShootingRange()
    for _, obj in ipairs({workspace, lp}) do
        for _, attr in ipairs({"ShootingRange", "Mode", "Map", "MapName"}) do
            local v = obj:GetAttribute(attr)
            if v == true and attr == "ShootingRange" then return true end
            if type(v) == "string" then
                local t = v:lower():gsub("[%s_%-]", "")
                if t:find("shootingrange", 1, true) or t:find("firingrange", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

-- AllyLabel / TeammateLabel vs.
local function hasAllyLabels(plr)
    local char = plr.Character
    if not char then return false end
    for _, n in ipairs({"HumanoidRootPart", "Head", "HitboxHead"}) do
        local part = char:FindFirstChild(n)
        if part then
            for _, l in ipairs({"AllyLabel", "TeammateLabel", "TeamLabel", "FriendLabel"}) do
                if part:FindFirstChild(l) then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- TEAMCHECK (korundu + güçlendirildi)
-- ============================================================
local function isTeamMate(plr)
    if plr == lp then return true end
    if lp.Team and plr.Team and lp.Team == plr.Team then return true end
    local myTid = lp:GetAttribute("TeamID")
    local theirTid = plr:GetAttribute("TeamID")
    if myTid ~= nil and theirTid ~= nil and myTid == theirTid then return true end
    return false
end

-- YENİ: Ragebot tarzı kapsamlı canAttack
local function canAttack(plr)
    if plr == lp or isTeamMate(plr) then return false end
    local myEnv = lp:GetAttribute("EnvironmentID")
    if not myEnv or plr:GetAttribute("EnvironmentID") ~= myEnv then return false end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if char:FindFirstChildWhichIsA("ForceField", true) then return false end
    if plr:GetAttribute("IsInvincible") == true then return false end
    if isInvincible(plr) then return false end
    if hasAllyLabels(plr) then return false end
    if isKatana(plr) then return false end  -- katana kullanıcıları parry'ler, atla
    local r = getRoot(char)
    if r and isNearOtherMatch(r.Position, plr) then return false end
    return true
end

-- YENİ: Priority'li hedef seçimi (ragebot getBestTarget)
local function findBestTarget(pos)
    local best, bestV = nil, math.huge
    local useHP = CONFIG.TARGET_MODE == "LowestHealth"
    for _, plr in ipairs(Players:GetPlayers()) do
        if canAttack(plr) then
            local root = getRoot(plr.Character)
            if root then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                local v = useHP and (hum and hum.Health or math.huge)
                    or (root.Position - pos).Magnitude
                if CONFIG.PRIORITY_VOIDED and root.Position.Magnitude > 1000000 then
                    v = v - 2000000000
                end
                if CONFIG.PRIORITY_ATTACKERS and scanWeapon(plr) ~= "" then
                    v = v - 1000000000
                end
                if v < bestV then
                    bestV = v
                    best = { Player = plr, Root = root, Char = plr.Character }
                end
            end
        end
    end
    return best
end

-- Eski findClosest -> findBestTarget'a yönlendirildi
local function findClosest(pos) return findBestTarget(pos) end

-- ============================================================
-- VOIDSPAM (DEĞİŞMEDİ)
-- ============================================================
local function voidSpam(hrp, center)
    local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end

    for i = 1, CONFIG.VOID_TP_PER_FRAME do
        local angle = (i / CONFIG.VOID_TP_PER_FRAME) * math.pi * 2
        local radius = math.random(100, CONFIG.VOID_TRACK_RADIUS)
        local x = center.X + math.cos(angle) * radius
        local z = center.Z + math.sin(angle) * radius
        local y = math.random(CONFIG.VOID_MIN_Y, CONFIG.VOID_MAX_Y)
        fastSetCF(hrp, CFrame.new(x, y, z))
    end
end

-- ============================================================
-- PAYLOAD (değişmedi)
-- ============================================================
local function orient(base, pitch, yaw, roll)
    return {
        ["\0"]=base["\0"], ["\1"]=base["\1"], ["\2"]=base["\2"],
        ["\3"]=pitch,     ["\4"]=yaw or 0,     ["\5"]=roll or 0
    }
end

local KNIFE_SURFACE         = { ["\0"]=0,     ["\1"]=1,    ["\2"]=0, ["\3"]=0,          ["\4"]=0,       ["\5"]=0 }
local KNIFE_ABOVE_PRIMARY   = { ["\0"]=-9e37, ["\1"]=0,    ["\2"]=0, ["\3"]=-math.pi/2, ["\4"]=math.pi, ["\5"]=math.pi }
local KNIFE_ABOVE_SECONDARY = { ["\0"]=0,     ["\1"]=-9e7, ["\2"]=0, ["\3"]=-math.pi/2, ["\4"]=math.pi, ["\5"]=math.pi }
local PRIMARY_BASE          = { ["\0"]=-9e37, ["\1"]=0,    ["\2"]=0 }
local SECONDARY_BASE        = { ["\0"]=0,     ["\1"]=-9e7, ["\2"]=0 }

local function itemField(item, key)
    if not item then return nil end
    local ok, v = pcall(function() return item:Get(key) end)
    if ok and v ~= nil then return v end
    return rawget(item, key)
end

local function isMeleeItem(item)
    if type(item) ~= "table" then return false end
    local info = rawget(item, "Info")
    if type(info) ~= "table" then return false end
    return (rawget(info, "Type") or rawget(info, "Class")) == "Melee"
end

local function hasRiotShield(enemy)
    if not enemy or not enemy.Char then return false end
    for _, child in ipairs(enemy.Char:GetChildren()) do
        if child:IsA("Tool") and child.Name == "Riot Shield" then return true end
    end
    return false
end

local function computeTPPosFromState(state, isKnife, shieldFront)
    local ep   = state.Position
    local look = Vector3.new(state.CFrame.LookVector.X, 0, state.CFrame.LookVector.Z)
    if look.Magnitude > 0.01 then look = look.Unit end

    if shieldFront then
        return Vector3.new(ep.X + look.X * CONFIG.TP_FRONT,  ep.Y + 0.5, ep.Z + look.Z * CONFIG.TP_FRONT)
    elseif isKnife then
        return Vector3.new(ep.X - look.X * CONFIG.TP_BACK,   ep.Y + 0.5, ep.Z - look.Z * CONFIG.TP_BACK)
    else
        local right = Vector3.new(state.CFrame.RightVector.X, 0, state.CFrame.RightVector.Z)
        if right.Magnitude > 0.01 then right = right.Unit end
        return Vector3.new(ep.X + right.X * CONFIG.TP_SIDE,  ep.Y + 0.5, ep.Z + right.Z * CONFIG.TP_SIDE)
    end
end

local function buildPayload(predictedCF, targetPart, isKnife)
    local _, eYaw, eRoll = predictedCF:ToOrientation()
    local pitch = -math.pi / 2
    local primary, secondary, anim, fireType
    if isKnife then
        primary   = orient(KNIFE_ABOVE_PRIMARY,   pitch, eYaw, eRoll)
        secondary = orient(KNIFE_ABOVE_SECONDARY, pitch, eYaw, eRoll)
        anim      = ANIM_HEAVY
        fireType  = START_AIMING or START_SHOOTING
    else
        primary   = orient(PRIMARY_BASE,   pitch, eYaw, eRoll)
        secondary = orient(SECONDARY_BASE, pitch, eYaw, eRoll)
        anim      = ANIM_ATTACK
        fireType  = START_SHOOTING
    end
    return {
        [utf8.char(1)] = {
            [utf8.char(0)] = primary,
            [utf8.char(1)] = secondary,
            [utf8.char(2)] = targetPart,
            [utf8.char(3)] = KNIFE_SURFACE,
        },
        [utf8.char(2)] = anim,
    }, fireType
end

local function tryEquipMelee()
    local f = localFighter()
    local items = f and rawget(f, "Items")
    if type(items) ~= "table" then return end
    for i, it in ipairs(items) do
        if isMeleeItem(it) then
            pcall(function() f:EquipItem(i) end)
            return
        end
    end
end

-- YENİ: canAttackNow'a ek doğrulama (hız + geçerlilik)
local function canAttackNow(predState)
    if predState.Speed >= CONFIG.BACKSTAB_SPEED then return false end
    return true
end

-- ============================================================
-- STATE (değişmedi)
-- ============================================================
local state          = "VOID"
local stateEndsAt    = 0
local currentEnemy   = nil
local firedThisAtk   = false
local lastEquip      = 0
local cycleCount     = 0
local successCount   = 0
local lastGroundPos  = nil
local nextKnifeReadyAt = 0
local nextMeleeReadyAt = 0
local aimPitch, aimYaw = 0, 0

-- YENİ: cache'i invalidasyona açık hale getir
local cachedEnemy, cachedEnemyAt = nil, 0
local function getClosestEnemy()
    local now = tick()
    if now - cachedEnemyAt < 0.05 then
        if cachedEnemy and canAttack(cachedEnemy.Player) then
            return cachedEnemy
        end
        -- cache invalid: temizle ve yeniden hesapla
        cachedEnemy, cachedEnemyAt = nil, 0
    end
    cachedEnemyAt = now
    local searchFrom = lastGroundPos
    if not searchFrom then
        local lpRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        searchFrom = lpRoot and lpRoot.Position
    end
    if not searchFrom then cachedEnemy = nil; return nil end
    cachedEnemy = findBestTarget(searchFrom)
    return cachedEnemy
end

-- ============================================================
-- AIM LOCK (değişmedi, sadece getClosestEnemy artık daha akıllı)
-- ============================================================
MainTrove:Connect(RunService.RenderStepped, function(dt)
    if not CameraController then return end
    local enemy = getClosestEnemy()
    if not enemy then return end

    local targetPart = enemy.Char:FindFirstChild("HitboxHead")
        or enemy.Char:FindFirstChild("Head")
        or enemy.Root
    if not targetPart or not targetPart.Parent then return end

    local from
    if state == "ATTACK" and lastGroundPos then
        from = lastGroundPos
    else
        local enemyLook = enemy.Root.CFrame.LookVector
        local lookH = Vector3.new(enemyLook.X, 0, enemyLook.Z)
        if lookH.Magnitude > 0.01 then lookH = lookH.Unit end
        from = enemy.Root.Position - lookH * 3
    end

    local dir = targetPart.Position - from
    if dir.Magnitude < 0.01 then return end
    dir = dir.Unit

    local targetPitch = math.asin(math.clamp(dir.Y, -1, 1))
    local targetYaw   = math.atan2(-dir.X, -dir.Z)

    if CONFIG.AIM_SMOOTHING > 0 then
        local alpha = math.clamp(dt / CONFIG.AIM_SMOOTHING, 0, 1)
        local dYaw = targetYaw - aimYaw
        if dYaw > math.pi then dYaw = dYaw - 2*math.pi
        elseif dYaw < -math.pi then dYaw = dYaw + 2*math.pi end
        aimYaw = aimYaw + dYaw * alpha
        aimPitch = aimPitch + (targetPitch - aimPitch) * alpha
    else
        aimPitch = targetPitch
        aimYaw   = targetYaw
    end

    applyCameraRotation(aimPitch, aimYaw)
end)

-- ============================================================
-- ANA DÖNGÜ (VOID kısmı aynı, ATTACK kısmı güçlendirildi)
-- ============================================================
MainTrove:Connect(RunService.Heartbeat, function()
    local now    = tick()
    local lpRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not lpRoot then return end

    -- YENİ: Shooting range'de saldırı yok (sadece void spam)
    if isShootingRange() then
        voidSpam(lpRoot, lpRoot.Position)
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then updateEnemyTracker(plr) end
    end

    local f = localFighter()
    if not f then return end

    local item = f.EquippedItem
    if not isMeleeItem(item) then
        if now - lastEquip > 0.6 then
            lastEquip = now
            tryEquipMelee()
        end
        voidSpam(lpRoot, lpRoot.Position)
        return
    end

    local isKnife = tostring(item.Name or "") == "Knife"
    local cooldownReady
    if isKnife then cooldownReady = now >= nextKnifeReadyAt
    else cooldownReady = now >= nextMeleeReadyAt end

    -- ===== VOID (DEĞİŞMEDİ) =====
    if state == "VOID" then
        local enemy = getClosestEnemy()
        local center = lpRoot.Position
        local predState = nil
        if enemy then
            predState = getPredictedState(enemy.Player)
            center = predState.Position
        end

        voidSpam(lpRoot, center)

        if enemy and cooldownReady and predState then
            if canAttackNow(predState) then
                currentEnemy = enemy
                firedThisAtk = false
                state        = "ATTACK"
                stateEndsAt  = now + CONFIG.ATTACK_DURATION
                cycleCount   = cycleCount + 1
                if CONFIG.DEBUG then
                    print(string.format("[#%d] STRIKE -> %s (v=%.1f, conf=%.2f, tPred=%.3f)",
                        cycleCount, enemy.Player.Name,
                        predState.Speed, predState.Confidence, predState.PredictionTime))
                end
            end
        end
        return
    end

    -- ===== ATTACK (GÜÇLENDİRİLDİ) =====
    if state == "ATTACK" then
        -- YENİ: Kapsamlı target validasyonu
        local invalid = currentEnemy == nil
            or currentEnemy.Root.Parent == nil
            or currentEnemy.Player.Character ~= currentEnemy.Char
            or not canAttack(currentEnemy.Player)

        if now >= stateEndsAt or invalid then
            if CONFIG.DEBUG and invalid then
                print(string.format("[#%d] CANCELLED (target invalid)", cycleCount))
            end
            state       = "VOID"
            stateEndsAt = now + CONFIG.VOID_DURATION
            voidSpam(lpRoot, lpRoot.Position)
            return
        end

        if not firedThisAtk then
            -- YENİ: Fire öncesi son doğrulamalar
            local predState = getPredictedState(currentEnemy.Player)

            if not canAttackNow(predState) then
                -- Hedef kaçmış/hızlanmış -> iptal
                if CONFIG.DEBUG then print(string.format("[#%d] CANCEL (speed %.1f)", cycleCount, predState.Speed)) end
                state = "VOID"
                stateEndsAt = now + CONFIG.VOID_DURATION
                return
            end

            if isNearOtherMatch(predState.RealPosition, currentEnemy.Player) then
                if CONFIG.DEBUG then print(string.format("[#%d] CANCEL (other match nearby)", cycleCount)) end
                state = "VOID"
                stateEndsAt = now + CONFIG.VOID_DURATION
                return
            end

            local hum = lpRoot.Parent and lpRoot.Parent:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end

            local shieldFront = isKnife and hasRiotShield(currentEnemy)

            local tpPos = computeTPPosFromState(predState, isKnife, shieldFront)
            fastSetCF(lpRoot, CFrame.lookAt(tpPos, predState.Position))
            lastGroundPos = lpRoot.Position

            local targetPart = currentEnemy.Char:FindFirstChild("HitboxBody")
                or currentEnemy.Char:FindFirstChild("HitboxHead")
                or currentEnemy.Char:FindFirstChild("Head")
                or currentEnemy.Root

            -- YENİ: targetPart geçerlilik kontrolü
            if not targetPart or not targetPart.Parent then
                state = "VOID"
                stateEndsAt = now + CONFIG.VOID_DURATION
                return
            end

            local payload, fireType = buildPayload(predState.CFrame, targetPart, isKnife)
            local oid = itemField(item, "ObjectID")
            if oid then
                local ok = pcall(function() UseItem:FireServer(oid, fireType, payload, nil) end)
                if ok then
                    successCount = successCount + 1
                    if isKnife then nextKnifeReadyAt = now + CONFIG.KNIFE_COOLDOWN
                    else            nextMeleeReadyAt = now + CONFIG.MELEE_COOLDOWN end
                end
                if CONFIG.DEBUG then
                    print(string.format("[#%d] FIRE ok=%s (total=%d, TP=%.1f studs back)",
                        cycleCount, tostring(ok), successCount, CONFIG.TP_BACK))
                end
            end
            firedThisAtk = true
        end
        return
    end
end)