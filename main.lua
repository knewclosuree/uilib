--[[
═══════════════════════════════════════════════════════════════════════════════
    FrostLib  •  Modular Glass / Gaussian-Blur UI Library for Roblox
    ---------------------------------------------------------------------------
  QUICK START: 
 local Window = GlassUI:CreateWindow({
    Title    = "My Hub",
    SubTitle = "v1.0",
    Size     = UDim2.new(0, 620, 0, 420),
    Key      = "Key: Active",   -- shows a key chip in the sidebar
})
Window:SetUserProfile({ Status = "Premium" })  -- auto-pulls avatar from LocalPlayer

local main = Window:CreateTab({ Name = "Main" })
main:CreateSection("Combat")
main:CreateToggle({ Name = "Aimbot", Flag = "aim", Callback = function(v) print(v) end })
main:CreateSlider({ Name = "FOV", Min = 0, Max = 500, Default = 120, Suffix = "px", Flag = "fov" })
main:CreateDropdown({ Name = "Target", Options = {"Head","Torso"}, Multi = false })
main:CreateKeybind({ Name = "Toggle UI", Default = Enum.KeyCode.RightShift })
main:CreateColorPicker({ Name = "ESP Color", Default = Color3.new(1,0,0) })
═══════════════════════════════════════════════════════════════════════════════
]]

--==============================================================================
--  SERVICES & ENVIRONMENT
--==============================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer


local function getGuiParent()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local cg = game:GetService("CoreGui")
    return cg
end


local function protect(gui)
    local ok = pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    pcall(function()
        if protectgui then protectgui(gui) end
    end)
    return ok
end


local hasFiles = (typeof(writefile) == "function")
                 and (typeof(readfile) == "function")
                 and (typeof(isfile)  == "function")

--==============================================================================
--  LIBRARY ROOT
--==============================================================================

local GlassUI = {}
GlassUI.__index = GlassUI

GlassUI.Version       = "1.0.0"
GlassUI.Flags         = {}     -- flag -> { value, set(v) }  (every interactive element)
GlassUI.Windows       = {}     -- list of created windows
GlassUI.Connections   = {}     -- tracked connections for :Destroy()
GlassUI.Registry      = {}     -- component name -> builder(parent, opts)
GlassUI.ConfigFolder  = "GlassUI"

-- Theme palette (mutable; swap to reskin the whole library)
GlassUI.Theme = {
    Background   = Color3.fromRGB(18, 18, 24),
    Surface      = Color3.fromRGB(28, 28, 38),
    SurfaceLight = Color3.fromRGB(40, 40, 54),
    Element      = Color3.fromRGB(34, 34, 46),
    Accent       = Color3.fromRGB(120, 110, 255),
    AccentDim    = Color3.fromRGB(80, 72, 180),
    Text         = Color3.fromRGB(235, 235, 245),
    SubText      = Color3.fromRGB(160, 160, 180),
    Stroke       = Color3.fromRGB(255, 255, 255),
    Success      = Color3.fromRGB(95, 220, 140),
    Danger       = Color3.fromRGB(255, 95, 110),
    Glass        = 0.12,   -- base background transparency for glass frames
    Font         = Enum.Font.GothamMedium,
    FontBold     = Enum.Font.GothamBold,
}

-- Global glow configuration. Drive these live from your script.
GlassUI.Glow = {
    Enabled        = true,
    Brightness     = 0.7,                       -- 0 = invisible, 1 = full strength
    Color          = Color3.fromRGB(120, 110, 255),
    Rainbow        = false,
    RainbowSpeed   = 1,
    Animation      = "Breathe",                 -- preset name
    AnimationSpeed = 1,
    Thickness      = 1.5,
}

--==============================================================================
--  LOW-LEVEL UTILITIES
--==============================================================================

-- Instance factory. Create("Frame", {props}, {children})
local function Create(class, props, children)
    local inst = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                inst[k] = v
            end
        end
    end
    if children then
        for _, c in ipairs(children) do
            c.Parent = inst
        end
    end
    if props and props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

local function track(conn)
    table.insert(GlassUI.Connections, conn)
    return conn
end

local function tween(inst, time, goal, style, dir)
    local info = TweenInfo.new(
        time or 0.2,
        style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out
    )
    local t = TweenService:Create(inst, info, goal)
    t:Play()
    return t
end

local function lerp(a, b, t) return a + (b - a) * t end

local function round(n, inc)
    inc = inc or 1
    return math.floor(n / inc + 0.5) * inc
end

-- Rounded corner shortcut
local function corner(parent, radius)
    return Create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent       = parent,
    })
end

-- Inner padding shortcut
local function padding(parent, all)
    return Create("UIPadding", {
        PaddingTop    = UDim.new(0, all),
        PaddingBottom = UDim.new(0, all),
        PaddingLeft   = UDim.new(0, all),
        PaddingRight  = UDim.new(0, all),
        Parent        = parent,
    })
end

-- Ripple click feedback for any GuiObject
local function ripple(parent)
    track(parent.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
           and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local circle = Create("Frame", {
            BackgroundColor3       = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.82,
            BorderSizePixel        = 0,
            AnchorPoint            = Vector2.new(0.5, 0.5),
            ZIndex                 = (parent.ZIndex or 1) + 1,
            Parent                 = parent,
        })
        corner(circle, 999)
        local px = input.Position.X - parent.AbsolutePosition.X
        local py = input.Position.Y - parent.AbsolutePosition.Y
        circle.Position = UDim2.fromOffset(px, py)
        local size = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 2
        tween(circle, 0.45, {
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
        })
        task.delay(0.46, function() circle:Destroy() end)
    end))
end

-- Make a frame draggable by a handle
local function makeDraggable(handle, target)
    local dragging, startPos, startMouse
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging   = true
            startPos   = target.Position
            startMouse = input.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startMouse
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

