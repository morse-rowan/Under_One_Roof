--!strict
-- The playable game's shape: a five-person household, rent every three days,
-- no horizon, and a score that counts the days survived.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")

local function expect(condition: any, reason: string?)
    assert(condition, reason or "endless-run contract failed")
end

local function countEvents(state: any, kind: string): number
    local total = 0
    for _, event in state.events do
        if event.kind == kind then
            total += 1
        end
    end
    return total
end

return function()
    ------------------------------------------------------------------- the household
    local household = Setup.household("teal")
    expect(#household == 1 + #Setup.npcs, "the household is the player plus every roommate")
    expect(#Setup.npcs >= 4, "the apartment is shared with several roommates")
    expect(household[1].id == "teal" and household[1].role == "player", "the player picks a colour")
    local ids = {}
    for _, actor in household do
        expect(not ids[actor.id], "duplicate identity: " .. actor.id)
        ids[actor.id] = true
    end
    for _, npc in Setup.npcs do
        expect(not Setup.isPlayerColor(npc.id), npc.id .. " must not also be a player colour")
        expect(Setup.beans[npc.id], npc.id .. " has no bean in the apartment")
    end
    expect(Setup.household("not-a-colour")[1].id == Setup.defaultColor, "unknown colours fall back")

    ------------------------------------------------------------------ the rent cycle
    local state = Round.new(Setup.household("blue"), 13, Setup.rules)
    expect(state.config.rentEvery == 3, "rent is a three-day bill")
    expect(state.config.days == 0, "the playable game has no horizon")
    local observation = Round.observe(state, "blue")
    expect(observation.rentDueIn == 2, "day one is two nights from the bill")
    expect(observation.rentNight == false, "day one is not a settlement night")

    -- A contribution made on day one must still be there when the bill closes.
    expect(Round.decide(state, "blue", state.revision, { kind = "contribute", amount = 5 }, nil))
    expect(state.rentPaid == 5, "the contribution landed")
    local paidBefore = state.rentPaid
    local day = state.day
    while state.day == day do
        expect(Flow.advance(Round, Policy, state))
    end
    expect(state.day == 2, "the household reached the next day")
    expect(state.rentPaid >= paidBefore, "contributions survive a night inside the cycle")
    expect(countEvents(state, "rent_settled") == 0, "rent does not settle on day one")
    expect(countEvents(state, "rent_pending") >= 1, "a night inside the cycle only reports")

    while state.day < 4 and state.status == "running" do
        expect(Flow.advance(Round, Policy, state))
    end
    expect(countEvents(state, "rent_settled") == 1, "rent settles once the third night closes")
    expect(state.survived >= 3, "three nights came through")
    expect(Round.observe(state, "blue").rentDueIn == 2, "a new cycle opens on day four")
    expect(state.rentPaid == 0, "the new cycle starts from nothing")

    ---------------------------------------------------------------------- the score
    local run = Round.new(Setup.household("blue"), 7, Setup.rules)
    local guard = 0
    while run.status == "running" and guard < 600 do
        Flow.advance(Round, Policy, run)
        guard += 1
    end
    expect(run.status == "evicted", "an endless run ends when the landlord gives up")
    expect(run.day > 3, "the run outlived the old three-day horizon: day " .. run.day)
    local outcome = Round.outcome(run, "blue")
    expect(outcome.days == run.survived, "the outcome reports the days survived")
    expect(outcome.days >= 1 and outcome.days <= run.day, "the score is the nights come through")
    expect(Round.observe(run, "blue").daysSurvived == run.survived, "observers see the score")

    -- The research suite's own three-day contract is untouched by the playable rules.
    local horizon = Round.new(Setup.household("blue"), 13, { days = 3, eviction = 1000 })
    expect(horizon.config.rentEvery == 1, "the default remains a nightly bill")
    local steps = 0
    while horizon.status == "running" and steps < 100 do
        Flow.advance(Round, Policy, horizon)
        steps += 1
    end
    expect(horizon.status == "horizon", "a horizon run still ends on its last night")
    expect(horizon.survived == 3, "three days survived")
    expect(countEvents(horizon, "rent_settled") == 3, "a nightly bill settles every night")
    print(
        string.format(
            "Endless run: %d-person household, 3-day rent, evicted on day %d after %d days survived",
            #household,
            run.day,
            run.survived
        )
    )
end
