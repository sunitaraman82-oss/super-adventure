--!nocheck
--!nolint
-- ============================================================
--   sleepy.gg  |  Rebuilt UI  –  Mobile & PC compatible
--   rebuilt by: claude  |  platform-aware, touch + keyboard
-- ============================================================

-- ── Services ─────────────────────────────────────────────────
local Players        = cloneref and cloneref(game:GetService("Players"))        or game:GetService("Players")
local RunService     = cloneref and cloneref(game:GetService("RunService"))      or game:GetService("RunService")
local UserInputService = cloneref and cloneref(game:GetService("UserInputService")) or game:GetService("UserInputService")
local TweenService   = cloneref and cloneref(game:GetService("TweenService"))    or game:GetService("TweenService")
local CoreGui        = cloneref and cloneref(game:GetService("CoreGui"))         or game:GetService("CoreGui")
local GuiService     = cloneref and cloneref(game:GetService("GuiService"))      or game:GetService("GuiService")

local LocalPlayer    = Players.LocalPlayer
local Camera         = workspace.CurrentCamera

-- ── Platform detection ────────────────────────────────────────
local IS_MOBILE   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local VIEWPORT    = Camera.ViewportSize

-- ── Shared flags table ────────────────────────────────────────
getgenv().meow_flags = getgenv().meow_flags or {}
local flags = getgenv().meow_flags

-- ── Theme ─────────────────────────────────────────────────────
local ACCENT     = Color3.fromRGB(0, 162, 255)
local BG_MAIN    = Color3.fromRGB(10, 10, 12)
local BG_SIDE    = Color3.fromRGB(14, 14, 16)
local BG_SECTION = Color3.fromRGB(18, 18, 21)
local BG_ELEMENT = Color3.fromRGB(22, 22, 26)
local TEXT_HI    = Color3.fromRGB(240, 243, 255)
local TEXT_LO    = Color3.fromRGB(72, 72, 73)
local BORDER     = Color3.fromRGB(23, 23, 29)

-- ── Sizes ─────────────────────────────────────────────────────
local WIN_W, WIN_H
if IS_MOBILE then
    WIN_W = math.clamp(VIEWPORT.X * 0.96, 340, 700)
    WIN_H = math.clamp(VIEWPORT.Y * 0.84, 360, 520)
else
    WIN_W = 780
    WIN_H = 505
end

local SIDE_W     = IS_MOBILE and 110 or 162
local HEADER_H   = 56
local FONT_MAIN  = Font.fromEnum(Enum.Font.GothamBold)
local FONT_SMALL = Font.fromEnum(Enum.Font.GothamMedium)

-- ── Utility ───────────────────────────────────────────────────
local function tween(obj, props, t, style)
    TweenService:Create(obj, TweenInfo.new(t or 0.22, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local function new(cls, props)
    local i = Instance.new(cls)
    for k, v in pairs(props) do
        if k ~= "Parent" then i[k] = v end
    end
    if props.Parent then i.Parent = props.Parent end
    return i
end

local function corner(parent, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 7), Parent = parent })
end

local function stroke(parent, color, thick)
    new("UIStroke", { Color = color or BORDER, Thickness = thick or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

local function draggify(frame)
    local dragging, startInput, startPos = false, nil, nil
    frame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            startInput = inp.Position
            startPos   = frame.Position
        end
    end)
    frame.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local vx, vy = Camera.ViewportSize.X, Camera.ViewportSize.Y
        local newX = math.clamp(startPos.X.Offset + (inp.Position.X - startInput.X), 0, vx - frame.AbsoluteSize.X)
        local newY = math.clamp(startPos.Y.Offset + (inp.Position.Y - startInput.Y), 0, vy - frame.AbsoluteSize.Y)
        tween(frame, { Position = UDim2.fromOffset(newX, newY) }, 0.05, Enum.EasingStyle.Linear)
    end)
end

-- ── Root ScreenGui ────────────────────────────────────────────
local ScreenGui = new("ScreenGui", {
    Parent = CoreGui,
    Name = "SleepyHubUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    IgnoreGuiInset = true,
    Enabled = true,
})

