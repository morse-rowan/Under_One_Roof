--!strict
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

-- Check the actual serialized place: catches broken mappings and accidental test packaging.
return function()
    local place = roblox.deserializePlace(fs.readFile("build/RoommateDev.rbxlx"))
    local shared = place:GetService("ReplicatedStorage"):FindFirstChild("Shared")
    assert(shared and shared:FindFirstChild("BuildInfo"), "Shared/BuildInfo missing")
    assert(shared.BuildInfo:IsA("ModuleScript"), "BuildInfo must be a ModuleScript")
    local server = place:GetService("ServerScriptService"):FindFirstChild("Server")
    assert(server and server:FindFirstChild("Main"), "Server/Main missing")
    assert(server.Main:IsA("Script"), "Server entry must be a Script")
    local scripts = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    assert(scripts and scripts:FindFirstChild("Client"), "Client folder missing")
    assert(scripts.Client.Main:IsA("LocalScript"), "Client entry must be a LocalScript")
    for _, name in { "VisualStudy", "GridMovement", "RoundBrain", "RoundRoutine" } do
        assert(shared:FindFirstChild(name) and shared[name]:IsA("ModuleScript"), name .. " missing")
    end
    -- The model adapter and the errand driver are server-only on purpose: a client
    -- must never be able to read the bridge URL or drive a roommate.
    for _, name in
        {
            "RoundBrainService",
            "RoundErrands",
            "RoundVoices",
            "PresentationConfig",
            "PresentationAccess",
        }
    do
        assert(server:FindFirstChild(name) and server[name]:IsA("ModuleScript"), name .. " missing")
        assert(not scripts.Client:FindFirstChild(name), name .. " must not ship to clients")
        assert(not shared:FindFirstChild(name), name .. " must not be replicated")
    end
    assert(server.VisualSandbox:IsA("ModuleScript"), "Visual sandbox server missing")
    assert(server.VisualStudyScene:IsA("ModuleScript"), "Visual scene builder missing")
    assert(scripts.Client.VisualSandbox:IsA("ModuleScript"), "Visual sandbox client missing")
    local stage = place:GetService("Workspace"):FindFirstChild("DevStage")
    assert(stage and stage.Floor.Anchored, "Anchored development floor missing")
    assert(stage.Spawn:IsA("SpawnLocation"), "Development spawn missing")
    for _, instance in place:GetDescendants() do
        assert(not string.find(instance.Name, ".spec", 1, true), "Test leaked into place")
    end
end
