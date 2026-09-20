--!strict
local Round = require("../src/simulation/MvpRound")
local U = require("../src/shared/LabUtil")
local actors = {
    { id = "green", role = "player", cash = 50, income = 10, goal = 20, expense = 5 },
    { id = "blue", role = "npc", cash = 50, income = 10, goal = 20, expense = 5 },
}
local calm = {
    messPercent = 0,
    partyPercent = 0,
    leakPercent = 0,
    roachPercent = 0,
    randomInspectionPercent = 0,
    pressurePerDay = 0,
}
local function expect(value, message)
    assert(value, message or "MVP contract assertion failed")
end
local function advance(s)
    expect(Round.advance(s, s.revision))
end

return function()
    local s = Round.new(actors, 41, calm)
    local original = U.copy(s)
    expect(not Round.decide(s, "green", s.revision, { kind = "contribute", amount = 5 }, {
        channel = "private",
        target = "ghost",
        speech = "A payment cannot survive rejection.",
    }))
    expect(U.equal(s, original), "Atomic decision rolls back money and events")
    expect(Round.decide(s, "green", s.revision, nil, {
        channel = "group",
        speech = "Could you contribute after this conversation?",
    }))
    expect(s.used.green == nil and s.messageCounts.green == 1, "Speech does not consume effort")
    expect(Round.decide(s, "green", s.revision, { kind = "contribute", amount = 5 }, nil))
    expect(not Round.decide(s, "green", s.revision, { kind = "contribute", amount = 5 }, nil))
    advance(s)
    advance(s)
    local challenge = Round.workView(s, "green")
    expect(challenge.stage == "preview" and #challenge.sequence == 3)
    expect(Round.workView(s, "blue") == nil, "Only the worker receives the preview")
    expect(Round.observe(s, "green").work.sequence == nil, "Ordinary observations omit answers")
    expect(not Round.submitWork(s, "green", s.revision, challenge.id, challenge.sequence))
    expect(not Round.beginRecall(s, "blue", s.revision, challenge.id))
    local beforeRng = s.rng
    expect(Round.beginRecall(s, "green", s.revision, challenge.id))
    expect(Round.workView(s, "green").sequence == nil, "Recall never resends the solution")
    local recalling = U.copy(s)
    expect(not Round.submitWork(s, "green", s.revision, challenge.id, { 999 }))
    expect(not Round.submitWork(s, "green", s.revision, challenge.id, { [2] = 1 }))
    expect(U.equal(s, recalling), "Malformed answers do not mutate payout")
    local failed = U.copy(s)
    local money = s.actors.green.cash
    expect(Round.submitWork(s, "green", s.revision, challenge.id, challenge.sequence))
    expect(s.actors.green.cash == money + 15, "Authority scores the recalled sequence")
    expect(s.actors.blue.cash == 55, "NPC income is independent of work accuracy")
    expect(s.rng == beforeRng, "Memory challenge leaves the chaos stream unchanged")
    local paid = U.copy(s)
    expect(not Round.submitWork(s, "green", s.revision, challenge.id, challenge.sequence))
    expect(U.equal(paid, s), "Cannot collect income twice")
    expect(Round.submitWork(failed, "green", failed.revision, challenge.id, {}))
    expect(failed.actors.green.cash == money + 10, "Empty answer preserves guaranteed income")

    local tired = Round.new(actors, 41, calm)
    advance(tired)
    tired.actors.green.tired = true -- fixture: overnight effects are covered in round tests
    advance(tired)
    expect(#Round.workView(tired, "green").sequence == 5)
    expect(tired.rng == beforeRng, "Difficulty tuning does not perturb household RNG")

    local lastDay = U.copy(calm)
    lastDay.days = 1
    lastDay.partyPercent = 100
    local ended = Round.new(actors, 3, lastDay)
    while ended.status == "running" do
        if ended.phase == "work" then
            expect(Round.work(ended, ended.revision, 0))
        end
        advance(ended)
    end
    expect(#ended.plans == 0, "No party is queued without a next workday")
    local outcome = Round.outcome(ended, "green")
    expect(outcome.final and outcome.survived and outcome.goalMet and outcome.success)
    ended.status = "evicted" -- outcome fixture: wealth cannot turn eviction into success
    outcome = Round.outcome(ended, "green")
    expect(outcome.goalMet and not outcome.success and not outcome.survived)
    ended.actors.green.debt = 1
    expect(
        not Round.outcome(ended, "green").goalMet,
        "Unpaid obligations invalidate a reserve goal"
    )
    expect(Round.observe(ended, "green").messagesRemaining == 0)
end
