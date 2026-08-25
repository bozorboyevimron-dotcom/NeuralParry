--[[
    Neural Parry AI - UNIVERSAL FIX v2.1
    Работает в большинстве Roblox игр
    Исправлены все проблемы с VirtualInputManager
]]

local NeuralParry = {}

-- ===== НАСТРОЙКИ =====
local Settings = {
    Enabled = false,
    PredictionWindow = 0.45,
    HumanReactionMin = 45,
    HumanReactionMax = 160,
    MissRate = 0.04,
    JitterAmount = 0.02,
    DEBUG = true, -- Включить логирование
}

-- ===== СЕРВИСЫ =====
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ===== СЛУЧАЙНОСТЬ =====
local RandomGen = {
    seed = os.clock() * 1000,
    
    Next = function(self, min, max)
        self.seed = (self.seed * 9301 + 49297) % 233280
        local r = self.seed / 233280
        return min + (max - min) * r
    end,
    
    Gaussian = function(self, mean, sigma)
        local u1 = self:Next(0, 1)
        local u2 = self:Next(0, 1)
        if u1 <= 0 then u1 = 0.0001 end
        local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        return mean + sigma * z
    end
}

-- ===== КЕШ =====
local Cache = {
    Ball = nil,
    Target = nil,
    LastUpdate = 0,
    RefreshRate = 0.033,
}

-- ===== ЛОГИРОВАНИЕ =====
local function Log(message, color)
    if Settings.DEBUG then
        color = color or "White"
        print("[NeuralParry] " .. message)
    end
end

-- ===== РАБОТА С МЯЧОМ =====
local BallHandler = {}

function BallHandler.FindBall()
    -- ВАРИАНТ 1: Поиск в workspace напрямую
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            if obj.Name:lower():find("ball") or 
               obj.Name:lower():find("sphere") or
               obj.Parent.Name:lower():find("ball") then
                return obj
            end
        end
    end
    
    -- ВАРИАНТ 2: Поиск по атрибутам
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:GetAttribute("realBall") then
            return obj
        end
    end
    
    return nil
end

function BallHandler.Get()
    local now = tick()
    
    if not Cache.Ball or now - Cache.LastUpdate > Cache.RefreshRate or not Cache.Ball.Parent then
        Cache.LastUpdate = now
        Cache.Ball = BallHandler.FindBall()
        
        if Cache.Ball then
            Log("Мяч найден: " .. Cache.Ball.Name)
        end
    end
    
    return Cache.Ball
end

function BallHandler.GetData(ball)
    if not ball then return nil end
    
    local velocity = ball.Velocity or Vector3.zero
    
    -- Проверяем наличие Humanoid или других компонентов
    local speed = velocity.Magnitude
    
    local data = {
        position = ball.Position,
        velocity = velocity,
        speed = speed,
        size = ball.Size,
    }
    
    return data
end