-- Build the signature frosted-glass panel: dark translucent fill + sheen + stroke
local function glassPanel(props)
    local propsCopy = props or {}
    local radius = propsCopy._radius or 10
    propsCopy._radius = nil   -- remove so we never try to assign it to the Frame

    local frame = Create("Frame", propsCopy)
    frame.BackgroundColor3       = (props and props.BackgroundColor3) or GlassUI.Theme.Surface
    frame.BackgroundTransparency = (props and props.BackgroundTransparency) or GlassUI.Theme.Glass
    frame.BorderSizePixel        = 0
    corner(frame, radius)

    Create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 210)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.86),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = frame,
    })
    return frame
end

--==============================================================================
--  ACRYLIC / GAUSSIAN BLUR BACKDROP
--==============================================================================

local Acrylic = {
    Blur     = nil,
    Refs     = 0,     -- how many windows currently want blur
    Target   = 18,
}

function Acrylic:Init()
    if self.Blur then return end
    self.Blur = Create("BlurEffect", { Size = 0, Parent = Lighting })
end

function Acrylic:Add()
    self:Init()
    self.Refs += 1
    tween(self.Blur, 0.35, { Size = self.Target })
end

function Acrylic:Remove()
    self.Refs = math.max(0, self.Refs - 1)
    if self.Refs == 0 and self.Blur then
        tween(self.Blur, 0.35, { Size = 0 })
    end
end

function Acrylic:SetIntensity(n)
    self.Target = n
    if self.Blur and self.Refs > 0 then
        tween(self.Blur, 0.25, { Size = n })
    end
end

--==============================================================================
--  GLOW STROKE ENGINE
--  One render loop drives every registered stroke. This is what makes the
--  toggle / brightness / colour / rainbow / animation work globally + live.
--==============================================================================

local GlowEngine = {
    Strokes = {},     -- [stroke] = { base = thicknessMultiplier }
}

function GlowEngine:Register(stroke, baseMul)
    self.Strokes[stroke] = { base = baseMul or 1 }
    return stroke
end

function GlowEngine:Unregister(stroke)
    self.Strokes[stroke] = nil
end

-- Animation presets: each returns a 0..1 intensity multiplier for time t.
GlowEngine.Presets = {
    Static    = function() return 1 end,
    Breathe   = function(t) return math.sin(t * 2) * 0.5 + 0.5 end,
    Pulse     = function(t) local x = (t % 1); return x < 0.15 and 1 or 0.25 end,
    Flicker   = function(t) return (math.noise(t * 6) * 0.5 + 0.5) end,
    Wave      = function(t) return (math.sin(t * 3) * 0.5 + 0.5) ^ 2 end,
    Heartbeat = function(t)
        local x = t % 1.2
        if x < 0.10 then return 1
        elseif x < 0.20 then return 0.3
        elseif x < 0.30 then return 0.9
        else return 0.2 end
    end,
}

function GlowEngine:Start()
    track(RunService.RenderStepped:Connect(function()
        local cfg = GlassUI.Glow
        local t   = os.clock()

        -- resolve colour (rainbow overrides static colour)
        local col = cfg.Color
        if cfg.Rainbow then
            col = Color3.fromHSV((t * 0.12 * cfg.RainbowSpeed) % 1, 0.85, 1)
        end

        -- resolve animation intensity 0..1
        local presetFn = self.Presets[cfg.Animation] or self.Presets.Static
        local intensity = presetFn(t * cfg.AnimationSpeed)

        -- map brightness -> transparency window
        local brightTrans = 1 - math.clamp(cfg.Brightness, 0, 1)        -- brightest
        local dimTrans    = math.clamp(brightTrans + 0.55, 0, 1)        -- dimmest

        for stroke, data in pairs(self.Strokes) do
            if not stroke or not stroke.Parent then
                self.Strokes[stroke] = nil
            elseif not cfg.Enabled then
                stroke.Transparency = 1                                 -- fully off
            else
                stroke.Color        = col
                stroke.Thickness    = cfg.Thickness * data.base
                stroke.Transparency = lerp(dimTrans, brightTrans, intensity)
            end
        end
    end))
end

-- Helper to attach a glow stroke to any GuiObject and auto-register it
local function attachGlow(obj, baseMul, applyOffset)
    local stroke = Create("UIStroke", {
        Color        = GlassUI.Glow.Color,
        Thickness    = GlassUI.Glow.Thickness * (baseMul or 1),
        Transparency = 0.3,
        ApplyStrokeMode = applyOffset and Enum.ApplyStrokeMode.Border
                         or Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Round,
        Parent       = obj,
    })
    GlowEngine:Register(stroke, baseMul)
    return stroke
end

--==============================================================================
--  PUBLIC GLOW API  (call these from your script)
--==============================================================================

function GlassUI:SetGlowEnabled(state)   self.Glow.Enabled        = state and true or false end
function GlassUI:SetGlowBrightness(n)    self.Glow.Brightness     = math.clamp(n, 0, 1)       end
function GlassUI:SetGlowColor(c)         self.Glow.Color          = c                          end
function GlassUI:SetGlowRainbow(state)   self.Glow.Rainbow        = state and true or false   end
function GlassUI:SetGlowSpeed(n)         self.Glow.AnimationSpeed = math.max(0.05, n)          end
function GlassUI:SetGlowThickness(n)     self.Glow.Thickness      = math.max(0, n)             end
function GlassUI:GetGlowPresets()        return { "Static","Breathe","Pulse","Flicker","Wave","Heartbeat" } end
function GlassUI:SetGlowAnimation(name)
    if GlowEngine.Presets[name] then self.Glow.Animation = name end
end
function GlassUI:ToggleGlow()  -- one-call on/off flip (for a switch in-script)
    self.Glow.Enabled = not self.Glow.Enabled
    return self.Glow.Enabled
end

--==============================================================================
--  NOTIFICATIONS
--==============================================================================

local NotifyHolder

