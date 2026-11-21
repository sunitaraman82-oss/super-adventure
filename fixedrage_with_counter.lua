--!nocheck
-- ============================================================
--  FIXEDRAGE v3.1  +  KICIA COUNTER  (merged)
--  Counter modes : UE | KICIA | SOLIX
--  New tab "Counter" added to the existing BestRage UI
-- ============================================================

-- ── kill previous counter instance on re-inject ─────────────
if getgenv()._KiciaCounterCleanup then
    pcall(getgenv()._KiciaCounterCleanup)
end

local cloneref = cloneref or function(o) return o end
local repS  = cloneref(game:GetService("ReplicatedStorage"))
local plrs  = cloneref(game:GetService("Players"))
local runS  = cloneref(game:GetService("RunService"))
local ws    = cloneref(game:GetService("Workspace"))
local UIS   = game:GetService("UserInputService")
local lplr  = plrs.LocalPlayer

local util              = require(repS.Modules.Utility)
local enum              = require(repS.Modules.EnumLibrary)
local FighterController = require(lplr.PlayerScripts.Controllers.FighterController)
local SpectateController= require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController"))

-- ================================================================
--  COUNTER CONFIG  (live-edited by the new Counter tab)
-- ================================================================
getgenv().CounterCFG = getgenv().CounterCFG or {
    enabled   = false,
    mode      = "UE",   -- "UE" | "KICIA" | "SOLIX"
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
local CCFG = getgenv().CounterCFG

-- ================================================================
--  RAGE CONFIG  (unchanged)
-- ================================================================
getgenv().Config = getgenv().Config or {
    Enabled         = true,
    FireRate        = 0.0005,
    WeaponSlot      = "Melee",
    DesyncMode      = "KnifeAware",
    JitterRange     = 3,
    OrbitSpeed      = 6.0,
    OrbitRadius     = 14,
    LowestHealth    = true,
    FFAMode         = false,
    FFAFireBoost    = true,
    KnifeHoverHeight= 9,
    KnifeBehindOffset=-4,
    MaxDist         = 1000,
}

local slots = { Primary = 1, Secondary = 2, Melee = 3 }
local function getSlotNumber() return slots[getgenv().Config.WeaponSlot] or 3 end

task.spawn(function()
    while not FighterController.LocalFighter do task.wait(0.1) end
    pcall(function() FighterController.LocalFighter:EquipItem(getSlotNumber()) end)
    while true do
        task.wait(1)
        if getgenv().Config.Enabled and FighterController.LocalFighter then
            pcall(function() FighterController.LocalFighter:EquipItem(getSlotNumber()) end)
        end
    end
end)

-- ================================================================
--  RAGE HELPERS  (unchanged)
-- ================================================================
local lastFire   = 0
local deflecting = {}
plrs.PlayerRemoving:Connect(function(p) deflecting[p] = nil end)

local function updateDeflection()
    if not FighterController or not FighterController.Objects then return end
    for _, fighterObj in FighterController.Objects do
        local player = fighterObj.Player
        if not player then continue end
        if not fighterObj.Entity or not fighterObj.Entity:IsAlive() or fighterObj:Get("IsSpectating") then
            deflecting[player] = false; continue
        end
        local equipped    = fighterObj.EquippedItem
        local isKatana    = equipped and equipped.ViewModel and equipped.ViewModel.Name == "Katana"
        local isDeflecting= false
        if isKatana then
            isDeflecting = (equipped._attack_cooldown and equipped._attack_cooldown > tick()) or false
        end
        deflecting[player] = isDeflecting
    end
end

local function isEnemy(player)
    if player == lplr then return false end
    local duel       = SpectateController.CurrentDuelSubject
    local localDueler= duel and duel:GetDueler(lplr)
    local localTeam  = localDueler and localDueler:Get("TeamID") or nil
    if localTeam and duel and duel.Duelers then
        for _, dueler in duel.Duelers do
            if dueler.Player == player then
                return dueler:Get("TeamID") ~= localTeam
            end
        end
    end
    local pTeam = player:GetAttribute("TeamID")
    local lTeam = lplr:GetAttribute("TeamID")
    if pTeam and lTeam then return pTeam ~= lTeam end
    return true
end

local function pickTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end
    local cfg = getgenv().Config
    local bestPlayer, bestRoot, bestHead = nil, nil, nil
    local bestScore = math.huge
    for _, player in plrs:GetPlayers() do
        if not isEnemy(player) then continue end
        local pChar = player.Character
        if not pChar then continue end
        if pChar:FindFirstChildOfClass("ForceField") then continue end
        local pHum = pChar:FindFirstChildWhichIsA("Humanoid")
        if not pHum or pHum.Health <= 0 then continue end
        local pRoot = pChar:FindFirstChild("HumanoidRootPart")
        local pHead = pChar:FindFirstChild("Head")
        if not (pRoot and pHead) then continue end
        local dist  = (myRoot.Position - pRoot.Position).Magnitude
        if dist > cfg.MaxDist then continue end
        local score = dist
        if deflecting[player] then score = score + 1000 end
        if cfg.LowestHealth  then score = score + pHum.Health * 2 end
        if score < bestScore  then
            bestScore = score
            bestPlayer, bestRoot, bestHead = player, pRoot, pHead
        end
    end
    return bestPlayer, bestRoot, bestHead
end

local function hasKnifeViewModel(targetPlayer)
    if not targetPlayer then return false end
    local viewModels = ws:FindFirstChild("ViewModels")
    if not viewModels then return false end
    for _, model in viewModels:GetChildren() do
        if model:IsA("Model")
            and string.find(model.Name, targetPlayer.Name, 1, true)
            and string.find(model.Name, "Knife", 1, true) then
            return true
        end
    end
    return false
end

local restoreBound = false
local function applyDesync(desyncCF)
    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local oldCF, oldVel, oldRotVel = myRoot.CFrame, myRoot.Velocity, myRoot.RotVelocity
    myRoot.CFrame = desyncCF
    if restoreBound then return end
    restoreBound = true
    runS:BindToRenderStep("__restore", 101, function()
        if myRoot then
            myRoot.CFrame     = oldCF
            myRoot.Velocity   = oldVel
            myRoot.RotVelocity= oldRotVel
        end
        runS:UnbindFromRenderStep("__restore")
        restoreBound = false
    end)
end

-- ================================================================
--  FFA SYSTEM  (unchanged)
-- ================================================================
local ffa = { AutoRespawn = true, DropVacuum = true }
getgenv().FFA = ffa

local function forceRemoteRespawn()
    pcall(function()
        local remotesFolder = repS:FindFirstChild("Remotes")
        if not remotesFolder then return end
        local duelsFolder   = remotesFolder:FindFirstChild("Duels")
        if not duelsFolder  then return end
        local respawnRemote = duelsFolder:FindFirstChild("RespawnNow")
        if respawnRemote and respawnRemote:IsA("RemoteEvent") then
            respawnRemote:FireServer()
        end
    end)
end

lplr.CharacterAdded:Connect(function(newCharacter)
    local humanoid = newCharacter:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        if not ffa.AutoRespawn then return end
        task.spawn(function()
            while ffa.AutoRespawn do
                local char = lplr.Character
                if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then break end
                forceRemoteRespawn()
                task.wait(0.1)
            end
        end)
    end)
end)

