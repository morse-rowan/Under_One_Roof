--!strict
local Sandbox = {}

-- `options.paletteKeys = false` frees the number keys for a mode that needs them.
-- The returned handle lets a gameplay module ask where a player is standing
-- without ever reaching into this module's internals.
function Sandbox.start(options: any?)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local config = require(shared.VisualStudy)
    local Grid = require(shared.GridMovement)
    local Scene = require(script.Parent.VisualStudyScene)
    Players.CharacterAutoLoads = false
    -- `options.roommates` makes the four standing beans into walking actors. They
    -- then reserve tiles dynamically like players instead of being permanent walls,
    -- and a caller drives them through the `roommates` handle returned below.
    local mobile = (options and options.roommates) == true
    local scene = Scene.build(
        workspace:WaitForChild("DevStage") :: Model,
        config,
        Grid,
        { mobileRoommates = mobile }
    )
    if RunService:IsStudio() then
        require(script.Parent.NemotronSanity).start(scene)
    end
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
    -- The colour the player picked on the home screen, so their bean matches the
    -- identity the round gives them. Rebuilt beans keep it.
    local tints: { [Player]: { number } } = {}
    local defaultTint = { 57, 138, 222 }

    local function paint(model: Model, rgb: { number })
        local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") and part.Name ~= "Eye" then
                part.Color = color
            end
        end
    end
    local blocked = Grid.blocked(config, not mobile)

    -- Walking roommates, keyed by bean name. Empty unless `options.roommates`.
    -- The client identifies an actor by `modelName`, so these carry synthetic
    -- negative IDs that can never collide with a Roblox UserId.
    local npcs: { [string]: any } = {}

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
    -- Everything that occupies a tile, for `Grid.begin`'s reservation check: a
    -- player and a roommate must not step onto the same square or swap places.
    local function occupants(): { any }
        local all = {}
        for _, actor in actors do
            table.insert(all, actor)
        end
        for _, actor in npcs do
            table.insert(all, actor)
        end
        return all
    end
    local function entry(userId: number, actor: any): any
        return {
            userId = userId,
            modelName = actor.model.Name,
            cell = actor.cell,
            target = actor.target,
            startsAt = actor.landsAt - config.hopSeconds,
            angle = actor.angle,
        }
    end
    local function snapshot(player: Player)
        local entries = {}
        for owner, actor in actors do
            table.insert(entries, entry(owner.UserId, actor))
        end
        for _, actor in npcs do
            table.insert(entries, entry(actor.userId, actor))
        end
        remote:FireClient(player, { kind = "snapshot", actors = entries })
    end
    local function freeSpawn(owner: Player): any
        for offset = 0, config.columns - 1 do
            local candidate = { c = (config.spawn.c + offset) % config.columns, r = config.spawn.r }
            local available = not blocked[Grid.key(candidate)]
            local mine = actors[owner]
            for _, actor in occupants() do
                if
                    actor ~= mine
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
    -- One broadcast shape for every hop, whoever took it.
    local function announce(userId: number, actor: any, destination: any, now: number)
        remote:FireAllClients({
            kind = "hop",
            userId = userId,
            modelName = actor.model.Name,
            cell = actor.cell,
            target = destination,
            startsAt = now,
            angle = actor.angle,
        })
    end

    if mobile then
        for index, data in config.roommates do
            local model = scene:FindFirstChild(data.name) :: Model?
            if model then
                npcs[data.name] = {
                    userId = -index,
                    cell = { c = data.c, r = data.r },
                    home = { c = data.c, r = data.r },
                    target = nil,
                    landsAt = 0,
                    model = model,
                    angle = 0,
                }
                stamp(npcs[data.name])
            else
                warn("[Roommate] No bean named " .. data.name .. "; it cannot walk.")
            end
        end
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
            tints[player] or defaultTint,
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
        for _, actor in occupants() do
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
            then Grid.begin(config, actor, request.direction, now, blocked, occupants())
            else nil
        if not destination then
            remote:FireClient(player, { kind = "rejected" })
            return
        end
        actor.angle = math.atan2(destination.c - actor.cell.c, destination.r - actor.cell.r)
        stamp(actor)
        announce(player.UserId, actor, destination, now)
    end)
    local label = (options and options.label) or "visual-sandbox-1"
    ReplicatedStorage:SetAttribute("DevServerReady", label)
    print(string.format("[Roommate] Server ready (%s): grid movement online", label))
    return {
        config = config,
        grid = Grid,
        scene = scene,
        -- Recolour one player's bean. Presentation only: no rule reads this.
        tint = function(player: Player, rgb: { number })
            tints[player] = rgb
            local actor = actors[player]
            if actor then
                paint(actor.model, rgb)
            end
        end,
        -- Walking roommates. Empty unless `options.roommates` was set; a caller that
        -- owns the round drives them, because only it knows what the errand is.
        roommates = {
            enabled = mobile,
            -- Where the grid says furniture is, with the roommates left out.
            blocked = blocked,
            cellOf = function(name: string): any?
                local actor = npcs[name]
                return if actor then actor.target or actor.cell else nil
            end,
            homeOf = function(name: string): any?
                local actor = npcs[name]
                return if actor then actor.home else nil
            end,
            busy = function(name: string): boolean
                local actor = npcs[name]
                return actor == nil or actor.target ~= nil
            end,
            -- One hop, refused exactly like a player's when the tile is taken.
            step = function(name: string, direction: any): boolean
                local actor = npcs[name]
                if not actor then
                    return false
                end
                local now = workspace:GetServerTimeNow()
                Grid.finish(actor, now)
                local destination = Grid.begin(config, actor, direction, now, blocked, occupants())
                if not destination then
                    return false
                end
                actor.angle = math.atan2(destination.c - actor.cell.c, destination.r - actor.cell.r)
                stamp(actor)
                announce(actor.userId, actor, destination, now)
                return true
            end,
        },
        cellOf = function(player: Player): any?
            local actor = actors[player]
            if not actor then
                return nil
            end
            -- Mid-hop counts as already arrived: the chore you jumped toward is
            -- the one you meant, and the round's own budget still gates it.
            return actor.target or actor.cell
        end,
    }
end

return Sandbox
