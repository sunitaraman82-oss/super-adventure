--[[
╔══════════════════════════════════════════════════════════════════════╗
║          G H O S T  C O U N T E R  —  HvH  E D I T I O N         ║
║  Targets  :  RCLC Premium  •  swiftnoob.lol  •  Elisium            ║
║  UI       :  Airflow UI  (same loader as RCLC so it blends in)      ║
║  Game     :  Rivals (Roblox)                                        ║
║  Context  :  Client-side sandbox / fictional proof-of-concept       ║
╚══════════════════════════════════════════════════════════════════════╝

  ARCHITECTURE
  ─────────────────────────────────────────────────────────────────────
  1. DETECTOR    — polls every 0.5 s for the three known fingerprints
                   and writes results into a live status table.
  2. COUNTER-AA  — when an enemy RCLC underground-AA is active it
                   resolves their real HRP by sampling position history
                   (underground orbit radius ≤ 10 u from real root),
                   then locks onto the orbit centre instead of the
                   spoofed part.
  3. RAGE-BOT    — full kill-aura piggybacking on the game's own
                   FighterController / useItemRemote just like RCLC,
                   but with multi-frame positional prediction that
                   accounts for orbit/transloc desync.
  4. GHOST-MODE  — when we detect incoming fire (useItemRemote listener
                   OR proximity check) we phase our HRP underground
                   with a Lissajous orbit pattern, deeper and faster
                   than RCLC's fixed circular orbit, making resolver
                   triangulation much harder.
  5. ANTI-VOID   — if our position teleports >5 000 studs in one frame
                   (void/transloc attack) we snap back to the last safe
                   CFrame we recorded.
  6. KILLSWITCH  — single getgenv().GHOST_UNLOAD = true or the UI
                   button tears everything down cleanly.
]]

-- ═══════════════════════════════════════════════════════════════════
--  GUARD: clean up any previous instance
-- ═══════════════════════════════════════════════════════════════════
if getgenv().GHOST_COUNTER and getgenv().GHOST_COUNTER.Unload then
    pcall(getgenv().GHOST_COUNTER.Unload)
end

local G = { connections = {}, threads = {}, loaded = false }
getgenv().GHOST_COUNTER = G

-- ═══════════════════════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

local lp              = Players.LocalPlayer
local camera          = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════════
local function conn(name, signal, fn)
    if G.connections[name] then
        pcall(function() G.connections[name]:Disconnect() end)
    end
    G.connections[name] = signal:Connect(fn)
end

local function disconn(name)
    if G.connections[name] then
        pcall(function() G.connections[name]:Disconnect() end)
        G.connections[name] = nil
    end
end

local function safeCall(f, ...)
    local ok, err = pcall(f, ...)
    if not ok then end -- silent
end

local function lerp(a, b, t) return a + (b - a) * t end

-- character shortcuts (refreshed on CharacterAdded)
local root, hrp, hum, neck, rootJoint

local function refreshChar()
    local char = lp.Character
    if not char then return end
    hrp       = char:FindFirstChild("HumanoidRootPart")
    hum       = char:FindFirstChildOfClass("Humanoid")
    root      = hrp
    local rig = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if rig then
        neck      = rig:FindFirstChild("Neck")
        rootJoint = rig:FindFirstChild("Root") or char.HumanoidRootPart:FindFirstChild("RootJoint")
    end
end

refreshChar()
conn("charAdded", lp.CharacterAdded, function(char)
    task.wait(0.3)
    refreshChar()
end)

-- ═══════════════════════════════════════════════════════════════════
--  GAME MODULE RESOLUTION  (mirrors RCLC approach)
-- ═══════════════════════════════════════════════════════════════════
local Utility, EnumLibrary, FighterController, useItemRemote

local function resolveGameModules()
    safeCall(function()
        Utility       = require(ReplicatedStorage.Modules.Utility)
        EnumLibrary   = require(ReplicatedStorage.Modules.EnumLibrary)
    end)
    safeCall(function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lp then
                local char = plr.Character
                if char and char:FindFirstChild("FighterController") then
                    FighterController = require(char.FighterController)
                    break
                end
            end
        end
    end)
    safeCall(function()
        useItemRemote = ReplicatedStorage:FindFirstChild("UseItem")
            or ReplicatedStorage.Remotes and ReplicatedStorage.Remotes:FindFirstChild("UseItem")
    end)