local visitedDrops = {}
local function handleNewDrop(object)
    if not ffa.DropVacuum then return end
    if not (object:IsA("BasePart") and object.Name == "_drop") then return end
    if visitedDrops[object] then return end
    visitedDrops[object] = true
    task.wait()
    pcall(function()
        local char = lplr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if object:IsDescendantOf(ws) and hrp then
            object.CFrame    = hrp.CFrame + Vector3.new(0, 3, 0)
            object.Anchored  = true
            object.CanCollide= false
            object.Transparency = 1
            for _, child in pairs(object:GetDescendants()) do
                if child:IsA("BasePart") or child:IsA("UnionOperation") or child:IsA("MeshPart") then
                    pcall(function() child.Transparency = 1; child.CanCollide = false end)
                elseif child:IsA("BillboardGui") or child:IsA("SurfaceGui") or child:IsA("ParticleEmitter") or child:IsA("SelectionBox") then
                    pcall(function() child.Enabled = false end)
                end
            end
        end
    end)
end

for _, object in ipairs(ws:GetDescendants()) do
    if object:IsA("BasePart") and object.Name == "_drop" then visitedDrops[object] = true end
end
ws.DescendantAdded:Connect(handleNewDrop)

-- ================================================================
--  UI SETUP  (BestRage base — extended with Counter tab)
-- ================================================================
local TweenService = game:GetService("TweenService")
local PlayerGui    = lplr:WaitForChild("PlayerGui")

