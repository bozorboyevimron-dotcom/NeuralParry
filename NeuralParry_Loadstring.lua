-- Neural Parry AI v2.1 - LOADSTRING VERSION
-- Скопируй всю строку ниже и вставь в консоль Roblox executor

loadstring(game:HttpGet("https://raw.githubusercontent.com/bozorboyevimron-dotcom/NeuralParry/main/NeuralParry_Universal.lua"))()

-- ИЛИ используй эту компактную версию (если первая не работает):
--[[
loadstring([[
local NeuralParry = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Settings = {
    Enabled = false,
    PredictionWindow = 0.45,
    HumanReactionMin = 45,
    HumanReactionMax = 160,
    MissRate = 0.04,
    JitterAmount = 0.02,
    DEBUG = true,
}

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

local Cache = {Ball = nil, Target = nil, LastUpdate = 0, RefreshRate = 0.033}

local function Log(message)
    if Settings.DEBUG then print("[NeuralParry] " .. message) end
end

local BallHandler = {}

function BallHandler.FindBall()
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            if obj.Name:lower():find("ball") or obj.Name:lower():find("sphere") or obj.Parent.Name:lower():find("ball") then
                return obj
            end
        end
    end
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj:GetAttribute("realBall") then return obj end
    end
    return nil
end

function BallHandler.Get()
    local now = tick()
    if not Cache.Ball or now - Cache.LastUpdate > Cache.RefreshRate or not Cache.Ball.Parent then
        Cache.LastUpdate = now
        Cache.Ball = BallHandler.FindBall()
        if Cache.Ball then Log("Мяч найден: " .. Cache.Ball.Name) end
    end
    return Cache.Ball
end

function BallHandler.GetData(ball)
    if not ball then return nil end
    local velocity = ball.Velocity or Vector3.zero
    local speed = velocity.Magnitude
    return {position = ball.Position, velocity = velocity, speed = speed, size = ball.Size}
end

local ParryEngine = {
    lastParryTime = 0, cooldown = 0.1,
    reactionCount = 0, missCount = 0, failCount = 0,
    
    GetNaturalDelay = function(self)
        local mean = (Settings.HumanReactionMin + Settings.HumanReactionMax) / 2
        local sigma = (Settings.HumanReactionMax - Settings.HumanReactionMin) / 6
        local delay = RandomGen:Gaussian(mean, sigma)
        delay = math.max(Settings.HumanReactionMin - 10, math.min(Settings.HumanReactionMax + 10, delay))
        local jitter = RandomGen:Next(-Settings.JitterAmount, Settings.JitterAmount)
        return math.max(0, (delay + jitter) / 1000)
    end,
    
    ShouldParry = function(self)
        if RandomGen:Next(0, 1) < Settings.MissRate then self.missCount = self.missCount + 1 return false end
        return true
    end,
    
    TryRemoteEvent = function(self)
        local parryRemote = ReplicatedStorage:FindFirstChild("ParryEvent")
        if parryRemote and parryRemote:IsA("RemoteEvent") then Log("Парирование через RemoteEvent") parryRemote:FireServer() return true end
        parryRemote = workspace:FindFirstChild("ParryEvent")
        if parryRemote and parryRemote:IsA("RemoteEvent") then parryRemote:FireServer() return true end
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("RemoteEvent") and (obj.Name:find("Parry") or obj.Name:find("parry")) then Log("Найден: " .. obj.Name) obj:FireServer() return true end
        end
        return false
    end,
    
    TryKeyPress = function(self)
        Log("Попытка нажатия клавиши")
        local parryKeys = {Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.F, Enum.KeyCode.Space, Enum.KeyCode.Q}
        for _, keyCode in pairs(parryKeys) do
            local success = pcall(function()
                UserInputService:SendKeyEvent(true, keyCode, false)
                task.wait(RandomGen:Next(20, 40) / 1000)
                UserInputService:SendKeyEvent(false, keyCode, false)
            end)
            if success then Log("Клавиша " .. keyCode.Name .. " нажата") return true end
        end
        return false
    end,
    
    Execute = function(self)
        local now = tick()
        if now - self.lastParryTime < self.cooldown then return false end
        local delay = self:GetNaturalDelay()
        task.wait(delay)
        if not self:ShouldParry() then return false end
        if self:TryRemoteEvent() then self.lastParryTime = tick() self.reactionCount = self.reactionCount + 1 return true end
        if self:TryKeyPress() then self.lastParryTime = tick() self.reactionCount = self.reactionCount + 1 return true end
        self.failCount = self.failCount + 1
        return false
    end
}

local function MainLoop()
    if not Settings.Enabled then return end
    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local ball = BallHandler.Get()
    if not ball or not ball.Parent then return end
    local data = BallHandler.GetData(ball)
    if not data or data.speed < 0.5 then return end
    local distance = (hrp.Position - data.position).Magnitude
    local timeToHit = distance / data.speed
    if timeToHit <= Settings.PredictionWindow and timeToHit > 0 then
        if RandomGen:Next(0, 1) < 0.1 then task.wait(RandomGen:Next(0.01, 0.05)) end
        ParryEngine:Execute()
    end
end

local function CreateGUI()
    if game.CoreGui:FindFirstChild("NeuralParryGUI") then game.CoreGui:FindFirstChild("NeuralParryGUI"):Destroy() end
    local screenGui = Instance.new("ScreenGui") screenGui.Name = "NeuralParryGUI" screenGui.ResetOnSpawn = false screenGui.Parent = game.CoreGui
    local mainFrame = Instance.new("Frame") mainFrame.Size = UDim2.new(0, 280, 0, 200) mainFrame.Position = UDim2.new(0, 15, 0, 15)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25) mainFrame.BackgroundTransparency = 0.1 mainFrame.BorderSizePixel = 0 mainFrame.Parent = screenGui
    local titleLabel = Instance.new("TextLabel") titleLabel.Size = UDim2.new(1, 0, 0, 25) titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50) titleLabel.TextColor3 = Color3.fromRGB(200, 200, 220) titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14 titleLabel.Text = "Neural Parry AI v2.1" titleLabel.BorderSizePixel = 0 titleLabel.Parent = mainFrame
    local toggleBtn = Instance.new("TextButton") toggleBtn.Size = UDim2.new(0, 250, 0, 40) toggleBtn.Position = UDim2.new(0, 15, 0, 35)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(100, 0, 0) toggleBtn.TextColor3 = Color3.fromRGB(220, 220, 220) toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 13 toggleBtn.Text = "PARRY: OFF" toggleBtn.BorderSizePixel = 0 toggleBtn.Parent = mainFrame
    toggleBtn.MouseButton1Click:Connect(function()
        Settings.Enabled = not Settings.Enabled
        toggleBtn.Text = Settings.Enabled and "PARRY: ON" or "PARRY: OFF"
        toggleBtn.BackgroundColor3 = Settings.Enabled and Color3.fromRGB(0, 120, 50) or Color3.fromRGB(120, 0, 0)
        Log(Settings.Enabled and "Парирование ВКЛЮЧЕНО" or "Парирование ВЫКЛЮЧЕНО")
    end)
    local statsLabel = Instance.new("TextLabel") statsLabel.Size = UDim2.new(0, 250, 0, 30) statsLabel.Position = UDim2.new(0, 15, 0, 85)
    statsLabel.BackgroundTransparency = 1 statsLabel.TextColor3 = Color3.fromRGB(150, 200, 150) statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 11 statsLabel.Text = "Parries: 0 | Misses: 0" statsLabel.TextXAlignment = Enum.TextXAlignment.Left statsLabel.Parent = mainFrame
    local statusLabel = Instance.new("TextLabel") statusLabel.Size = UDim2.new(0, 250, 0, 30) statusLabel.Position = UDim2.new(0, 15, 0, 120)
    statusLabel.BackgroundTransparency = 1 statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150) statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 10 statusLabel.Text = "Status: Disabled" statusLabel.TextXAlignment = Enum.TextXAlignment.Left statusLabel.Parent = mainFrame
    RunService.Heartbeat:Connect(function()
        statsLabel.Text = string.format("Parries: %d | Misses: %d | Failed: %d", ParryEngine.reactionCount, ParryEngine.missCount, ParryEngine.failCount)
        local ball = BallHandler.Get()
        statusLabel.Text = (Settings.Enabled and "Status: ACTIVE" or "Status: Disabled")
    end)
end

CreateGUI()
Log("Neural Parry AI v2.1 загружено!")
Log("F6 - включить/выключить")

RunService.PreSimulation:Connect(function() pcall(MainLoop) end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F6 then Settings.Enabled = not Settings.Enabled end
end)

return NeuralParry
]])()
]]