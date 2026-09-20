--!strict
local Env = require("./support/roblox-env")
local task = require("@lune/task")
local serde = require("@lune/serde")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")

return function()
    local delay = 0.12
    local fail = false
    local requests = 0
    local http = {
        JSONEncode = function(_self, value)
            return serde.encode("json", value)
        end,
        JSONDecode = function(_self, value)
            return serde.decode("json", value)
        end,
        RequestAsync = function()
            requests += 1
            local currentDelay = delay
            task.wait(currentDelay)
            if fail then
                error("injected network failure")
            end
            return { Body = serde.encode("json", { ok = true, decision = { choice = 0 } }) }
        end,
    }
    local Service = Env.new({ HttpService = http })("src/server/RoundBrainService.luau")
    local brain = Service.new({ enabled = true, deadline = 0.01, maxCalls = 8 })
    local state = Round.new(Setup.actors, 13, Setup.rules)
    brain.prefetch(Round, state, "action")
    assert(
        brain.decide(Round.observe(state, "green"), "action", "green") == nil,
        "deadline returns fallback"
    )
    task.wait(0.15)
    assert(
        brain.decide(Round.observe(state, "green"), "action", "green") == nil,
        "late result leaked past deadline"
    )
    assert(string.find(brain.status(), "4 fallback", 1, true), "timeouts must count as fallback")
    delay = 0
    brain.prefetch(Round, state, "action")
    assert(
        brain.decide(Round.observe(state, "green"), "action", "green"),
        "fresh batch should work"
    )
    assert(brain.decide(Round.observe(state, "green"), "action", "green") == nil, "consume once")
    brain.prefetch(Round, state, "action")
    assert(requests == 8, "call budget must cap transport")
    brain.reset()
    delay = 0.12
    task.spawn(function()
        brain.prefetch(Round, state, "action")
    end)
    task.wait(0.01)
    brain.reset()
    task.wait(0.18)
    assert(
        brain.decide(Round.observe(state, "green"), "action", "green") == nil,
        "reset must invalidate pending results"
    )
    assert(string.find(brain.status(), "0/8 calls", 1, true), "reset clears accounting")
    delay, fail = 0, true
    brain.prefetch(Round, state, "action")
    assert(
        brain.decide(Round.observe(state, "green"), "action", "green") == nil,
        "network errors must fall back"
    )
end