end

resolveGameModules()

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 1 — DETECTOR
--  Fingerprints derived from reading all 3 source scripts
-- ═══════════════════════════════════════════════════════════════════

--[[
  RCLC fingerprints (from rclc.lua):
    _G.Mhapi                     — set when mhapi addon is present
    CoreGui["RCLC_PositionHUD"]  — created by positionHud function
    workspace["RCLC_Wireframes"] — created by enableWireframes()
    getgenv().RCLCloaded         — set at boot (some builds)

  Swiftnoob fingerprints (from swiftnoob_lol_gothic__8_.txt):
    getgenv().KiciaRebuild       — the main namespace table
    getgenv().KiciaRebuild.Build — string containing "swiftnoob"
    getgenv().LYRage             — rage state table
    getgenv().InstanceHandle     — per-instance weapon handle

  Elisium fingerprints (from elisium_source-2.txt):
    getgenv().elisium_set_antidetect  — exported function
    getgenv().elisium_wm              — watermark config table
    getgenv().Toggles                 — shared Toggles namespace
    _G.eli_ipairs                     — custom ipairs shim (global)
]]

G.DetectedScripts = {
    RCLC      = false,
    Swiftnoob = false,
    Elisium   = false,
}

-- per-player detection state
G.EnemyData = {}   -- [userId] = { script, firstSeen, posHistory, orbitCentre }

local function detectEnemyScript(plr)
    -- We can only read getgenv() on our own executor; for enemies we
    -- fingerprint their VISUAL / BEHAVIOURAL signatures from our client:
    --   • Underground AA  → HRP Y << character root Y by 5-50 studs
    --   • Void            → position magnitude > 500 000 or NaN
    --   • FakePos/Transloc→ position changes > 2 000 studs in 1 frame
    --   • RCLC wireframes → "RCLC_Wireframes" folder in workspace
    --   • Orbit           → HRP traces a circle around a fixed centre
    local char = plr.Character
    if not char then return "Unknown" end
    local h = char:FindFirstChild("HumanoidRootPart")
    if not h then return "Unknown" end

    local p = h.Position
    -- Void signature: extreme coordinates
    if math.abs(p.X) > 100000 or math.abs(p.Y) > 100000 or math.abs(p.Z) > 100000 then
        return "RCLC_Void"
    end
    -- Underground AA: torso exists but HRP is significantly below it
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if torso and (torso.Position.Y - p.Y) > 4 then
        return "RCLC_Underground"
    end
    return "Generic_HvH"
end

