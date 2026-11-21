--!nocheck
-- ============================================================
--  KICIA COUNTER  -  STANDALONE
--  Extracted from kicia_rebuild_with_counters_final.lua
--  Works in any executor (Delta, Synapse, etc.)
--  Modes: UE Counter | Kicia Counter | Solix Counter
--  Right-click the HUD label to open the settings panel
-- ============================================================

-- guard: must run via executor
if not getgenv then
    warn("[KiciaCounter] FATAL: run via executor, not as LocalScript")
    return
end

-- kill previous instance if re-injecting
if getgenv()._KiciaCounterCleanup then
    pcall(getgenv()._KiciaCounterCleanup)
end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local lp         = Players.LocalPlayer
if not lp then warn("[KiciaCounter] no LocalPlayer"); return end

-- ----------------------------------------------------------------
-- CONFIG  (live-edited by the panel)
-- ----------------------------------------------------------------
local CFG = {
    enabled   = false,
    mode      = "UE",   -- "UE" | "KICIA" | "SOLIX"
    showHud   = true,
    -- UE
    cooldown  = 0.18,
    yDistance = 500,
    -- KICIA / SOLIX
    cycleMs   = 50,
    flyMs     = 25,
    boost     = 100000,
    boostMs   = 600,
    flySpeed  = 15000,
    zigAmp    = 400,
    zigFreq   = 8,
    depth     = 6,
    radius    = 30,
}

-- ----------------------------------------------------------------
-- GUI parent  (gethui preferred, CoreGui fallback)
-- ----------------------------------------------------------------
local guiParent
do
    local ok, h = pcall(function()
        local fn = getgenv().gethui or gethui
        return fn and fn()
    end)
    guiParent = (ok and h) or game:GetService("CoreGui")
end

-- ----------------------------------------------------------------
-- HUD  (draggable watermark)
-- ----------------------------------------------------------------
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "KiciaCounterHUD"
hudGui.ResetOnSpawn   = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.DisplayOrder   = 999
hudGui.Parent         = guiParent

local hudFrame = Instance.new("Frame", hudGui)
hudFrame.Size             = UDim2.new(0, 230, 0, 22)
hudFrame.Position         = UDim2.new(0, 8, 0, 8)
hudFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
hudFrame.BorderSizePixel  = 0
Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 4)

local hudAccent = Instance.new("Frame", hudFrame)
hudAccent.Size             = UDim2.new(0, 3, 1, 0)
hudAccent.BackgroundColor3 = Color3.fromRGB(100, 60, 220)
hudAccent.BorderSizePixel  = 0
Instance.new("UICorner", hudAccent).CornerRadius = UDim.new(0, 4)

local hudLabel = Instance.new("TextLabel", hudFrame)
hudLabel.Size                 = UDim2.new(1, -8, 1, 0)
hudLabel.Position             = UDim2.new(0, 8, 0, 0)
hudLabel.BackgroundTransparency = 1
hudLabel.Font                 = Enum.Font.GothamBold
hudLabel.TextSize             = 11
hudLabel.TextColor3           = Color3.fromRGB(220, 210, 255)
hudLabel.TextXAlignment       = Enum.TextXAlignment.Left
hudLabel.Text                 = "KICIA COUNTER | OFF"

-- HUD drag
do
    local dragging, dragStart, startPos = false
    hudFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = i.Position; startPos = hudFrame.Position
        end
    end)
    hudFrame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            hudFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ----------------------------------------------------------------
-- PANEL  (settings window, right-click HUD to open)
-- ----------------------------------------------------------------
local panelGui = Instance.new("ScreenGui")
panelGui.Name           = "KiciaCounterPanel"
panelGui.ResetOnSpawn   = false
panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
panelGui.DisplayOrder   = 1000
panelGui.Parent         = guiParent

local panel = Instance.new("Frame", panelGui)
panel.Size             = UDim2.new(0, 260, 0, 500)
panel.Position         = UDim2.new(0, 8, 0, 36)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
panel.BorderSizePixel  = 0
panel.Visible          = false
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)

