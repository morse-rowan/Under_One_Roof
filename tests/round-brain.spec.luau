--!strict
-- The model boundary. Two obligations are checked here: a model never receives
-- controller state, and a model can never talk the round into an illegal move.
-- Latency, the bridge and the hosted model itself are not covered; those need the
-- running bridge and a Studio playtest.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")
local Brain = require("../src/shared/RoundBrain")

local function expect(condition: any, message: string)
    assert(condition, message)
end

-- Anything on these lists is either administrative or a controller tell.
local BANNED_KEYS = {
    "role",
    "memory",
    "relationships",
    "playerActions",
    "npcActions",
    "actionsRemaining",
    "actionLimit",
    "audience",
    "seenBy",
    "revision",
}
local BANNED_EVENT_TEXT = { "player", "npc", "finish_chore", "pickup_trash", "pay_cleanup" }

local function walk(value: any, path: string, visit: (string, any, any) -> ())
    if type(value) ~= "table" then
        return
    end
    for key, item in value do
        visit(path, key, item)
        walk(item, path .. "." .. tostring(key), visit)
    end
end

return function()
    ------------------------------------------------------------------ projection

    local state = Round.new(Setup.actors, 13, Setup.rules)
    expect(Flow.advance(Round, Policy, state), "morning must advance")
    expect(state.phase == "action_one", "expected the first action window")
    -- A roommate's mess the player can physically clear: the one route that would
    -- otherwise read differently from paying someone to do it.
    local chore = #state.items + 1
    table.insert(state.items, {
        id = chore,
        kind = "dishes",
        creator = "green",
        age = 1,
        resolved = false,
        stage = "open",
        day = state.day,
    })
    state.revision += 1
    expect(
        Round.decide(
            state,
            Setup.player,
            state.revision,
            { kind = "finish_chore", reference = chore },
            nil
        ),
        "the player must be able to finish a roommate's chore"
    )
    -- Green spent the morning on rent, so give it enough to pay for a cleanup.
    state.actors.green.cash = 20
    local paid = #state.items + 1
    table.insert(state.items, {
        id = paid,
        kind = "dishes",
        creator = Setup.player,
        age = 1,
        resolved = false,
        stage = "open",
        day = state.day,
    })
    state.revision += 1
    expect(
        Round.decide(
            state,
            "green",
            state.revision,
            { kind = "pay_cleanup", reference = paid, amount = state.config.cleanup },
            nil
        ),
        "a roommate must be able to pay for the player's mess"
    )
    for _ = 1, 4 do
        if state.status == "running" and state.phase ~= "work" then
            Flow.advance(Round, Policy, state)
        end
    end

    local context = Brain.context(Round.observe(state, "green"), "communication")
    walk(context, "context", function(path, key, _)
        for _, banned in BANNED_KEYS do
            expect(
                key ~= banned,
                string.format("%s.%s reaches the model but is controller state", path, banned)
            )
        end
    end)
    expect(context.actor.role == nil, "an actor's controller is never sent")
    expect(context.actor.cash ~= nil and context.actor.goal ~= nil, "own economy is sent")
    expect(context.rules.rent ~= nil and context.rules.speechBytes ~= nil, "rules are sent")
    expect(context.decisionMode == "communication", "the turn's mode is stated")

    -- The player physically did one chore and a roommate paid for another. Both must
    -- read identically: that sameness is the whole point of the normalisation.
    local shapes: { [number]: string } = {}
    walk(context.events, "events", function(path, key, item)
        if type(item) == "string" then
            for _, banned in BANNED_EVENT_TEXT do
                expect(
                    item ~= banned,
                    string.format("%s.%s exposes the cleanup route: %s", path, tostring(key), item)
                )
            end
        end
    end)
    for _, event in context.events do
        if event.kind == "requirement_handled" then
            shapes[event.data.reference] = (string.gsub(event.data.text, "^%a+ ", "", 1)):gsub(
                "#%d+",
                "#n"
            )
        end
        expect(event.kind ~= "phase_closed", "per-controller effort counts are withheld")
    end
    expect(shapes[chore] ~= nil, "the player's own chore must appear as a handled requirement")
    expect(shapes[paid] ~= nil, "a roommate's paid cleanup must appear the same way")
    expect(
        shapes[chore] == shapes[paid],
        "doing a chore and paying for one must read identically: "
            .. shapes[chore]
            .. " / "
            .. shapes[paid]
    )

    ---------------------------------------------------------------------- packet

    local full = Round.observe(state, "green")
    local packet = Brain.packet(full, "action", { historyEvents = 3, historyRecaps = 1 })
    expect(packet.version == Brain.version and packet.mode == "action", "packet is labelled")
    expect(#packet.observation.events <= 3, "history is bounded")
    expect(#packet.observation.recaps <= 1, "recaps are bounded")
    local retained = {}
    for _, event in packet.observation.events do
        retained[event.id] = true
    end
    for _, recap in packet.observation.recaps do
        for _, id in recap.eventIds do
            expect(retained[id], "a recap cannot cite an event the model was not shown")
        end
    end
    expect(string.find(packet.system, "Return JSON only") ~= nil, "the reply shape is stated")

    -------------------------------------------------------------------- aliasing

    local aliased = {
        actorIds = { "p1", "green" },
        actor = { id = "p1", cash = 5 },
        phase = "midday",
        messagesRemaining = 2,
        rules = { speechBytes = 40 },
        events = {},
        items = {},
        plans = {},
        recaps = {},
        candidates = { { kind = "wait" } },
    }
    local names = Brain.aliases(aliased)
    expect(names.green == "green", "a colour ID keeps its own colour")
    expect(names.p1 ~= "green" and table.find(Brain.palette, names.p1), "a non-colour ID gets one")

    ------------------------------------------------------------------ validation

    local stop = {
        actorIds = { "blue", "green", "red" },
        actor = { id = "green", cash = 12 },
        phase = "midday",
        status = "running",
        messagesRemaining = 2,
        rules = { speechBytes = 40 },
        candidates = { { kind = "wait" }, { kind = "contribute", amount = 5 } },
    }
    local action = { assessment = "short", choice = 1, message = nil }
    local decision, reason = Brain.validate(action, stop, "action")
    expect(
        decision and decision.action.kind == "contribute",
        "a legal index is accepted: " .. reason
    )
    expect(decision.action ~= stop.candidates[2], "the accepted action is a copy")

    local speaking = {
        assessment = "",
        choice = nil,
        message = { channel = "private", target = "blue", speech = "Can you cover rent?" },
    }
    decision, reason = Brain.validate(speaking, stop, "communication")
    expect(decision and decision.message.target == "blue", "a colour target maps to an actor")
    decision = Brain.validate({ choice = nil, message = nil }, stop, "communication")
    expect(decision and decision.action == nil and decision.message == nil, "silence is legal")

    local quiet = {
        actorIds = stop.actorIds,
        actor = stop.actor,
        phase = "action_one",
        status = "running",
        messagesRemaining = 0,
        rules = stop.rules,
        candidates = stop.candidates,
    }

    for _, case in
        {
            { "not a table", stop, "action" },
            { { choice = 0, extra = 1 }, stop, "action" },
            { { choice = 9 }, stop, "action" },
            { { choice = -1 }, stop, "action" },
            { { choice = 0.5 }, stop, "action" },
            { { choice = "0" }, stop, "action" },
            { { choice = nil }, stop, "action" },
            { { choice = 0, message = { channel = "group", speech = "hi" } }, stop, "action" },
            { { choice = 0 }, stop, "communication" },
            { { assessment = string.rep("x", 801), choice = 0 }, stop, "action" },
            {
                { message = { channel = "private", target = "green", speech = "me" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "private", target = "orange", speech = "who" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "group", target = "blue", speech = "x" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "shout", target = nil, speech = "x" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "group", target = nil, speech = "" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "group", target = nil, speech = string.rep("x", 41) } },
                stop,
                "communication",
            },
            {
                { message = { channel = "group", target = nil, speech = "x", tone = "angry" } },
                stop,
                "communication",
            },
            {
                { message = { channel = "group", target = nil, speech = "x" } },
                quiet,
                "communication",
            },
        }
    do
        local rejected, why = Brain.validate(case[1], case[2], case[3])
        expect(rejected == nil, "an illegal reply was accepted: " .. why)
        expect(#why > 0, "every rejection carries a reason")
    end

    ---------------------------------------- the round still refuses what it must

    local live = Round.new(Setup.actors, 5, Setup.rules)
    local observation = Round.observe(live, "green")
    local forged, why = Brain.validate({ choice = 0 }, observation, "action")
    expect(forged, "a first legal candidate is accepted: " .. why)
    -- Even an accepted decision is replayed through the round, which owns legality.
    expect(
        Round.decide(live, "green", live.revision, forged.action, nil),
        "a validated action must survive the round's own check"
    )
    expect(
        not Round.decide(live, "green", live.revision, { kind = "contribute", amount = 999 }, nil),
        "the round still refuses an action the boundary never produced"
    )
end
