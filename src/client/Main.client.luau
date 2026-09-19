--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
    return
end

local buildInfo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BuildInfo"))
local screen = Instance.new("ScreenGui")
screen.Name = "DevelopmentStatus"
screen.ResetOnSpawn = false

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(500, 44)
label.Position = UDim2.fromOffset(16, 16)
label.BackgroundColor3 = Color3.fromRGB(28, 34, 42)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 18
label.Parent = screen
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function updateStatus()
    local serverReady = ReplicatedStorage:GetAttribute("DevServerReady") == buildInfo.version
    label.Text = if serverReady
        then "Development ready: client + server connected"
        else "Client ready; waiting for development server..."
    label.BackgroundColor3 = if serverReady
        then Color3.fromRGB(27, 84, 62)
        else Color3.fromRGB(112, 77, 22)
end

ReplicatedStorage:GetAttributeChangedSignal("DevServerReady"):Connect(updateStatus)
updateStatus()
print(string.format("[Roommate] Client ready (%s)", buildInfo.version))