local function ensureNotifyHolder(screen)
    if NotifyHolder and NotifyHolder.Parent then return NotifyHolder end
    NotifyHolder = Create("Frame", {
        Name                   = "Notifications",
        AnchorPoint            = Vector2.new(1, 1),
        Position               = UDim2.new(1, -16, 1, -16),
        Size                   = UDim2.new(0, 300, 1, -32),
        BackgroundTransparency = 1,
        Parent                 = screen,
    })
    Create("UIListLayout", {
        Padding            = UDim.new(0, 10),
        VerticalAlignment  = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment= Enum.HorizontalAlignment.Right,
        SortOrder          = Enum.SortOrder.LayoutOrder,
        Parent             = NotifyHolder,
    })
    return NotifyHolder
end

function GlassUI:Notify(opts)
    opts = opts or {}
    local holder = ensureNotifyHolder(self._screen)
    local card = glassPanel({
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundColor3       = self.Theme.Surface,
        BackgroundTransparency = 0.12,
        Parent                 = holder,
    })
    card.BackgroundTransparency = 1
    attachGlow(card, 1)
    padding(card, 12)
    Create("UIListLayout", {
        Padding   = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent    = card,
    })
    Create("TextLabel", {
        Text                 = opts.Title or "Notification",
        Font                 = self.Theme.FontBold,
        TextSize             = 15,
        TextColor3           = self.Theme.Text,
        TextXAlignment       = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size                 = UDim2.new(1, 0, 0, 18),
        Parent               = card,
    })
    if opts.Content then
        Create("TextLabel", {
            Text                 = opts.Content,
            Font                 = self.Theme.Font,
            TextSize             = 13,
            TextColor3           = self.Theme.SubText,
            TextWrapped          = true,
            TextXAlignment       = Enum.TextXAlignment.Left,
            AutomaticSize        = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Size                 = UDim2.new(1, 0, 0, 0),
            Parent               = card,
        })
    end
    tween(card, 0.25, { BackgroundTransparency = 0.12 })
    task.delay(opts.Duration or 4, function()
        tween(card, 0.25, { BackgroundTransparency = 1 })
        for _, ch in ipairs(card:GetDescendants()) do
            if ch:IsA("TextLabel") then tween(ch, 0.25, { TextTransparency = 1 }) end
            if ch:IsA("UIStroke")  then GlowEngine:Unregister(ch) end
        end
        task.delay(0.3, function() card:Destroy() end)
    end)
end

--==============================================================================
--  COMPONENT BUILDERS
--  Each is registered into GlassUI.Registry so the set is extensible.
--==============================================================================

-- Shared row container for a labelled element inside a tab
local function elementRow(parent, height)
    local row = glassPanel({
        Size                   = UDim2.new(1, 0, 0, height or 40),
        BackgroundColor3       = GlassUI.Theme.Element,
        BackgroundTransparency = 0.35,
        _radius                = 8,
        Parent                 = parent,
    })
    attachGlow(row, 0.85)
    return row
end

local Components = {}

-- ---- LABEL ----------------------------------------------------------------
function Components.Label(tab, opts)
    opts = type(opts) == "table" and opts or { Text = tostring(opts) }
    local lbl = Create("TextLabel", {
        Text                 = opts.Text or "Label",
        Font                 = GlassUI.Theme.Font,
        TextSize             = 14,
        TextColor3           = GlassUI.Theme.SubText,
        TextXAlignment       = Enum.TextXAlignment.Left,
        TextWrapped          = true,
        AutomaticSize        = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Size                 = UDim2.new(1, 0, 0, 18),
        Parent               = tab._content,
    })
    return {
        Instance = lbl,
        Set = function(_, t) lbl.Text = t end,
    }
end

-- ---- SECTION HEADER -------------------------------------------------------
function Components.Section(tab, title)
    local holder = Create("Frame", {
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 24),
        Parent                 = tab._content,
    })
    Create("TextLabel", {
        Text                 = string.upper(tostring(title or "Section")),
        Font                 = GlassUI.Theme.FontBold,
        TextSize             = 12,
        TextColor3           = GlassUI.Theme.Accent,
        TextXAlignment       = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Size                 = UDim2.new(1, 0, 1, 0),
        Parent               = holder,
    })
    return holder
end

-- ---- PARAGRAPH ------------------------------------------------------------
function Components.Paragraph(tab, opts)
    opts = opts or {}
    local box = elementRow(tab._content, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.Size = UDim2.new(1, 0, 0, 0)
    padding(box, 12)
    Create("UIListLayout", { Padding = UDim.new(0, 4), Parent = box })
    Create("TextLabel", {
        Text = opts.Title or "Title", Font = GlassUI.Theme.FontBold,
        TextSize = 14, TextColor3 = GlassUI.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18),
        Parent = box,
    })
    Create("TextLabel", {
        Text = opts.Content or "", Font = GlassUI.Theme.Font,
        TextSize = 13, TextColor3 = GlassUI.Theme.SubText, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        Parent = box,
    })
    return { Instance = box }
end

-- ---- BUTTON ---------------------------------------------------------------
function Components.Button(tab, opts)
    opts = opts or {}
    local row = elementRow(tab._content, 38)
    local btn = Create("TextButton", {
        Text                 = opts.Name or "Button",
        Font                 = GlassUI.Theme.Font,
        TextSize             = 14,
        TextColor3           = GlassUI.Theme.Text,
        BackgroundTransparency = 1,
        Size                 = UDim2.new(1, 0, 1, 0),
        AutoButtonColor      = false,
        Parent               = row,
    })
    ripple(row)
    track(btn.MouseEnter:Connect(function() tween(row, 0.15, { BackgroundTransparency = 0.2 }) end))
    track(btn.MouseLeave:Connect(function() tween(row, 0.15, { BackgroundTransparency = 0.35 }) end))
    track(btn.MouseButton1Click:Connect(function()
        if opts.Callback then task.spawn(opts.Callback) end
    end))
    return {
        Instance = row,
        SetText  = function(_, t) btn.Text = t end,
    }