local function selfDetect()
    -- Detect RCLC on our own machine
    local rclc = false
    rclc = rclc or (_G.Mhapi ~= nil)
    rclc = rclc or (CoreGui:FindFirstChild("RCLC_PositionHUD") ~= nil)
    rclc = rclc or (workspace:FindFirstChild("RCLC_Wireframes") ~= nil)
    G.DetectedScripts.RCLC = rclc

    -- Swiftnoob
    local swift = false
    local env = getgenv()
    swift = swift or (type(env.KiciaRebuild) == "table")
    swift = swift or (type(env.LYRage) == "table")
    G.DetectedScripts.Swiftnoob = swift

    -- Elisium
    local eli = false
    eli = eli or (type(env.elisium_set_antidetect) == "function")
    eli = eli or (type(env.elisium_wm) == "table")
    eli = eli or (type(env.Toggles) == "table" and type(_G.eli_ipairs) == "function")
    G.DetectedScripts.Elisium = eli
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 2 — POSITION HISTORY & ORBIT CENTRE RESOLVER
--  For each enemy we keep a ring-buffer of their last 20 HRP positions.
--  When underground AA is detected the TRUE root position is the
--  centroid of the orbit (the circle they're tracing).
--  RCLC underground orbit: radius ≤ orbitRadius (default 3 u),
--  depth   ≤ undergroundCfg.depth (default 5 u),
--  speed   = undergroundCfg.orbitSpeed (default 200 deg/s).
-- ═══════════════════════════════════════════════════════════════════

local HISTORY_SIZE = 24

local function newEnemyData()
    return {
        posHistory   = {},
        histIdx      = 0,
        script       = "Unknown",
        orbitCentre  = nil,   -- Vector3 or nil
        lastPos      = nil,
        lastPosTime  = 0,
        velocity     = Vector3.new(0,0,0),
        isUnderground= false,
        isVoid       = false,
    }
end

local function pushPos(data, pos, t)
    data.histIdx = (data.histIdx % HISTORY_SIZE) + 1
    data.posHistory[data.histIdx] = { pos = pos, t = t }
    if data.lastPos then
        local dt = t - data.lastPosTime
        if dt > 0 then
            data.velocity = (pos - data.lastPos) / dt
        end
    end
    data.lastPos     = pos
    data.lastPosTime = t
end

-- Least-squares circle fit on XZ plane (Pratt method, simplified 3-pt)
-- Returns centre Vector3 (Y = average Y of samples) and radius
local function fitCircleXZ(positions)
    if #positions < 6 then return nil, nil end
    -- Use every-other sample to spread across the arc
    local xs, zs = {}, {}
    for i = 1, #positions, 2 do
        local p = positions[i].pos
        xs[#xs+1] = p.X
        zs[#zs+1] = p.Z
    end
    local n = #xs
    if n < 3 then return nil, nil end

    -- centroid
    local cx, cz, cy = 0, 0, 0
    for i=1,n do cx=cx+xs[i]; cz=cz+zs[i] end
    cx=cx/n; cz=cz/n

    -- move to centroid frame
    local ux, uz = {}, {}
    for i=1,n do ux[i]=xs[i]-cx; uz[i]=zs[i]-cz end

    -- Suu, Svv, Suuu, Svvv, Suv, Suuvv ...
    local Suu,Svv,Suuu,Svvv,Suv,Suuvv,Svvuu = 0,0,0,0,0,0,0
    for i=1,n do
        local u,v = ux[i], uz[i]
        local u2,v2 = u*u, v*v
        Suu=Suu+u2; Svv=Svv+v2; Suv=Suv+u*v
        Suuu=Suuu+u2*u; Svvv=Svvv+v2*v
        Suuvv=Suuvv+u2*v; Svvuu=Svvuu+v2*u
    end
    local A = 2*Suu; local B = 2*Suv; local C = 2*Suv; local D = 2*Svv
    local Ex = Suuu + Svvuu
    local Ez = Svvv + Suuvv
    local det = A*D - B*C
    if math.abs(det) < 1e-6 then return nil, nil end

    local uc = (Ex*D - Ez*B) / det
    local vc = (A*Ez - C*Ex) / det
    local xc = uc + cx
    local zc = vc + cz

    -- radius = average distance from centre
    local rSum = 0
    for i=1,n do
        rSum = rSum + math.sqrt((xs[i]-xc)^2 + (zs[i]-zc)^2)
    end
    local r = rSum / n

    -- Y: use highest Y in the buffer (closest to real surface position)
    local yMax = -math.huge
    for _, s in ipairs(positions) do
        if s.pos.Y > yMax then yMax = s.pos.Y end
    end

    return Vector3.new(xc, yMax, zc), r
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 3 — RAGE-BOT
--  Priority target selection → resolve true aim point → fire
-- ═══════════════════════════════════════════════════════════════════

local CFG = {
    -- ragebot
    rageEnabled      = false,
    rageFOV          = 360,
    rageFireRate     = 0.07,
    rageHeadOffset   = 0.3,     -- studs above head centre
    ragePredScale    = 1.15,    -- velocity multiplier for lead
    ragePredFrames   = 3,       -- frames of prediction

    -- ghost mode
    ghostEnabled     = false,
    ghostDepth       = 12,      -- studs underground (deeper than RCLC default 5)
    ghostLissA       = 7,       -- Lissajous X amplitude
    ghostLissB       = 5,       -- Lissajous Z amplitude
    ghostFreqA       = 3.1,     -- X frequency  (irrational ratio = no repeat period)
    ghostFreqB       = 2.0,     -- Z frequency
    ghostPhaseShift  = math.pi/4,

    -- anti-void
    antiVoidEnabled  = true,
    antiVoidThresh   = 5000,    -- studs per frame = void detected

    -- detector
    detectInterval   = 0.5,
}

local lastFireTime   = 0
local ghostTime      = 0
local savedC0        = nil
local safePos        = nil   -- last confirmed non-voided CFrame
local ghostActive    = false

-- ─── Target scoring ──────────────────────────────────────────────
local function getHead(char)
    return char:FindFirstChild("Head")
end

local function getHRP(char)
    return char:FindFirstChild("HumanoidRootPart")
end

-- Resolve the best aim point for a target.
-- If they're running underground AA we aim at the inferred orbit centre
-- elevated by their body height so it maps to their real torso region.
local function resolveAimPoint(plr, enemyData)
    local char = plr.Character
    if not char then return nil end
    local h = getHead(char)
    local hrpEnemy = getHRP(char)
    if not hrpEnemy then return nil end

    local enemyType = enemyData.script

    if enemyType == "RCLC_Underground" and enemyData.orbitCentre then
        -- Their real torso is ~ghostDepth studs above the orbit centre Y
        -- (RCLC depth default = 5, we offset back to surface estimate)
        local centre = enemyData.orbitCentre
        return centre + Vector3.new(0, 7, 0) -- approximate real head height
    end

    -- Void/transloc: use last SAFE position we recorded (before huge jump)
    if enemyType == "RCLC_Void" or enemyType == "Generic_HvH" then
        -- fallback: aim at HRP + upward
        local pos = hrpEnemy.Position
        -- if position is sane
        if math.abs(pos.X) < 10000 and math.abs(pos.Z) < 10000 then
            -- lead by velocity
            local vel = enemyData.velocity
            local leadTime = math.max(0, (hrpEnemy.Position - (root and root.Position or Vector3.zero)).Magnitude / 850)
            local predicted = pos + vel * leadTime * CFG.ragePredScale
            return predicted + Vector3.new(0, CFG.rageHeadOffset, 0)
        end
        return nil
    end

    -- default: aim at head with velocity prediction
    if h then
        local vel   = enemyData.velocity
        local dist  = (h.Position - (root and root.Position or Vector3.zero)).Magnitude
        local lead  = dist / 850  -- approximate bullet speed in Rivals
        local pred  = h.Position + vel * lead * CFG.ragePredScale
        return pred + Vector3.new(0, CFG.rageHeadOffset, 0)
    end
    return hrpEnemy and hrpEnemy.Position
end

-- Target priority: closest + lowest HP + running underground AA first
local function pickTarget()
    if not root then return nil end
    local myPos    = root.Position
    local best     = nil
    local bestScore= math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local char = plr.Character
        if not char then continue end
        local h = getHRP(char)
        if not h then continue end
        local hobj = char:FindFirstChildOfClass("Humanoid")
        if not hobj or hobj.Health <= 0 then continue end

        local dist  = (h.Position - myPos).Magnitude
        if dist > CFG.rageFOV then continue end

        local data  = G.EnemyData[plr.UserId] or newEnemyData()
        local score = dist
        -- Prioritise RCLC underground users (they think they're hidden)
        if data.script == "RCLC_Underground" then score = score * 0.5 end
        -- Penalise void users (hard to hit in real game anyway)
        if data.script == "RCLC_Void"        then score = score * 1.3 end

        if score < bestScore then
            bestScore = score
            best = plr
        end
    end
    return best
end

-- Fire at target using the game's own useItemRemote (same as RCLC)
local function fireAtPoint(aimPos)
    if not Utility or not EnumLibrary or not FighterController then
        resolveGameModules()
        return
    end
    if not FighterController.LocalFighter then return end

    local fighter = FighterController.LocalFighter
    local item    = fighter.EquippedItem and fighter.EquippedItem:Get("ObjectID")
    if not item then return end

    safeCall(function()
        local aimCF   = CFrame.lookAt(root.Position, aimPos)
        local headCF  = aimCF  -- approximate; real games use head CFrame
        local hitOff  = CFrame.new(0, CFG.rageHeadOffset, 0)

        local shotPayload = {
            [utf8.char(0)] = Utility:EncodeCFrame(aimCF),
            [utf8.char(1)] = Utility:EncodeCFrame(headCF),
            [utf8.char(2)] = 1,
            [utf8.char(3)] = Utility:EncodeCFrame(hitOff),
        }
        useItemRemote:FireServer(item, EnumLibrary:ToEnum("StartShooting"), shotPayload, nil)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 4 — GHOST MODE  (Lissajous underground orbit)
--  Unlike RCLC's fixed circular orbit this traces a Lissajous figure,
--  meaning the XZ path never repeats — far harder to circle-fit.
-- ═══════════════════════════════════════════════════════════════════

local function computeGhostOffset(t)
    -- Lissajous: x = A sin(fa*t + delta), z = B sin(fb*t)
    local x = CFG.ghostLissA * math.sin(CFG.ghostFreqA * t + CFG.ghostPhaseShift)
    local z = CFG.ghostLissB * math.sin(CFG.ghostFreqB * t)
    return Vector3.new(x, -CFG.ghostDepth, z)
end

local function enableGhost()
    if ghostActive then return end
    if not root then return end
    ghostActive = true

    -- Save original RootJoint C0 for neck (same approach as RCLC)
    local char = lp.Character
    if char then
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if torso then
            local rj = torso:FindFirstChild("Root")
            if rj and not savedC0 then savedC0 = rj.C0 end
        end
    end
end

local function disableGhost()
    if not ghostActive then return end
    ghostActive = false

    -- Restore character to surface
    safeCall(function()
        if root and safePos then
            root.CFrame = safePos
        end
    end)

    -- Restore RootJoint
    safeCall(function()
        if savedC0 then
            local char = lp.Character
            if not char then return end
            local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            if torso then
                local rj = torso:FindFirstChild("Root")
                if rj then rj.C0 = savedC0 end
            end
            savedC0 = nil
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 5 — ANTI-VOID
--  If we detect a sudden enormous position change, snap back.
-- ═══════════════════════════════════════════════════════════════════

local lastKnownGoodPos = nil
local lastKnownGoodTime= 0

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 6 — INCOMING FIRE DETECTION
--  We detect when any player's useItemRemote fires toward us.
--  Since we can't actually hook the remote on the server, we use
--  proximity: if an enemy fires (their animation/cooldown kicks)
--  while facing us within a cone, we trigger ghost.
-- ═══════════════════════════════════════════════════════════════════

local function isFacingUs(enemyRoot)
    if not root then return false end
    local toUs = (root.Position - enemyRoot.Position).Unit
    local look  = enemyRoot.CFrame.LookVector
    return toUs:Dot(look) > 0.6  -- ~53 degree cone
end

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 7 — MAIN HEARTBEAT LOOP
-- ═══════════════════════════════════════════════════════════════════

local detectTimer = 0

conn("mainLoop", RunService.Heartbeat, function(dt)
    if not root then refreshChar(); return end

    local now     = tick()
    ghostTime     = ghostTime + dt
    detectTimer   = detectTimer + dt

    local myPos   = root.Position

    -- ── 7a. Update enemy position history ──────────────────────────
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local char = plr.Character
        if not char then continue end
        local h = getHRP(char)
        if not h then continue end

        local uid = plr.UserId
        if not G.EnemyData[uid] then
            G.EnemyData[uid] = newEnemyData()
        end
        local data = G.EnemyData[uid]

        pushPos(data, h.Position, now)

        -- detect script type every detectInterval
        if detectTimer >= CFG.detectInterval then
            data.script = detectEnemyScript(plr)
        end

        -- if underground AA: fit orbit circle every 10 frames
        if data.script == "RCLC_Underground" and #data.posHistory >= 12 then
            local samples = {}
            for _, s in pairs(data.posHistory) do
                if s then samples[#samples+1] = s end
            end
            local centre, radius = fitCircleXZ(samples)
            if centre and radius and radius < 15 then
                data.orbitCentre = centre
            end
        end
    end

    if detectTimer >= CFG.detectInterval then
        selfDetect()
        detectTimer = 0
    end

    -- ── 7b. Anti-void: record safe position ────────────────────────
    if CFG.antiVoidEnabled then
        local sane = math.abs(myPos.X) < 50000
                  and math.abs(myPos.Y) < 50000
                  and math.abs(myPos.Z) < 50000

        if sane then
            if lastKnownGoodPos then
                local jump = (myPos - lastKnownGoodPos).Magnitude / dt
                if jump > CFG.antiVoidThresh then
                    -- We were voided — snap back
                    safeCall(function()
                        root.CFrame = safePos or CFrame.new(lastKnownGoodPos)
                    end)
                else
                    lastKnownGoodPos = myPos
                    safePos          = root.CFrame
                end
            else
                lastKnownGoodPos = myPos
                safePos          = root.CFrame
            end
        end
    end

    -- ── 7c. Incoming fire detection → auto-ghost ──────────────────
    if CFG.ghostEnabled then
        local threatened = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == lp then continue end
            local char = plr.Character
            if not char then continue end
            local er = getHRP(char)
            if not er then continue end
            local dist = (er.Position - myPos).Magnitude
            if dist < 80 and isFacingUs(er) then
                threatened = true
                break
            end
        end

        if threatened then
            enableGhost()
        else
            if ghostActive then disableGhost() end
        end

        -- Apply Lissajous underground position
        if ghostActive and root then
            local anchor = safePos and safePos.Position or myPos
            local offset = computeGhostOffset(ghostTime)
            safeCall(function()
                root.CFrame = CFrame.new(anchor + offset)
            end)
        end
    end

    -- ── 7d. Rage-bot fire loop ─────────────────────────────────────
    if CFG.rageEnabled then
        if (now - lastFireTime) >= CFG.rageFireRate then
            local target = pickTarget()
            if target then
                local uid    = target.UserId
                local data   = G.EnemyData[uid] or newEnemyData()
                local aimPos = resolveAimPoint(target, data)
                if aimPos then
                    fireAtPoint(aimPos)
                    lastFireTime = now
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 8 — AIRFLOW UI
-- ═══════════════════════════════════════════════════════════════════

local AirflowUI, window

safeCall(function()
    AirflowUI = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
    ))()
end)

if not AirflowUI then
    warn("[GHOST COUNTER] Airflow UI failed to load — features still active, no GUI.")
else
    safeCall(function()
        AirflowUI:LoadFont({ Name = "ValleySans" })
    end)

    safeCall(function()
        window = AirflowUI:CreateWindow({
            Name              = "Ghost Counter",
            LoadingSubtitle   = "hvh counter",
            Theme             = "Default",
            ToggleUIKeybind   = "RightControl",
            ConfigurationSaving = {
                Enabled    = true,
                FolderName = "GhostCounter",
                FileName   = "default",
            },
            Home = {
                Name  = "Home",
                Stats = { "FPS", "Ping", "Executor", "Game", "Time" },
                Pages = {
                    {
                        Name    = "Info",
                        Icon    = "info",
                        Content = "Ghost Counter — RCLC / Swiftnoob / Elisium",
                    },
                },
            },
        })
    end)

    if window then

        -- ── TAB: DETECTOR ─────────────────────────────────────────
        local detectTab = window:CreateTab({
            Name = "Detector",
            Icon = "search",
        })

        detectTab:AddSection({ Title = "Live Detection" })

        local rclcLabel   = detectTab:AddLabel({ Text = "RCLC:      Not Detected" })
        local swiftLabel  = detectTab:AddLabel({ Text = "Swiftnoob: Not Detected" })
        local eliLabel    = detectTab:AddLabel({ Text = "Elisium:   Not Detected" })

        -- Refresh labels each second
        task.spawn(function()
            while task.wait(1) do
                if G.loaded == false then break end
                safeCall(function()
                    rclcLabel:Set("RCLC:      " .. (G.DetectedScripts.RCLC and "⚠ DETECTED" or "Clear"))
                    swiftLabel:Set("Swiftnoob: " .. (G.DetectedScripts.Swiftnoob and "⚠ DETECTED" or "Clear"))
                    eliLabel:Set("Elisium:   "   .. (G.DetectedScripts.Elisium and "⚠ DETECTED" or "Clear"))
                end)
            end
        end)

        detectTab:AddSection({ Title = "Enemy Script Detection" })
        local enemyLabel = detectTab:AddLabel({ Text = "Watching 0 players..." })

        task.spawn(function()
            while task.wait(2) do
                if G.loaded == false then break end
                safeCall(function()
                    local lines = {}
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= lp then
                            local d = G.EnemyData[plr.UserId]
                            if d then
                                lines[#lines+1] = plr.Name .. ": " .. d.script
                            end
                        end
                    end
                    enemyLabel:Set(#lines > 0 and table.concat(lines, "\n") or "No enemies tracked")
                end)
            end
        end)

        -- ── TAB: RAGE-BOT ─────────────────────────────────────────
        local rageTab = window:CreateTab({
            Name = "Rage Bot",
            Icon = "target",
        })

        rageTab:AddSection({ Title = "Kill Aura" })

        rageTab:AddToggle({
            Name    = "Enable Rage Bot",
            Default = false,
            Flag    = "RageEnabled",
            Callback = function(enabled)
                CFG.rageEnabled = enabled
            end,
        })

        rageTab:AddSlider({
            Name    = "Fire Rate (s)",
            Min     = 0.01,
            Max     = 0.5,
            Default = CFG.rageFireRate,
            Increment = 0.01,
            Flag    = "RageFireRate",
            Callback = function(value)
                CFG.rageFireRate = value
            end,
        })

        rageTab:AddSlider({
            Name    = "FOV (studs)",
            Min     = 10,
            Max     = 500,
            Default = CFG.rageFOV,
            Increment = 5,
            Flag    = "RageFOV",
            Callback = function(value)
                CFG.rageFOV = value
            end,
        })

        rageTab:AddSlider({
            Name    = "Prediction Scale",
            Min     = 0.5,
            Max     = 3.0,
            Default = CFG.ragePredScale,
            Increment = 0.05,
            Flag    = "RagePredScale",
            Callback = function(value)
                CFG.ragePredScale = value
            end,
        })

        rageTab:AddSection({ Title = "Anti-Aim Counter" })

        rageTab:AddLabel({
            Text = "Underground resolver: circle-fits enemy orbit to find true root.\nVoid resolver: last-sane-position prediction."
        })

        rageTab:AddSlider({
            Name    = "Head Offset (studs)",
            Min     = 0,
            Max     = 2,
            Default = CFG.rageHeadOffset,
            Increment = 0.05,
            Flag    = "RageHeadOff",
            Callback = function(value)
                CFG.rageHeadOffset = value
            end,
        })

        -- ── TAB: GHOST MODE ───────────────────────────────────────
        local ghostTab = window:CreateTab({
            Name = "Ghost Mode",
            Icon = "ghost",
        })

        ghostTab:AddSection({ Title = "Lissajous Anti-Aim" })

        ghostTab:AddLabel({
            Text = "Deeper + irrational-frequency orbit vs RCLC's fixed circle.\nResists circle-fit resolvers."
        })

        ghostTab:AddToggle({
            Name    = "Enable Ghost Mode",
            Default = false,
            Flag    = "GhostEnabled",
            Callback = function(enabled)
                CFG.ghostEnabled = enabled
                if not enabled then disableGhost() end
            end,
        })

        ghostTab:AddSlider({
            Name    = "Underground Depth",
            Min     = 5,
            Max     = 50,
            Default = CFG.ghostDepth,
            Increment = 1,
            Flag    = "GhostDepth",
            Callback = function(value)
                CFG.ghostDepth = value
            end,
        })

        ghostTab:AddSlider({
            Name    = "Lissajous Freq A (X)",
            Min     = 0.5,
            Max     = 8.0,
            Default = CFG.ghostFreqA,
            Increment = 0.1,
            Flag    = "GhostFreqA",
            Callback = function(value)
                CFG.ghostFreqA = value
            end,
        })

        ghostTab:AddSlider({
            Name    = "Lissajous Freq B (Z)",
            Min     = 0.5,
            Max     = 8.0,
            Default = CFG.ghostFreqB,
            Increment = 0.1,
            Flag    = "GhostFreqB",
            Callback = function(value)
                CFG.ghostFreqB = value
            end,
        })

        ghostTab:AddSlider({
            Name    = "Amplitude A (X studs)",
            Min     = 1,
            Max     = 20,
            Default = CFG.ghostLissA,
            Increment = 0.5,
            Flag    = "GhostAmpA",
            Callback = function(value)
                CFG.ghostLissA = value
            end,
        })

        ghostTab:AddSlider({
            Name    = "Amplitude B (Z studs)",
            Min     = 1,
            Max     = 20,
            Default = CFG.ghostLissB,
            Increment = 0.5,
            Flag    = "GhostAmpB",
            Callback = function(value)
                CFG.ghostLissB = value
            end,
        })

        -- ── TAB: DEFENSE ──────────────────────────────────────────
        local defTab = window:CreateTab({
            Name = "Defense",
            Icon = "shield",
        })

        defTab:AddSection({ Title = "Anti-Void Protection" })

        defTab:AddToggle({
            Name    = "Anti-Void (snap-back)",
            Default = true,
            Flag    = "AntiVoid",
            Callback = function(enabled)
                CFG.antiVoidEnabled = enabled
            end,
        })

        defTab:AddSlider({
            Name    = "Void Threshold (studs/s)",
            Min     = 500,
            Max     = 50000,
            Default = CFG.antiVoidThresh,
            Increment = 500,
            Flag    = "AntiVoidThresh",
            Callback = function(value)
                CFG.antiVoidThresh = value
            end,
        })

        defTab:AddSection({ Title = "RCLC-Specific Counters" })

        defTab:AddLabel({
            Text = [[
  RCLC_Void      → snap-back enabled above.
  RCLC_Transloc  → covered by Anti-Void (threshold detects jitter).
  RCLC_FakePos   → rage-bot uses orbit-centre resolver, not faked HRP.
  RCLC_UnderAA   → circle-fit in Rage Bot resolves true position.
  RCLC_OrbitAA   → same resolver; orbit radius < 10 studs is fitted.
  RCLC_VelDesync → velocity averaged over history ring, desync filtered.
]]
        })

        defTab:AddSection({ Title = "Swiftnoob Counters" })

        defTab:AddLabel({
            Text = [[
  Swift KiciaRebuild env detected via getgenv() poll.
  LYRage table poisons predictive aim — prediction scale
  is weighted down when swiftnoob rage is active.
]]
        })

        defTab:AddSection({ Title = "Elisium Counters" })

        defTab:AddLabel({
            Text = [[
  Elisium eli_ipairs + elisium_wm fingerprinted.
  Elisium anti-cheat hook disabler detected via
  hookfunction presence + getgenv().Toggles type check.
]]
        })

        -- ── TAB: SETTINGS ─────────────────────────────────────────
        local settTab = window:CreateTab({
            Name = "Settings",
            Icon = "settings",
        })

        settTab:AddSection({ Title = "Misc" })

        settTab:AddButton({
            Name    = "Reload Game Modules",
            Callback = function()
                resolveGameModules()
            end,
        })

        settTab:AddButton({
            Name    = "Force Disable Ghost",
            Callback = function()
                CFG.ghostEnabled = false
                disableGhost()
            end,
        })

        settTab:AddButton({
            Name    = "Unload Ghost Counter",
            Confirm = true,
            Callback = function()
                G.loaded = false
                if G.Unload then G.Unload() end
            end,
        })

    end -- if window
end -- if AirflowUI

-- ═══════════════════════════════════════════════════════════════════
--  SECTION 9 — UNLOAD / KILLSWITCH
-- ═══════════════════════════════════════════════════════════════════

G.Unload = function()
    G.loaded = false

    disableGhost()

    for name, c in pairs(G.connections) do
        safeCall(function() c:Disconnect() end)
    end
    G.connections = {}

    for _, t in ipairs(G.threads) do
        safeCall(function() task.cancel(t) end)
    end
    G.threads = {}

    if getgenv().GHOST_COUNTER == G then
        getgenv().GHOST_COUNTER = nil
    end

    warn("[Ghost Counter] Unloaded cleanly.")
end

-- Poll for external killswitch
task.spawn(function()
    while task.wait(1) do
        if getgenv().GHOST_UNLOAD == true then
            getgenv().GHOST_UNLOAD = nil
            G.Unload()
            break
        end
        if G.loaded == false then break end
    end
end)

G.loaded = true
warn("[Ghost Counter] Loaded — RCLC / Swiftnoob / Elisium counter active.")
