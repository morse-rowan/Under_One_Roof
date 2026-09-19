--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local buildInfo = require(shared:WaitForChild("BuildInfo"))

-- A Studio-only readiness marker exercises server -> client replication without an API key.
if RunService:IsStudio() then
    ReplicatedStorage:SetAttribute("DevServerReady", buildInfo.version)
    print(string.format("[Roommate] Server ready (%s)", buildInfo.version))
end