end

-- ---- TOGGLE / SWITCH ------------------------------------------------------
function Components.Toggle(tab, opts)
    opts = opts or {}
    local state = opts.Default or false
    local row = elementRow(tab._content, 40)
    padding(row, 10)
    Create("TextLabel", {
        Text = opts.Name or "Toggle", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -52, 1, 0), Parent = row,
    })
    local track_ = Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 42, 0, 22),
        BackgroundColor3 = GlassUI.Theme.SurfaceLight,
        BackgroundTransparency = 0.1, Parent = row,
    })
    corner(track_, 999)
    local knob = Create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 16, 0, 16),
        BackgroundColor3 = GlassUI.Theme.Text, Parent = track_,
    })
    corner(knob, 999)
    local glow = attachGlow(track_, 0.8)

    local api = {}
    function api.Set(_, v, skip)
        state = v and true or false
        if state then
            tween(track_, 0.2, { BackgroundColor3 = GlassUI.Theme.Accent })
            tween(knob, 0.2, { Position = UDim2.new(1, -19, 0.5, 0) })
        else
            tween(track_, 0.2, { BackgroundColor3 = GlassUI.Theme.SurfaceLight })
            tween(knob, 0.2, { Position = UDim2.new(0, 3, 0.5, 0) })
        end
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = state, set = api.Set } end
        if not skip and opts.Callback then task.spawn(opts.Callback, state) end
    end

    local hit = Create("TextButton", {
        Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = row,
    })
    track(hit.MouseButton1Click:Connect(function() api:Set(not state) end))
    api:Set(state, true)
    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = state, set = api.Set } end
    return api
end

-- ---- SLIDER ---------------------------------------------------------------
function Components.Slider(tab, opts)
    opts = opts or {}
    local min, max = opts.Min or 0, opts.Max or 100
    local inc      = opts.Increment or 1
    local value    = math.clamp(opts.Default or min, min, max)
    local suffix   = opts.Suffix or ""

    local row = elementRow(tab._content, 50)
    padding(row, 10)
    Create("UIListLayout", { Padding = UDim.new(0, 6), Parent = row })

    local top = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = row })
    Create("TextLabel", {
        Text = opts.Name or "Slider", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Parent = top,
    })
    local valLbl = Create("TextLabel", {
        Text = tostring(value) .. suffix, Font = GlassUI.Theme.FontBold, TextSize = 13,
        TextColor3 = GlassUI.Theme.Accent, TextXAlignment = Enum.TextXAlignment.Right,
        BackgroundTransparency = 1, Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0.6, 0, 0, 0), Parent = top,
    })

    local bar = Create("Frame", {
        BackgroundColor3 = GlassUI.Theme.SurfaceLight, BackgroundTransparency = 0.2,
        Size = UDim2.new(1, 0, 0, 8), Parent = row,
    })
    corner(bar, 999)
    local fill = Create("Frame", {
        BackgroundColor3 = GlassUI.Theme.Accent, BorderSizePixel = 0,
        Size = UDim2.new((value - min) / (max - min), 0, 1, 0), Parent = bar,
    })
    corner(fill, 999)
    attachGlow(fill, 0.7)

    local api = {}
    local function update(v, skip)
        value = round(math.clamp(v, min, max), inc)
        local pct = (value - min) / (max - min)
        tween(fill, 0.08, { Size = UDim2.new(pct, 0, 1, 0) })
        valLbl.Text = tostring(value) .. suffix
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = value, set = api.Set } end
        if not skip and opts.Callback then task.spawn(opts.Callback, value) end
    end
    function api.Set(_, v, skip) update(v, skip) end

    local dragging = false
    local function fromInput(input)
        local rel = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        update(min + math.clamp(rel, 0, 1) * (max - min))
    end
    track(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; fromInput(input)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch) then fromInput(input) end
    end))

    update(value, true)
    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = value, set = api.Set } end
    return api
end