local Colors = {
    Bg      = Color3.fromRGB(25, 15, 35),
    Panel   = Color3.fromRGB(40, 25, 55),
    Element = Color3.fromRGB(60, 40, 80),
    Accent  = Color3.fromRGB(255, 105, 180),
    -- counter accent (purple)
    CAccent = Color3.fromRGB(100, 60, 220),
    Text    = Color3.fromRGB(240, 240, 240),
}

local function Create(className, properties)
    local inst = Instance.new(className)
    for k, v in pairs(properties) do inst[k] = v end
    return inst
end

local ScreenGui = Create("ScreenGui", {
    Name         = "BestRageV3_UI",
    ResetOnSpawn = false,
    Parent       = PlayerGui,
})

local ToggleBtn = Create("TextButton", {
    Size             = UDim2.new(0, 80, 0, 35),
    Position         = UDim2.new(0, 20, 0.5, -17),
    BackgroundColor3 = Colors.Panel,
    Text             = "MENU",
    TextColor3       = Colors.Accent,
    Font             = Enum.Font.GothamBold,
    TextSize         = 14,
    Parent           = ScreenGui,
})
Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = ToggleBtn })
Create("UIStroke", { Color = Colors.Accent, Thickness = 1.5, Parent = ToggleBtn })

-- Main window is taller now (Counter tab needs more room → 480 instead of 380)
local MainFrame = Create("Frame", {
    Name             = "Main",
    Size             = UDim2.new(0, 320, 0, 480),
    Position         = UDim2.new(0.5, -160, 0.5, -240),
    BackgroundColor3 = Colors.Bg,
    BorderSizePixel  = 0,
    Parent           = ScreenGui,
    ClipsDescendants = true,
    Visible          = false,
})
Create("UICorner", { CornerRadius = UDim.new(0, 8),   Parent = MainFrame })
Create("UIStroke", { Color = Colors.Accent, Thickness = 1.5, Parent = MainFrame })

local isMenuOpen = false
local function closeMenu()
    isMenuOpen = false
    local t = TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(0, 0, 0, 0) })
    t:Play(); t.Completed:Connect(function() MainFrame.Visible = false end)
end
local function openMenu()
    isMenuOpen = true
    MainFrame.Visible = true
    MainFrame.Size    = UDim2.new(0, 0, 0, 0)
    TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 320, 0, 480) }):Play()
end
ToggleBtn.MouseButton1Click:Connect(function()
    if isMenuOpen then closeMenu() else openMenu() end
end)

-- window drag
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UIS.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- ── Title bar ───────────────────────────────────────────────
local TopBar = Create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = MainFrame })
Create("TextLabel", {
    Text               = "CRISIS+ | MOBILE",
    Size               = UDim2.new(1, -50, 1, 0),
    Position           = UDim2.new(0, 15, 0, 0),
    BackgroundTransparency = 1,
    TextColor3         = Colors.Accent,
    Font               = Enum.Font.GothamBold,
    TextSize           = 14,
    TextXAlignment     = Enum.TextXAlignment.Left,
    Parent             = TopBar,
})
local CloseBtn = Create("TextButton", {
    Text               = "X",
    Size               = UDim2.new(0, 30, 0, 30),
    Position           = UDim2.new(1, -40, 0.5, -15),
    BackgroundTransparency = 1,
    TextColor3         = Colors.Text,
    Font               = Enum.Font.GothamBold,
    TextSize           = 16,
    Parent             = TopBar,
})
CloseBtn.MouseButton1Click:Connect(closeMenu)

-- ── Tab bar  (4 tabs now: Combat | Desync | FFA | Counter) ──
local TabContainer = Create("Frame", {
    Size               = UDim2.new(1, -20, 0, 30),
    Position           = UDim2.new(0, 10, 0, 45),
    BackgroundTransparency = 1,
    Parent             = MainFrame,
})
Create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding       = UDim.new(0, 4),
    Parent        = TabContainer,
})

local function MakeTabBtn(label)
    local btn = Create("TextButton", {
        Size             = UDim2.new(0.25, -3, 1, 0),
        BackgroundColor3 = Colors.Element,
        Text             = label,
        TextColor3       = Colors.Text,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        Parent           = TabContainer,
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })
    return btn
end

local CombatBtn  = MakeTabBtn("Combat")
local DesyncBtn  = MakeTabBtn("Desync")
local FFABtn     = MakeTabBtn("FFA")
local CounterBtn = MakeTabBtn("Counter")

