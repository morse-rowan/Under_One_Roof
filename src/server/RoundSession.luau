--!strict
-- Server authority for the playable MVP round. `MvpRound` owns every rule; this
-- module only decides when a phase opens or closes, whose turn it is, and whether
-- the player is standing close enough to touch a chore. Nothing here recomputes a
-- cost, a meter or a legality: it asks the round for candidates and replays one.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Session = {}

local shared = ReplicatedStorage:WaitForChild("Shared")
local Round = require(shared:WaitForChild("MvpRound"))
local Setup = require(shared:WaitForChild("RoundSetup"))
local Policy = require(shared:WaitForChild("RoundPolicy"))
local World = require(shared:WaitForChild("RoundWorld"))
local Grid = require(shared:WaitForChild("GridMovement"))
local Props = require(script.Parent.RoundProps)
local Flow = require(shared:WaitForChild("HousepadFlow"))
local Send = require(shared:WaitForChild("HousepadSend"))
local Interactions = require(shared:WaitForChild("RoundInteractions"))
local Build = require(shared:WaitForChild("BuildInfo"))
local Routine = require(shared:WaitForChild("RoundRoutine"))
local Clues = require(script.Parent.RoundClues)
local BrainService = require(script.Parent.RoundBrainService)
local Errands = require(script.Parent.RoundErrands)

local CHORE_ACTIONS = { finish_chore = true, pickup_trash = true }

