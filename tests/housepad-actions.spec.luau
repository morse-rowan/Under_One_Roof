--!strict
local Actions = require("../src/shared/HousepadActions")

local function expect(value: any, message: string)
    assert(value, message)
end

return function()
    local rent = { kind = "contribute", amount = 5 }
    local service = { kind = "pay_cleanup", reference = 3, amount = 10 }
    local wait = { kind = "wait" }
    local inspect = { kind = "inspect", reference = 7 }
    local askCancel = { kind = "request_cancel", reference = 7 }
    local cancel = { kind = "cancel_plan", reference = 8 }
    local physical = { kind = "finish_chore", reference = 3 }
    local o = {
        actor = { id = "blue" },
        actorIds = { "blue", "green", "red", "green", 99 },
        candidates = { rent, service, wait, inspect, askCancel, cancel, physical },
        items = { { id = 3, kind = "leak" } },
        -- This plan is intentionally private: no action may expose its identity.
        plans = {},
    }

    local money = Actions.options(o, "#")
    expect(#money == 3, "financial picker contains only established nonphysical actions")
    expect(money[1].action == rent and money[1].token == "#rent", "rent keeps its candidate")
    expect(money[2].action == service and money[2].token == "#service:3", "service token is stable")
    expect(money[3].action == wait and money[3].token == "#wait", "wait remains explicit")
    expect(string.find(money[2].label, "10"), "labels come from RoundGuide")

    local plans = Actions.options(o, "!")
    expect(#plans == 3, "plan picker excludes chores and money actions")
    expect(plans[1].token == "!inspect:7", "inspection stays opaque")
    expect(plans[2].token == "!request-cancel:7", "request cancellation is distinct")
    expect(plans[3].token == "!cancel:8", "own cancellation has a stable token")
    for _, option in plans do
        expect(not string.find(option.label, "green"), "unknown plan owner must stay hidden")
    end

    expect(Actions.resolve(o, "contribute", nil, 5) == rent, "current amount resolves")
    expect(
        Actions.resolve(o, "pay_rent", nil, 5) == rent,
        "rent text alias resolves existing action"
    )
    expect(Actions.resolve(o, "pay_cleanup", 3, 10) == service, "reference and amount resolve")
    expect(Actions.resolve(o, "pay_cleanup", 3, 5) == nil, "forged amount is rejected")
    expect(Actions.resolve(o, "inspect", 999) == nil, "unknown reference is rejected")
    expect(
        Actions.resolve({ candidates = {} }, "wait", nil) == nil,
        "stale or exhausted choices fail"
    )
    expect(Actions.resolve(o, "finish_chore", 3) == nil, "physical actions are never text actions")

    local recipients = Actions.recipients(o)
    expect(
        #recipients == 2 and recipients[1] == "green" and recipients[2] == "red",
        "public roommates only"
    )
    local mention = Actions.preview(o, "Could @gr")
    expect(
        mention and mention.mode == "@" and mention.recipients[1] == "green",
        "mentions use public IDs"
    )
    local picker = Actions.preview(o, "I can #ser")
    expect(
        picker and picker.mode == "#" and picker.options[2].action == service,
        "picker is a hint"
    )
    expect(Actions.preview(o, "I'll take care of it") == nil, "ordinary prose does not execute")
end
