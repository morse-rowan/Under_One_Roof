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

local STOP_PHASES = { morning = true, midday = true, night = true }
local CHORE_ACTIONS = { finish_chore = true, pickup_trash = true }

function Session.start(sandbox: any)
    local config = sandbox.config
    local remote = Instance.new("RemoteEvent")
    remote.Name = "RoundLink"
    remote.Parent = ReplicatedStorage

    local issues = Instance.new("Folder")
    issues.Name = "Issues"
    issues.Parent = sandbox.scene

    local sessions: { [Player]: any } = {}
    local lastRequest: { [Player]: number } = {}

    local function now(): number
        return workspace:GetServerTimeNow()
    end

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
                and (item.resolved or model:GetAttribute("Stage") ~= stage or not model.Parent)
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
        return World.reachable(
            config,
            state.items,
            sandbox.cellOf(session.player),
            Round.candidates(state, Setup.player),
            Setup.player
        )
    end

    local function push(session: any)
        local state = session.state
        local chore = reachableChore(session)
        remote:FireClient(session.player, {
            kind = "state",
            observation = Round.observe(state, Setup.player),
            startedAt = session.phaseStartedAt,
            endsAt = session.phaseEndsAt,
            work = Round.workView(state, Setup.player),
            reachable = chore and { reference = chore.action.reference, prompt = chore.prompt },
        })
    end

    local function changed(session: any)
        syncProps(session)
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

    local function npcTurn(session: any, speaking: boolean)
        local state = session.state
        for _, id in state.order do
            if state.actors[id].role == "npc" and state.status == "running" then
                local observation = Round.observe(state, id)
                local decision = Policy.decide(observation, Policy.styleFor(id), speaking)
                if speaking then
                    if decision.message then
                        commit(session, id, nil, decision.message)
                    end
                elseif decision.action then
                    commit(session, id, decision.action, nil)
                end
            end
        end
        changed(session)
    end

    ------------------------------------------------------------------ phase clock

    local advance

    local function beginRecall(session: any)
        local state = session.state
        local view = Round.workView(state, Setup.player)
        if view and view.stage == "preview" then
            Round.beginRecall(state, Setup.player, state.revision, view.id)
            changed(session)
        end
    end

    -- Running out of time still pays the guaranteed base wage; only the bonus is lost.
    local function forceSubmit(session: any)
        local state = session.state
        local view = Round.workView(state, Setup.player)
        if view and view.stage == "preview" then
            beginRecall(session)
            view = Round.workView(state, Setup.player)
        end
        if view and view.stage == "recall" then
            Round.submitWork(state, Setup.player, state.revision, view.id, {})
            changed(session)
        end
    end

    local function schedule(session: any)
        local state = session.state
        local phase = state.phase
        local duration = Setup.phaseSeconds(phase)
        local start = now()
        session.beats = {}
        session.phaseStartedAt = start
        session.phaseEndsAt = start + duration
        local function beat(at: number, fn: (any) -> ())
            table.insert(session.beats, { at = at, fn = fn })
        end
        if phase == "work" then
            local view = Round.workView(state, Setup.player)
            local preview = Setup.previewSeconds(if view then view.length else 3)
            session.phaseEndsAt = start + preview + duration
            beat(start + preview, beginRecall)
            beat(session.phaseEndsAt - 0.5, forceSubmit)
        elseif STOP_PHASES[phase] then
            for _, fraction in { 0.15, 0.4, 0.62 } do
                beat(start + duration * fraction, function(s)
                    npcTurn(s, true)
                end)
            end
            beat(start + duration * 0.82, function(s)
                npcTurn(s, false)
            end)
        else
            beat(start + duration * Setup.npcCommitAt, function(s)
                npcTurn(s, false)
            end)
        end
    end

    local function runBeats(session: any, until_: number)
        table.sort(session.beats, function(a, b)
            return a.at < b.at
        end)
        while #session.beats > 0 and session.beats[1].at <= until_ do
            local entry = table.remove(session.beats, 1)
            entry.fn(session)
        end
    end

    function advance(session: any)
        local state = session.state
        runBeats(session, math.huge)
        if state.phase == "work" and not state.workSubmitted then
            forceSubmit(session)
        end
        local ok = Round.advance(state, state.revision)
        if not ok then
            return
        end
        if state.status == "running" then
            schedule(session)
        else
            session.beats = {}
            session.phaseEndsAt = now()
        end
        changed(session)
    end

    ---------------------------------------------------------------- session setup

    local function clearProps(player: Player)
        local previous = sessions[player]
        for _, model in if previous then previous.props else {} do
            model:Destroy()
        end
    end

    local function newSession(player: Player)
        clearProps(player)
        local seed = 1 + math.floor((os.time() + player.UserId) % 2147483645)
        local session = {
            player = player,
            state = Round.new(Setup.actors, seed, Setup.rules),
            carrying = {},
            props = {},
            beats = {},
            phaseStartedAt = now(),
            phaseEndsAt = now(),
        }
        sessions[player] = session
        schedule(session)
        changed(session)
        print(
            string.format(
                "[Round] %s started %s (seed %d, %d days)",
                player.Name,
                Setup.version,
                seed,
                session.state.config.days
            )
        )
        return session
    end

    ------------------------------------------------------------- player requests

    -- Rebuild the request from the server's own candidate list so a forged amount
    -- or an out-of-date reference can never be applied.
    local function candidateFor(state: any, kind: any, reference: any): any?
        for _, candidate in Round.candidates(state, Setup.player) do
            if candidate.kind == kind and candidate.reference == reference then
                return candidate
            end
        end
        return nil
    end

    local function tryAction(session: any, kind: any, reference: any)
        local state = session.state
        local candidate = candidateFor(state, kind, reference)
        if not candidate then
            return
        end
        if CHORE_ACTIONS[kind] then
            local chore = reachableChore(session)
            if not chore or chore.action.reference ~= candidate.reference then
                return
            end
        end
        if commit(session, Setup.player, candidate, nil, true) then
            if kind == "pickup_trash" then
                session.carrying[candidate.reference] = true
            elseif kind == "finish_chore" then
                session.carrying[candidate.reference] = nil
            end
            changed(session)
        end
    end

    local function trySpeech(session: any, request: any)
        local state = session.state
        local speech = request.speech
        if type(speech) ~= "string" then
            return
        end
        speech = string.sub(speech, 1, state.config.speechBytes)
        local channel = if request.channel == "private" then "private" else "group"
        local target = if channel == "private" then request.target else nil
        if channel == "private" and (type(target) ~= "string" or not state.actors[target]) then
            return
        end
        local envelope = { channel = channel, target = target, speech = speech }
        if commit(session, Setup.player, nil, envelope, true) then
            changed(session)
        end
    end

    local function trySubmit(session: any, answers: any)
        local state = session.state
        local view = Round.workView(state, Setup.player)
        if not view or view.stage ~= "recall" or type(answers) ~= "table" then
            return
        end
        local clean = {}
        for index = 1, math.min(#answers, view.length) do
            local value = answers[index]
            if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > view.symbols then
                return
            end
            clean[index] = value
        end
        if Round.submitWork(state, Setup.player, state.revision, view.id, clean) then
            changed(session)
        end
    end

    remote.OnServerEvent:Connect(function(player: Player, request: any)
        local session = sessions[player]
        if not session or type(request) ~= "table" or type(request.kind) ~= "string" then
            return
        end
        local clock = os.clock()
        if clock - (lastRequest[player] or 0) < 0.1 then
            return
        end
        lastRequest[player] = clock
        local state = session.state
        local kind = request.kind
        if kind == "sync" then
            push(session)
        elseif kind == "restart" then
            if state.status ~= "running" then
                newSession(player)
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
        elseif kind == "recall" then
            beginRecall(session)
        elseif kind == "submit" then
            trySubmit(session, request.answers)
        elseif kind == "ready" and state.phase ~= "work" then
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

    -- One clock for every session: scheduled beats first, then the phase boundary.
    RunService.Heartbeat:Connect(function()
        local stamp = now()
        for _, session in sessions do
            if session.state.status == "running" then
                runBeats(session, stamp)
                if stamp >= session.phaseEndsAt then
                    advance(session)
                end
            end
        end
    end)

    print("[Round] Authority online: " .. Round.mechanicsVersion .. " / " .. Setup.version)
end

return Session