local pAccent = Instance.new("Frame", panel)
pAccent.Size             = UDim2.new(1, 0, 0, 2)
pAccent.BackgroundColor3 = Color3.fromRGB(100, 60, 220)
pAccent.BorderSizePixel  = 0

local titleBar = Instance.new("Frame", panel)
titleBar.Size             = UDim2.new(1, 0, 0, 28)
titleBar.Position         = UDim2.new(0, 0, 0, 2)
titleBar.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
titleBar.BorderSizePixel  = 0

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size                 = UDim2.new(1, -36, 1, 0)
titleLbl.Position             = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font                 = Enum.Font.GothamBold
titleLbl.TextSize             = 12
titleLbl.TextColor3           = Color3.fromRGB(200, 185, 255)
titleLbl.TextXAlignment       = Enum.TextXAlignment.Left
titleLbl.Text                 = "⚡ KICIA COUNTER"

-- TAP / click HUD to toggle panel (mobile touch + PC left click both work)
local lastTap = 0
hudFrame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.MouseButton2 then
        local now = tick()
        -- debounce 0.2s so drag doesn't flicker the panel
        if now - lastTap > 0.2 then
            lastTap = now
            panel.Visible = not panel.Visible
        end
    end
end)

-- panel drag
do
    local dragging, dragStart, startPos = false
    titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = i.Position; startPos = panel.Position
        end
    end)
    titleBar.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local scroll = Instance.new("ScrollingFrame", panel)
scroll.Size                   = UDim2.new(1, 0, 1, -32)
scroll.Position               = UDim2.new(0, 0, 0, 30)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel        = 0
scroll.ScrollBarThickness     = 3
scroll.ScrollBarImageColor3   = Color3.fromRGB(100, 60, 220)
scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y

local layout = Instance.new("UIListLayout", scroll)
layout.Padding   = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local pad = Instance.new("UIPadding", scroll)
pad.PaddingLeft  = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop   = UDim.new(0, 6)

-- ----------------------------------------------------------------
-- UI builder helpers
-- ----------------------------------------------------------------
local function makeLabel(parent, text, order)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size                  = UDim2.new(1, 0, 0, 14)
    lbl.BackgroundTransparency = 1
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 10
    lbl.TextColor3            = Color3.fromRGB(130, 110, 180)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left
    lbl.Text                  = text:upper()
    lbl.LayoutOrder           = order or 0
    return lbl
end

local function makeToggle(parent, label, default, order, callback)
    local row = Instance.new("Frame", parent)
    row.Size             = UDim2.new(1, 0, 0, 28)
    row.BackgroundColor3 = Color3.fromRGB(22, 20, 32)
    row.BorderSizePixel  = 0
    row.LayoutOrder      = order or 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size                  = UDim2.new(1, -44, 1, 0)
    lbl.Position              = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextSize              = 11
    lbl.TextColor3            = Color3.fromRGB(210, 200, 240)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left
    lbl.Text                  = label

    local state = default
    local knobBg = Instance.new("Frame", row)
    knobBg.Size             = UDim2.new(0, 34, 0, 16)
    knobBg.Position         = UDim2.new(1, -42, 0.5, -8)
    knobBg.BackgroundColor3 = state and Color3.fromRGB(100, 60, 220) or Color3.fromRGB(50, 45, 65)
    knobBg.BorderSizePixel  = 0
    Instance.new("UICorner", knobBg).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", knobBg)
    knob.Size             = UDim2.new(0, 12, 0, 12)
    knob.Position         = state and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function setState(v)
        state = v
        knobBg.BackgroundColor3 = v and Color3.fromRGB(100, 60, 220) or Color3.fromRGB(50, 45, 65)
        knob.Position = v and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
        if callback then callback(v) end
    end

    row.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then setState(not state) end
    end)
    return row, setState
end

