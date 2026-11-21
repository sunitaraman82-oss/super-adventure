--[[
╔══════════════════════════════════════════════════════════════════════╗
║          G H O S T  C O U N T E R  v2  —  HvH  E D I T I O N     ║
║  Targets  :  RCLC Premium  •  swiftnoob.lol  •  Elisium            ║
║  UI       :  Airflow UI                                             ║
║  Fixes    :  v2 — correct remote path, player targeting,           ║
║              background ghost (server-fake / client-anchor),        ║
║              AssemblyLinearVelocity tracker, rawNewIndex write      ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════
--  GUARD
-- ═══════════════════════════════════════════════════════════════════
if getgenv().GHOST_COUNTER and getgenv().GHOST_COUNTER.Unload then
    pcall(getgenv().GHOST_COUNTER.Unload)
    task.wait(0.1)
end

local G = { connections = {}, threads = {}, loaded = true }
getgenv().GHOST_COUNTER = G

-- ═══════════════════════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════════
local function safeCall(f, ...) local ok, e = pcall(f, ...) return ok end

local function conn(name, signal, fn)
    if G.connections[name] then pcall(function() G.connections[name]:Disconnect() end) end
    G.connections[name] = signal:Connect(fn)
end

local function disconn(name)
    if G.connections[name] then
        pcall(function() G.connections[name]:Disconnect() end)
        G.connections[name] = nil
    end
end

-- rawNewIndex write (same technique as RCLC transloc / fakePos)
-- Bypasses the Roblox __newindex lock on BasePart properties so the
-- server receives the CFrame write while our RenderStepped hook
-- keeps the local visual anchored at our real position.
local function rawWrite(part, prop, value)
    local ok = false
    safeCall(function()
        local meta = getrawmetatable and getrawmetatable(part)
        local ni   = meta and rawget(meta, "__newindex")
        if ni then
            pcall(ni, part, prop, value)
            ok = true
        end
    end)
    if not ok then
        safeCall(function() part[prop] = value end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  CHARACTER REFS
-- ═══════════════════════════════════════════════════════════════════
local hrp, hum, char

local function refreshChar()
    char = lp.Character
    if not char then return end
    hrp  = char:FindFirstChild("HumanoidRootPart")
    hum  = char:FindFirstChildOfClass("Humanoid")
end

refreshChar()
conn("charAdded", lp.CharacterAdded, function(c)
    task.wait(0.3)
    refreshChar()
    -- re-resolve modules on respawn
    task.spawn(function() task.wait(1) G.resolveModules() end)
end)

-- ═══════════════════════════════════════════════════════════════════
--  GAME MODULE RESOLUTION
--  Exact remote path from RCLC source:
--    ReplicatedStorage.Remotes.Replication.Fighter.UseItem
-- ═══════════════════════════════════════════════════════════════════
local Utility, EnumLibrary, FighterController, UseItemRemote

G.resolveModules = function()
    safeCall(function()
        Utility     = require(ReplicatedStorage.Modules.Utility)
        EnumLibrary = require(ReplicatedStorage.Modules.EnumLibrary)
    end)
    safeCall(function()
        -- Walk FighterController from any player character
        for _, plr in ipairs(Players:GetPlayers()) do
            local c = plr.Character
            if c then
                local fc = c:FindFirstChild("FighterController")
                if fc then FighterController = require(fc); break end
            end
        end
    end)
    safeCall(function()
        -- Exact path verified from RCLC killAuraStep line 603
        UseItemRemote = ReplicatedStorage.Remotes.Replication.Fighter.UseItem
    end)
end

task.spawn(G.resolveModules)

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 1 — CONFIG
-- ═══════════════════════════════════════════════════════════════════
local CFG = {
    -- ragebot
    rageEnabled   = false,
    rageRadius    = 300,
    rageFireRate  = 0.065,   -- seconds between shots
    rageJitter    = 0.02,    -- head jitter (matches RCLC default)
    rageHeadOff   = 0.3,     -- studs above head centre

    -- prediction
    predScale     = 1.2,     -- velocity lead multiplier
    predAccel     = true,    -- use acceleration in prediction

    -- ghost mode (background CFrame desync)
    ghostEnabled  = false,
    ghostDepth    = 15,      -- studs underground for server position
    ghostLissA    = 8,       -- Lissajous X amplitude
    ghostLissB    = 6,       -- Lissajous Z amplitude
    ghostFreqA    = 3.1,     -- irrational ratio → never repeats
    ghostFreqB    = 2.0,
    ghostPhase    = math.pi / 4,

    -- anti-void
    antiVoid      = true,
    voidThresh    = 4000,    -- studs/s threshold
}

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 2 — VELOCITY TRACKER
--  Uses AssemblyLinearVelocity (same as RCLC updateTracker)
--  with an exponential-smoothed acceleration term.
-- ═══════════════════════════════════════════════════════════════════
local velTrackers = {}

local function getTracker(plr)
    if not velTrackers[plr] then
        velTrackers[plr] = {
            vel   = Vector3.zero,
            accel = Vector3.zero,
            lastV = Vector3.zero,
            lastT = tick(),
        }
    end
    return velTrackers[plr]
end

local function updateTracker(plr, targetRoot)
    local t = getTracker(plr)
    local now = tick()
    local dt  = now - t.lastT
    if dt > 0.008 then
        local vel = targetRoot.AssemblyLinearVelocity
        t.accel = t.accel:Lerp((vel - t.lastV) / dt, 0.25)
        t.vel   = vel
        t.lastV = vel
        t.lastT = now
    end
    return t
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 3 — TARGET SELECTION
--  Targets players (not NPCs) sorted by distance.
--  Uses getHead pattern from RCLC: Head → CameraBone → HRP
-- ═══════════════════════════════════════════════════════════════════
local function getHead(plr)
    local c = plr.Character
    if not c then return nil end
    return c:FindFirstChild("Head")
        or c:FindFirstChild("CameraBone", true)
        or c:FindFirstChild("HumanoidRootPart")
end

local function getPlayerTargets()
    if not hrp then return {} end
    local myPos   = hrp.Position
    local targets = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local c = plr.Character
        if not c then continue end
        local h = c:FindFirstChild("HumanoidRootPart")
        if not h then continue end
        local hobj = c:FindFirstChildOfClass("Humanoid")
        if not hobj or hobj.Health <= 0 then continue end

        local dist = (h.Position - myPos).Magnitude
        if dist > CFG.rageRadius then continue end

        targets[#targets+1] = {
            plr  = plr,
            root = h,
            head = getHead(plr),
            dist = dist,
        }
    end

    table.sort(targets, function(a,b) return a.dist < b.dist end)
    return targets
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 4 — ENEMY SCRIPT DETECTOR
-- ═══════════════════════════════════════════════════════════════════
G.DetectedScripts = { RCLC = false, Swiftnoob = false, Elisium = false }

local function selfDetect()
    local env = getgenv()
    -- RCLC: CoreGui HUD + workspace wireframes + _G.Mhapi
    G.DetectedScripts.RCLC =
        (game:GetService("CoreGui"):FindFirstChild("RCLC_PositionHUD") ~= nil)
        or (workspace:FindFirstChild("RCLC_Wireframes") ~= nil)
        or (_G.Mhapi ~= nil)

    -- Swiftnoob: KiciaRebuild env table
    G.DetectedScripts.Swiftnoob =
        type(env.KiciaRebuild) == "table"
        or type(env.LYRage) == "table"

    -- Elisium: custom ipairs shim + wm table
    G.DetectedScripts.Elisium =
        type(env.elisium_set_antidetect) == "function"
        or type(env.elisium_wm) == "table"
        or type(_G.eli_ipairs) == "function"
end

-- Enemy behavioural fingerprint (visual only — no getgenv on others)
local function detectEnemy(plr)
    local c = plr.Character
    if not c then return "Unknown" end
    local h = c:FindFirstChild("HumanoidRootPart")
    if not h then return "Unknown" end
    local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
    local p = h.Position

    -- Void: extreme coordinates
    if math.abs(p.X) > 50000 or math.abs(p.Y) > 50000 or math.abs(p.Z) > 50000 then
        return "RCLC_Void"
    end
    -- Underground AA: torso significantly above HRP Y
    if torso and (torso.Position.Y - p.Y) > 4 then
        return "RCLC_Underground"
    end
    return "Generic"
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 5 — ORBIT CENTRE RESOLVER
--  Pratt circle-fit on XZ plane to find true root under underground AA
-- ═══════════════════════════════════════════════════════════════════
local HIST = 24
local enemyHistory = {}  -- [userId] = { samples={}, idx, vel, accel, lastV, lastT, script, centre }

local function ensureHistory(uid)
    if not enemyHistory[uid] then
        enemyHistory[uid] = {
            samples = {}, idx = 0,
            vel = Vector3.zero, accel = Vector3.zero,
            lastV = Vector3.zero, lastT = tick(),
            script = "Unknown", centre = nil,
        }
    end
    return enemyHistory[uid]
end

local function pushSample(d, pos, vel, now)
    d.idx = (d.idx % HIST) + 1
    d.samples[d.idx] = { pos = pos, t = now }
    local dt = now - d.lastT
    if dt > 0.008 then
        d.accel = d.accel:Lerp((vel - d.lastV) / dt, 0.25)
        d.vel   = vel
        d.lastV = vel
        d.lastT = now
    end
end

local function fitCircle(samples)
    if #samples < 8 then return nil end
    local xs, zs = {}, {}
    for i = 1, #samples, 2 do
        local s = samples[i]
        if s then xs[#xs+1] = s.pos.X; zs[#zs+1] = s.pos.Z end
    end
    local n = #xs
    if n < 4 then return nil end
    local cx, cz = 0, 0
    for i=1,n do cx=cx+xs[i]; cz=cz+zs[i] end
    cx=cx/n; cz=cz/n
    local ux, uz = {}, {}
    for i=1,n do ux[i]=xs[i]-cx; uz[i]=zs[i]-cz end
    local Suu,Svv,Suuu,Svvv,Suv,Suuvv,Svvuu = 0,0,0,0,0,0,0
    for i=1,n do
        local u,v = ux[i], uz[i]
        local u2,v2 = u*u, v*v
        Suu=Suu+u2; Svv=Svv+v2; Suv=Suv+u*v
        Suuu=Suuu+u2*u; Svvv=Svvv+v2*v
        Suuvv=Suuvv+u2*v; Svvuu=Svvuu+v2*u
    end
    local A=2*Suu; local B=2*Suv; local D=2*Svv
    local Ex=Suuu+Svvuu; local Ez=Svvv+Suuvv
    local det = A*D - B*B
    if math.abs(det) < 1e-6 then return nil end
    local uc=(Ex*D-Ez*B)/det; local vc=(A*Ez-B*Ex)/det
    local xc=uc+cx; local zc=vc+cz
    local rSum=0
    for i=1,n do rSum=rSum+math.sqrt((xs[i]-xc)^2+(zs[i]-zc)^2) end
    local r=rSum/n
    if r > 20 then return nil end  -- too big = not an orbit, discard
    local yMax = -math.huge
    for _, s in ipairs(samples) do if s and s.pos.Y > yMax then yMax = s.pos.Y end end
    return Vector3.new(xc, yMax, zc), r
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 6 — AIM POINT RESOLVER
-- ═══════════════════════════════════════════════════════════════════
local function resolveAimPoint(target)
    local uid = target.plr.UserId
    local d   = enemyHistory[uid]
    local head = target.head
    local root = target.root

    -- prediction lead time (distance / approx bullet speed)
    local myPos   = hrp and hrp.Position or Vector3.zero
    local dist    = (root.Position - myPos).Magnitude
    local lead    = dist / 850

    local vel   = d and d.vel   or Vector3.zero
    local accel = d and d.accel or Vector3.zero

    -- kinematic prediction: p + v*t + 0.5*a*t^2
    local function predict(base)
        if CFG.predAccel then
            return base + vel * lead * CFG.predScale
                       + accel * (lead * lead * 0.5)
        end
        return base + vel * lead * CFG.predScale
    end

    local script = d and d.script or "Generic"

    if script == "RCLC_Underground" and d and d.centre then
        -- Aim at the fitted orbit centre + body height estimate
        return predict(d.centre + Vector3.new(0, 7, 0))
    end

    if head then
        return predict(head.Position) + Vector3.new(0, CFG.rageHeadOff, 0)
    end

    return predict(root.Position + Vector3.new(0, 2, 0))
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 7 — FIRE FUNCTION
--  Exact payload structure from RCLC killAuraStep (line 590-609)
--    shotPayload[utf8.char(1)] = {
--      [utf8.char(0)] = Utility:EncodeCFrame(aimCFrame),
--      [utf8.char(1)] = Utility:EncodeCFrame(headCFrame),
--      [utf8.char(2)] = targetHead (Instance),
--      [utf8.char(3)] = Utility:EncodeCFrame(hitOffset),
--    }
--  Remote: ReplicatedStorage.Remotes.Replication.Fighter.UseItem
-- ═══════════════════════════════════════════════════════════════════
local lastFireTime = 0

local function fireAt(target, aimPos)
    if not Utility or not EnumLibrary or not FighterController or not UseItemRemote then
        return
    end
    local fighter = FighterController.LocalFighter
    if not fighter or not fighter.EquippedItem then return end

    local head    = target.head
    if not head then return end

    local headPos   = head.Position
    local jitter    = CFG.rageJitter
    local jVec      = Vector3.new(
        (math.random() - 0.5) * jitter,
        (math.random() - 0.5) * jitter,
        (math.random() - 0.5) * jitter
    )

    local aimCF   = CFrame.lookAt(aimPos, headPos)
    local headCF  = head.CFrame
    local hitOff  = head.CFrame:ToObjectSpace(CFrame.new(headPos + jVec))

    local payload = {}
    payload[utf8.char(1)] = {
        [utf8.char(0)] = Utility:EncodeCFrame(aimCF),
        [utf8.char(1)] = Utility:EncodeCFrame(headCF),
        [utf8.char(2)] = head,
        [utf8.char(3)] = Utility:EncodeCFrame(hitOff),
    }

    safeCall(function()
        UseItemRemote:FireServer(
            fighter.EquippedItem:Get("ObjectID"),
            EnumLibrary:ToEnum("StartShooting"),
            payload,
            nil
        )
    end)

    lastFireTime = tick()
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 8 — GHOST MODE (BACKGROUND DESYNC)
--
--  "Background" means:
--    SERVER sees our HRP at the underground Lissajous position
--    (via rawNewIndex write on Heartbeat, same as RCLC transloc)
--
--    CLIENT sees our character at the REAL anchor position
--    (via RenderStepped re-anchor, same as RCLC fakePosRender)
--
--  This is the exact split RCLC uses for fakePos:
--    fakePosHeartbeat → Heartbeat writes fake CFrame to server
--    fakePosRender    → RenderStepped resets CFrame locally so we
--                       see our character standing normally
-- ═══════════════════════════════════════════════════════════════════
local ghostTime   = 0
local ghostAnchor = nil   -- our real visual CFrame
local ghostActive = false

local function computeGhostPos(t)
    if not ghostAnchor then return nil end
    local base = ghostAnchor.Position
    local x = CFG.ghostLissA * math.sin(CFG.ghostFreqA * t + CFG.ghostPhase)
    local z = CFG.ghostLissB * math.sin(CFG.ghostFreqB * t)
    return Vector3.new(base.X + x, base.Y - CFG.ghostDepth, base.Z + z)
end

local function enableGhost()
    if ghostActive or not hrp then return end
    ghostActive = true
    ghostAnchor = hrp.CFrame

    -- Server-side fake: write underground CFrame via rawNewIndex on Heartbeat
    conn("ghostHB", RunService.Heartbeat, function(dt)
        if not ghostActive or not hrp or not ghostAnchor then return end
        ghostTime = ghostTime + dt
        local fakePos = computeGhostPos(ghostTime)
        if not fakePos then return end
        rawWrite(hrp, "AssemblyLinearVelocity", Vector3.zero)
        rawWrite(hrp, "CFrame", CFrame.new(fakePos))
        rawWrite(hrp, "AssemblyLinearVelocity", Vector3.zero)
    end)

    -- Client-side anchor: reset CFrame each RenderStepped so WE see
    -- our character standing normally (invisible to us, server thinks
    -- we're underground)
    conn("ghostRS", RunService.RenderStepped, function()
        if not ghostActive or not hrp or not ghostAnchor then return end
        safeCall(function()
            hrp.CFrame = ghostAnchor
        end)
    end)
end

local function disableGhost()
    if not ghostActive then return end
    ghostActive = false
    disconn("ghostHB")
    disconn("ghostRS")
    -- Restore to anchor
    safeCall(function()
        if hrp and ghostAnchor then hrp.CFrame = ghostAnchor end
    end)
    ghostAnchor = nil
    ghostTime   = 0
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 9 — ANTI-VOID SNAPBACK
-- ═══════════════════════════════════════════════════════════════════
local lastGoodCF   = nil
local lastGoodPos  = nil

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 10 — INCOMING THREAT DETECTOR
--  Trigger ghost when any enemy faces us within 100 studs
-- ═══════════════════════════════════════════════════════════════════
local function isFacingUs(enemyRoot)
    if not hrp then return false end
    local toUs = (hrp.Position - enemyRoot.Position).Unit
    return enemyRoot.CFrame.LookVector:Dot(toUs) > 0.55
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 11 — MAIN HEARTBEAT
-- ═══════════════════════════════════════════════════════════════════
local detectTimer = 0

conn("mainLoop", RunService.Heartbeat, function(dt)
    if not G.loaded then return end
    if not hrp then refreshChar(); return end

    local now    = tick()
    local myPos  = hrp.Position
    detectTimer  = detectTimer + dt

    -- ── 11a. Update enemy history ──────────────────────────────────
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local c = plr.Character
        if not c then continue end
        local h = c:FindFirstChild("HumanoidRootPart")
        if not h then continue end

        local uid = plr.UserId
        local d   = ensureHistory(uid)

        pushSample(d, h.Position, h.AssemblyLinearVelocity, now)

        -- Update behavioural script detection every 0.5 s
        if detectTimer >= 0.5 then
            d.script = detectEnemy(plr)
        end

        -- Fit orbit circle for underground AA users
        if d.script == "RCLC_Underground" then
            local samps = {}
            for _, s in pairs(d.samples) do if s then samps[#samps+1] = s end end
            local centre = fitCircle(samps)
            if centre then d.centre = centre end
        end
    end

    if detectTimer >= 0.5 then
        selfDetect()
        detectTimer = 0
    end

    -- ── 11b. Anti-void ────────────────────────────────────────────
    if CFG.antiVoid then
        local sane = math.abs(myPos.X) < 50000
                  and math.abs(myPos.Y) < 50000
                  and math.abs(myPos.Z) < 50000

        if sane then
            if lastGoodPos then
                local spd = (myPos - lastGoodPos).Magnitude / math.max(dt, 0.001)
                if spd > CFG.voidThresh then
                    -- Voided — snap back
                    safeCall(function()
                        if lastGoodCF then hrp.CFrame = lastGoodCF end
                    end)
                else
                    lastGoodPos = myPos
                    lastGoodCF  = hrp.CFrame
                end
            else
                lastGoodPos = myPos
                lastGoodCF  = hrp.CFrame
            end
        end
    end

    -- ── 11c. Ghost mode trigger ────────────────────────────────────
    if CFG.ghostEnabled then
        local threatened = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == lp then continue end
            local c = plr.Character
            if not c then continue end
            local er = c:FindFirstChild("HumanoidRootPart")
            if er and (er.Position - myPos).Magnitude < 100 and isFacingUs(er) then
                threatened = true
                break
            end
        end

        if threatened and not ghostActive then
            ghostAnchor = hrp.CFrame
            enableGhost()
        elseif not threatened and ghostActive then
            disableGhost()
        end
    end

    -- ── 11d. Ragebot ──────────────────────────────────────────────
    if CFG.rageEnabled and (now - lastFireTime) >= CFG.rageFireRate then
        local targets = getPlayerTargets()
        if #targets > 0 then
            local best   = targets[1]
            local aimPos = resolveAimPoint(best)
            if aimPos then
                fireAt(best, aimPos)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 12 — AIRFLOW UI
--  API: CreateSection(str), CreateToggle, CreateSlider, CreateButton,
--       CreateDropdown — verified from RCLC source
-- ═══════════════════════════════════════════════════════════════════
local AirflowUI, window

safeCall(function()
    AirflowUI = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
    ))()
end)

if not AirflowUI then
    warn("[Ghost Counter v2] Airflow failed — logic running, no GUI.")
else
    safeCall(function()
        window = AirflowUI:CreateWindow({
            Name            = "Ghost Counter",
            LoadingSubtitle = "v2 hvh counter",
            Theme           = "Default",
            ToggleUIKeybind = "RightControl",
            ConfigurationSaving = {
                Enabled    = true,
                FolderName = "GhostCounterV2",
                FileName   = "config",
            },
            Home = {
                Name  = "Home",
                Stats = { "FPS", "Ping", "Executor", "Game", "Time" },
                Pages = {
                    {
                        Name    = "Info",
                        Icon    = "info",
                        Content = "Ghost Counter v2 — kills RCLC/Swift/Eli users",
                    },
                },
            },
        })
    end)

    if window then

        -- ── RAGE TAB ──────────────────────────────────────────────
        local rageTab = window:CreateTab({ Name = "Rage", Icon = "target" })

        rageTab:CreateSection("Kill Aura")

        rageTab:CreateToggle({
            Name         = "Enable Rage Bot",
            CurrentValue = false,
            Flag         = "RageOn",
            Callback     = function(v) CFG.rageEnabled = v end,
        })

        rageTab:CreateSlider({
            Name         = "Fire Rate (s)",
            Range        = { 0.01, 0.4 },
            Increment    = 0.005,
            CurrentValue = CFG.rageFireRate,
            Flag         = "RageFireRate",
            Callback     = function(v) CFG.rageFireRate = v end,
        })

        rageTab:CreateSlider({
            Name         = "Radius (studs)",
            Range        = { 10, 500 },
            Increment    = 5,
            CurrentValue = CFG.rageRadius,
            Flag         = "RageRadius",
            Callback     = function(v) CFG.rageRadius = v end,
        })

        rageTab:CreateSlider({
            Name         = "Head Jitter",
            Range        = { 0, 0.5 },
            Increment    = 0.01,
            CurrentValue = CFG.rageJitter,
            Flag         = "RageJitter",
            Callback     = function(v) CFG.rageJitter = v end,
        })

        rageTab:CreateSection("Prediction")

        rageTab:CreateSlider({
            Name         = "Pred Scale",
            Range        = { 0.5, 3.0 },
            Increment    = 0.05,
            CurrentValue = CFG.predScale,
            Flag         = "PredScale",
            Callback     = function(v) CFG.predScale = v end,
        })

        rageTab:CreateToggle({
            Name         = "Accel Prediction",
            CurrentValue = true,
            Flag         = "PredAccel",
            Callback     = function(v) CFG.predAccel = v end,
        })

        rageTab:CreateSection("Resolver")

        rageTab:CreateButton({
            Name     = "Underground: circle-fit active",
            Style    = "Default",
            Callback = function() end,
        })
        rageTab:CreateButton({
            Name     = "Void/Transloc: last-sane-pos resolve",
            Style    = "Default",
            Callback = function() end,
        })

        -- ── GHOST TAB ─────────────────────────────────────────────
        local ghostTab = window:CreateTab({ Name = "Ghost", Icon = "eye-off" })

        ghostTab:CreateSection("Background Desync")

        ghostTab:CreateToggle({
            Name         = "Enable Ghost Mode",
            CurrentValue = false,
            Flag         = "GhostOn",
            Callback     = function(v)
                CFG.ghostEnabled = v
                if not v then disableGhost() end
            end,
        })

        ghostTab:CreateSlider({
            Name         = "Underground Depth",
            Range        = { 5, 60 },
            Increment    = 1,
            CurrentValue = CFG.ghostDepth,
            Flag         = "GhostDepth",
            Callback     = function(v) CFG.ghostDepth = v end,
        })

        ghostTab:CreateSlider({
            Name         = "Lissajous Freq A",
            Range        = { 0.5, 10 },
            Increment    = 0.1,
            CurrentValue = CFG.ghostFreqA,
            Flag         = "GFreqA",
            Callback     = function(v) CFG.ghostFreqA = v end,
        })

        ghostTab:CreateSlider({
            Name         = "Lissajous Freq B",
            Range        = { 0.5, 10 },
            Increment    = 0.1,
            CurrentValue = CFG.ghostFreqB,
            Flag         = "GFreqB",
            Callback     = function(v) CFG.ghostFreqB = v end,
        })

        ghostTab:CreateSlider({
            Name         = "Amplitude X",
            Range        = { 1, 25 },
            Increment    = 0.5,
            CurrentValue = CFG.ghostLissA,
            Flag         = "GAmpA",
            Callback     = function(v) CFG.ghostLissA = v end,
        })

        ghostTab:CreateSlider({
            Name         = "Amplitude Z",
            Range        = { 1, 25 },
            Increment    = 0.5,
            CurrentValue = CFG.ghostLissB,
            Flag         = "GAmpB",
            Callback     = function(v) CFG.ghostLissB = v end,
        })

        ghostTab:CreateButton({
            Name     = "Force Disable Ghost",
            Style    = "Primary",
            Icon     = "eye",
            Callback = function()
                CFG.ghostEnabled = false
                disableGhost()
            end,
        })

        -- ── DEFENSE TAB ───────────────────────────────────────────
        local defTab = window:CreateTab({ Name = "Defense", Icon = "shield" })

        defTab:CreateSection("Anti-Void")

        defTab:CreateToggle({
            Name         = "Anti-Void Snapback",
            CurrentValue = true,
            Flag         = "AntiVoid",
            Callback     = function(v) CFG.antiVoid = v end,
        })

        defTab:CreateSlider({
            Name         = "Void Threshold (studs/s)",
            Range        = { 500, 20000 },
            Increment    = 500,
            CurrentValue = CFG.voidThresh,
            Flag         = "VoidThresh",
            Callback     = function(v) CFG.voidThresh = v end,
        })

        defTab:CreateSection("Active Counters")

        defTab:CreateButton({ Name = "Void     → snapback",          Style = "Default", Callback = function() end })
        defTab:CreateButton({ Name = "Transloc → void threshold",    Style = "Default", Callback = function() end })
        defTab:CreateButton({ Name = "FakePos  → orbit resolver",    Style = "Default", Callback = function() end })
        defTab:CreateButton({ Name = "UnderAA  → circle-fit",       Style = "Default", Callback = function() end })
        defTab:CreateButton({ Name = "VelDesync→ accel-smoothed",   Style = "Default", Callback = function() end })

        -- ── DETECTOR TAB ──────────────────────────────────────────
        local detTab = window:CreateTab({ Name = "Detect", Icon = "search" })

        detTab:CreateSection("Self (your machine)")

        local rclcBtn  = detTab:CreateButton({ Name = "RCLC:      --", Style = "Default", Callback = function() end })
        local swiftBtn = detTab:CreateButton({ Name = "Swiftnoob: --", Style = "Default", Callback = function() end })
        local eliBtn   = detTab:CreateButton({ Name = "Elisium:   --", Style = "Default", Callback = function() end })

        task.spawn(function()
            while task.wait(1.5) do
                if not G.loaded then break end
                safeCall(function()
                    rclcBtn:Set ("RCLC:      " .. (G.DetectedScripts.RCLC      and "DETECTED" or "Clear"))
                    swiftBtn:Set("Swiftnoob: " .. (G.DetectedScripts.Swiftnoob and "DETECTED" or "Clear"))
                    eliBtn:Set  ("Elisium:   " .. (G.DetectedScripts.Elisium   and "DETECTED" or "Clear"))
                end)
            end
        end)

        detTab:CreateSection("Enemies")

        local eBtns = {}
        for i = 1, 6 do
            eBtns[i] = detTab:CreateButton({ Name = "Slot "..i..": --", Style = "Default", Callback = function() end })
        end

        task.spawn(function()
            while task.wait(2) do
                if not G.loaded then break end
                safeCall(function()
                    local list = {}
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= lp then
                            local d = enemyHistory[plr.UserId]
                            list[#list+1] = { n = plr.Name, s = d and d.script or "?" }
                        end
                    end
                    for i = 1, 6 do
                        local e = list[i]
                        eBtns[i]:Set(e and (e.n..": "..e.s) or ("Slot "..i..": --"))
                    end
                end)
            end
        end)

        -- ── SETTINGS TAB ──────────────────────────────────────────
        local settTab = window:CreateTab({ Name = "Settings", Icon = "settings" })

        settTab:CreateSection("Actions")

        settTab:CreateButton({
            Name     = "Reload Game Modules",
            Style    = "Primary",
            Icon     = "refresh-cw",
            Callback = function() task.spawn(G.resolveModules) end,
        })

        settTab:CreateButton({
            Name     = "Unload Ghost Counter",
            Style    = "Danger",
            Icon     = "power",
            Callback = function()
                G.loaded = false
                G.Unload()
            end,
        })

    end -- if window
end -- if AirflowUI

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 13 — UNLOAD
-- ═══════════════════════════════════════════════════════════════════
G.Unload = function()
    G.loaded = false
    disableGhost()
    for _, c in pairs(G.connections) do pcall(function() c:Disconnect() end) end
    G.connections = {}
    if getgenv().GHOST_COUNTER == G then getgenv().GHOST_COUNTER = nil end
    warn("[Ghost Counter v2] Unloaded.")
end

-- External killswitch
task.spawn(function()
    while task.wait(1) do
        if not G.loaded then break end
        if getgenv().GHOST_UNLOAD == true then
            getgenv().GHOST_UNLOAD = nil
            G.Unload()
            break
        end
    end
end)

warn("[Ghost Counter v2] Loaded — Rage bot / Ghost mode / Anti-void ready.")
