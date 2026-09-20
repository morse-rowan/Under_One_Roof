--!strict
local Sandbox = {}

function Sandbox.start()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local config = require(shared.VisualStudy)
    local Grid = require(shared.GridMovement)
    local Scene = require(script.Parent.VisualStudyScene)
    Players.CharacterAutoLoads = false
    local scene = Scene.build(workspace:WaitForChild("DevStage") :: Model, config, Grid)
    require(script.Parent.NemotronSanity).start(scene)
    Lighting.ClockTime = 14
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(137, 132, 121)
    Lighting.OutdoorAmbient = Color3.fromRGB(166, 169, 165)
    Lighting.EnvironmentDiffuseScale = 0.5
    Lighting.EnvironmentSpecularScale = 0.2
    Lighting.GlobalShadows = true

    local remote = Instance.new("RemoteEvent")
    remote.Name = "VisualStudyMove"
    remote.Parent = ReplicatedStorage
    local actors: { [Player]: any } = {}
    local lastRequest: { [Player]: number } = {}
    local blocked = Grid.blocked(config)

    local function pose(cell: any, angle: number): CFrame
        local x, z = Grid.point(config, cell)
        return CFrame.new(x, config.floorY, z) * CFrame.Angles(0, angle, 0)
    end
    local function stamp(actor: any)
        actor.model:SetAttribute("Column", actor.cell.c)
        actor.model:SetAttribute("Row", actor.cell.r)
        actor.model:SetAttribute("Room", Grid.room(config, actor.cell))
        actor.model:SetAttribute("Hopping", actor.target ~= nil)
    end
    local function snapshot(player: Player)
        local entries = {}
        for owner, actor in actors do
            table.insert(entries, {
                userId = owner.UserId,
                modelName = actor.model.Name,
                cell = actor.cell,
                target = actor.target,
                startsAt = actor.landsAt - config.hopSeconds,
                angle = actor.angle,
            })
        end
        remote:FireClient(player, { kind = "snapshot", actors = entries })
    end
    local function freeSpawn(owner: Player): any
        for offset = 0, config.columns - 1 do
            local candidate = { c = (config.spawn.c + offset) % config.columns, r = config.spawn.r }
            local available = not blocked[Grid.key(candidate)]
            for other, actor in actors do
                if
                    other ~= owner
                    and (
                        Grid.key(actor.cell) == Grid.key(candidate)
                        or (actor.target and Grid.key(actor.target) == Grid.key(candidate))
                    )
                then
                    available = false
                end
            end
            if available then
                return candidate
            end
        end
        return nil
    end
    local function joined(player: Player)
        if actors[player] then
            return
        end
        local cell = freeSpawn(player)
        if not cell then
            return
        end
        if player.Character then
            player.Character:Destroy()
        end
        local model = Scene.bean(
            workspace.DevStage.VisualStudy,
            player.Name,
            { 57, 138, 222 },
            pose(cell, 0).Position,
            config.palettes.Warm
        )
        local humanoid = Instance.new("Humanoid")
        humanoid.RequiresNeck = false
        humanoid.BreakJointsOnDeath = false
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.JumpHeight = 0
        humanoid.AutoRotate = false
        humanoid.EvaluateStateMachine = false
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.Parent = model
        actors[player] = { cell = cell, target = nil, landsAt = 0, model = model, angle = 0 }
        stamp(actors[player])
        player.Character = model
        humanoid.Died:Once(function()
            task.defer(function()
                if
                    player.Parent == Players
                    and actors[player]
                    and actors[player].model == model
                then
                    actors[player] = nil
                    joined(player)
                    for other in actors do
                        snapshot(other)
                    end
                end
            end)
        end)
        for other in actors do
            snapshot(other)
        end
    end

    Players.PlayerAdded:Connect(joined)
    Players.PlayerRemoving:Connect(function(player)
        local actor = actors[player]
        if actor then
            actor.model:Destroy()
        end
        actors[player] = nil
        lastRequest[player] = nil
        for other in actors do
            snapshot(other)
        end
    end)
    for _, player in Players:GetPlayers() do
        joined(player)
    end

    RunService.Heartbeat:Connect(function()
        local now = workspace:GetServerTimeNow()
        for _, actor in actors do
            if Grid.finish(actor, now) then
                actor.model:PivotTo(pose(actor.cell, actor.angle))
                stamp(actor)
            end
        end
    end)

    remote.OnServerEvent:Connect(function(player: Player, request: any)
        local actor = actors[player]
        if not actor or type(request) ~= "table" then
            return
        end
        local now = workspace:GetServerTimeNow()
        -- A small abuse cap; legitimate client sends at most one request per hop.
        if now - (lastRequest[player] or 0) < 0.04 then
            remote:FireClient(player, { kind = "rejected" })
            return
        end
        lastRequest[player] = now
        if request.kind == "sync" then
            snapshot(player)
            return
        end
        if Grid.finish(actor, now) then
            actor.model:PivotTo(pose(actor.cell, actor.angle))
            stamp(actor)
        end
        if request.kind == "reset" and not actor.target then
            local cell = freeSpawn(player)
            if cell then
                actor.cell = cell
                actor.angle = 0
                actor.model:PivotTo(pose(cell, 0))
                stamp(actor)
                for other in actors do
                    snapshot(other)
                end
                return
            end
        end
        local destination = if request.kind == "step"
            then Grid.begin(config, actor, request.direction, now, blocked, actors)
            else nil
        if not destination then
            remote:FireClient(player, { kind = "rejected" })
            return
        end
        actor.angle = math.atan2(destination.c - actor.cell.c, destination.r - actor.cell.r)
        stamp(actor)
        remote:FireAllClients({
            kind = "hop",
            userId = player.UserId,
            modelName = actor.model.Name,
            cell = actor.cell,
            target = destination,
            startsAt = now,
            angle = actor.angle,
        })
    end)
    ReplicatedStorage:SetAttribute("DevServerReady", "visual-sandbox-1")
    print("[Roommate] Server ready (visual-sandbox-1): visual movement trial; gameplay disabled")
end

return Sandbox