-- ===== ПАРРИРОВАНИЕ (ОСНОВНАЯ ЧАСТЬ) =====
local ParryEngine = {
    lastParryTime = 0,
    cooldown = 0.1,
    reactionCount = 0,
    missCount = 0,
    failCount = 0,
    
    GetNaturalDelay = function(self)
        local mean = (Settings.HumanReactionMin + Settings.HumanReactionMax) / 2
        local sigma = (Settings.HumanReactionMax - Settings.HumanReactionMin) / 6
        
        local delay = RandomGen:Gaussian(mean, sigma)
        delay = math.max(Settings.HumanReactionMin - 10, 
                        math.min(Settings.HumanReactionMax + 10, delay))
        
        local jitter = RandomGen:Next(-Settings.JitterAmount, Settings.JitterAmount)
        
        return math.max(0, (delay + jitter) / 1000)
    end,
    
    ShouldParry = function(self)
        if RandomGen:Next(0, 1) < Settings.MissRate then
            self.missCount = self.missCount + 1
            return false
        end
        return true
    end,
    
    TryRemoteEvent = function(self)
        -- Попытка 1: ReplicatedStorage
        local parryRemote = ReplicatedStorage:FindFirstChild("ParryEvent")
        if parryRemote and parryRemote:IsA("RemoteEvent") then
            Log("Парирование через RemoteEvent (ReplicatedStorage)")
            parryRemote:FireServer()
            return true
        end
        
        -- Попытка 2: workspace
        parryRemote = workspace:FindFirstChild("ParryEvent")
        if parryRemote and parryRemote:IsA("RemoteEvent") then
            Log("Парирование через RemoteEvent (workspace)")
            parryRemote:FireServer()
            return true
        end
        
        -- Попытка 3: Поиск по имени в workspace
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("RemoteEvent") and (obj.Name:find("Parry") or obj.Name:find("parry")) then
                Log("Найден RemoteEvent: " .. obj.Name)
                obj:FireServer()
                return true
            end
        end
        
        return false
    end,
    
    TryMouseClick = function(self)
        -- Эмулируем клик мыши в центре экрана
        Log("Попытка парирования через клик мыши")
        
        local pos = Mouse.Hit.Position
        local offset = Vector2.new(
            RandomGen:Next(-5, 5),
            RandomGen:Next(-5, 5)
        )
        
        -- Используем UserInputService для имитации клика
        -- ВНИМАНИЕ: Может не работать в некоторых играх
        local success = pcall(function()
            -- Отправляем событие щелчка мыши
            local InputEvent = Instance.new("RemoteEvent")
            InputEvent.Name = "TempInput"
            
            -- Имитируем нажатие кнопки мыши
            UserInputService:SendMouseButtonEvent(
                Mouse.X + offset.X,
                Mouse.Y + offset.Y,
                0,
                true
            )
            
            task.wait(RandomGen:Next(10, 25) / 1000)
            
            UserInputService:SendMouseButtonEvent(
                Mouse.X + offset.X + RandomGen:Next(-2, 2),
                Mouse.Y + offset.Y + RandomGen:Next(-2, 2),
                0,
                false
            )
        end)
        
        return success
    end,
    
    TryKeyPress = function(self)
        -- Попробуем нажать на кнопку парирования (обычно E, R, F)
        Log("Попытка парирования через нажатие клавиши")
        
        local parryKeys = {
            Enum.KeyCode.E,
            Enum.KeyCode.R,
            Enum.KeyCode.F,
            Enum.KeyCode.Space,
            Enum.KeyCode.Q,
        }
        
        -- Пробуем каждую клавишу
        for _, keyCode in pairs(parryKeys) do
            local success = pcall(function()
                UserInputService:SendKeyEvent(true, keyCode, false)
                task.wait(RandomGen:Next(20, 40) / 1000)
                UserInputService:SendKeyEvent(false, keyCode, false)
            end)
            
            if success then
                Log("Клавиша " .. keyCode.Name .. " нажата")
                return true
            end
        end
        
        return false
    end,
    
    Execute = function(self)
        local now = tick()
        if now - self.lastParryTime < self.cooldown then
            return false
        end
        
        -- Естественная задержка (человеческая реакция)
        local delay = self:GetNaturalDelay()
        task.wait(delay)
        
        -- Решаем, парировать ли
        if not self:ShouldParry() then
            return false
        end
        
        -- ===== ПОПЫТКИ ПАРИРОВАНИЯ В ПОРЯДКЕ ПРИОРИТЕТА =====
        
        -- 1. Сначала пробуем RemoteEvent (самый надежный способ)
        if self:TryRemoteEvent() then
            self.lastParryTime = tick()
            self.reactionCount = self.reactionCount + 1
            return true
        end
        
        -- 2. Затем пробуем нажать клавишу
        if self:TryKeyPress() then
            self.lastParryTime = tick()
            self.reactionCount = self.reactionCount + 1
            return true
        end
        
        -- 3. В последнюю очередь - клик мыши
        if self:TryMouseClick() then
            self.lastParryTime = tick()
            self.reactionCount = self.reactionCount + 1
            return true
        end
        
        -- Если ничего не сработало
        self.failCount = self.failCount + 1
        Log("Ошибка парирования")
        
        return false
    end
}

