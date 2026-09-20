--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local shared = ReplicatedStorage:WaitForChild("Shared")
local build = require(shared:WaitForChild("BuildInfo"))
if build.menuPreview then
    require(script.Parent.MenuPreview).start()
end
if build.mode == "mvp" then
    -- The apartment and its grid stay exactly as the visual study left them; the
    -- round is layered on top and owns every rule.
    local sandbox = require(script.Parent.VisualSandbox).start({
        label = build.version,
        paletteKeys = false,
    })
    require(script.Parent.RoundSession).start(sandbox)
    return
end
if build.mode == "visual-sandbox" then
    require(script.Parent.VisualSandbox).start()
    return
end
local config = require(shared:WaitForChild("Apartment"))
local Simulation = require(shared:WaitForChild("Simulation"))
local adapter = require(script.Parent.FakeRoommate)
local Scene = require(script.Parent.ApartmentScene)
local buildInfo = require(shared:WaitForChild("BuildInfo"))

local remote = Instance.new("RemoteEvent")
remote.Name = "ApartmentAction"
remote.Parent = ReplicatedStorage
local states: { [Player]: Simulation.State } = {}
local lastRequest: { [Player]: number } = {}
local pendingChores: { [Player]: { id: string, started: number } } = {}
local stations = Scene.build(workspace:WaitForChild("DevStage") :: Model, config)

local function canReach(player: Player, id: any): boolean
    local station = if type(id) == "string" then stations[id] else nil
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart else nil
    local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
    return station ~= nil
        and root ~= nil
        and humanoid ~= nil
        and humanoid.Health > 0
        and (root.Position - station.Position).Magnitude <= 8
end

local function send(player: Player, message: string?)
    remote:FireClient(player, states[player], message)
end

local function characterReady(player: Player, character: Model)
    pendingChores[player] = nil
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.WalkSpeed = if states[player] and states[player].phase == "action" then 16 else 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    local function simplify(item: Instance)
        if
            item:IsA("Accessory")
            or item:IsA("Shirt")
            or item:IsA("Pants")
            or item:IsA("ShirtGraphic")
            or item:IsA("Decal")
        then
            item:Destroy()
        elseif item:IsA("BasePart") then
            item.Color = Color3.fromRGB(244, 211, 118)
            if item:IsA("MeshPart") then
                item.TextureID = ""
            end
        elseif item:IsA("SpecialMesh") then
            item.TextureId = ""
        elseif item:IsA("BodyColors") then
            for _, property in
                {
                    "HeadColor3",
                    "TorsoColor3",
                    "LeftArmColor3",
                    "RightArmColor3",
                    "LeftLegColor3",
                    "RightLegColor3",
                }
            do
                (item :: any)[property] = Color3.fromRGB(244, 211, 118)
            end
        end
    end
    for _, item in character:GetDescendants() do
        simplify(item)
    end
    character.DescendantAdded:Connect(function(item)
        -- Never destroy a descendant while Roblox is still parenting it.
        task.defer(simplify, item)
    end)
    local appearanceConnection: RBXScriptConnection?
    appearanceConnection = player.CharacterAppearanceLoaded:Connect(function(loaded)
        if loaded == character then
            for _, item in character:GetDescendants() do
                simplify(item)
            end
            if appearanceConnection then
                appearanceConnection:Disconnect()
            end
        end
    end)
    character.Destroying:Once(function()
        if appearanceConnection then
            appearanceConnection:Disconnect()
        end
    end)
end

local function movement(player: Player)
    local humanoid = if player.Character
        then player.Character:FindFirstChildOfClass("Humanoid")
        else nil
    if humanoid then
        humanoid.WalkSpeed = if states[player].phase == "action" then 16 else 0
    end
end

local function joined(player: Player)
    states[player] = Simulation.new(config)
    player.CharacterAdded:Connect(function(character)
        characterReady(player, character)
    end)
    if player.Character then
        task.spawn(characterReady, player, player.Character)
    end
end
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
    states[player] = nil
    lastRequest[player] = nil
    pendingChores[player] = nil
end)
for _, player in Players:GetPlayers() do
    joined(player)
end

remote.OnServerEvent:Connect(function(player: Player, request: any)
    if type(request) ~= "table" or type(request.kind) ~= "string" or not states[player] then
        return
    end
    local now = os.clock()
    if now - (lastRequest[player] or 0) < 0.15 then
        return
    end
    lastRequest[player] = now
    local state = states[player]
    local message = ""
    if request.kind == "sync" then
        message = "Keep the apartment for three days. Plan first; then move with WASD."
    elseif request.kind == "talk" then
        local _, reply = Simulation.openConversation(state, request.roommate, config)
        message = reply
    elseif request.kind == "message" then
        local _, reply = Simulation.message(state, request.text, request.terms, config, adapter)
        message = reply
    elseif request.kind == "start" then
        local _, reply = Simulation.startAction(state)
        message = reply
    elseif request.kind == "beginChore" then
        if
            state.phase == "action"
            and state.effort > 0
            and canReach(player, request.id)
            and state.tasks[request.id].status == "open"
        then
            pendingChores[player] = { id = request.id, started = now }
        end
        return
    elseif request.kind == "completeChore" then
        local pending = pendingChores[player]
        pendingChores[player] = nil
        if
            not pending
            or pending.id ~= request.id
            or now - pending.started < 1
            or not canReach(player, request.id)
        then
            send(player, "Stay close to the station and hold E for one second.")
            return
        end
        local _, reply = Simulation.completeTask(state, request.id, config)
        message = reply
    elseif request.kind == "finish" then
        pendingChores[player] = nil
        local _, reply = Simulation.resolve(state, config)
        message = reply
    elseif request.kind == "next" then
        pendingChores[player] = nil
        local _, reply = Simulation.nextDay(state, config)
        message = reply
    elseif request.kind == "restart" and (state.phase == "won" or state.phase == "lost") then
        pendingChores[player] = nil
        states[player] = Simulation.new(config)
        if player.Character then
            player.Character:PivotTo(CFrame.new(-15, 4, 10))
        end
        message = "Fresh start. Try a different strategy."
    else
        return
    end
    movement(player)
    send(player, message)
end)

task.spawn(function()
    local previous = os.clock()
    while true do
        task.wait(0.5)
        local now = os.clock()
        local elapsed = now - previous
        previous = now
        for player, state in states do
            if Simulation.tick(state, elapsed, config) then
                if state.phase ~= "action" then
                    pendingChores[player] = nil
                end
                movement(player)
                send(
                    player,
                    if state.phase ~= "action" then "Time is up. Here's what happened." else nil
                )
            end
        end
    end
end)

ReplicatedStorage:SetAttribute("DevServerReady", buildInfo.version)
print(string.format("[Roommate] Server ready (%s): apartment simulation online", buildInfo.version))
