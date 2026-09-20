--!strict
-- Covers the three engine-independent modules that join `MvpRound` to the
-- apartment: where an issue sits, what the offline roommates do, and what the
-- player is allowed to read. Roblox services, props and input stay untested here
-- and need a Studio playtest.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local World = require("../src/shared/RoundWorld")
local Text = require("../src/shared/RoundText")
local Grid = require("../src/shared/GridMovement")
local Visual = require("../src/shared/VisualStudy")

local function expect(condition: any, message: string)
    assert(condition, message)
end

local STOPS = { morning = true, midday = true, night = true }

local function isStop(state: any): boolean
    return STOPS[state.phase] == true
end

-- Drives a whole round with the shipped offline policies, exactly the way
-- `RoundSession` does, so a rules change that makes a policy illegal fails here.
local function play(seed: number, perfectRecall: boolean): (any, number)
    local state = Round.new(Setup.actors, seed, Setup.rules)
    local decisions = 0
    local guard = 0
    while state.status == "running" do
        guard += 1
        expect(guard < 200, "round did not terminate")
        if state.phase == "work" then
            local view = Round.workView(state, Setup.player)
            expect(view ~= nil and view.stage == "preview", "work preview missing")
            local answers = {}
            if perfectRecall then
                for index, value in view.sequence do
                    answers[index] = value
                end
            end
            expect(
                Round.beginRecall(state, Setup.player, state.revision, view.id),
                "recall refused"
            )
            expect(
                Round.submitWork(state, Setup.player, state.revision, view.id, answers),
                "work submission refused"
            )
        else
            local speaking = isStop(state)
            for _, id in state.order do
                local observation = Round.observe(state, id)
                local decision = Policy.decide(observation, Policy.styleFor(id), speaking)
                if speaking and decision.message then
                    local ok, reason =
                        Round.decide(state, id, state.revision, nil, decision.message)
                    expect(ok, "illegal policy message: " .. reason)
                    decisions += 1
                end
                if decision.action then
                    local ok, reason = Round.decide(state, id, state.revision, decision.action, nil)
                    expect(ok, "illegal policy action: " .. reason)
                    decisions += 1
                end
            end
        end
        local ok, reason = Round.advance(state, state.revision)
        expect(ok, "advance refused: " .. reason)
    end
    return state, decisions
end