-- ---- DROPDOWN (single + multi) -------------------------------------------
function Components.Dropdown(tab, opts)
    opts = opts or {}
    local options = opts.Options or {}
    local multi   = opts.Multi or false
    local selected = multi and {} or (opts.Default or nil)
    if multi and type(opts.Default) == "table" then
        for _, v in ipairs(opts.Default) do selected[v] = true end
    end
    local open = false

    local row = elementRow(tab._content, 40)
    row.ClipsDescendants = true
    row.AutomaticSize = Enum.AutomaticSize.None
    padding(row, 10)
    Create("UIListLayout", { Padding = UDim.new(0, 6), Parent = row })

    local head = Create("TextButton", {
        Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
        AutoButtonColor = false, Parent = row,
    })
    Create("TextLabel", {
        Text = opts.Name or "Dropdown", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Parent = head,
    })
    local chosen = Create("TextLabel", {
        Text = "...", Font = GlassUI.Theme.Font, TextSize = 13,
        TextColor3 = GlassUI.Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
        BackgroundTransparency = 1, Size = UDim2.new(0.4, -16, 1, 0),
        Position = UDim2.new(0.6, 0, 0, 0), Parent = head,
    })
    local arrow = Create("TextLabel", {
        Text = "v", Font = GlassUI.Theme.FontBold, TextSize = 12,
        TextColor3 = GlassUI.Theme.SubText, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 14, 1, 0),
        BackgroundTransparency = 1, Parent = head,
    })

    local listHolder = Create("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Parent = row,
    })
    Create("UIListLayout", { Padding = UDim.new(0, 4), Parent = listHolder })

    local api = {}
    local optButtons = {}

    local function describe()
        if multi then
            local t = {}
            for k, on in pairs(selected) do if on then table.insert(t, k) end end
            chosen.Text = #t == 0 and "None" or table.concat(t, ", ")
        else
            chosen.Text = selected and tostring(selected) or "None"
        end
    end

    local function refreshVisual()
        for name, b in pairs(optButtons) do
            local on = multi and selected[name] or (selected == name)
            tween(b, 0.12, { BackgroundTransparency = on and 0.1 or 0.6 })
            b.TextColor3 = on and GlassUI.Theme.Accent or GlassUI.Theme.SubText
        end
        describe()
    end

    local function choose(name)
        if multi then
            selected[name] = not selected[name]
        else
            selected = name
            open = false
            tween(arrow, 0.2, { Rotation = 0 })
            tween(row, 0.2, { Size = UDim2.new(1, 0, 0, 40) })
        end
        refreshVisual()
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = selected, set = api.Set } end
        if opts.Callback then task.spawn(opts.Callback, selected) end
    end

    function api.Refresh(_, newOptions)
        options = newOptions or options
        for _, b in pairs(optButtons) do b:Destroy() end
        optButtons = {}
        for _, name in ipairs(options) do
            local ob = Create("TextButton", {
                Text = tostring(name), Font = GlassUI.Theme.Font, TextSize = 13,
                TextColor3 = GlassUI.Theme.SubText, BackgroundColor3 = GlassUI.Theme.SurfaceLight,
                BackgroundTransparency = 0.6, AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 28), Parent = listHolder,
            })
            corner(ob, 6)
            optButtons[name] = ob
            track(ob.MouseButton1Click:Connect(function() choose(name) end))
        end
        refreshVisual()
    end

    function api.Set(_, v, skip)
        if multi then
            selected = {}
            if type(v) == "table" then for _, x in ipairs(v) do selected[x] = true end end
        else
            selected = v
        end
        refreshVisual()
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = selected, set = api.Set } end
        if not skip and opts.Callback then task.spawn(opts.Callback, selected) end
    end

    track(head.MouseButton1Click:Connect(function()
        open = not open
        tween(arrow, 0.2, { Rotation = open and 180 or 0 })
        local h = open and (40 + (#options * 32) + 6) or 40
        tween(row, 0.2, { Size = UDim2.new(1, 0, 0, h) })
    end))

    api:Refresh(options)
    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = selected, set = api.Set } end
    return api
end

-- ---- KEYBIND --------------------------------------------------------------
function Components.Keybind(tab, opts)
    opts = opts or {}
    local current = opts.Default
    local binding = false

    local row = elementRow(tab._content, 40)
    padding(row, 10)
    Create("TextLabel", {
        Text = opts.Name or "Keybind", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -90, 1, 0), Parent = row,
    })
    local keyBtn = Create("TextButton", {
        Text = current and current.Name or "None", Font = GlassUI.Theme.FontBold,
        TextSize = 13, TextColor3 = GlassUI.Theme.Accent,
        BackgroundColor3 = GlassUI.Theme.SurfaceLight, BackgroundTransparency = 0.2,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 80, 0, 26), AutoButtonColor = false, Parent = row,
    })
    corner(keyBtn, 6)
    attachGlow(keyBtn, 0.7)

    local api = {}
    function api.Set(_, key)
        current = key
        keyBtn.Text = key and key.Name or "None"
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = key, set = api.Set } end
    end

    track(keyBtn.MouseButton1Click:Connect(function()
        binding = true
        keyBtn.Text = "..."
    end))
    track(UserInputService.InputBegan:Connect(function(input, gpe)
        if binding and input.UserInputType == Enum.UserInputType.Keyboard then
            binding = false
            api:Set(input.KeyCode)
        elseif not gpe and current and input.KeyCode == current then
            if opts.Callback then task.spawn(opts.Callback) end
        end
    end))

    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = current, set = api.Set } end
    return api
end

-- ---- TEXT INPUT -----------------------------------------------------------
function Components.Input(tab, opts)
    opts = opts or {}
    local row = elementRow(tab._content, 40)
    padding(row, 10)
    Create("TextLabel", {
        Text = opts.Name or "Input", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(0.4, 0, 1, 0), Parent = row,
    })
    local boxBg = Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.55, 0, 0, 26), BackgroundColor3 = GlassUI.Theme.SurfaceLight,
        BackgroundTransparency = 0.2, Parent = row,
    })
    corner(boxBg, 6)
    local tb = Create("TextBox", {
        Text = opts.Default or "", PlaceholderText = opts.Placeholder or "...",
        Font = GlassUI.Theme.Font, TextSize = 13, TextColor3 = GlassUI.Theme.Text,
        PlaceholderColor3 = GlassUI.Theme.SubText, BackgroundTransparency = 1,
        Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0),
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = boxBg,
    })
    local api = {}
    function api.Set(_, v) tb.Text = v end
    track(tb.FocusLost:Connect(function()
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = tb.Text, set = api.Set } end
        if opts.Callback then task.spawn(opts.Callback, tb.Text) end
    end))
    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = tb.Text, set = api.Set } end
    return api
end