-- ── Content area ────────────────────────────────────────────
local ContentArea = Create("Frame", {
    Size             = UDim2.new(1, -20, 1, -90),
    Position         = UDim2.new(0, 10, 0, 80),
    BackgroundColor3 = Colors.Panel,
    Parent           = MainFrame,
})
Create("UICorner", { CornerRadius = UDim.new(0, 6),   Parent = ContentArea })
Create("UIStroke", { Color = Colors.Accent, Thickness = 1, Transparency = 0.5, Parent = ContentArea })

local function CreatePage()
    local page = Create("ScrollingFrame", {
        Size                  = UDim2.new(1, -10, 1, -10),
        Position              = UDim2.new(0, 5, 0, 5),
        BackgroundTransparency = 1,
        ScrollBarThickness    = 2,
        ScrollBarImageColor3  = Colors.Accent,
        CanvasSize            = UDim2.new(0, 0, 0, 0),
        Visible               = false,
        Parent                = ContentArea,
    })
    Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = page })
    return page
end

local CombatPage  = CreatePage()
local DesyncPage  = CreatePage()
local FFAPage     = CreatePage()
local CounterPage = CreatePage()   -- ← new

local allTabs = {
    { page = CombatPage,  btn = CombatBtn  },
    { page = DesyncPage,  btn = DesyncBtn  },
    { page = FFAPage,     btn = FFABtn     },
    { page = CounterPage, btn = CounterBtn },
}

local function SwitchTab(targetPage, targetBtn)
    for _, t in ipairs(allTabs) do
        t.page.Visible     = false
        t.btn.BackgroundColor3 = Colors.Element
        t.btn.TextColor3   = Colors.Text
    end
    targetPage.Visible          = true
    targetBtn.BackgroundColor3  = Colors.Accent
    targetBtn.TextColor3        = Colors.Bg
end

for _, t in ipairs(allTabs) do
    local p, b = t.page, t.btn
    b.MouseButton1Click:Connect(function() SwitchTab(p, b) end)
end

-- ================================================================
--  UI WIDGET HELPERS  (shared by both rage and counter tabs)
-- ================================================================
local function CreateHeader(text, parent)
    local frame = Create("Frame", { Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Parent = parent })
    Create("TextLabel", {
        Text               = text,
        Size               = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3         = Colors.Accent,
        Font               = Enum.Font.GothamBold,
        TextSize           = 11,
        TextXAlignment     = Enum.TextXAlignment.Left,
        Parent             = frame,
    })
end

local function CreateToggle(name, getState, setState, parent, accentColor)
    accentColor = accentColor or Colors.Accent
    local isChecked = getState()
    local frame = Create("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = parent })
    Create("TextLabel", {
        Text               = name,
        Size               = UDim2.new(0.75, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3         = Colors.Text,
        Font               = Enum.Font.Gotham,
        TextSize           = 12,
        TextXAlignment     = Enum.TextXAlignment.Left,
        Parent             = frame,
    })
    local Pill = Create("Frame", {
        Size             = UDim2.new(0, 34, 0, 16),
        Position         = UDim2.new(1, -34, 0.5, -8),
        BackgroundColor3 = isChecked and accentColor or Colors.Element,
        Parent           = frame,
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = Pill })
    local Knob = Create("Frame", {
        Size             = UDim2.new(0, 12, 0, 12),
        Position         = isChecked and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6),
        BackgroundColor3 = Color3.fromRGB(255,255,255),
        Parent           = Pill,
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Knob })
    local Btn = Create("TextButton", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "", Parent = frame })
    Btn.MouseButton1Click:Connect(function()
        isChecked = not isChecked
        setState(isChecked)
        TweenService:Create(Pill, TweenInfo.new(0.2), { BackgroundColor3 = isChecked and accentColor or Colors.Element }):Play()
        TweenService:Create(Knob, TweenInfo.new(0.2), { Position = isChecked and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6) }):Play()
    end)
end