local function makeSlider(parent, label, min, max, default, rounding, order, callback)
    local row = Instance.new("Frame", parent)
    row.Size             = UDim2.new(1, 0, 0, 44)
    row.BackgroundColor3 = Color3.fromRGB(22, 20, 32)
    row.BorderSizePixel  = 0
    row.LayoutOrder      = order or 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size                  = UDim2.new(1, -8, 0, 20)
    lbl.Position              = UDim2.new(0, 8, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextSize              = 11
    lbl.TextColor3            = Color3.fromRGB(210, 200, 240)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    local track = Instance.new("Frame", row)
    track.Size             = UDim2.new(1, -16, 0, 6)
    track.Position         = UDim2.new(0, 8, 0, 30)
    track.BackgroundColor3 = Color3.fromRGB(40, 36, 55)
    track.BorderSizePixel  = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    fill.Size             = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(100, 60, 220)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local function setVal(v)
        v = math.clamp(v, min, max)
        v = math.floor(v / (10^-rounding) + 0.5) / (10^-rounding)
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        lbl.Text  = label .. ":  " .. tostring(v)
        if callback then callback(v) end
    end
    setVal(default)

    local dragging = false
    local function onInput(i)
        local abs = track.AbsolutePosition
        local sz  = track.AbsoluteSize
        local pct = math.clamp((i.Position.X - abs.X) / sz.X, 0, 1)
        setVal(min + (max - min) * pct)
    end
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; onInput(i) end
    end)
    track.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then onInput(i) end
    end)
    return row
end