-- ---- COLOR PICKER ---------------------------------------------------------
function Components.ColorPicker(tab, opts)
    opts = opts or {}
    local color = opts.Default or Color3.fromRGB(255, 255, 255)
    local h, s, v = color:ToHSV()
    local open = false

    local row = elementRow(tab._content, 40)
    row.ClipsDescendants = true
    padding(row, 10)
    Create("UIListLayout", { Padding = UDim.new(0, 8), Parent = row })

    local head = Create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Parent = row })
    Create("TextLabel", {
        Text = opts.Name or "Color", Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Size = UDim2.new(1, -40, 1, 0), Parent = head,
    })
    local swatch = Create("TextButton", {
        Text = "", BackgroundColor3 = color, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 30, 0, 18),
        AutoButtonColor = false, Parent = head,
    })
    corner(swatch, 4)
    attachGlow(swatch, 0.6)

    -- SV square
    local sv = Create("ImageButton", {
        Image = "rbxassetid://4155801252", -- sat/val gradient asset
        BackgroundColor3 = Color3.fromHSV(h, 1, 1), Size = UDim2.new(1, 0, 0, 100),
        AutoButtonColor = false, Parent = row,
    })
    corner(sv, 6)
    local svCursor = Create("Frame", {
        Size = UDim2.new(0, 6, 0, 6), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(255,255,255), BorderSizePixel = 0, Parent = sv,
    })
    corner(svCursor, 999)
    -- Hue bar
    local hue = Create("ImageButton", {
        Image = "rbxassetid://3641079629", Size = UDim2.new(1, 0, 0, 14),
        AutoButtonColor = false, Parent = row,
    })
    corner(hue, 6)
    local hueCursor = Create("Frame", {
        Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Color3.fromRGB(255,255,255),
        BorderSizePixel = 0, Parent = hue,
    })

    local api = {}
    local function apply(skip)
        color = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = color
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
        hueCursor.Position = UDim2.new(h, 0, 0, 0)
        if opts.Flag then GlassUI.Flags[opts.Flag] = { value = color, set = api.Set } end
        if not skip and opts.Callback then task.spawn(opts.Callback, color) end
    end
    function api.Set(_, c, skip) h, s, v = c:ToHSV(); apply(skip) end

    local function svDrag(input)
        local rx = math.clamp((input.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
        local ry = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
        s, v = rx, 1 - ry; apply()
    end
    local function hueDrag(input)
        h = math.clamp((input.Position.X - hue.AbsolutePosition.X) / hue.AbsoluteSize.X, 0, 0.999); apply()
    end
    local svActive, hueActive = false, false
    track(sv.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then svActive=true; svDrag(i) end end))
    track(hue.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then hueActive=true; hueDrag(i) end end))
    track(UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then svActive=false; hueActive=false end end))
    track(UserInputService.InputChanged:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseMovement then
            if svActive then svDrag(i) elseif hueActive then hueDrag(i) end
        end
    end))

    track(swatch.MouseButton1Click:Connect(function()
        open = not open
        tween(row, 0.2, { Size = UDim2.new(1, 0, 0, open and 180 or 40) })
    end))

    apply(true)
    if opts.Flag then GlassUI.Flags[opts.Flag] = { value = color, set = api.Set } end
    return api
end

-- Register all built-ins into the public registry
for name, fn in pairs(Components) do
    GlassUI.Registry[name] = fn
end

-- Public hook to add brand-new component types at runtime
function GlassUI:RegisterComponent(name, builder)
    self.Registry[name] = builder
end

--==============================================================================
--  TAB OBJECT
--==============================================================================

local Tab = {}
Tab.__index = Tab

local function bindComponent(tabObj, regName, methodName)
    Tab[methodName] = function(self, ...)
        local builder = GlassUI.Registry[regName]
        if not builder then warn("[GlassUI] missing component:", regName); return end
        return builder(self, ...)
    end
end

-- expose tab methods that map to registry components
bindComponent(Tab, "Button",      "CreateButton")
bindComponent(Tab, "Toggle",      "CreateToggle")
bindComponent(Tab, "Slider",      "CreateSlider")
bindComponent(Tab, "Dropdown",    "CreateDropdown")
bindComponent(Tab, "Keybind",     "CreateKeybind")
bindComponent(Tab, "Input",       "CreateInput")
bindComponent(Tab, "ColorPicker", "CreateColorPicker")
bindComponent(Tab, "Label",       "CreateLabel")
bindComponent(Tab, "Paragraph",   "CreateParagraph")
bindComponent(Tab, "Section",     "CreateSection")

-- Generic escape hatch for custom registered components
function Tab:CreateElement(regName, ...)
    local builder = GlassUI.Registry[regName]
    if builder then return builder(self, ...) end
    warn("[GlassUI] unknown element:", regName)
end

--==============================================================================
--  WINDOW OBJECT
--==============================================================================

local Window = {}
Window.__index = Window

function Window:CreateTab(opts)
    opts = type(opts) == "table" and opts or { Name = tostring(opts) }
    local self_ = setmetatable({}, Tab)
    self_._window = self

    -- tab button in sidebar
    local btn = Create("TextButton", {
        Text = "   " .. (opts.Name or "Tab"),
        Font = GlassUI.Theme.Font, TextSize = 14,
        TextColor3 = GlassUI.Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = GlassUI.Theme.Element, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 34), AutoButtonColor = false,
        Parent = self.TabList,
    })
    corner(btn, 8)

    -- content page (scrolling)
    local page = Create("ScrollingFrame", {
        Visible = false, Active = true, BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = GlassUI.Theme.Accent,
        Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = self.Pages,
    })
    Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
    padding(page, 4)
    self_._content = page

    track(btn.MouseButton1Click:Connect(function() self:SelectTab(self_) end))
    self_._btn = btn

    table.insert(self.Tabs, self_)
    if #self.Tabs == 1 then self:SelectTab(self_) end
    return self_
end

function Window:SelectTab(tabObj)
    for _, t in ipairs(self.Tabs) do
        local active = (t == tabObj)
        t._content.Visible = active
        tween(t._btn, 0.18, {
            BackgroundTransparency = active and 0.2 or 1,
            TextColor3 = active and GlassUI.Theme.Text or GlassUI.Theme.SubText,
        })
    end
end

