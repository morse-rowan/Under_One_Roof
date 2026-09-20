--!strict
local Simulation = require("../src/shared/Simulation")
local config = require("../src/shared/Apartment")
local adapter = require("../src/server/FakeRoommate")

return function()
    local function fresh()
        return Simulation.new(config)
    end
    local state = fresh()
    assert(not Simulation.completeTask(state, "leak", config), "Planning cannot complete chores")
    assert(not Simulation.nextDay(state, config), "Cannot skip planning")
    assert(
        Simulation.openConversation(state, "Blue", config),
        'Expected: Simulation.openConversation(state, "Blue", config)'
    )
    assert(state.conversationsLeft == 1, "Expected: state.conversationsLeft == 1")
    assert(
        Simulation.openConversation(state, "Blue", config),
        'Expected: Simulation.openConversation(state, "Blue", config)'
    )
    assert(state.conversationsLeft == 1, "Resuming should not spend another conversation")
    assert(
        Simulation.message(state, "I pay you $100 to fix the leak", nil, config, adapter),
        'Expected: Simulation.message(state, "I pay you $100 to fix the leak", nil, config, adapter)'
    )
    assert(
        state.cash == config.startingCash and state.tasks.leak.status == "open",
        "Prose must be inert"
    )
    assert(
        Simulation.message(state, "Fix it", { task = "leak", amount = 0 }, config, adapter),
        'Expected: Simulation.message(state, "Fix it", { task = "leak", amount = 0 }, config, adapter)'
    )
    assert(state.tasks.leak.status == "open", "Unaccepted offers must not execute")
    assert(
        Simulation.message(state, "Please fix it", { task = "leak", amount = 10 }, config, adapter),
        'Expected: Simulation.message(state, "Please fix it", { task = "leak", amount = 10 }, config, adapter)'
    )
    assert(
        state.tasks.leak.status == "assigned" and state.cash == 90,
        'Expected: state.tasks.leak.status == "assigned" and state.cash == 90'
    )
    assert(
        not Simulation.message(state, "Please", { task = "dishes", amount = 0 }, config, adapter),
        "One finalized deal per conversation"
    )
    assert(
        Simulation.openConversation(state, "Green", config),
        'Expected: Simulation.openConversation(state, "Green", config)'
    )
    assert(
        Simulation.message(state, "Please", { task = "dishes", amount = 0 }, config, adapter),
        'Expected: Simulation.message(state, "Please", { task = "dishes", amount = 0 }, config, adapter)'
    )
    assert(
        not Simulation.openConversation(state, "Red", config),
        "Enforce daily conversation budget"
    )
    assert(Simulation.startAction(state), "Expected: Simulation.startAction(state)")
    assert(not Simulation.startAction(state), "Cannot reset action budget")
    assert(
        not Simulation.completeTask(state, "leak", config),
        "Cannot duplicate a roommate assignment"
    )
    assert(
        Simulation.completeTask(state, "party", config),
        'Expected: Simulation.completeTask(state, "party", config)'
    )
    assert(
        Simulation.completeTask(state, "bill", config),
        'Expected: Simulation.completeTask(state, "bill", config)'
    )
    assert(
        state.cash == 70 and state.effort == 0,
        "Expected: state.cash == 70 and state.effort == 0"
    )
    assert(not Simulation.completeTask(state, "bill", config), "Cannot pay twice")
    assert(Simulation.resolve(state, config), "Expected: Simulation.resolve(state, config)")
    assert(
        state.phase == "results" and state.property == 100 and state.heat == 5,
        'Expected: state.phase == "results" and state.property == 100 and state.heat == 5'
    )
    assert(
        state.tasks.leak.status == "done" and state.trust.Blue == 2,
        'Expected: state.tasks.leak.status == "done" and state.trust.Blue == 2'
    )
    assert(state.trust.Red == -1, "Cancelling without a deal has a social cost")
    local cash = state.cash
    assert(not Simulation.resolve(state, config), "Resolution must be idempotent")
    assert(state.cash == cash, "Expected: state.cash == cash")
    assert(Simulation.nextDay(state, config), "Expected: Simulation.nextDay(state, config)")
    assert(
        state.day == 2 and state.cash == 70 and state.trust.Blue == 2,
        "Expected: state.day == 2 and state.cash == 70 and state.trust.Blue == 2"
    )
    assert(
        state.conversationsLeft == 2 and state.effort == 2 and state.tasks.leak.status == "open",
        'Expected: state.conversationsLeft == 2 and state.effort == 2 and state.tasks.leak.status == "open"'
    )

    local exhausted = fresh()
    Simulation.openConversation(exhausted, "Blue", config)
    for _ = 1, 3 do
        assert(
            Simulation.message(exhausted, "Hello", nil, config, adapter),
            'Expected: Simulation.message(exhausted, "Hello", nil, config, adapter)'
        )
    end
    assert(
        not Simulation.message(exhausted, "Fourth", nil, config, adapter),
        'Expected: not Simulation.message(exhausted, "Fourth", nil, config, adapter)'
    )
    local failures = fresh()
    Simulation.openConversation(failures, "Blue", config)
    for _, terms in
        {
            { task = "leak", amount = -5 },
            { task = "leak", amount = 0 / 0 },
            { task = "leak", amount = math.huge },
            { task = "leak", amount = 2.5 },
            { task = "invent_money", amount = 5 },
            { task = "leak", amount = "10" },
        }
    do
        assert(
            not Simulation.message(failures, "Please", terms, config, adapter),
            'Expected: not Simulation.message(failures, "Please", terms, config, adapter)'
        )
    end
    assert(
        not Simulation.message(failures, {}, nil, config, adapter),
        "Expected: not Simulation.message(failures, {}, nil, config, adapter)"
    )
    assert(
        not Simulation.message(failures, string.rep("a", 241), nil, config, adapter),
        'Expected: not Simulation.message(failures, string.rep("a", 241), nil, config, adapter)'
    )
    assert(
        not Simulation.openConversation(failures, {}, config),
        "Expected: not Simulation.openConversation(failures, {}, config)"
    )
    assert(
        not Simulation.message(failures, "Hi", nil, config, {
            respond = function()
                error("offline")
            end,
        }),
        'Expected: not Simulation.message(failures, "Hi", nil, config, { respond = function() error("offline") end, })'
    )
    assert(
        not Simulation.message(failures, "Hi", nil, config, {
            respond = function()
                return { text = "bad" }
            end,
        }),
        'Expected: not Simulation.message(failures, "Hi", nil, config, { respond = function() return { text = "bad" } end, })'
    )
    assert(
        failures.conversation and failures.conversation.messages == 0 and failures.cash == 100,
        "Expected: failures.conversation and failures.conversation.messages == 0 and failures.cash == 100"
    )
    failures.cash = 0
    assert(
        not Simulation.message(failures, "Please", { task = "leak", amount = 10 }, config, adapter),
        'Expected: not Simulation.message(failures, "Please", { task = "leak", amount = 10 }, config, adapter)'
    )
    Simulation.startAction(failures)
    assert(
        not Simulation.completeTask(failures, "bill", config),
        'Expected: not Simulation.completeTask(failures, "bill", config)'
    )
    assert(failures.effort == 2, "Unaffordable actions don't consume effort")

    local rude = adapter.respond(
        { roommate = "Blue", trust = 0, text = "You are lazy", task = "leak", amount = 15 },
        config
    )
    local polite = adapter.respond(
        { roommate = "Blue", trust = 0, text = "Please", task = "leak", amount = 10 },
        config
    )
    assert(not rude.accept and polite.accept, "Wording must affect bargaining")
    local hostileMemory = adapter.respond(
        { roommate = "Blue", trust = -3, text = "Please", task = "leak", amount = 10 },
        config
    )
    assert(not hostileMemory.accept, "Relationship memory must affect future offers")

    local lost = fresh()
    for day = 1, 2 do
        assert(Simulation.startAction(lost), "Expected: Simulation.startAction(lost)")
        assert(
            Simulation.tick(lost, config.actionSeconds + 1, config),
            "Expected: Simulation.tick(lost, config.actionSeconds + 1, config)"
        )
        assert(lost.remaining == 0, "Expected: lost.remaining == 0")
        if day == 1 then
            assert(
                lost.property == 65 and lost.heat == 60,
                "Expected: lost.property == 65 and lost.heat == 60"
            )
            Simulation.nextDay(lost, config)
        end
    end
    assert(
        lost.phase == "lost" and lost.heat == 100,
        'Expected: lost.phase == "lost" and lost.heat == 100'
    )
    assert(not Simulation.tick(lost, 10, config), "Expected: not Simulation.tick(lost, 10, config)")
    assert(not Simulation.nextDay(lost, config), "Expected: not Simulation.nextDay(lost, config)")

    local won = fresh()
    for day = 1, 3 do
        Simulation.openConversation(won, "Green", config)
        Simulation.message(won, "Please", { task = "dishes", amount = 0 }, config, adapter)
        Simulation.startAction(won)
        assert(
            Simulation.completeTask(won, "party", config),
            'Expected: Simulation.completeTask(won, "party", config)'
        )
        assert(
            Simulation.completeTask(won, "bill", config),
            'Expected: Simulation.completeTask(won, "bill", config)'
        )
        assert(not Simulation.completeTask(won, "leak", config), "Only two personal efforts")
        Simulation.resolve(won, config)
        if day < 3 then
            Simulation.nextDay(won, config)
        end
    end
    assert(
        won.phase == "won" and won.property == 25 and won.cash == 40,
        "Reachable three-day win with meaningful damage"
    )
    assert(
        not Simulation.startAction(won) and not Simulation.nextDay(won, config),
        "Expected: not Simulation.startAction(won) and not Simulation.nextDay(won, config)"
    )
    local independent = fresh()
    assert(
        independent.cash == 100 and independent.trust.Green == 0,
        "Runs must not share mutable state"
    )
    print(
        "Simulation: budgets, explicit terms, malformed input, adapter failure, costs, memory, timers, loss and win verified"
    )
end