return function()
    ------------------------------------------------------------------ the fixture
    local probe = Round.new(Setup.actors, 13, Setup.rules)
    expect(probe.actors[Setup.player].role == "player", "the player actor must be the player")
    for id in Setup.beans do
        expect(probe.actors[id] ~= nil, "bean " .. id .. " has no actor")
        expect(probe.actors[id].role == "npc", "bean " .. id .. " must be an NPC")
    end
    expect(#probe.order == 3, "expected a three-roommate household")

    ------------------------------------------------------------------- the world
    local blocked = Grid.blocked(Visual)
    local sink = World.fixture(Visual, "Sink")
    local bin = World.fixture(Visual, "Trash")
    expect(sink ~= nil and bin ~= nil, "the apartment needs a sink and a bin")
    expect(World.fixture(Visual, "NotAFixture") == nil, "unknown fixtures must be nil")

    local dishes =
        { id = 1, kind = "dishes", creator = "green", stage = "open", age = 0, resolved = false }
    local litter =
        { id = 2, kind = "trash", creator = "red", stage = "open", age = 0, resolved = false }
    local bagged =
        { id = 2, kind = "trash", creator = "red", stage = "bagged", age = 0, resolved = false }
    expect(
        Grid.key(World.actionCell(Visual, dishes)) == Grid.key(sink),
        "dishes belong at the sink"
    )
    expect(
        Grid.key(World.actionCell(Visual, bagged)) == Grid.key(bin),
        "a bag is only finished at the bin"
    )
    expect(
        Grid.key(World.actionCell(Visual, litter)) == Grid.key(World.litterCell(Visual, 2)),
        "loose trash is picked up where it lies"
    )
    expect(
        Grid.key(World.homeCell(Visual, bagged)) == Grid.key(World.litterCell(Visual, 2)),
        "a dropped bag must not rest on the bin as if it were dealt with"
    )
    expect(World.actionCell(Visual, { kind = "leak" }) == nil, "a leak has no hands-on chore")

    for id = 1, 40 do
        local cell = World.litterCell(Visual, id)
        expect(not blocked[Grid.key(cell)], "litter must never spawn inside furniture")
        expect(
            Grid.key(cell) == Grid.key(World.litterCell(Visual, id)),
            "the same issue must always land on the same tile"
        )
    end

    expect(World.adjacent({ c = 2, r = 1 }, { c = 2, r = 0 }), "neighbours are adjacent")
    expect(World.adjacent({ c = 2, r = 1 }, { c = 2, r = 1 }), "the same cell is adjacent")
    expect(not World.adjacent({ c = 2, r = 2 }, { c = 2, r = 0 }), "two tiles away is not adjacent")
    expect(not World.adjacent(nil, sink), "an unknown position reaches nothing")

    -- Reach is only ever an extra gate; the round's candidates still decide legality.
    local items = { dishes }
    local legal = { { kind = "finish_chore", reference = 1 } }
    expect(
        World.reachable(Visual, items, { c = 2, r = 1 }, legal, "blue") ~= nil,
        "standing next to the sink must offer the dishes"
    )
    expect(
        World.reachable(Visual, items, { c = 9, r = 1 }, legal, "blue") == nil,
        "the lounge is too far from the sink"
    )
    expect(
        World.reachable(Visual, items, { c = 2, r = 1 }, {}, "blue") == nil,
        "no candidate means no chore, however close you stand"
    )
    expect(
        World.reachable(Visual, items, { c = 2, r = 1 }, legal, "green") == nil,
        "you cannot clean up after yourself for credit"
    )
    dishes.resolved = true
    expect(
        World.reachable(Visual, items, { c = 2, r = 1 }, legal, "blue") == nil,
        "a resolved issue is not still standing there"
    )
    dishes.resolved = false

    ------------------------------------------------------------------- the policy
    local finished, decisions = play(13, true)
    expect(finished.status ~= "running", "the seeded round must reach an ending")
    expect(decisions > 20, "the roommates barely acted: " .. decisions)
    local lazy = play(13, false)
    expect(lazy.status ~= "running", "a round with no recall must still finish")

    -- An asking player gets a different answer from each roommate. `green` agrees;
    -- `red` wants to see a rent receipt first.
    local function replyTo(style: string, paid: boolean): string?
        local observation = {
            status = "running",
            day = 1,
            phase = "morning",
            heat = 0,
            rent = 30,
            rentPaid = if paid then 5 else 0,
            messagesRemaining = 3,
            actor = { id = "green", cash = 12 },
            items = {},
            candidates = { { kind = "cancel_plan", reference = 4 }, { kind = "wait" } },
            events = {
                {
                    kind = "cancel_requested",
                    day = 1,
                    data = { actor = "blue", target = "green", reference = 4 },
                },
                {
                    kind = "action",
                    day = 1,
                    data = { actor = "blue", action = { kind = "contribute", amount = 5 } },
                },
            },
        }
        if not paid then
            table.remove(observation.events, 2)
        end
        local decision = Policy.decide(observation, style, true)
        return decision.note
    end
    expect(replyTo("household", false) == "agreed", "the household roommate should agree")
    expect(replyTo("cash", false) == "refused", "the cash roommate should want rent paid first")
    expect(replyTo("cash", true) == "agreed", "a rent receipt should change that answer")

    --------------------------------------------------------------------- the text
    expect(Text.name("blue", "blue") == "You", "the viewer is addressed as themselves")
    expect(Text.name("green", "blue") == "Green", "other roommates are colors")
    expect(Text.name("system", "blue") == "The building", "system issues have no roommate")

    -- Buying a cleanup and doing it yourself must read identically (contract M13).
    local bought = Text.line({
        kind = "action",
        data = { actor = "green", action = { kind = "pay_cleanup", reference = 7, amount = 5 } },
    }, "blue")
    local worked = Text.line({
        kind = "action",
        data = { actor = "green", action = { kind = "finish_chore", reference = 7 } },
    }, "blue")
    expect(bought == worked, "paying and working must not be distinguishable in the shared log")
    expect(
        bought == "Green handled outstanding requirement #7.",
        "unexpected normalised wording: " .. tostring(bought)
    )
    expect(
        Text.line({ kind = "phase_closed", data = { actionsUsed = {} } }, "blue") == nil,
        "per-controller effort counts must never be rendered"
    )

    -- Everything the finished round can show a player has to render.
    local rendered = 0
    for _, id in finished.order do
        local observation = Round.observe(finished, id)
        for _, event in observation.events do
            local line = Text.line(event, id)
            if line then
                rendered += 1
                expect(not string.find(line, "npc"), "a line leaked a role: " .. line)
                expect(not string.find(line, "nil"), "a line leaked a nil: " .. line)
            end
        end
        for _, candidate in observation.candidates do
            expect(#Text.action(candidate) > 0, "every legal option needs a label")
        end
    end
    expect(rendered > 30, "the round produced almost nothing to read: " .. rendered)
    print(
        string.format(
            "Round glue: world placement, %d policy decisions and %d rendered lines verified",
            decisions,
            rendered
        )
    )
end
