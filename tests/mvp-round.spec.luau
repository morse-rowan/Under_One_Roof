--!strict
local Round = require("../src/simulation/MvpRound")
local U = require("../src/shared/LabUtil")
local function expect(condition: any, message: string?)
    assert(condition, message or "MVP round assertion failed")
end
local actors = {
    { id = "player", role = "player", cash = 20, income = 15, goal = 40, expense = 5 },
    { id = "blue", role = "npc", cash = 10, income = 10, goal = 25, expense = 5 },
    { id = "red", role = "npc", cash = 15, income = 15, goal = 30, expense = 5 },
}
local calm = {
    messPercent = 0,
    partyPercent = 0,
    leakPercent = 0,
    roachPercent = 0,
    pressurePerDay = 0,
    randomInspectionPercent = 0,
}

local function advance(s)
    expect(Round.advance(s, s.revision))
end

local function choose(s, id, kind, reference)
    for _, candidate in Round.candidates(s, id) do
        if candidate.kind == kind and (not reference or candidate.reference == reference) then
            expect(Round.apply(s, id, s.revision, candidate))
            return
        end
    end
    error("No candidate: " .. kind)
end

return function()
    local s = Round.new(actors, 1, calm)
    expect(s.actors.player.cash == 15 and s.phase == "morning")
    expect(Round.message(s, "blue", s.revision, "private", "red", "I need my food money tomorrow."))
    local observer = Round.observe(s, "player")
    for _, event in observer.events do
        expect(event.kind ~= "message", "Private text must not leak")
        expect(
            event.kind ~= "expense" or event.data.actor == "player",
            "Private expense must not leak"
        )
    end
    expect(Round.message(s, "blue", s.revision, "group", nil, "Can someone cover rent?"))
    expect(Round.observe(s, "player").events[#Round.observe(s, "player").events].kind == "message")
    local saved = U.copy(s)
    expect(not Round.apply(s, "blue", s.revision - 1, { kind = "wait" }))
    expect(not Round.apply(s, "blue", s.revision, { kind = "contribute", amount = -5 }))
    expect(not Round.message(s, "blue", s.revision, "private", "ghost", "hello"))
    expect(U.equal(saved, s), "Rejected requests must be inert")
    choose(s, "blue", "contribute")
    expect(s.rentPaid == 5 and s.actors.blue.cash == 0)
    expect(#Round.candidates(s, "blue") == 0, "Stop action budget enforced")
    advance(s)
    expect(s.phase == "action_one")
    expect(not Round.message(s, "blue", s.revision, "group", nil, "hello"))
    advance(s)
    expect(s.phase == "work")
    expect(not Round.advance(s, s.revision), "Work requires a result")
    expect(not Round.work(s, s.revision, 0 / 0))
    expect(Round.work(s, s.revision, 1))
    expect(not Round.work(s, s.revision, 1), "No double income")
    expect(s.actors.blue.cash == 10 and s.actors.player.cash == 35)
    advance(s)
    expect(s.phase == "midday" and #s.checkpoints == 2)
    advance(s)
    advance(s)
    expect(s.phase == "night" and #s.checkpoints == 3)
    advance(s)
    expect(s.day == 2 and s.phase == "morning" and s.heat == 20)

    local chaotic = U.copy(calm)
    chaotic.messPercent = 100
    chaotic.partyPercent = 100
    local mess = Round.new(actors, 13, chaotic)
    advance(mess)
    local pending = mess.plans[1]
    expect(#Round.observe(mess, "player").plans == 0)
    choose(mess, "player", "inspect", pending.id)
    expect(#Round.observe(mess, "player").plans == 1)
    choose(mess, "player", "request_cancel", pending.id)
    expect(pending.status == "pending", "A request does not force compliance")
    local cancelled = U.copy(mess)
    choose(cancelled, pending.actor, "cancel_plan", pending.id)
    advance(cancelled)
    expect(#cancelled.items == 0, "Prevented plan creates no chore")
    advance(mess)
    local item = mess.items[1]
    expect(item.creator == pending.actor and item.age == 0)
    expect(Round.work(mess, mess.revision, 0))
    advance(mess)
    advance(mess)
    for _, candidate in Round.candidates(mess, item.creator) do
        expect(
            candidate.kind ~= "pay_cleanup" or candidate.reference ~= item.id,
            "Creator cannot undo mess"
        )
    end
    local before = Round.observe(mess, "player").cleanliness
    local dirty = U.copy(mess)
    advance(dirty)
    expect(dirty.items[1].age == 1 and Round.observe(dirty, "player").cleanliness < before)
    if item.kind == "trash" then
        choose(mess, "player", "pickup_trash", item.id)
        expect(not item.resolved, "Bagged trash still needs removal")
    end
    choose(mess, "player", "finish_chore", item.id)
    expect(item.resolved)
    local host = mess.plans[#mess.plans].actor
    advance(mess)
    local noParty = U.copy(mess)
    choose(noParty, host, "cancel_plan", #noParty.plans)
    advance(noParty)
    expect(not noParty.actors.player.tired)
    advance(mess)
    expect(mess.actors[host].modifier == 5 and mess.actors.player.modifier == -5)
    expect(Round.observe(mess, "player").work.difficulty == 5)
    advance(mess)
    advance(mess)
    expect(Round.work(mess, mess.revision, 0))
    local hostIncome, playerIncome
    for _, event in mess.events do
        if event.day == 2 and event.kind == "income" then
            if event.data.actor == host then
                hostIncome = event.data.amount
            elseif event.data.actor == "player" then
                playerIncome = event.data.amount
            end
        end
    end
    expect(hostIncome == mess.actors[host].income + 5 and playerIncome == 10)

    local debt = Round.new(
        { { id = "blue", role = "npc", cash = 0, income = 3, goal = 10, expense = 5 } },
        1,
        calm
    )
    expect(debt.actors.blue.debt == 5)
    advance(debt)
    advance(debt)
    expect(Round.work(debt, debt.revision, 0))
    expect(debt.actors.blue.debt == 2 and debt.actors.blue.cash == 0, "Unpaid expenses persist")

    local function run(seed)
        local state = Round.new(actors, seed)
        while state.status == "running" do
            if state.phase == "work" then
                expect(Round.work(state, state.revision, 0.5))
            end
            advance(state)
        end
        return state
    end
    expect(U.equal(run(47), run(47)), "Seeded replay is exact")
    local inspection = U.copy(calm)
    inspection.messPercent = 100
    inspection.inspectionDay = 1
    inspection.inspectionCleanliness = 100
    local inspected = Round.new(actors, 2, inspection)
    advance(inspected)
    advance(inspected)
    expect(Round.work(inspected, inspected.revision, 0))
    advance(inspected)
    advance(inspected)
    local payer = if inspected.items[1].creator == "blue" then "red" else "blue"
    local cash = inspected.actors[payer].cash
    choose(inspected, payer, "pay_cleanup", 1)
    expect(
        inspected.items[1].resolved
            and inspected.actors[payer].cash == cash - Round.defaults.cleanup
    )
    advance(inspected)
    expect(
        inspected.heat == Round.defaults.inspectionHeat,
        "Scheduled inspection sees unresolved dirt"
    )
    local leaks = U.copy(calm)
    leaks.leakPercent = 100
    local leaking = Round.new(actors, 2, leaks)
    advance(leaking)
    advance(leaking)
    expect(leaking.items[1].kind == "leak" and leaking.heat == 0)
    expect(Round.work(leaking, leaking.revision, 0))
    advance(leaking)
    advance(leaking)
    advance(leaking)
    expect(leaking.heat == Round.defaults.leakHeat, "Unresolved leaks escalate eviction pressure")
    local evictConfig = U.copy(calm)
    evictConfig.eviction = 20
    local evict = Round.new(actors, 1, evictConfig)
    while evict.status == "running" do
        if evict.phase == "work" then
            expect(Round.work(evict, evict.revision, 0))
        end
        advance(evict)
    end
    expect(evict.status == "evicted" and evict.day == 1)
    local terminal = U.copy(evict)
    expect(not Round.advance(evict, evict.revision))
    expect(U.equal(terminal, evict))
end
