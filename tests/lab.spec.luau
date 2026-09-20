--!strict
local Lab = require("../src/shared/Lab")
local U = require("../src/shared/LabUtil")
local Session = require("../src/server/LabSession")
local config = {
    actors = {
        {
            id = "alpha",
            role = "player",
            cash = 30,
            income = 15,
            goal = 90,
            preference = "quiet",
            stats = {},
        },
        {
            id = "omega",
            role = "npc",
            cash = 30,
            income = 15,
            goal = 110,
            preference = "party",
            stats = {},
        },
    },
    time = { days = 3, social_rounds = 2, action_rounds = 2 },
    economy = {
        bill = 30,
        bill_jitter = 0,
        unit = 15,
        debt_days = 1,
        unpaid_heat = 20,
        paid_cooling = 5,
    },
    mechanics = { promises = true, debt = true, information = true, alliances = true, plans = true },
    social = { fulfilled_trust = 10, breach_trust = 20 },
    plans = {
        compensation = 15,
        repair_cost = 10,
        repair_gain = 20,
        party_heat = 10,
        party_damage = 5,
        stress = 10,
        conflict_trust = 10,
    },
    communication = { speech_bytes = 240, private = true },
}

return function()
    local function step(state, action, speech)
        return Lab.apply(state, config, {
            actor = Lab.actor(state),
            revision = state.revision,
            action = action,
            speech = speech or "",
            channel = "public",
        })
    end
    local state = Lab.new(config, 7)
    local session = Session.new(config, 7)
    assert(
        not session:request("alpha", { actor = "omega" }),
        "Controller cannot impersonate another actor"
    )
    assert(session:observe("alpha").actors == nil, "Server adapter projects private observations")
    assert(state.actors.alpha.cash == 45, "Automatic income applies once at day start")
    local saved = Lab.save(state)
    assert(
        not Lab.advance(state, config),
        "Cannot double-credit income by advancing the wrong phase"
    )
    assert(U.equal(state, saved), "Rejected transition is inert")
    local id = Lab.actor(state)
    local other = if id == "alpha" then "omega" else "alpha"
    local obs = Lab.observe(state, config, id)
    assert(obs.actors == nil and obs.actor.id == id, "No full-world actor dump")
    assert(obs.actor.knowledge[other .. ":savings"] == nil, "No hidden goal leakage")
    for _, event in obs.events do
        assert(event.kind ~= "income" or event.actor == id, "Income is private")
    end
    assert(not step(state, { kind = "invent_money", amount = 1000 }), "Only enumerated actions")
    assert(U.equal(state, saved), "Invalid action does not spend a turn")
    assert(
        step(
            state,
            { kind = "offer", target = other, amount = 15, purpose = "bill" },
            "I paid already"
        )
    )
    assert(state.bill.paid == 0, "Speech and offers do not transfer money")
    local deal = state.commitments[1]
    assert(step(state, { kind = "accept", reference = deal.id }))
    while state.phase == "social" do
        assert(step(state, { kind = "wait" }))
    end
    while Lab.actor(state) ~= id do
        assert(step(state, { kind = "wait" }))
    end
    assert(step(state, { kind = "fulfill", reference = deal.id }))
    assert(state.bill.paid == 15 and state.actors[id].cash == 30, "Exactly one payment")
    while state.phase ~= "settlement" do
        assert(step(state, { kind = "wait" }))
    end
    assert(Lab.advance(state, config))
    assert(
        state.totals.fulfilled == 1 and state.totals.commitments_due == 1,
        "Due commitments settle once"
    )
    assert(state.actors[other].relationships[id] == 10, "Fulfillment matters to observer")
    assert(state.actors[id].cash == 45, "Next day's income independent of work")
    local cash = 0
    for _, actor in state.actors do
        cash += actor.cash
    end
    assert(
        cash == state.totals.initial + state.totals.income - state.totals.expenses,
        "Money accounting"
    )
    local copy = Lab.load(Lab.save(state))
    assert(U.equal(copy, state), "Checkpoint restores complete state")
    copy.actors[id].cash = 0
    assert(state.actors[id].cash ~= 0, "Branch does not mutate parent")
    local invalid = Lab.save(state)
    invalid.rules = "future"
    assert(not pcall(Lab.load, invalid), "Incompatible rules rejected")

    local a, b = Lab.new(config, 99), Lab.new(config, 99)
    for _ = 1, 30 do
        if a.phase == "settlement" then
            Lab.advance(a, config)
            Lab.advance(b, config)
        elseif a.status == "active" then
            step(a, { kind = "wait" })
            step(b, { kind = "wait" })
        end
        assert(
            U.equal(a, b),
            "Identical actions replay all state including independent RNG streams"
        )
    end
    print(
        "Lab: private observations, authority, accounting, income, commitments, checkpoint isolation and replay verified"
    )
end