local function makeDropdown(parent, label, options, default, order, callback)
    local row = Instance.new("Frame", parent)
    row.Size              = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3  = Color3.fromRGB(22, 20, 32)
    row.BorderSizePixel   = 0
    row.LayoutOrder       = order or 0
    row.ClipsDescendants  = true
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size                  = UDim2.new(1, -8, 0, 18)
    lbl.Position              = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 10
    lbl.TextColor3            = Color3.fromRGB(130, 110, 180)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left
    lbl.Text                  = label:upper()

    local selected, open = default, false

    local btn = Instance.new("TextButton", row)
    btn.Size             = UDim2.new(1, -16, 0, 22)
    btn.Position         = UDim2.new(0, 8, 0, 24)
    btn.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
    btn.BorderSizePixel  = 0
    btn.Font             = Enum.Font.Gotham
    btn.TextSize         = 11
    btn.TextColor3       = Color3.fromRGB(220, 210, 255)
    btn.Text             = selected .. "  ▾"
    btn.AutoButtonColor  = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local listFrame = Instance.new("Frame", row)
    listFrame.Size             = UDim2.new(1, -16, 0, #options * 24)
    listFrame.Position         = UDim2.new(0, 8, 0, 48)
    listFrame.BackgroundColor3 = Color3.fromRGB(28, 24, 42)
    listFrame.BorderSizePixel  = 0
    listFrame.Visible          = false
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 4)
    local ll = Instance.new("UIListLayout", listFrame)
    ll.SortOrder = Enum.SortOrder.LayoutOrder

    for i, opt in ipairs(options) do
        local ob = Instance.new("TextButton", listFrame)
        ob.Size                  = UDim2.new(1, 0, 0, 24)
        ob.BackgroundTransparency = 1
        ob.Font                  = Enum.Font.Gotham
        ob.TextSize              = 11
        ob.TextColor3            = Color3.fromRGB(200, 190, 230)
        ob.Text                  = opt
        ob.LayoutOrder           = i
        ob.MouseButton1Click:Connect(function()
            selected = opt
            btn.Text = selected .. "  ▾"
            open = false; listFrame.Visible = false
            row.Size = UDim2.new(1, 0, 0, 52)
            if callback then callback(opt) end
        end)
    end

    btn.MouseButton1Click:Connect(function()
        open = not open
        listFrame.Visible = open
        row.Size = UDim2.new(1, 0, 0, open and (52 + #options * 24) or 52)
    end)
    return row
end

local function makeDivider(parent, order)
    local d = Instance.new("Frame", parent)
    d.Size             = UDim2.new(1, 0, 0, 1)
    d.BackgroundColor3 = Color3.fromRGB(50, 44, 70)
    d.BorderSizePixel  = 0
    d.LayoutOrder      = order or 0
    return d
end

-- ----------------------------------------------------------------
-- Build panel contents
-- ----------------------------------------------------------------
makeLabel(scroll, "── counter ──", 0)
makeToggle(scroll, "Enable Counter", false, 1, function(v) CFG.enabled = v end)
makeToggle(scroll, "Show HUD", true, 2, function(v)
    CFG.showHud = v
    hudGui.Enabled = v
end)

makeDivider(scroll, 3)
makeLabel(scroll, "── mode ──", 4)
makeDropdown(scroll, "Counter Mode", {"UE", "KICIA", "SOLIX"}, "UE", 5, function(v)
    CFG.mode = v
end)

makeDivider(scroll, 6)
makeLabel(scroll, "── ue settings ──", 7)
makeSlider(scroll, "Cooldown (s)",  0.05, 1,    0.18,   2, 8,  function(v) CFG.cooldown  = v end)
makeSlider(scroll, "Y Distance",    100,  2000,  500,    0, 9,  function(v) CFG.yDistance = v end)

makeDivider(scroll, 10)
makeLabel(scroll, "── kicia / solix ──", 11)
makeSlider(scroll, "Cycle Ms",          10,    200,    50,     0, 12, function(v) CFG.cycleMs  = v end)
makeSlider(scroll, "Fly Ms",            5,     100,    25,     0, 13, function(v) CFG.flyMs    = v end)
makeSlider(scroll, "Fly Speed",         1000,  50000,  15000,  0, 14, function(v) CFG.flySpeed = v end)
makeSlider(scroll, "Boost Power",       10000, 500000, 100000, 0, 15, function(v) CFG.boost    = v end)
makeSlider(scroll, "Boost Interval Ms", 100,   2000,   600,    0, 16, function(v) CFG.boostMs  = v end)
makeSlider(scroll, "Zig Amplitude",     50,    2000,   400,    0, 17, function(v) CFG.zigAmp   = v end)
makeSlider(scroll, "Zig Frequency",     1,     20,     8,      0, 18, function(v) CFG.zigFreq  = v end)
makeSlider(scroll, "Depth (studs)",     1,     50,     6,      0, 19, function(v) CFG.depth    = v end)
makeSlider(scroll, "Radius (Solix)",    5,     100,    30,     0, 20, function(v) CFG.radius   = v end)

makeDivider(scroll, 21)
local hint = Instance.new("TextLabel", scroll)
hint.Size                  = UDim2.new(1, 0, 0, 30)
hint.BackgroundTransparency = 1
hint.Font                  = Enum.Font.Gotham
hint.TextSize              = 10
hint.TextColor3            = Color3.fromRGB(100, 90, 130)
hint.TextWrapped           = true
hint.Text                  = "Tap the HUD bar to open/close panel"
hint.LayoutOrder           = 22

-- ----------------------------------------------------------------
-- KICIA / SOLIX state
-- ----------------------------------------------------------------
local KS = {
    t0=0, boostAt=0,
    fly=Vector3.zero, spawn=Vector3.zero,
    stop=nil, stopIdx=-1,
    list={}, last=nil, started=false,
}

local function ksInit(root)
    local now  = os.clock()
    KS.t0      = now
    KS.boostAt = now
    KS.spawn   = root.Position
    KS.fly     = root.Position
    KS.stop, KS.stopIdx = nil, -1
    KS.list, KS.last = {}, nil
    KS.started = true
end

local function buildSolixList(spawn)
    KS.list = {}
    local rng = Random.new()
    local rcp = RaycastParams.new()
    rcp.FilterType = Enum.RaycastFilterType.Exclude
    rcp.FilterDescendantsInstances = { lp.Character or Instance.new("Folder") }
    for _ = 1, 60 do
        if #KS.list >= 16 then break end
        local ang  = rng:NextNumber(0, math.pi * 2)
        local dist = rng:NextNumber(4, math.max(CFG.radius, 5))
        local origin = spawn + Vector3.new(math.cos(ang)*dist, 8, math.sin(ang)*dist)
        local ok, hit = pcall(function()
            return workspace:Raycast(origin, Vector3.new(0,-30,0), rcp)
        end)
        if ok and hit and hit.Normal.Y > 0.7 then
            KS.list[#KS.list+1] = hit.Position - Vector3.new(0, CFG.depth, 0)
        end
    end
end

local function resolveStop(mode, spawn)
    local fallback = spawn - Vector3.new(0, CFG.depth, 0)
    if mode ~= "SOLIX" then return fallback end
    if KS.spawn ~= spawn or #KS.list == 0 then
        KS.spawn = spawn
        buildSolixList(spawn)
    end
    local n = #KS.list
    if n == 0 then return fallback end
    local idx = math.random(1, n)
    if n > 1 and idx == KS.last then idx = idx % n + 1 end
    KS.last = idx
    return KS.list[idx]
end

local function ksSolixStep(mode, root, dt)
    local now    = os.clock()
    local t      = now - KS.t0
    local cycle  = math.max(CFG.cycleMs, 5) / 1000
    local flyW   = math.min(CFG.flyMs / 1000, cycle * 0.95)
    local flying = (t % cycle) < flyW

    if now >= KS.boostAt then
        if flying then KS.fly = KS.fly + Vector3.new(0, CFG.boost, 0) end
        KS.boostAt = now + CFG.boostMs / 1000
    end

    if not flying then
        local idx = math.floor(t / cycle)
        if idx ~= KS.stopIdx or not KS.stop then
            KS.stopIdx = idx
            KS.stop    = resolveStop(mode, KS.spawn)
        end
        pcall(function()
            root.CFrame = CFrame.new(KS.stop) * CFrame.Angles(math.pi/2, 0, 0)
            root.AssemblyLinearVelocity = Vector3.zero
        end)
    else
        local zig = math.cos(t * CFG.zigFreq) * CFG.zigAmp * dt
        KS.fly = KS.fly + Vector3.new(zig, CFG.flySpeed * dt, 0)
        pcall(function()
            root.CFrame = CFrame.new(KS.fly) * CFrame.Angles(-math.pi/2, 0, 0)
            root.AssemblyLinearVelocity = Vector3.zero
        end)
    end
end

-- ----------------------------------------------------------------
-- UE COUNTER state
-- ----------------------------------------------------------------
local UE = { last = 0 }

local function ueStep(root)
    local now = os.clock()
    if now - UE.last < CFG.cooldown then return end
    UE.last = now
    pcall(function()
        local char = lp.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
        root.CFrame = CFrame.new(root.Position + Vector3.new(0, CFG.yDistance, 0))
        root.AssemblyLinearVelocity = Vector3.zero
    end)
end

-- ----------------------------------------------------------------
-- MAIN HEARTBEAT LOOP
-- ----------------------------------------------------------------
local conn = RunService.Heartbeat:Connect(function(dt)
    if not CFG.enabled then
        KS.started = false
        hudLabel.Text = "KICIA COUNTER | OFF"
        hudAccent.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
        return
    end

    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        hudLabel.Text = "KICIA COUNTER | NO CHAR"
        return
    end

    local mode = CFG.mode

    if mode == "UE" then
        KS.started = false
        ueStep(root)
        hudAccent.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
        hudLabel.Text = ("KICIA COUNTER | UE | ▲ y+%d"):format(CFG.yDistance)
    else
        if not KS.started then ksInit(root) end
        ksSolixStep(mode, root, dt)
        local col = mode == "KICIA" and Color3.fromRGB(100, 60, 220) or Color3.fromRGB(60, 180, 100)
        hudAccent.BackgroundColor3 = col
        hudLabel.Text = ("KICIA COUNTER | %s | ◈ cycling"):format(mode)
    end
end)

-- ----------------------------------------------------------------
-- CHARACTER RESET  (restore humanoid on death/respawn)
-- ----------------------------------------------------------------
lp.CharacterRemoving:Connect(function(c)
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function()
        hum.PlatformStand = false
        hum.WalkSpeed     = 16
    end) end
    KS.started = false
end)

-- ----------------------------------------------------------------
-- CLEANUP  (re-inject safe: kills previous instance)
-- ----------------------------------------------------------------
getgenv()._KiciaCounterCleanup = function()
    pcall(function() conn:Disconnect() end)
    pcall(function() hudGui:Destroy() end)
    pcall(function() panelGui:Destroy() end)
    getgenv()._KiciaCounterCleanup = nil
end

print("[Kicia Counter] standalone loaded ✓  tap HUD bar to open panel")