-- Profile panel (avatar + username + status) shown at top of sidebar
function Window:SetUserProfile(opts)
    opts = opts or {}
    local userId = opts.UserId or (LocalPlayer and LocalPlayer.UserId)
    local name   = opts.Name or (LocalPlayer and LocalPlayer.DisplayName) or "User"
    local status = opts.Status or "Premium"

    if self.Profile then self.Profile:Destroy() end
    local p = glassPanel({
        Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = GlassUI.Theme.Element,
        BackgroundTransparency = 0.3, _radius = 10, Parent = self.Sidebar,
    })
    p.LayoutOrder = -1
    attachGlow(p, 0.8)
    padding(p, 8)

    local avatar = Create("ImageLabel", {
        BackgroundColor3 = GlassUI.Theme.SurfaceLight, Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = p,
    })
    corner(avatar, 999)
    if opts.Avatar then
        avatar.Image = opts.Avatar
    elseif userId then
        task.spawn(function()
            local ok, content = pcall(function()
                return Players:GetUserThumbnailAsync(
                    userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
            end)
            if ok then avatar.Image = content end
        end)
    end

    Create("TextLabel", {
        Text = name, Font = GlassUI.Theme.FontBold, TextSize = 14,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Position = UDim2.new(0, 48, 0, 6),
        Size = UDim2.new(1, -52, 0, 18), Parent = p,
    })
    Create("TextLabel", {
        Text = status, Font = GlassUI.Theme.Font, TextSize = 12,
        TextColor3 = GlassUI.Theme.Accent, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Position = UDim2.new(0, 48, 0, 24),
        Size = UDim2.new(1, -52, 0, 16), Parent = p,
    })
    self.Profile = p
    return p
end

-- Key display chip (e.g. shows the active key / expiry)
function Window:SetKeyDisplay(text)
    if self.KeyChip then
        self.KeyChip.Text = "  " .. text
        return
    end
    local chip = Create("TextLabel", {
        Text = "  " .. text, Font = GlassUI.Theme.Font, TextSize = 12,
        TextColor3 = GlassUI.Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = GlassUI.Theme.Element, BackgroundTransparency = 0.4,
        Size = UDim2.new(1, 0, 0, 26), Parent = self.Sidebar,
    })
    corner(chip, 6)
    attachGlow(chip, 0.5)
    self.KeyChip = chip
end

function Window:Notify(opts) return GlassUI:Notify(opts) end

function Window:Toggle()
    self.Open = not self.Open
    if self.Open then
        self.Root.Visible = true
        tween(self.Root, 0.25, { GroupTransparency = 0 })
        Acrylic:Add()
    else
        tween(self.Root, 0.25, { GroupTransparency = 1 })
        Acrylic:Remove()
        task.delay(0.26, function() if not self.Open then self.Root.Visible = false end end)
    end
end

function Window:Destroy()
    Acrylic:Remove()
    if self._screen then self._screen:Destroy() end
end

--==============================================================================
--  CREATE WINDOW
--==============================================================================

function GlassUI:CreateWindow(opts)
    opts = opts or {}

    -- one ScreenGui per session, reused for all windows + notifications
    if not self._screen or not self._screen.Parent then
        self._screen = Create("ScreenGui", {
            Name = "GlassUI_" .. tostring(math.random(1000, 9999)),
            ResetOnSpawn = false, IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        })
        protect(self._screen)
        self._screen.Parent = getGuiParent()
        Acrylic:Init()
        GlowEngine:Start()
    end

    local win = setmetatable({}, Window)
    win.Tabs = {}
    win.Open = true
    win._screen = self._screen

    -- root canvas group lets us fade the whole window at once
    local root = Create("CanvasGroup", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = opts.Size or UDim2.new(0, 620, 0, 420),
        BackgroundColor3 = GlassUI.Theme.Background,
        BackgroundTransparency = 0.35,
        Parent = self._screen,
    })
    corner(root, 14)
    attachGlow(root, 1.4)
    win.Root = root

    local backing = Create("Frame", {
        BackgroundColor3 = Color3.fromRGB(12, 12, 18),
        BackgroundTransparency = 0.75,      -- slightly transparent, still glass feel
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 1,                        -- behind all other content
        Parent = root,
    })
    corner(backing, 14)                    -- match root radius
    win.Root = root

    -- top bar
    local top = Create("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = root,
    })
    makeDraggable(top, root)
    Create("TextLabel", {
        Text = opts.Title or "GlassUI", Font = GlassUI.Theme.FontBold, TextSize = 16,
        TextColor3 = GlassUI.Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 6),
        Size = UDim2.new(1, -120, 0, 20), Parent = top,
    })
    if opts.SubTitle then
        Create("TextLabel", {
            Text = opts.SubTitle, Font = GlassUI.Theme.Font, TextSize = 12,
            TextColor3 = GlassUI.Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 24),
            Size = UDim2.new(1, -120, 0, 16), Parent = top,
        })
    end

    -- close + minimize buttons
    local function topBtn(symbol, xoff, cb)
        local b = Create("TextButton", {
            Text = symbol, Font = GlassUI.Theme.FontBold, TextSize = 14,
            TextColor3 = GlassUI.Theme.SubText, BackgroundColor3 = GlassUI.Theme.Element,
            BackgroundTransparency = 0.4, AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, xoff, 0, 10), Size = UDim2.new(0, 24, 0, 24),
            AutoButtonColor = false, Parent = top,
        })
        corner(b, 6)
        track(b.MouseButton1Click:Connect(cb))
        track(b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundTransparency = 0.1 }) end))
        track(b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundTransparency = 0.4 }) end))
        return b
    end
    topBtn("-", -42, function() win:Toggle() end)
    topBtn("X", -12, function() win:Destroy() end)

    -- sidebar (profile + key chip + tab list)
    local sidebar = glassPanel({
        BackgroundColor3 = GlassUI.Theme.Surface, BackgroundTransparency = 0.4,
        Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(0, 170, 1, -62),
        _radius = 10, Parent = root,
    })
    padding(sidebar, 8)
    Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
    win.Sidebar = sidebar

    win.TabList = Create("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -90),
        Parent = sidebar,
    })
    Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = win.TabList })

    -- pages container (right side)
    win.Pages = glassPanel({
        BackgroundColor3 = GlassUI.Theme.Surface, BackgroundTransparency = 0.45,
        Position = UDim2.new(0, 192, 0, 50), Size = UDim2.new(1, -204, 1, -62),
        _radius = 10, Parent = root,
    })
    padding(win.Pages, 10)

    -- optional auto profile
    if opts.Profile ~= false then
        win:SetUserProfile(opts.Profile or {})
    end
    if opts.Key then
        win:SetKeyDisplay(type(opts.Key) == "string" and opts.Key or "Key: Active")
    end

    Acrylic:Add()
    table.insert(self.Windows, win)
    return win
