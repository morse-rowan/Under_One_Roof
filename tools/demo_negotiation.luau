--!strict
-- Bounded paired presentation probe. No fallback: only validated model decisions
-- count as evidence. Identical households differ solely by Blue's private request.
local net = require("@lune/net")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Brain = require("../src/shared/RoundBrain")

local url = process.args[1] or "http://127.0.0.1:8789/decide"
local results = {}
for _, requested in { false, true } do
    local state = Round.new(Setup.actors, 13, Setup.rules)
    -- Fixture setup, not a claim these contributions were played turns.
    state.rentPaid = 55
    if requested then
        assert(Round.message(state, "blue", state.revision, "private", "red",
            "Red, please keep your cash today for your expenses. I will cover the last $5 of rent next. Do not contribute this turn."))
    end
    local observation = Round.observe(state, "red")
    local packet = Brain.packet(observation, "action")
    local response = net.request({
        url = url,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = serde.encode("json", {
            system = packet.system, observation = packet.observation,
            maxTokens = packet.responseTokens, version = packet.version,
        }),
    })
    local payload = serde.decode("json", response.body)
    local decision, reason = Brain.validate(payload.decision, observation, "action")
    local result: any = { requested = requested, ok = false,
        reason = payload.error or reason, beforeRent = state.rentPaid }
    if payload.ok and decision and decision.action then
        result.ok, result.reason = Round.decide(state, "red", state.revision, decision.action, nil)
        result.action, result.afterRent = decision.action, state.rentPaid
    end
    table.insert(results, result)
end
print(serde.encode("json", { scenario = "last-five-rent", results = results,
    changed = results[1].ok and results[2].ok and results[1].afterRent ~= results[2].afterRent }))