local function CreateSlider(name, min, max, default, parent, callback, accentColor)
    accentColor = accentColor or Colors.Accent
    local frame = Create("Frame", { Size = UDim2.new(1,0,0,36), BackgroundTransparency = 1, Parent = parent })
    local Top   = Create("Frame", { Size = UDim2.new(1,0,0,16), BackgroundTransparency = 1, Parent = frame })
    Create("TextLabel", {
        Text = name, Size = UDim2.new(0.7,0,1,0), BackgroundTransparency = 1,
        TextColor3 = Colors.Text, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = Top,
    })
    local ValLabel = Create("TextLabel", {
        Text = tostring(default), Size = UDim2.new(0.3,0,1,0), Position = UDim2.new(0.7,0,0,0),
        BackgroundTransparency = 1, TextColor3 = accentColor,
        Font = Enum.Font.GothamBold, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = Top,
    })
    local Bar  = Create("Frame", { Size = UDim2.new(1,0,0,6), Position = UDim2.new(0,0,0,22), BackgroundColor3 = Colors.Element, Parent = frame })
    Create("UICorner", { CornerRadius = UDim.new(0,3), Parent = Bar })
    local Fill = Create("Frame", { Size = UDim2.new((default-min)/(max-min),0,1,0), BackgroundColor3 = accentColor, Parent = Bar })
    Create("UICorner", { CornerRadius = UDim.new(0,3), Parent = Fill })
    local Knob = Create("Frame", { Size = UDim2.new(0,12,0,12), Position = UDim2.new((default-min)/(max-min),-6,0.5,-6), BackgroundColor3 = accentColor, Parent = Bar })
    Create("UICorner", { CornerRadius = UDim.new(0,6), Parent = Knob })
    local Btn  = Create("TextButton", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "", Parent = Bar })
    local isDragging = false
    local function update(input)
        local pct = math.clamp((input.Position.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
        local val = min + (max - min) * pct
        if max <= 1 or (max - min) < 10 then val = math.round(val*1000)/1000 else val = math.floor(val) end
        TweenService:Create(Fill, TweenInfo.new(0.05), { Size = UDim2.new(pct,0,1,0) }):Play()
        TweenService:Create(Knob, TweenInfo.new(0.05), { Position = UDim2.new(pct,-6,0.5,-6) }):Play()
        ValLabel.Text = tostring(val)
        if callback then callback(val) end
    end
    Btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            isDragging = true; update(i)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if isDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            update(i)
        end
    end)
end

local function CreateDropdown(name, options, default, parent, callback, accentColor)
    accentColor = accentColor or Colors.Accent
    local frame = Create("Frame", { Size = UDim2.new(1,0,0,45), BackgroundTransparency = 1, Parent = parent })
    Create("TextLabel", {
        Text = name, Size = UDim2.new(1,0,0,15), BackgroundTransparency = 1,
        TextColor3 = Colors.Text, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
    })
    local Btn = Create("TextButton", {
        Size = UDim2.new(1,0,0,24), Position = UDim2.new(0,0,0,18),
        BackgroundColor3 = Colors.Element, Text = "", Parent = frame,
    })
    Create("UICorner", { CornerRadius = UDim.new(0,4), Parent = Btn })
    local Label = Create("TextLabel", {
        Text = default, Size = UDim2.new(1,-20,1,0), Position = UDim2.new(0,5,0,0),
        BackgroundTransparency = 1, TextColor3 = Colors.Text,
        Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = Btn,
    })
    Create("TextLabel", {
        Text = "v", Size = UDim2.new(0,20,1,0), Position = UDim2.new(1,-20,0,0),
        BackgroundTransparency = 1, TextColor3 = accentColor,
        Font = Enum.Font.GothamBold, TextSize = 12, Parent = Btn,
    })
    local currentIndex = 1
    for i, v in ipairs(options) do if v == default then currentIndex = i; break end end
    Btn.MouseButton1Click:Connect(function()
        currentIndex = currentIndex % #options + 1
        Label.Text = options[currentIndex]
        if callback then callback(options[currentIndex]) end
    end)
end

-- ================================================================
--  HUD  (kicia-style draggable watermark for counter status)
-- ================================================================
local guiParent
do
    local ok, h = pcall(function()
        local fn = getgenv().gethui or gethui
        return fn and fn()
    end)
    guiParent = (ok and h) or game:GetService("CoreGui")
end

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
    local hDrag, hStart, hPos = false
    hudFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            hDrag = true; hStart = i.Position; hPos = hudFrame.Position
        end
    end)
    hudFrame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then hDrag = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if hDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - hStart
            hudFrame.Position = UDim2.new(hPos.X.Scale, hPos.X.Offset + d.X, hPos.Y.Scale, hPos.Y.Offset + d.Y)
        end
    end)
end

-- ================================================================
--  COUNTER TAB CONTENT
-- ================================================================
CreateHeader("── COUNTER ──", CounterPage)

-- Enable toggle (purple accent)
CreateToggle("Enable Counter", function() return CCFG.enabled end, function(v)
    CCFG.enabled = v
    hudGui.Enabled = true   -- always show HUD when tab is used
end, CounterPage, Colors.CAccent)