function Session.start(sandbox: any)
    local config = sandbox.config
    -- One switch for the whole server. Each household gets its own call budget, so
    -- restarting a run also restarts the spend.
    local brainEnabled = Build.brain.enabled == true
    local remote = Instance.new("RemoteEvent")
    remote.Name = "RoundLink"
    remote.Parent = ReplicatedStorage

    local issues = Instance.new("Folder")
    issues.Name = "Issues"
    issues.Parent = sandbox.scene

    local sessions: { [Player]: any } = {}
    local lastRequest: { [Player]: number } = {}
    local best: { [Player]: number } = {}
    local chosenColor: { [Player]: string } = {}

    local function cellPoint(cell: any): Vector3
        local x, z = Grid.point(config, cell)
        return Vector3.new(x, config.floorY, z)
    end

    ----------------------------------------------------------------- presentation

    -- Props are owned per session and keyed by issue ID. A carried bag is parented
    -- to the bean so the client's own hop interpolation moves it, instead of the
    -- server snapping it to cell centres every tick.
    local function syncProps(session: any)
        local state = session.state
        local character = session.player.Character
        for _, item in state.items do
            local model = session.props[item.id]
            local stage = if item.kind == "trash" then item.stage else item.kind
            if item.resolved then
                session.carrying[item.id] = nil
            end
            if
                model
                and (
                    item.resolved
                    or model:GetAttribute("Stage") ~= stage
                    or model:GetAttribute("VisualAge") ~= math.min(item.age or 0, 4)
                    or not model.Parent
                )
            then
                model:Destroy()
                model = nil
                session.props[item.id] = nil
            end
            if not item.resolved then
                if not model then
                    model = Props.build(issues, item)
                    model:SetAttribute("Stage", stage)
                    session.props[item.id] = model
                end
                local held = session.carrying[item.id]
                    and character
                    and character.PrimaryPart ~= nil
                if held and model.Parent ~= character then
                    model.Parent = character
                    model:SetAttribute("Room", nil)
                    Props.place(
                        model,
                        (character :: any).PrimaryPart.Position + Vector3.new(0, 0.9, 0)
                    )
                elseif not held and model.Parent ~= issues then
                    model.Parent = issues
                end
                local cell = if held then nil else World.homeCell(config, item)
                if cell then
                    model:SetAttribute("Room", Grid.room(config, cell))
                    Props.place(model, cellPoint(cell))
                end
            end
        end
    end

    -- The one chore the player could do from where they are standing right now.
    local function reachableChore(session: any): any?
        local state = session.state
        if state.status ~= "running" then
            return nil
        end
        -- Chores still win; `Interactions` adds the clue fallback behind them.
        local interactionState = {
            actor = { id = session.playerId },
            items = state.items,
            candidates = Round.candidates(state, session.playerId),
        }
        return Interactions.reachable(config, interactionState, sandbox.cellOf(session.player))
    end

    local function push(session: any)
        local state = session.state
        if state.status ~= "running" then
            -- Days survived is the score. Kept per player for this server's
            -- lifetime only: nothing is persisted or published.
            if session.record == nil then
                session.record = state.survived > (best[session.player] or 0)
            end
            best[session.player] = math.max(best[session.player] or 0, state.survived)
            session.best = best[session.player]
        end
        local chore = reachableChore(session)
        remote:FireClient(session.player, {
            kind = "state",
            observation = Round.observe(state, session.playerId),
            developer = RunService:IsStudio(),
            notice = session.notice,
            color = session.color,
            colors = Setup.playerColors,
            best = session.best,
            record = session.record == true,
            entered = session.entered,
            receipt = session.receipt,
            targets = Interactions.targets(
                config,
                Round.observe(state, session.playerId),
                sandbox.cellOf(session.player)
            ),
            manual = true,
            reachable = chore and { reference = chore.action.reference, prompt = chore.prompt },
        })
    end

    local function changed(session: any)
        syncProps(session)
        Clues.sync(
            session.clues,
            Interactions.markers(config, Round.observe(session.state, session.playerId)),
            cellPoint,
            function(cell)
                return Grid.room(config, cell)
            end
        )
        push(session)
    end

    -------------------------------------------------------------------- NPC turns

    -- Policy failures become labelled administrative waits instead of silent skips.
    -- A rejected player click is ordinary stale input and stays quiet.
    local function commit(session: any, id: string, action: any?, message: any?, quiet: boolean?)
        local state = session.state
        local ok, reason = Round.decide(state, id, state.revision, action, message)
        if not ok and not quiet and reason ~= "empty_decision" then
            warn(string.format("[Round] %s decision rejected (%s); treated as a wait", id, reason))
        end
        return ok
    end

    -- Only explicit requests move the round. The flow has no wall clock.
    local function advance(session: any)
        local ok, reason = Flow.advance(Round, Policy, session.state, session.brain)
        session.notice = if ok then nil else reason
        changed(session)
    end

    ---------------------------------------------------------------- session setup

    local function clearProps(player: Player)
        local previous = sessions[player]
        if previous and previous.clues then
            previous.clues:Destroy()
        end
        for _, model in if previous then previous.props else {} do
            model:Destroy()
        end
    end

    local function newSession(player: Player, chosenSeed: number?, color: string?)
        clearProps(player)
        local seed = chosenSeed or (1 + math.floor((os.time() + player.UserId) % 2147483645))
        local picked = if color and Setup.isPlayerColor(color)
            then color
            else chosenColor[player] or Setup.defaultColor
        chosenColor[player] = picked
        local clueFolder = Instance.new("Folder")
        clueFolder.Name = "Clues_" .. player.UserId
        clueFolder.Parent = sandbox.scene
        local session = {
            clues = clueFolder,
            brain = BrainService.new({
                url = Build.brain.url,
                maxCalls = Build.brain.maxCalls,
                deadline = Build.brain.deadline,
                isEnabled = function()
                    return brainEnabled
                end,
            }),
            player = player,
            playerId = picked,
            color = picked,
            best = best[player] or 0,
            -- False until the player actually plays: the colour can still change.
            entered = false,
            -- Set once, when this household ends, if it beat the player's best.
            record = nil,
            state = Round.new(Setup.household(picked), seed, Setup.rules),
            carrying = {},
            props = {},
            notice = nil,
        }
        sessions[player] = session
        if sandbox.tint then
            sandbox.tint(player, Setup.rgb(picked))
        end
        Flow.speak(Round, Policy, session.state, session.brain)
        changed(session)
        print(
            string.format(
                "[Round] %s started %s as %s (seed %d, rent every %d days, roommates %s)",
                player.Name,
                Setup.version,
                picked,
                seed,
                session.state.config.rentEvery,
                session.brain.status()
            )
        )
        return session
    end

    ------------------------------------------------------------- player requests

    -- Rebuild the request from the server's own candidate list so a forged amount
    -- or an out-of-date reference can never be applied.
    local function candidateFor(session: any, kind: any, reference: any): any?
        local state = session.state
        for _, candidate in Round.candidates(state, session.playerId) do
            if candidate.kind == kind and candidate.reference == reference then
                return candidate
            end
        end
        return nil
    end

    local function tryAction(session: any, kind: any, reference: any)
        local candidate = candidateFor(session, kind, reference)
        if not candidate then
            return
        end
        if CHORE_ACTIONS[kind] then
            local chore = reachableChore(session)
            if not chore or chore.action.reference ~= candidate.reference then
                return
            end
        end
        if commit(session, session.playerId, candidate, nil, true) then
            if kind == "pickup_trash" then
                session.carrying[candidate.reference] = true
            elseif kind == "finish_chore" then
                session.carrying[candidate.reference] = nil
            end
            session.notice = nil
            changed(session)
        end
    end

    local function trySpeech(session: any, request: any)
        local state = session.state
        -- `Send` owns the prose/attachment transaction; `MvpRound.decide` still
        -- rejects an illegal channel or target, so this speaks as the player.
        local ok, reason = Send.submit(Round, state, session.playerId, request)
        session.notice = reason
        session.receipt = { requestId = request.requestId, accepted = ok }
        if ok then
            Flow.speak(Round, Policy, state, session.brain)
        end
        changed(session)
    end

    local function command(player: Player, raw: any)
        -- Both the remote and server command-bar path are development-only.
        if not RunService:IsStudio() then
            return
        end
        local session = sessions[player]
        if not session then
            return
        end
        local parsed, reason = Flow.parse(raw)
        if not parsed then
            session.notice = reason
        elseif parsed.kind == "help" then
            session.notice = Flow.help
        elseif parsed.kind == "reset" then
            newSession(player, parsed.seed)
            return
        elseif parsed.kind == "brain" then
            -- Server-wide, and deliberately not reset by `/reset`: a demo run is
            -- either using live roommates or it is not.
            brainEnabled = parsed.enabled
            session.notice = "Live roommates: " .. session.brain.status()
        elseif session.state.status ~= "running" then
            session.notice = "The household has finished. Use /reset."
        elseif parsed.kind == "set" then
            session.notice =
                Flow.setStat(Round, session.state, session.playerId, parsed.stat, parsed.value)
        elseif parsed.kind == "next" then
            advance(session)
            return
        elseif parsed.kind == "day" then
            local day = session.state.day
            for _ = 1, 6 do
                if session.state.status ~= "running" or session.state.day ~= day then
                    break
                end
                Flow.advance(Round, Policy, session.state, session.brain)
            end
            session.notice = "Advanced to the next morning or the household's ending."
        end
        changed(session)
    end

    if RunService:IsStudio() then
        local controls = Instance.new("BindableFunction")
        controls.Name = "HousepadCommand"
        controls.Parent = game:GetService("ServerStorage")
        controls.OnInvoke = function(raw: any, userId: number?)
            local player = if userId
                then Players:GetPlayerByUserId(userId)
                else Players:GetPlayers()[1]
            if not player then
                return "No player is connected."
            end
            command(player, raw)
            local session = sessions[player]
            return {
                notice = session.notice,
                observation = Round.observe(session.state, session.playerId),
            }
        end
    end

    remote.OnServerEvent:Connect(function(player: Player, request: any)
        local session = sessions[player]
        if not session or type(request) ~= "table" or type(request.kind) ~= "string" then
            return
        end
        local clock = os.clock()
        if clock - (lastRequest[player] or 0) < 0.1 then
            if request.kind == "message" then
                session.notice = "One moment—send again when you're ready."
                session.receipt = { requestId = request.requestId, accepted = false }
                push(session)
            end
            return
        end
        lastRequest[player] = clock
        local state = session.state
        local kind = request.kind
        if kind == "sync" then
            push(session)
        elseif kind == "command" then
            command(player, request.text)
        elseif kind == "restart" then
            if state.status ~= "running" then
                newSession(player)
            end
        elseif kind == "newRound" then
            -- Deliberate "start a new household" from the home screen. Unlike
            -- restart, it may discard a running household, because the player
            -- asked for that from a screen where nothing else is happening.
            newSession(player, nil, request.color)
        elseif kind == "color" then
            -- The home screen's colour picker. It rebuilds the household only
            -- while the player has not entered it, and never mid-run.
            if
                type(request.color) == "string"
                and Setup.isPlayerColor(request.color)
                and request.color ~= session.playerId
                and not session.entered
                and state.status == "running"
            then
                newSession(player, nil, request.color)
            end
        elseif kind == "enter" then
            -- The player opened the household from the home screen: the colour
            -- is settled from here on.
            if not session.entered then
                session.entered = true
                push(session)
            end
        elseif state.status ~= "running" then
            return
        elseif kind == "action" then
            tryAction(session, request.action, request.reference)
        elseif kind == "chore" then
            local chore = reachableChore(session)
            if chore then
                tryAction(session, chore.action.kind, chore.action.reference)
            end
        elseif kind == "message" then
            trySpeech(session, request)
        elseif kind == "ready" then
            advance(session)
        end
    end)

    Players.PlayerAdded:Connect(newSession)
    Players.PlayerRemoving:Connect(function(player)
        clearProps(player)
        sessions[player] = nil
        lastRequest[player] = nil
    end)
    for _, player in Players:GetPlayers() do
        newSession(player)
    end

    -- Roommates walk and carry out their own choices while an action window is open.
    -- `commit` and `changed` are passed in, so the errands never touch the round or
    -- the client directly: they ask for the same replay a player's click gets.
    local errands = Errands.new({
        sandbox = sandbox,
        round = Round,
        policy = Policy,
        routine = Routine,
        beans = Setup.beans,
        commit = function(session: any, id: string, action: any): boolean
            return commit(session, id, action, nil, true)
        end,
        changed = changed,
    })

    -- Movement changes only the interaction hint, never the phase or NPC turn.
    -- Only push when the reachable chore actually changes, preserving typed drafts.
    RunService.Heartbeat:Connect(function()
        -- There is one apartment and one set of beans, so one household drives them.
        -- Every player still has their own round; a second player would watch the
        -- first player's roommates walk. Solo play is the demo's scope.
        local host = Players:GetPlayers()[1]
        if host and sessions[host] then
            errands.update(sessions[host])
        end
        for _, session in sessions do
            local chore = reachableChore(session)
            local cell = sandbox.cellOf(session.player)
            local key = (if chore then tostring(chore.action.reference) .. chore.prompt else "")
                .. (if cell then Grid.key(cell) else "")
            if key ~= session.reachableKey then
                session.reachableKey = key
                push(session)
            end
        end
    end)

    print("[Round] Authority online: " .. Round.mechanicsVersion .. " / " .. Setup.version)
end

return Session