end

--==============================================================================
--  CONFIG SAVE / LOAD  (flag-based)
--==============================================================================

function GlassUI:GetConfig()
    local data = {}
    for flag, entry in pairs(self.Flags) do
        local v = entry.value
        if typeof(v) == "Color3" then
            data[flag] = { __type = "Color3", r = v.R, g = v.G, b = v.B }
        elseif typeof(v) == "EnumItem" then
            data[flag] = { __type = "KeyCode", name = v.Name }
        elseif type(v) == "table" then
            data[flag] = { __type = "table", value = v }
        else
            data[flag] = v
        end
    end
    return data
end

function GlassUI:LoadConfigTable(data)
    for flag, raw in pairs(data) do
        local entry = self.Flags[flag]
        if entry and entry.set then
            local v = raw
            if type(raw) == "table" and raw.__type == "Color3" then
                v = Color3.new(raw.r, raw.g, raw.b)
            elseif type(raw) == "table" and raw.__type == "KeyCode" then
                v = Enum.KeyCode[raw.name]
            elseif type(raw) == "table" and raw.__type == "table" then
                v = raw.value
            end
            pcall(entry.set, entry, v)
        end
    end
end

function GlassUI:SaveConfig(name)
    if not hasFiles then warn("[GlassUI] file API unavailable"); return false end
    name = name or "default"
    pcall(function() if makefolder and not isfolder(self.ConfigFolder) then makefolder(self.ConfigFolder) end end)
    local path = self.ConfigFolder .. "/" .. name .. ".json"
    local ok = pcall(function()
        writefile(path, HttpService:JSONEncode(self:GetConfig()))
    end)
    return ok
end

function GlassUI:LoadConfig(name)
    if not hasFiles then warn("[GlassUI] file API unavailable"); return false end
    name = name or "default"
    local path = self.ConfigFolder .. "/" .. name .. ".json"
    if not isfile(path) then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and data then self:LoadConfigTable(data); return true end
    return false
end

--==============================================================================
--  KEY SYSTEM (optional gate before the menu loads)
--==============================================================================

function GlassUI:CreateKeySystem(opts)
    opts = opts or {}
    local validKeys = opts.Keys or {}
    local resultEvent = {}    -- tiny signal
    local fired = false
    local cb = nil

    if not self._screen or not self._screen.Parent then
        self._screen = Create("ScreenGui", {
            Name = "GlassUIKey", ResetOnSpawn = false, IgnoreGuiInset = true,
        })
        protect(self._screen)
        self._screen.Parent = getGuiParent()
        Acrylic:Init(); GlowEngine:Start()
    end
    Acrylic:Add()

    local box = glassPanel({
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 320, 0, 200), BackgroundColor3 = self.Theme.Background,
        BackgroundTransparency = self.Theme.Glass, _radius = 14, Parent = self._screen,
    })
    attachGlow(box, 1.3)
    padding(box, 18)
    Create("UIListLayout", { Padding = UDim.new(0, 10), Parent = box })

    Create("TextLabel", {
        Text = opts.Title or "Key System", Font = self.Theme.FontBold, TextSize = 18,
        TextColor3 = self.Theme.Text, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24), Parent = box,
    })
    Create("TextLabel", {
        Text = opts.Note or "Enter your key to continue", Font = self.Theme.Font,
        TextSize = 13, TextColor3 = self.Theme.SubText, TextWrapped = true,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), Parent = box,
    })
    local inputBg = Create("Frame", {
        BackgroundColor3 = self.Theme.Element, BackgroundTransparency = 0.2,
        Size = UDim2.new(1, 0, 0, 34), Parent = box,
    })
    corner(inputBg, 8)
    local input = Create("TextBox", {
        PlaceholderText = "Paste key...", Text = "", Font = self.Theme.Font, TextSize = 14,
        TextColor3 = self.Theme.Text, PlaceholderColor3 = self.Theme.SubText,
        BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0), ClearTextOnFocus = false, Parent = inputBg,
    })
    local submit = Create("TextButton", {
        Text = "Verify", Font = self.Theme.FontBold, TextSize = 14,
        TextColor3 = self.Theme.Text, BackgroundColor3 = self.Theme.Accent,
        BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 34),
        AutoButtonColor = false, Parent = box,
    })
    corner(submit, 8)
    attachGlow(submit, 0.9)

    local function check()
        local key = input.Text
        local valid = false
        for _, k in ipairs(validKeys) do if k == key then valid = true break end end
        if valid then
            fired = true
            box:Destroy()
            Acrylic:Remove()
            if cb then task.spawn(cb, true) end
        else
            input.Text = ""
            input.PlaceholderText = "Invalid key, try again"
            tween(box, 0.1, { Position = UDim2.new(0.5, 8, 0.5, 0) })
            task.delay(0.1, function() tween(box, 0.1, { Position = UDim2.new(0.5, 0, 0.5, 0) }) end)
        end
    end
    track(submit.MouseButton1Click:Connect(check))
    track(input.FocusLost:Connect(function(enter) if enter then check() end end))

    function resultEvent.OnVerified(_, fn) cb = fn; return resultEvent end
    return resultEvent
end

--==============================================================================
--  CLEANUP
--==============================================================================

function GlassUI:Destroy()
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    self.Connections = {}
    if Acrylic.Blur then Acrylic.Blur:Destroy(); Acrylic.Blur = nil end
    if self._screen then self._screen:Destroy() end
    self.Windows = {}
    self.Flags = {}
end

--==============================================================================
return GlassUI