-- ── Main window frame ─────────────────────────────────────────
local Main = new("Frame", {
    Parent = ScreenGui,
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromOffset(
        math.clamp(VIEWPORT.X/2 - WIN_W/2, 0, VIEWPORT.X - WIN_W),
        math.clamp(VIEWPORT.Y/2 - WIN_H/2, 0, VIEWPORT.Y - WIN_H)
    ),
    BackgroundColor3 = BG_MAIN,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corner(Main, 10)
stroke(Main, BORDER, 1)

-- mobile scale
if IS_MOBILE then
    local sc = Instance.new("UIScale")
    sc.Scale = math.clamp(VIEWPORT.X / 820, 0.42, 0.72)
    sc.Parent = Main
    Main.AnchorPoint = Vector2.new(0.5, 0.5)
    Main.Position = UDim2.fromScale(0.5, 0.5)
end

draggify(Main)

-- outer shadow
new("ImageLabel", {
    Parent = Main,
    Size = UDim2.new(1, 80, 1, 80),
    Position = UDim2.fromOffset(-40, -40),
    AnchorPoint = Vector2.new(0, 0),
    BackgroundTransparency = 1,
    Image = "rbxassetid://112971167999062",
    ImageColor3 = Color3.fromRGB(0, 0, 0),
    ImageTransparency = 0.3,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(112, 112, 147, 147),
    ZIndex = -1,
})

-- ── Sidebar ───────────────────────────────────────────────────
local Sidebar = new("Frame", {
    Parent = Main,
    Size = UDim2.new(0, SIDE_W, 1, 0),
    BackgroundColor3 = BG_MAIN,
    BorderSizePixel = 0,
    ZIndex = 2,
})

-- sidebar right border
new("Frame", {
    Parent = Sidebar,
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = BORDER,
    BorderSizePixel = 0,
})

-- logo
local acR = math.floor(ACCENT.R*255)
local acG = math.floor(ACCENT.G*255)
local acB = math.floor(ACCENT.B*255)
local LogoLabel = new("TextLabel", {
    Parent = Sidebar,
    Size = UDim2.new(1, 0, 0, 56),
    BackgroundTransparency = 1,
    FontFace = FONT_MAIN,
    Text = string.format('<font color="rgb(%d,%d,%d)">sleepy</font><font color="rgb(240,243,255)">.gg 🎃</font>', acR, acG, acB),
    TextColor3 = ACCENT,
    TextSize = IS_MOBILE and 20 or 26,
    RichText = true,
    BorderSizePixel = 0,
    ZIndex = 3,
})

-- nav button holder
local NavHolder = new("Frame", {
    Parent = Sidebar,
    Size = UDim2.new(1, 0, 1, -56),
    Position = UDim2.fromOffset(0, 56),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 2,
})
new("UIListLayout", {
    Parent = NavHolder,
    FillDirection = Enum.FillDirection.Vertical,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
new("UIPadding", {
    Parent = NavHolder,
    PaddingTop = UDim.new(0, 10),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
    PaddingBottom = UDim.new(0, 10),
})

-- ── Content area ──────────────────────────────────────────────
local ContentArea = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, -SIDE_W, 1, 0),
    Position = UDim2.fromOffset(SIDE_W, 0),
    BackgroundColor3 = BG_MAIN,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})

-- top tab-switcher bar (sub-tabs)
local TabBar = new("Frame", {
    Parent = ContentArea,
    Size = UDim2.new(1, 0, 0, HEADER_H),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 3,
})
new("Frame", {
    Parent = TabBar,
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = BORDER,
    BorderSizePixel = 0,
})
local TabBarList = new("Frame", {
    Parent = TabBar,
    Size = UDim2.new(1, -14, 1, 0),
    Position = UDim2.fromOffset(7, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
})
new("UIListLayout", {
    Parent = TabBarList,
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Center,
})

-- scroll canvas for section content
local ContentScroll = new("ScrollingFrame", {
    Parent = ContentArea,
    Size = UDim2.new(1, 0, 1, -HEADER_H),
    Position = UDim2.fromOffset(0, HEADER_H),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = IS_MOBILE and 3 or 4,
    ScrollBarImageColor3 = ACCENT,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ClipsDescendants = true,
    ZIndex = 2,
})
local ContentLayout = new("UIListLayout", {
    Parent = ContentScroll,
    FillDirection = Enum.FillDirection.Vertical,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
new("UIPadding", {
    Parent = ContentScroll,
    PaddingTop = UDim.new(0, 10),
    PaddingBottom = UDim.new(0, 14),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
})

-- ── Helper: make section ──────────────────────────────────────
local function makeSection(parent, title, icon)
    local sec = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = BG_SECTION,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    corner(sec, 8)
    stroke(sec, BORDER, 1)

    -- header bar
    local header = new("TextButton", {
        Parent = sec,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = BG_ELEMENT,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
    })
    corner(header, 8)

    if icon then
        new("ImageLabel", {
            Parent = header,
            Size = UDim2.fromOffset(16, 16),
            Position = UDim2.fromOffset(10, 9),
            BackgroundTransparency = 1,
            Image = icon,
            ImageColor3 = ACCENT,
            ZIndex = 5,
        })
    end

    new("TextLabel", {
        Parent = header,
        Position = UDim2.fromOffset(icon and 32 or 12, 0),
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        FontFace = FONT_MAIN,
        Text = title,
        TextColor3 = TEXT_HI,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })

    -- collapse arrow
    local arrow = new("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        FontFace = FONT_MAIN,
        Text = "▾",
        TextColor3 = TEXT_LO,
        TextSize = 14,
        ZIndex = 5,
    })

    -- content frame
    local content = new("Frame", {
        Parent = sec,
        Position = UDim2.fromOffset(0, 34),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    new("UIListLayout", {
        Parent = content,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    new("UIPadding", {
        Parent = content,
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 10),
    })

    -- collapse logic
    local open = true
    header.MouseButton1Click:Connect(function()
        open = not open
        content.Visible = open
        arrow.Text = open and "▾" or "▸"
    end)
    header.TouchTap:Connect(function()
        open = not open
        content.Visible = open
        arrow.Text = open and "▾" or "▸"
    end)

    return content
end

-- ── Helper: toggle row ────────────────────────────────────────
local function makeToggle(parent, labelText, flagKey, default)
    local row = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 4,
    })

    new("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = labelText,
        TextColor3 = TEXT_HI,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })

    -- pill toggle
    local pill = new("TextButton", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(36, 18),
        BackgroundColor3 = default and ACCENT or Color3.fromRGB(50, 50, 55),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
    })
    corner(pill, 999)

    local knob = new("Frame", {
        Parent = pill,
        Size = UDim2.fromOffset(12, 12),
        Position = default and UDim2.fromOffset(20, 3) or UDim2.fromOffset(4, 3),
        BackgroundColor3 = Color3.fromRGB(255,255,255),
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    corner(knob, 999)

    local state = default or false
    flags[flagKey] = state

    local function toggle()
        state = not state
        flags[flagKey] = state
        tween(pill, { BackgroundColor3 = state and ACCENT or Color3.fromRGB(50,50,55) }, 0.18)
        tween(knob, { Position = state and UDim2.fromOffset(20,3) or UDim2.fromOffset(4,3) }, 0.18)
    end

    pill.MouseButton1Click:Connect(toggle)
    pill.TouchTap:Connect(toggle)

    return row
end

-- ── Helper: slider row ────────────────────────────────────────
local function makeSlider(parent, labelText, flagKey, minV, maxV, default, suffix)
    local row = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 4,
    })

    local valLabel = new("TextLabel", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(60, 18),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = tostring(default) .. (suffix or ""),
        TextColor3 = ACCENT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 5,
    })

    new("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, -65, 0, 18),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = labelText,
        TextColor3 = TEXT_HI,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })

    local track = new("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 24),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(30, 30, 35),
        BorderSizePixel = 0,
        ZIndex = 5,
    })
    corner(track, 999)

    local fill = new("Frame", {
        Parent = track,
        Size = UDim2.fromScale(math.clamp((default - minV) / (maxV - minV), 0, 1), 1),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    corner(fill, 999)

    flags[flagKey] = default

    local function setVal(px)
        local abs = track.AbsoluteSize.X
        if abs == 0 then return end
        local pct = math.clamp((px - track.AbsolutePosition.X) / abs, 0, 1)
        local v = math.floor(minV + pct * (maxV - minV) + 0.5)
        flags[flagKey] = v
        fill.Size = UDim2.fromScale(pct, 1)
        valLabel.Text = tostring(v) .. (suffix or "")
    end

    local dragging = false
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setVal(inp.Position.X)
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then
            setVal(inp.Position.X)
        end
    end)

    return row
end

-- ── Helper: dropdown row ──────────────────────────────────────
local function makeDropdown(parent, labelText, flagKey, items, default)
    local row = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 4,
    })

    new("TextLabel", {
        Parent = row,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = labelText,
        TextColor3 = TEXT_HI,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    })

    local box = new("TextButton", {
        Parent = row,
        Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundColor3 = BG_ELEMENT,
        BorderSizePixel = 0,
        Text = default or items[1],
        FontFace = FONT_SMALL,
        TextColor3 = TEXT_HI,
        TextSize = 11,
        AutoButtonColor = false,
        ZIndex = 5,
    })
    corner(box, 5)
    stroke(box, BORDER)

    new("TextLabel", {
        Parent = box,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        FontFace = FONT_MAIN,
        Text = "▾",
        TextColor3 = TEXT_LO,
        TextSize = 12,
        ZIndex = 6,
    })

    flags[flagKey] = default or items[1]

    -- simple dropdown list (opens below)
    local listOpen = false
    local listFrame

    local function closeList()
        if listFrame then
            listFrame:Destroy()
            listFrame = nil
        end
        listOpen = false
    end

    local function openList()
        listOpen = true
        listFrame = new("Frame", {
            Parent = box,
            Position = UDim2.new(0, 0, 1, 2),
            Size = UDim2.new(1, 0, 0, math.min(#items, 6) * 22),
            BackgroundColor3 = BG_ELEMENT,
            BorderSizePixel = 0,
            ZIndex = 20,
            ClipsDescendants = true,
        })
        corner(listFrame, 5)
        stroke(listFrame, BORDER)
        local layout = new("UIListLayout", {
            Parent = listFrame,
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        for _, item in ipairs(items) do
            local opt = new("TextButton", {
                Parent = listFrame,
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                Text = item,
                FontFace = FONT_SMALL,
                TextColor3 = TEXT_HI,
                TextSize = 11,
                AutoButtonColor = false,
                ZIndex = 21,
            })
            opt.MouseButton1Click:Connect(function()
                box.Text = item
                flags[flagKey] = item
                closeList()
            end)
            opt.TouchTap:Connect(function()
                box.Text = item
                flags[flagKey] = item
                closeList()
            end)
            opt.MouseEnter:Connect(function()
                tween(opt, { BackgroundColor3 = BG_SECTION }, 0.1)
                opt.BackgroundTransparency = 0
            end)
            opt.MouseLeave:Connect(function()
                tween(opt, { BackgroundTransparency = 1 }, 0.1)
            end)
        end
    end

    box.MouseButton1Click:Connect(function()
        if listOpen then closeList() else openList() end
    end)
    box.TouchTap:Connect(function()
        if listOpen then closeList() else openList() end
    end)

    return row
end

-- ── Helper: button row ────────────────────────────────────────
local function makeButton(parent, labelText, cb)
    local btn = new("TextButton", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = BG_ELEMENT,
        BorderSizePixel = 0,
        Text = labelText,
        FontFace = FONT_SMALL,
        TextColor3 = TEXT_HI,
        TextSize = 12,
        AutoButtonColor = false,
        ZIndex = 5,
    })
    corner(btn, 6)
    stroke(btn, BORDER)

    local function onClick()
        tween(btn, { BackgroundColor3 = ACCENT }, 0.1)
        task.delay(0.2, function() tween(btn, { BackgroundColor3 = BG_ELEMENT }, 0.15) end)
        if cb then cb() end
    end

    btn.MouseButton1Click:Connect(onClick)
    btn.TouchTap:Connect(onClick)
    return btn
end

-- ════════════════════════════════════════════════════════════
--   NAV + TAB SYSTEM
-- ════════════════════════════════════════════════════════════
local Pages = {}           -- pages[navName][subTabName] = Frame
local CurrentNav    = nil
local CurrentSubTab = nil

local NAV_BUTTONS   = {}
local SUBTAB_BUTTONS = {}

local function hideAll()
    for _, pageTbl in pairs(Pages) do
        for _, frame in pairs(pageTbl) do
            frame.Visible = false
        end
    end
end

local function showPage(nav, sub)
    hideAll()
    -- clear sub-tab bar
    for _, c in ipairs(TabBarList:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    SUBTAB_BUTTONS = {}

    if not Pages[nav] then return end

    -- build sub-tab buttons
    local subNames = {}
    for k in pairs(Pages[nav]) do table.insert(subNames, k) end
    table.sort(subNames)

    local firstSub = sub or subNames[1]

    for _, subName in ipairs(subNames) do
        local isActive = (subName == firstSub)

        local btn = new("TextButton", {
            Parent = TabBarList,
            Size = UDim2.fromOffset(0, 36),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = isActive and 0 or 1,
            BackgroundColor3 = isActive and Color3.fromRGB(22,22,26) or BG_MAIN,
            Text = subName,
            FontFace = isActive and FONT_MAIN or FONT_SMALL,
            TextColor3 = isActive and TEXT_HI or TEXT_LO,
            TextSize = 13,
            AutoButtonColor = false,
            ZIndex = 10,
            BorderSizePixel = 0,
        })
        new("UIPadding", {
            Parent = btn,
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        })
        corner(btn, 7)

        -- accent underline
        local accent_line = new("Frame", {
            Parent = btn,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 10, 1, 4),
            Size = UDim2.new(1, -20, 0, 3),
            BackgroundColor3 = ACCENT,
            BackgroundTransparency = isActive and 0 or 1,
            BorderSizePixel = 0,
            ZIndex = 11,
        })
        corner(accent_line, 999)

        SUBTAB_BUTTONS[subName] = { btn = btn, line = accent_line }

        local function activate()
            -- deactivate all
            for sn, tbl in pairs(SUBTAB_BUTTONS) do
                tween(tbl.btn, { TextColor3 = TEXT_LO, BackgroundTransparency = 1 }, 0.15)
                tween(tbl.line, { BackgroundTransparency = 1 }, 0.15)
            end
            -- activate this one
            tween(btn, { TextColor3 = TEXT_HI, BackgroundTransparency = 0 }, 0.15)
            tween(accent_line, { BackgroundTransparency = 0 }, 0.15)
            -- show correct page
            hideAll()
            if Pages[nav] and Pages[nav][subName] then
                Pages[nav][subName].Visible = true
            end
            CurrentSubTab = subName
        end

        btn.MouseButton1Click:Connect(activate)
        btn.TouchTap:Connect(activate)

        if subName == firstSub then
            task.defer(activate)
        end
    end

    CurrentNav = nav
end

-- activate a nav button
local function activateNav(nav)
    for n, btn in pairs(NAV_BUTTONS) do
        tween(btn.text, { TextColor3 = TEXT_LO }, 0.15)
        tween(btn.icon, { ImageColor3 = TEXT_LO }, 0.15)
        tween(btn.frame, { BackgroundTransparency = 1 }, 0.15)
    end
    local b = NAV_BUTTONS[nav]
    if b then
        tween(b.text, { TextColor3 = TEXT_HI }, 0.15)
        tween(b.icon, { ImageColor3 = ACCENT }, 0.15)
        tween(b.frame, { BackgroundTransparency = 0 }, 0.15)
    end
    showPage(nav, nil)
end

-- create a nav button in sidebar
local function makeNavButton(name, icon)
    local btn = new("TextButton", {
        Parent = NavHolder,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Color3.fromRGB(28, 28, 32),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    corner(btn, 7)
    stroke(btn, Color3.fromRGB(23,23,29))

    local iconLbl = new("ImageLabel", {
        Parent = btn,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.fromOffset(IS_MOBILE and 16 or 20, IS_MOBILE and 16 or 20),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 0),
        BackgroundTransparency = 1,
        Image = icon,
        ImageColor3 = TEXT_LO,
        ZIndex = 4,
    })

    local textLbl = new("TextLabel", {
        Parent = btn,
        Position = UDim2.fromOffset(IS_MOBILE and 32 or 36, 0),
        Size = UDim2.new(1, IS_MOBILE and -34 or -40, 1, 0),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = name,
        TextColor3 = TEXT_LO,
        TextSize = IS_MOBILE and 12 or 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4,
    })

    NAV_BUTTONS[name] = { frame = btn, text = textLbl, icon = iconLbl }

    btn.MouseButton1Click:Connect(function() activateNav(name) end)
    btn.TouchTap:Connect(function() activateNav(name) end)

    return btn
end

-- ── Create a page (sub-tab content frame) ────────────────────
local function makePage(nav, sub)
    if not Pages[nav] then Pages[nav] = {} end
    local page = new("Frame", {
        Parent = ContentScroll,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 2,
    })
    new("UIListLayout", {
        Parent = page,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    })
    Pages[nav][sub] = page
    return page
end

-- ════════════════════════════════════════════════════════════
--   SECTION: main  (rage / voidspam / legit / anti-aim)
-- ════════════════════════════════════════════════════════════
makeNavButton("main", "rbxassetid://10723415766")

-- ─ rage tab ──────────────────────────────────────────────────
local pageRage = makePage("main", "rage")

local secSilent = makeSection(pageRage, "Silent Aim Suite", "rbxassetid://6031075931")
makeToggle(secSilent, "Enable Silent Aim",          "silent_aim_enabled",        false)
makeSlider(secSilent, "FOV Radius",                 "fov_radius_smoothed",       10, 800, 120, " px")
makeToggle(secSilent, "Visualise FOV",              "silent_aim_visualise_range",false)
makeSlider(secSilent, "Hit Chance",                 "hit_chance",                1, 100, 100, " %")
makeToggle(secSilent, "Riot Shield Check",          "riot_shield_check",         false)
makeToggle(secSilent, "Avoid Katana Deflect",       "avoid_katana",              false)

local secWallbang = makeSection(pageRage, "Wallbang & Manipulation", "rbxassetid://6031075931")
makeToggle(secWallbang, "Wallbang / Manipulation",  "manipulation_enabled",      false)
makeToggle(secWallbang, "Wallbang V2 Solver",       "wallbang_solver_v2",        false)
makeToggle(secWallbang, "Teleport V2 Origin",       "teleport_v2_origin",        false)

local secTarget = makeSection(pageRage, "Targeting & Priority", "rbxassetid://6031075931")
makeDropdown(secTarget, "Target Hitbox",    "target_hitbox",          {"Head","Torso","HumanoidRootPart","Random"}, "Head")
makeDropdown(secTarget, "Priority Method",  "target_priority",        {"Lowest Health","Distance","Crosshair","FOV - Lowest Health"}, "Lowest Health")
makeToggle(secTarget,   "Ragebot Priority List",   "ragebot_priority",          false)

local secMelee = makeSection(pageRage, "Knife Rage & Melee Aura", "rbxassetid://6031075931")
makeToggle(secMelee,  "Knife / Melee Rage",             "melee_aura",              false)
makeSlider(secMelee,  "Melee Safe Reach",               "melee_reach",             5, 25, 16, " studs")
makeToggle(secMelee,  "Auto Face Back (Backstab)",      "auto_face_back",          false)

-- ─ voidspam tab ──────────────────────────────────────────────
local pageVoid = makePage("main", "voidspam")

local secDesync = makeSection(pageVoid, "Subterranean & Void Desync", "rbxassetid://6031075931")
makeDropdown(secDesync, "Desync Mode", "fake_position_desync_mode",
    {"Position Desync V2","Position Desync V1","Underground V2","Void Teleport"}, "Position Desync V2")
makeToggle(secDesync, "Auto Void On Low HP (< 25 HP)", "auto_void_low_hp",         false)
makeToggle(secDesync, "Melee Underground Strike",      "melee_underground_strike",  false)
makeSlider(secDesync, "Melee Desync Reach",            "melee_desync_reach",        1, 30, 15, " studs")
makeToggle(secDesync, "Enable Fake Position",          "fake_position_enabled",     false)
makeSlider(secDesync, "Underground Depth",             "fake_position_depth",       1, 15, 6, " studs")
makeToggle(secDesync, "Walk Mode",                     "fake_position_walk_mode",   true)
makeToggle(secDesync, "Surface Camera Offset",         "fake_position_surface_cam", true)
makeToggle(secDesync, "Auto Noclip",                   "fake_position_auto_noclip", true)
makeToggle(secDesync, "Hide Meshes (Underground)",     "fake_position_hide_meshes", true)
makeToggle(secDesync, "Animation Desync",              "fake_position_anim_desync", true)
makeToggle(secDesync, "Ghost Visualizer",              "fake_position_visualizer",  true)

local secPanic = makeSection(pageVoid, "Panic / Jitter", "rbxassetid://6031075931")
makeToggle(secPanic, "Panic Jitter",    "fake_position_panic",   false)
makeSlider(secPanic, "Panic Min X",     "fake_position_panic_minx", -20, 0,  -5, "")
makeSlider(secPanic, "Panic Max X",     "fake_position_panic_maxx", 0,  20,   5, "")
makeToggle(secPanic, "Panic Z Axis",    "fake_position_panic_z", false)

-- ─ legit tab ─────────────────────────────────────────────────
local pageLegit = makePage("main", "legit")

local secLegit = makeSection(pageLegit, "Legit Aim Assist", "rbxassetid://6031075931")
makeToggle(secLegit, "Enable Legit Aimbot",  "legit_aimbot_enabled",   false)
makeSlider(secLegit, "Smooth",               "legit_smooth",           1, 60, 15, "")
makeSlider(secLegit, "FOV",                  "legit_fov",              5, 200, 80, " px")
makeDropdown(secLegit, "Target Part",        "legit_target_part",      {"Head","HumanoidRootPart","Torso"}, "Head")

-- ─ anti-aim tab ──────────────────────────────────────────────
local pageAA = makePage("main", "anti-aim")

local secAA = makeSection(pageAA, "Anti-Aim", "rbxassetid://6031075931")
makeToggle(secAA, "Enable Anti-Aim",   "antiaim_enabled",    false)
makeDropdown(secAA, "Pitch",           "antiaim_pitch",      {"Down","Up","Jitter","Random","Custom","Zero"}, "Down")
makeDropdown(secAA, "Yaw",             "antiaim_yaw",        {"Spin","Sway","Jitter","Backwards","Left","Right","Random","Custom"}, "Spin")
makeSlider(secAA,  "Spin Speed",       "antiaim_spin_speed", 1, 30, 15, "")
makeSlider(secAA,  "Jitter Range",     "antiaim_jitter_range", 5, 180, 45, "°")
makeToggle(secAA, "Hide Head",         "antiaim_hidehead",   false)

-- ════════════════════════════════════════════════════════════
--   SECTION: visuals  (VM / FX / HUD / world)
-- ════════════════════════════════════════════════════════════
makeNavButton("visuals", "rbxassetid://6031075931")

-- ─ viewmodel tab ─────────────────────────────────────────────
local pageVM = makePage("visuals", "viewmodel")

local secVM = makeSection(pageVM, "Viewmodel Chams & Wireframe", "rbxassetid://6031075931")
makeToggle(secVM, "Item Chams",            "item_chams",           false)
makeDropdown(secVM, "Chams Material",      "item_chams_material",  {"ForceField","Neon","Glass","Metal","Grass"}, "ForceField")
makeSlider(secVM, "Chams Transparency",    "item_chams_transparency", 0, 10, 2, "")
makeToggle(secVM, "Item Wireframe",        "item_wireframe",        false)
makeToggle(secVM, "Arm Wireframe",         "arm_appearance",        false)

-- ─ FX tab ────────────────────────────────────────────────────
local pageFX = makePage("visuals", "FX")

local secCross = makeSection(pageFX, "Crosshair", "rbxassetid://6031075931")
makeToggle(secCross, "Enable Crosshair",   "crosshair_enabled",   false)
makeToggle(secCross, "Dynamic Crosshair",  "crosshair_dynamic",   false)
makeSlider(secCross, "Length",             "crosshair_length",    1, 20, 8, "")
makeSlider(secCross, "Gap",                "crosshair_gap",       1, 20, 4, "")
makeSlider(secCross, "Thickness",          "crosshair_thickness", 1, 10, 2, "")
makeToggle(secCross, "Center Dot",         "crosshair_dot",       false)
makeToggle(secCross, "Outline",            "crosshair_outline",   true)

local secHitFX = makeSection(pageFX, "Hit FX & Sounds", "rbxassetid://6031075931")
makeToggle(secHitFX, "Hit Marker (World)",   "world_marker_enabled",   true)
makeToggle(secHitFX, "Hit Sound",            "hit_sound_enabled",       true)
makeDropdown(secHitFX, "Hit Sound Preset",   "hit_sound_preset",        {"Rust","Skeet","Bell","Bonk","Neverlose","Bubble","Custom ID"}, "Rust")
makeToggle(secHitFX, "Kill Sound",           "kill_sound_enabled",      false)
makeDropdown(secHitFX, "Kill Sound Preset",  "kill_sound_preset",       {"Oof","Fatality","Headshot","Skeet"}, "Fatality")
makeSlider(secHitFX, "Volume",               "sound_volume",            0, 10, 10, "")
makeSlider(secHitFX, "Pitch",                "sound_pitch",             1, 20, 10, "")

-- ─ HUD tab ───────────────────────────────────────────────────
local pageHUD = makePage("visuals", "HUD")

local secTargetHUD = makeSection(pageHUD, "Target HUD", "rbxassetid://6031075931")
makeToggle(secTargetHUD, "Show Target HUD",     "target_hud",             false)
makeToggle(secTargetHUD, "Target Highlight",    "target_highlight",       false)
makeToggle(secTargetHUD, "Snapline",            "target_snapline",        false)
makeToggle(secTargetHUD, "Bullet Tracers",      "bullet_tracers",         false)
makeToggle(secTargetHUD, "Tracer Shadows",      "tracer_shadows",         false)
makeSlider(secTargetHUD, "Tracer Hold",         "tracer_hold",             1, 20, 6, "")
makeSlider(secTargetHUD, "Tracer Fade",         "tracer_fade",             1, 20, 4, "")

local secIndicator = makeSection(pageHUD, "Indicator", "rbxassetid://6031075931")
makeToggle(secIndicator, "Desync Indicator",    "indicator_enabled",       false)

-- ─ world tab ─────────────────────────────────────────────────
local pageWorld = makePage("visuals", "world")

local secSky = makeSection(pageWorld, "Skybox", "rbxassetid://6031075931")
makeToggle(secSky, "Custom Skybox",          "world_sky_enabled",        false)
makeDropdown(secSky, "Skybox Preset",        "world_sky_preset",
    {"GreenHaze","Space2","PinkMountains","Valentines","PinkArt","PurplePlanet","Blizzard","Winter","FlamingSunset","Mountains","FPSBoost","AestheticMountains","BetterNight3"},
    "Space2")
makeToggle(secSky, "Auto-Rotate Sky",        "world_sky_autorotate",     false)
makeSlider(secSky, "Rotate Speed",           "world_sky_rotate_speed",   1, 200, 100, "")

local secLighting = makeSection(pageWorld, "Lighting & FX", "rbxassetid://6031075931")
makeToggle(secLighting, "Override Ambient",         "lighting_ambient_enabled",        false)
makeToggle(secLighting, "Override Brightness",      "lighting_brightness_enabled",     false)
makeSlider(secLighting, "Brightness Value",          "lighting_brightness_value",       0, 20, 5, "")
makeToggle(secLighting, "Remove Fog",               "world_no_fog",                    false)
makeToggle(secLighting, "Remove Shadows",           "world_no_shadows",                false)
makeToggle(secLighting, "Anti-Flash",               "anti_flash",                      false)
makeToggle(secLighting, "Anti-Shake",               "anti_shake",                      false)
makeToggle(secLighting, "No Textures",              "no_textures",                     false)
makeToggle(secLighting, "Override Camera FOV",      "camera_fov_enabled",              false)
makeSlider(secLighting, "Camera FOV",               "camera_fov",                      40, 160, 90, "°")
makeToggle(secLighting, "Color Correction",         "color_correction_enabled",        false)
makeSlider(secLighting, "CC Saturation",            "cc_saturation",                   -1, 2, 0, "")
makeSlider(secLighting, "CC Contrast",              "cc_contrast",                     -1, 2, 0, "")

-- ════════════════════════════════════════════════════════════
--   SECTION: ESP  (players / chams / tracers)
-- ════════════════════════════════════════════════════════════
makeNavButton("ESP", "rbxassetid://6031075931")

local pageESP = makePage("ESP", "players")

local secESP = makeSection(pageESP, "Player ESP", "rbxassetid://6031075931")
makeToggle(secESP, "Enable ESP",          "esp_enabled",           false)
makeToggle(secESP, "Box ESP",             "esp_box_enabled",       false)
makeDropdown(secESP, "Box Style",         "esp_box_style",         {"2D Box","Corner Box","Filled Box"}, "2D Box")
makeToggle(secESP, "Health Bar",          "esp_health_bar",        false)
makeToggle(secESP, "Ammo Bar",            "esp_ammo_bar",          false)
makeToggle(secESP, "Name Tag",            "esp_name",              false)
makeToggle(secESP, "Distance Label",      "esp_distance",          false)
makeToggle(secESP, "Weapon Label",        "esp_weapon",            false)
makeToggle(secESP, "Rank Label",          "esp_rank",              false)
makeToggle(secESP, "Streak Label",        "esp_streak",            false)
makeToggle(secESP, "Head Marker",         "esp_head_marker",       false)
makeToggle(secESP, "Deflect Indicator",   "esp_deflect",           false)

local pageChams = makePage("ESP", "chams")

local secChams = makeSection(pageChams, "Chams", "rbxassetid://6031075931")
makeToggle(secChams, "Enable Chams",          "chams_enabled",             false)
makeSlider(secChams, "Fill Transparency",     "chams_fill_transparency",   0, 10, 4, "")
makeSlider(secChams, "Outline Transparency",  "chams_outline_transparency", 0, 10, 0, "")
makeDropdown(secChams, "Depth Mode",          "chams_depth_mode",          {"AlwaysOnTop","Occluded"}, "AlwaysOnTop")

local pageTracers = makePage("ESP", "tracers")
local secTracers = makeSection(pageTracers, "Tracers (from ESP)", "rbxassetid://6031075931")
makeToggle(secTracers, "Player Tracers",      "esp_tracers",               false)
makeDropdown(secTracers, "Tracer Origin",     "tracer_origin",             {"Bottom","Center","Top"}, "Bottom")

-- ════════════════════════════════════════════════════════════
--   SECTION: misc  (movement / auto / exploits)
-- ════════════════════════════════════════════════════════════
makeNavButton("misc", "rbxassetid://6031075931")

-- ─ movement ──────────────────────────────────────────────────
local pageMove = makePage("misc", "movement")

local secMove = makeSection(pageMove, "Movement", "rbxassetid://6031075931")
makeToggle(secMove, "Speed Hack",        "walkspeed_enabled",        false)
makeSlider(secMove, "Speed Multiplier",  "walkspeed_mult",           1, 10, 2, "x")
makeToggle(secMove, "Noclip",            "noclip_enabled",           false)
makeToggle(secMove, "Flight",            "flight_enabled",           false)
makeSlider(secMove, "Flight Speed",      "flight_speed",             10, 500, 100, "")
makeToggle(secMove, "Double Jump",       "double_jump",              false)
makeSlider(secMove, "DJ Height Mult",    "double_jump_height",       1, 10, 1, "x")
makeToggle(secMove, "Long Jump",         "long_jump",                false)
makeDropdown(secMove, "LJ Mode",         "long_jump_mode",           {"Camera Look","Forward"}, "Camera Look")
makeSlider(secMove, "LJ Force",          "long_jump_force",          10, 500, 150, "")
makeToggle(secMove, "Auto-Strafe",       "auto_strafe",              false)
makeSlider(secMove, "Strafe Speed",      "auto_strafe_speed",        10, 200, 50, "")
makeToggle(secMove, "Sliding",           "sliding_enabled",          false)
makeSlider(secMove, "Slide Mult",        "sliding_mult",             1, 10, 2, "x")

-- ─ auto tab ──────────────────────────────────────────────────
local pageAuto = makePage("misc", "auto")

local secAuto = makeSection(pageAuto, "Auto Queue & Loadout", "rbxassetid://6031075931")
makeToggle(secAuto, "Auto Queue",             "auto_queue_enabled",        false)
makeToggle(secAuto, "Auto Loadout",           "auto_loadout_enabled",      false)
makeDropdown(secAuto, "Primary",             "auto_loadout_primary",       {"Assault Rifle","SMG","Shotgun","Sniper","RPG"}, "Assault Rifle")
makeDropdown(secAuto, "Secondary",           "auto_loadout_secondary",     {"Handgun","Revolver"}, "Handgun")
makeDropdown(secAuto, "Melee",               "auto_loadout_melee",         {"Fists","Knife","Katana"}, "Fists")
makeDropdown(secAuto, "Utility",             "auto_loadout_utility",       {"Grenade","Molotov","Smoke Grenade"}, "Grenade")
makeToggle(secAuto, "Auto Finish Loadout",   "auto_loadout_finish",        false)

local secACO = makeSection(pageAuto, "Auto Collect", "rbxassetid://6031075931")
makeToggle(secACO, "Auto Collect Orbs/Drops", "ACO",                       false)

-- ─ exploits tab ──────────────────────────────────────────────
local pageExp = makePage("misc", "exploits")

local secStaff = makeSection(pageExp, "Staff Detector", "rbxassetid://6031075931")
makeToggle(secStaff, "Enable Staff Detector", "staff_detector_enabled",   true)
makeToggle(secStaff, "Auto Hop On Staff",     "staff_auto_hop",           false)

local secMisc = makeSection(pageExp, "Miscellaneous", "rbxassetid://6031075931")
makeToggle(secMisc, "Hit Logs",           "hit_logs_enabled",             false)
makeToggle(secMisc, "Kill Logs",          "kill_logs_enabled",            false)

-- ════════════════════════════════════════════════════════════
--   SECTION: char (first-person / angles)
-- ════════════════════════════════════════════════════════════
makeNavButton("char", "rbxassetid://6031075931")

local pageFP = makePage("char", "first-person")

local secFP = makeSection(pageFP, "First-Person Settings", "rbxassetid://6031075931")
makeToggle(secFP, "Force First Person",   "force_first_person",   false)
makeToggle(secFP, "Invisible Arms",       "invisible_arms",        false)
makeToggle(secFP, "No Head",              "no_head",               false)

local pageAngles = makePage("char", "angles")

local secAngles = makeSection(pageAngles, "Custom Pitch/Yaw", "rbxassetid://6031075931")
makeSlider(secAngles, "Custom Pitch",    "fake_position_custom_pitch", -89, 89, 0, "°")
makeSlider(secAngles, "Custom Yaw",      "fake_position_custom_yaw",  -180,180, 0, "°")
makeToggle(secAngles, "Invert Pitch",    "fake_position_invert_pitch", false)

-- ════════════════════════════════════════════════════════════
--   SECTION: settings  (config / theme)
-- ════════════════════════════════════════════════════════════
makeNavButton("settings", "rbxassetid://6031075931")

local pageCfg = makePage("settings", "config")

local secCfg = makeSection(pageCfg, "Config Manager", "rbxassetid://6031075931")
makeButton(secCfg, "Save Config", function()
    if Library and Library.notifications then
        Library.notifications:create_notification({ name = "Config", info = "Saved!", lifetime = 2 })
    end
end)
makeButton(secCfg, "Load Config", function() end)
makeButton(secCfg, "Reset All Flags", function()
    for k in pairs(flags) do flags[k] = nil end
end)

local pageSettings = makePage("settings", "settings")

local secTheme = makeSection(pageSettings, "Theme & Keybinds", "rbxassetid://6031075931")
makeToggle(secTheme, "Open Menu (RightShift toggle)", "menu_open_bind", true)

-- ════════════════════════════════════════════════════════════
--   MOBILE: floating open/close button
-- ════════════════════════════════════════════════════════════
local uiVisible = true

if IS_MOBILE then
    local openBtn = new("TextButton", {
        Parent = ScreenGui,
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(0, 10, 0.5, -22),
        BackgroundColor3 = ACCENT,
        Text = "☰",
        FontFace = FONT_MAIN,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 20,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 999,
    })
    corner(openBtn, 10)
    stroke(openBtn, Color3.fromRGB(255,255,255), 1)

    -- draggable
    local dbDrag, dbStart, dbPos = false, nil, nil
    openBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then
            dbDrag = true; dbStart = inp.Position; dbPos = openBtn.Position
        end
    end)
    openBtn.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then
            dbDrag = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dbDrag and inp.UserInputType == Enum.UserInputType.Touch then
            local nx = math.clamp(dbPos.X.Offset + (inp.Position.X - dbStart.X), 0, VIEWPORT.X - 44)
            local ny = math.clamp(dbPos.Y.Offset + (inp.Position.Y - dbStart.Y), 0, VIEWPORT.Y - 44)
            openBtn.Position = UDim2.fromOffset(nx, ny)
        end
    end)

    openBtn.TouchTap:Connect(function()
        uiVisible = not uiVisible
        Main.Visible = uiVisible
        openBtn.Text = uiVisible and "✕" or "☰"
    end)
else
    -- PC: RightShift to toggle
    UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode.RightShift then
            uiVisible = not uiVisible
            Main.Visible = uiVisible
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--   Boot: activate first nav tab
-- ════════════════════════════════════════════════════════════
task.defer(function()
    activateNav("main")
end)

-- ════════════════════════════════════════════════════════════
--   Notifications helper (compatible with original Library)
-- ════════════════════════════════════════════════════════════
local NotifGui = new("ScreenGui", {
    Parent = CoreGui,
    Name = "SleepyNotifs",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Global,
    IgnoreGuiInset = true,
})

local NotifHolder = new("Frame", {
    Parent = NotifGui,
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -14, 1, -14),
    Size = UDim2.fromOffset(260, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 100,
})
new("UIListLayout", {
    Parent = NotifHolder,
    FillDirection = Enum.FillDirection.Vertical,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local notifIndex = 0
local function createNotification(opts)
    notifIndex += 1
    local n = new("Frame", {
        Parent = NotifHolder,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = BG_SECTION,
        BorderSizePixel = 0,
        ZIndex = 101,
        LayoutOrder = notifIndex,
    })
    corner(n, 8)
    stroke(n, BORDER)

    -- accent strip
    new("Frame", {
        Parent = n,
        Size = UDim2.fromOffset(3, 36),
        Position = UDim2.fromOffset(6, 8),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
        ZIndex = 102,
    })

    new("TextLabel", {
        Parent = n,
        Position = UDim2.fromOffset(16, 7),
        Size = UDim2.new(1, -20, 0, 18),
        BackgroundTransparency = 1,
        FontFace = FONT_MAIN,
        Text = opts.name or "Notification",
        TextColor3 = TEXT_HI,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102,
    })

    new("TextLabel", {
        Parent = n,
        Position = UDim2.fromOffset(16, 25),
        Size = UDim2.new(1, -20, 0, 18),
        BackgroundTransparency = 1,
        FontFace = FONT_SMALL,
        Text = opts.info or "",
        TextColor3 = TEXT_LO,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102,
    })

    -- progress bar
    local bar = new("Frame", {
        Parent = n,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
        ZIndex = 103,
    })

    local lifetime = opts.lifetime or 3
    tween(bar, { Size = UDim2.new(0, 0, 0, 2) }, lifetime, Enum.EasingStyle.Linear)

    task.delay(lifetime, function()
        tween(n, { BackgroundTransparency = 1 }, 0.3)
        task.delay(0.35, function() n:Destroy() end)
    end)
end

-- expose to global so the original script hooks can still use it
getgenv().sleepy_notify = createNotification

-- expose a Library-compatible shell
if not getgenv().Library then
    getgenv().Library = {
        notifications = {
            create_notification = createNotification
        }
    }
else
    getgenv().Library.notifications = getgenv().Library.notifications or {}
    getgenv().Library.notifications.create_notification = createNotification
end

print("[Sleepy UI] Rebuilt UI loaded — " .. (IS_MOBILE and "MOBILE" or "PC") .. " mode | RightShift (PC) or ☰ btn (mobile) to toggle")