CreateHeader("── MODE ──", CounterPage)
CreateDropdown("Counter Mode", {"UE", "KICIA", "SOLIX"}, CCFG.mode, CounterPage, function(v)
    CCFG.mode = v
end, Colors.CAccent)

CreateHeader("── UE SETTINGS ──", CounterPage)
CreateSlider("Cooldown (s)",  0.05, 1,    0.18, CounterPage, function(v) CCFG.cooldown  = v end, Colors.CAccent)
CreateSlider("Y Distance",    100,  2000,  500,  CounterPage, function(v) CCFG.yDistance = v end, Colors.CAccent)

CreateHeader("── KICIA / SOLIX ──", CounterPage)
CreateSlider("Cycle Ms",          10,    200,    50,     CounterPage, function(v) CCFG.cycleMs  = v end, Colors.CAccent)
CreateSlider("Fly Ms",            5,     100,    25,     CounterPage, function(v) CCFG.flyMs    = v end, Colors.CAccent)
CreateSlider("Fly Speed",         1000,  50000,  15000,  CounterPage, function(v) CCFG.flySpeed = v end, Colors.CAccent)
CreateSlider("Boost Power",       10000, 500000, 100000, CounterPage, function(v) CCFG.boost    = v end, Colors.CAccent)
CreateSlider("Boost Interval Ms", 100,   2000,   600,    CounterPage, function(v) CCFG.boostMs  = v end, Colors.CAccent)
CreateSlider("Zig Amplitude",     50,    2000,   400,    CounterPage, function(v) CCFG.zigAmp   = v end, Colors.CAccent)
CreateSlider("Zig Frequency",     1,     20,     8,      CounterPage, function(v) CCFG.zigFreq  = v end, Colors.CAccent)
CreateSlider("Depth (studs)",     1,     50,     6,      CounterPage, function(v) CCFG.depth    = v end, Colors.CAccent)
CreateSlider("Radius (Solix)",    5,     100,    30,     CounterPage, function(v) CCFG.radius   = v end, Colors.CAccent)

-- ================================================================
--  RAGE TABS CONTENT  (identical to original fixedrage)
-- ================================================================
CreateHeader("GENERAL", CombatPage)
CreateToggle("Rage (Master)",      function() return getgenv().Config.Enabled      end, function(v) getgenv().Config.Enabled      = v end, CombatPage)
CreateDropdown("Weapon Slot", {"Primary","Secondary","Melee"}, getgenv().Config.WeaponSlot, CombatPage, function(val) getgenv().Config.WeaponSlot = val end)
CreateToggle("Lowest Health Target",function() return getgenv().Config.LowestHealth end, function(v) getgenv().Config.LowestHealth = v end, CombatPage)
CreateSlider("Fire Rate (0=inst)", 0,    0.1,  getgenv().Config.FireRate,  CombatPage, function(v) getgenv().Config.FireRate  = v end)
CreateSlider("Max Distance",       50,   1000, getgenv().Config.MaxDist,   CombatPage, function(v) getgenv().Config.MaxDist   = v end)

CreateHeader("DESYNC SETTINGS", DesyncPage)
CreateDropdown("Desync Mode", {"KnifeAware","Jitter","Orbit","Off"}, getgenv().Config.DesyncMode, DesyncPage, function(val) getgenv().Config.DesyncMode = val end)
CreateSlider("Knife Hover Height",  5,   15, getgenv().Config.KnifeHoverHeight,  DesyncPage, function(v) getgenv().Config.KnifeHoverHeight  = v end)
CreateSlider("Knife Behind Offset",-8,    0, getgenv().Config.KnifeBehindOffset, DesyncPage, function(v) getgenv().Config.KnifeBehindOffset = v end)
CreateSlider("Jitter Range",        1,    8, getgenv().Config.JitterRange,       DesyncPage, function(v) getgenv().Config.JitterRange       = v end)
CreateSlider("Orbit Speed",         1,   12, getgenv().Config.OrbitSpeed,        DesyncPage, function(v) getgenv().Config.OrbitSpeed        = v end)
CreateSlider("Orbit Radius",        6,   30, getgenv().Config.OrbitRadius,       DesyncPage, function(v) getgenv().Config.OrbitRadius       = v end)

