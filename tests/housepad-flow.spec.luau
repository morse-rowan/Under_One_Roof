--!strict
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Flow = require("../src/shared/HousepadFlow")
local Policy = require("../src/shared/RoundPolicy")
local Data = require("../src/shared/HousepadData")

local function expect(condition: any, reason: string?)
    assert(condition, reason or "housepad-flow contract failed")
end

return function()
    for _, input in
        {
            "/set cash -1",
            "/set heat nan",
            "/set cleanliness 101",
            "/reset 0",
            "/next extra",
            "/set rent inf",
            "/set cash 1.5",
            "/set nope 3",
        }
    do
        expect(Flow.parse(input) == nil, "invalid command accepted: " .. input)
    end
    local command = Flow.parse(" /set LANDLORD 20 ")
    expect(command and command.stat == "landlord" and command.value == 20)
    expect(Flow.parse("/reset 42").seed == 42)
    expect(Flow.parse("/day").kind == "day")
    local state = Round.new(Setup.actors, 13, Setup.rules)
    Flow.setStat(Round, state, "blue", "landlord", 20)
    expect(state.heat == 80)
    Flow.setStat(Round, state, "blue", "rent", 999)
    expect(state.rentPaid == state.config.rent)
    Flow.setStat(Round, state, "blue", "cash", 100)
    expect(Round.observe(state, "blue").actor.cash == 100)
    Flow.setStat(Round, state, "blue", "cleanliness", 42)
    expect(Round.observe(state, "blue").cleanliness == 42)
    table.insert(state.items, {
        id = 1,
        kind = "dishes",
        creator = "green",
        age = 0,
        resolved = false,
        stage = "open",
        day = 1,
    })
    expect(
        Round.observe(state, "blue").cleanliness == 32,
        "real mess must still change dev-adjusted cleanliness"
    )
    Flow.setStat(Round, state, "blue", "cleanliness", 100)
    expect(Round.observe(state, "blue").cleanliness == 100)
    local metrics = Data.metrics(Round.observe(state, "blue"))
    expect(math.abs(metrics[1].fraction - 0.2) < 0.001 and metrics[1].tone == "bad")
    expect(metrics[2].fraction == 1 and metrics[3].fraction == 1)
    Flow.setStat(Round, state, "blue", "heat", 0)
    expect(Flow.advance(Round, Policy, state))
    expect(state.phase == "action_one")
    expect(Flow.advance(Round, Policy, state))
    expect(state.phase == "work")
    local cash = state.actors.blue.cash
    local wage = math.max(0, state.actors.blue.income + state.actors.blue.modifier)
    expect(Flow.advance(Round, Policy, state))
    expect(state.phase == "midday")
    expect(state.actors.blue.cash == cash + wage, "deferred work must pay only base wage")
    Flow.setStat(Round, state, "blue", "heat", 1000)
    expect(Flow.advance(Round, Policy, state))
    expect(state.status == "evicted", "debug heat must affect real eviction")
    local revision = state.revision
    expect(not Flow.advance(Round, Policy, state))
    expect(state.revision == revision, "a finished round cannot advance")
end