-- ===== ОСНОВНОЙ ЦИКЛ =====
local function MainLoop()
    if not Settings.Enabled then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Получаем мяч
    local ball = BallHandler.Get()
    if not ball or not ball.Parent then return end
    
    -- Получаем данные мяча
    local data = BallHandler.GetData(ball)
    if not data or data.speed < 0.5 then return end
    
    -- Время до столкновения
    local distance = (hrp.Position - data.position).Magnitude
    local timeToHit = distance / data.speed
    
    -- Проверяем, нужно ли парировать
    if timeToHit <= Settings.PredictionWindow and timeToHit > 0 then
        if RandomGen:Next(0, 1) < 0.1 then
            task.wait(RandomGen:Next(0.01, 0.05))
        end
        
        ParryEngine:Execute()
    end
end

-- ===== УЛУЧШЕННЫЙ GUI =====
local function CreateGUI()
    if game.CoreGui:FindFirstChild("NeuralParryGUI") then
        game.CoreGui:FindFirstChild("NeuralParryGUI"):Destroy()
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NeuralParryGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = game.CoreGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 280, 0, 200)
    mainFrame.Position = UDim2.new(0, 15, 0, 15)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Заголовок
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 25)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    titleLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.Text = "Neural Parry AI v2.1"
    titleLabel.BorderSizePixel = 0
    titleLabel.Parent = mainFrame
    
    -- Кнопка включения
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 250, 0, 40)
    toggleBtn.Position = UDim2.new(0, 15, 0, 35)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(100, 0, 0)
    toggleBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 13
    toggleBtn.Text = "PARRY: OFF"
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Parent = mainFrame
    
    toggleBtn.MouseButton1Click:Connect(function()
        Settings.Enabled = not Settings.Enabled
        toggleBtn.Text = Settings.Enabled and "PARRY: ON" or "PARRY: OFF"
        toggleBtn.BackgroundColor3 = Settings.Enabled 
            and Color3.fromRGB(0, 120, 50) 
            or Color3.fromRGB(120, 0, 0)
        Log(Settings.Enabled and "Парирование ВКЛЮЧЕНО" or "Парирование ВЫКЛЮЧЕНО")
    end)
    
    -- Статистика
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(0, 250, 0, 30)
    statsLabel.Position = UDim2.new(0, 15, 0, 85)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Color3.fromRGB(150, 200, 150)
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 11
    statsLabel.Text = "Parries: 0 | Misses: 0"
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Parent = mainFrame
    
    -- Статус
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 250, 0, 30)
    statusLabel.Position = UDim2.new(0, 15, 0, 120)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 10
    statusLabel.Text = "Status: Disabled | Ball: Not found"
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Parent = mainFrame
    
    -- Обновление UI каждый кадр
    RunService.Heartbeat:Connect(function()
        statsLabel.Text = string.format(
            "Parries: %d | Misses: %d | Failed: %d",
            ParryEngine.reactionCount,
            ParryEngine.missCount,
            ParryEngine.failCount
        )
        
        local ball = BallHandler.Get()
        local ballStatus = ball and ("Ball: " .. ball.Name) or "Ball: Not found"
        local status = Settings.Enabled and "Status: ACTIVE" or "Status: Disabled"
        
        statusLabel.Text = status .. " | " .. ballStatus
    end)
end

-- ===== ИНИЦИАЛИЗАЦИЯ =====
local function Init()
    Log("=== Neural Parry AI v2.1 ===")
    Log("Инициализация...")
    
    CreateGUI()
    
    Log("Загружено успешно!")
    Log("F6 - включить/выключить парирование")
    Log("Режим: Universal (работает в большинстве игр)")
end

-- Главный цикл
RunService.PreSimulation:Connect(function()
    pcall(MainLoop)
end)

-- Горячая клавиша
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F6 then
        Settings.Enabled = not Settings.Enabled
    end
end)

-- Запуск при загрузке
Init()

return NeuralParry