CreateHeader("FREE FOR ALL SETTINGS", FFAPage)
CreateToggle("FFA Mode (Boost)", function() return getgenv().Config.FFAMode      end, function(v) getgenv().Config.FFAMode      = v end, FFAPage)
CreateToggle("FFA Fire Boost",   function() return getgenv().Config.FFAFireBoost  end, function(v) getgenv().Config.FFAFireBoost  = v end, FFAPage)
CreateToggle("FFA Auto-Respawn", function() return getgenv().FFA.AutoRespawn      end, function(v) getgenv().FFA.AutoRespawn      = v end, FFAPage)
CreateToggle("FFA Drop Vacuum",  function() return getgenv().FFA.DropVacuum       end, function(v) getgenv().FFA.DropVacuum       = v end, FFAPage)

local UnloadBtn = Create("TextButton", {
    Size = UDim2.new(1,0,0,28), BackgroundColor3 = Colors.Element,
    Text = "Unload Script", TextColor3 = Colors.Text,
    Font = Enum.Font.GothamBold, TextSize = 12, Parent = FFAPage,
})
Create("UICorner", { CornerRadius = UDim.new(0,4), Parent = UnloadBtn })
UnloadBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

SwitchTab(CombatPage, CombatBtn)   -- default tab

local function UpdateCanvas(page)
    local layout = page:FindFirstChildOfClass("UIListLayout")
    if not layout then return end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 10)
    end)
    task.wait()
    page.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 10)
end
UpdateCanvas(CombatPage)
UpdateCanvas(DesyncPage)
UpdateCanvas(FFAPage)
UpdateCanvas(CounterPage)

