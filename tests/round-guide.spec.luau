--!strict
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Guide = require("../src/shared/RoundGuide")

return function()
    local s = Round.new(
        Setup.actors,
        13,
        { messPercent = 0, partyPercent = 0, leakPercent = 0, roachPercent = 0 }
    )
    local before = Round.observe(s, "blue")
    assert(before.actionsRemaining == 1, "morning choice available")
    assert(Round.message(s, "blue", s.revision, "group", nil, "Hi"), "message accepted")
    assert(Round.observe(s, "blue").actionsRemaining == 1, "chat does not spend effort")
    assert(Round.apply(s, "blue", s.revision, { kind = "wait" }), "wait accepted")
    assert(Round.observe(s, "blue").actionsRemaining == 0, "wait spends choice")
    assert(Round.advance(s, s.revision), "advance accepted")
    local o = Round.observe(s, "blue")
    assert(o.actionsRemaining == 2 and o.actionLimit == 2, "action window replenishes effort")
    s.items = {
        { id = 1, kind = "trash", creator = "green", stage = "open", age = 1, resolved = false },
        { id = 2, kind = "dishes", creator = "blue", age = 2, resolved = false },
    }
    o = Round.observe(s, "blue")
    local tasks = Guide.tasks(o)
    assert(tasks[1].id == 2 and not tasks[1].canWalk, "oldest first; cannot do own mess")
    assert(
        tasks[2].canWalk and string.find(tasks[2].detail, "Two choices"),
        "trash explains both steps"
    )
    assert(
        Round.apply(s, "blue", s.revision, { kind = "pickup_trash", reference = 1 }),
        "pickup accepted"
    )
    o = Round.observe(s, "blue")
    assert(o.actionsRemaining == 1, "pickup consumes one choice")
    assert(string.find(Guide.tasks(o)[2].detail, "kitchen bin"), "bagged trash points to bin")
    assert(
        Round.apply(s, "blue", s.revision, { kind = "finish_chore", reference = 1 }),
        "finish accepted"
    )
    o = Round.observe(s, "blue")
    assert(#Guide.tasks(o) == 1 and o.actionsRemaining == 0, "completed task removed")
    assert(string.find(Guide.summary(o).hint, "used up"), "exhausted guidance")
    assert(
        Guide.choice({ kind = "inspect", reference = 999 }, o) == "Investigate clue #999",
        "hidden clue stays opaque"
    )
    o.plans = { { id = 999, actor = "green", kind = "party" } }
    assert(
        string.find(Guide.choice({ kind = "request_cancel", reference = 999 }, o), "Green"),
        "visible clue names owner"
    )
    assert(Round.advance(s, s.revision), "advance to work")
    assert(Round.observe(s, "blue").actionsRemaining == 0, "work has no choices")
    s.status = "evicted"
    assert(Round.observe(s, "blue").actionLimit == 0, "terminal has no effort")
end
