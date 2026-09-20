--!strict
local Send = require("../src/shared/HousepadSend")
local Round = require("../src/simulation/MvpRound")
local U = require("../src/shared/LabUtil")

local actors = {
    { id = "blue", role = "player", cash = 20, income = 15, goal = 40, expense = 5 },
    { id = "green", role = "npc", cash = 10, income = 10, goal = 25, expense = 5 },
}

local calm = {
    messPercent = 0,
    partyPercent = 0,
    leakPercent = 0,
    roachPercent = 0,
    randomInspectionPercent = 0,
    pressurePerDay = 0,
}

local function expect(value: any, message: string)
    assert(value, message)
end

local function newRound(): any
    return Round.new(actors, 1, calm)
end

return function()
    local atomic = newRound()
    local before = U.copy(atomic)
    local ok = Send.submit(Round, atomic, "blue", {
        revision = atomic.revision,
        attachment = { kind = "contribute", amount = 5 },
        channel = "private",
        target = "ghost",
        speech = "Please cover this.",
    })
    expect(not ok and U.equal(atomic, before), "invalid private chat cannot spend attached rent")

    local success = newRound()
    ok = Send.submit(Round, success, "blue", {
        revision = success.revision,
        attachment = { kind = "contribute", amount = 5 },
        channel = "group",
        speech = "I covered part of rent.",
    })
    expect(ok, "a legal chip and message submit together")
    expect(
        success.actors.blue.cash == 10 and success.rentPaid == 5 and success.used.blue == 1,
        "attached rent uses the current candidate once"
    )
    expect(success.messageCounts.blue == 1, "message is committed with the chip")

    local prose = newRound()
    local cash = prose.actors.blue.cash
    ok = Send.submit(Round, prose, "blue", { channel = "group", speech = "#rent" })
    expect(ok and prose.actors.blue.cash == cash and prose.rentPaid == 0, "prose alone is chat")

    local stale = newRound()
    before = U.copy(stale)
    ok = Send.submit(Round, stale, "blue", {
        revision = stale.revision - 1,
        attachment = { kind = "contribute", amount = 5 },
        speech = "",
    })
    expect(not ok and U.equal(stale, before), "stale chip revisions are inert")

    local actionOnly = newRound()
    expect(Round.advance(actionOnly, actionOnly.revision), "open the action phase")
    ok = Send.submit(Round, actionOnly, "blue", {
        revision = actionOnly.revision,
        attachment = { kind = "wait" },
        speech = "",
    })
    expect(ok and actionOnly.used.blue == 1, "an attachment can act without prose")

    local physical = newRound()
    expect(Round.advance(physical, physical.revision), "open the action phase for a chore")
    physical.items = {
        { id = 1, kind = "dishes", creator = "green", age = 0, resolved = false },
    }
    before = U.copy(physical)
    ok = Send.submit(Round, physical, "blue", {
        revision = physical.revision,
        attachment = { kind = "finish_chore", reference = 1 },
        speech = "",
    })
    expect(not ok and U.equal(physical, before), "physical chores cannot attach to text")
end