-- ================================================================
--  KICIA / SOLIX COUNTER INTERNALS
-- ================================================================
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
    rcp.FilterDescendantsInstances = { lplr.Character or Instance.new("Folder") }
    for _ = 1, 60 do
        if #KS.list >= 16 then break end
        local ang  = rng:NextNumber(0, math.pi * 2)
        local dist = rng:NextNumber(4, math.max(CCFG.radius, 5))
        local origin = spawn + Vector3.new(math.cos(ang)*dist, 8, math.sin(ang)*dist)
        local ok, hit = pcall(function()
            return workspace:Raycast(origin, Vector3.new(0,-30,0), rcp)
        end)
        if ok and hit and hit.Normal.Y > 0.7 then
            KS.list[#KS.list+1] = hit.Position - Vector3.new(0, CCFG.depth, 0)
        end
    end
end

local function resolveStop(mode, spawn)
    local fallback = spawn - Vector3.new(0, CCFG.depth, 0)
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
    local cycle  = math.max(CCFG.cycleMs, 5) / 1000
    local flyW   = math.min(CCFG.flyMs / 1000, cycle * 0.95)
    local flying = (t % cycle) < flyW

    if now >= KS.boostAt then
        if flying then KS.fly = KS.fly + Vector3.new(0, CCFG.boost, 0) end
        KS.boostAt = now + CCFG.boostMs / 1000
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
        local zig = math.cos(t * CCFG.zigFreq) * CCFG.zigAmp * dt
        KS.fly = KS.fly + Vector3.new(zig, CCFG.flySpeed * dt, 0)
        pcall(function()
            root.CFrame = CFrame.new(KS.fly) * CFrame.Angles(-math.pi/2, 0, 0)
            root.AssemblyLinearVelocity = Vector3.zero
        end)
    end
end

-- ── UE counter ─────────────────────────────────────────────
local UE = { last = 0 }
local function ueStep(root)
    local now = os.clock()
    if now - UE.last < CCFG.cooldown then return end
    UE.last = now
    pcall(function()
        local char = lplr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
        root.CFrame = CFrame.new(root.Position + Vector3.new(0, CCFG.yDistance, 0))
        root.AssemblyLinearVelocity = Vector3.zero
    end)
end

-- ================================================================
--  MAIN HEARTBEAT  (rage + counter both live here)
-- ================================================================
local counterConn = runS.Heartbeat:Connect(function(dt)
    -- ── COUNTER BRANCH ────────────────────────────────────────
    if not CCFG.enabled then
        KS.started = false
        hudLabel.Text = "KICIA COUNTER | OFF"
        hudAccent.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
    else
        local char = lplr.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            hudLabel.Text = "KICIA COUNTER | NO CHAR"
        else
            local mode = CCFG.mode
            if mode == "UE" then
                KS.started = false
                ueStep(root)
                hudAccent.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
                hudLabel.Text = ("KICIA COUNTER | UE | ▲ y+%d"):format(CCFG.yDistance)
            else
                if not KS.started then ksInit(root) end
                ksSolixStep(mode, root, dt)
                local col = mode == "KICIA" and Color3.fromRGB(100, 60, 220) or Color3.fromRGB(60, 180, 100)
                hudAccent.BackgroundColor3 = col
                hudLabel.Text = ("KICIA COUNTER | %s | ◈ cycling"):format(mode)
            end
        end
    end

    -- ── RAGE BRANCH ───────────────────────────────────────────
    updateDeflection()
    local cfg = getgenv().Config
    local targetPlayer, targetRoot, targetHead = pickTarget()
    local desyncCF = nil

    local localFighter = FighterController.LocalFighter
    local item   = localFighter and localFighter.EquippedItem
    local info   = item and rawget(item, "Info")
    local data   = item and rawget(item, "Data")
    local reloading = (info and info.Type == "Gun" and data and data.Ammo <= 0)

    if reloading then
        local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            myRoot.CFrame = CFrame.new(myRoot.Position) * (myRoot.CFrame - myRoot.CFrame.Position)
        end
        desyncCF = nil
    elseif targetRoot and targetHead then
        if cfg.DesyncMode == "KnifeAware" then
            if hasKnifeViewModel(targetPlayer) then
                desyncCF = CFrame.lookAt((targetRoot.CFrame * CFrame.new(0, cfg.KnifeHoverHeight, cfg.KnifeBehindOffset)).Position, targetHead.Position)
            else
                desyncCF = CFrame.lookAt((targetRoot.CFrame * CFrame.new(0, 3, -20)).Position, targetHead.Position)
            end
        elseif cfg.DesyncMode == "Jitter" then
            local r = cfg.JitterRange
            desyncCF = CFrame.lookAt(targetHead.Position + Vector3.new(math.random(-r,r), math.random(-r,r), math.random(-r,r)), targetHead.Position)
        elseif cfg.DesyncMode == "Orbit" then
            local a      = tick() * cfg.OrbitSpeed
            local offset = CFrame.new(math.cos(a)*cfg.OrbitRadius, 4, math.sin(a)*cfg.OrbitRadius)
            desyncCF = CFrame.lookAt((targetRoot.CFrame * offset).Position, targetHead.Position)
        end
    end

    if desyncCF then applyDesync(desyncCF) end

    if not cfg.Enabled then return end
    if not (targetPlayer and targetHead and targetRoot) then return end
    if deflecting[targetPlayer] then return end
    if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then return end
    if not FighterController.LocalFighter then return end
    if reloading then return end
    if not item then return end

    local rate = (cfg.FFAMode and cfg.FFAFireBoost) and 0 or cfg.FireRate
    if tick() - lastFire < rate then return end
    lastFire = tick()

    local originPos = targetRoot.Position
    local aimCF    = CFrame.lookAt(originPos, targetHead.Position)

    local cameradata = {}
    cameradata[utf8.char(1)] = {
        [utf8.char(0)] = util:EncodeCFrame(aimCF),
        [utf8.char(1)] = util:EncodeCFrame(targetHead.CFrame),
        [utf8.char(2)] = targetHead,
        [utf8.char(3)] = util:EncodeCFrame(CFrame.new(0,0,0)),
    }

    if info and info.Type == "Melee" then
        local anim = enum:ToEnum("AttackAnimation1")
        if anim then
            repS.Remotes.Replication.Fighter.UseItem:FireServer(
                item:Get("ObjectID"), enum:ToEnum("StartShooting"),
                { [utf8.char(1)] = cameradata[utf8.char(1)], [utf8.char(2)] = anim }, nil
            )
            return
        end
    end

    repS.Remotes.Replication.Fighter.UseItem:FireServer(
        item:Get("ObjectID"), enum:ToEnum("StartShooting"), cameradata, nil
    )
end)

-- ================================================================
--  CHARACTER RESET  (restore humanoid on death/respawn)
-- ================================================================
lplr.CharacterRemoving:Connect(function(c)
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function()
        hum.PlatformStand = false
        hum.WalkSpeed     = 16
    end) end
    KS.started = false
end)

-- ================================================================
--  CLEANUP  (re-inject safe)
-- ================================================================
getgenv()._KiciaCounterCleanup = function()
    pcall(function() counterConn:Disconnect() end)
    pcall(function() hudGui:Destroy() end)
    pcall(function() ScreenGui:Destroy() end)
    getgenv()._KiciaCounterCleanup = nil
end

print("[BestRage + KiciaCounter] merged — Counter tab added ✓")
