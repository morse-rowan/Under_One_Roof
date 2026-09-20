local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local Round = require("../../src/simulation/MvpRound")

while true do
    local line = stdio.readLine()
    if not line or line == "" then
        break
    end
    local ok, result = pcall(function()
        local r = serde.decode("json", line)
        if r.op == "new" then
            return { state = Round.new(r.actors, r.seed, r.config) }
        elseif r.op == "observe" then
            return { observation = Round.observe(r.state, r.actor) }
        elseif r.op == "work_view" then
            return { challenge = Round.workView(r.state, r.actor) }
        end
        local accepted, reason
        if r.op == "action" then
            accepted, reason = Round.apply(r.state, r.actor, r.revision, r.action)
        elseif r.op == "decide" then
            accepted, reason = Round.decide(r.state, r.actor, r.revision, r.action, r.message)
        elseif r.op == "begin_recall" then
            accepted, reason = Round.beginRecall(r.state, r.actor, r.revision, r.challengeId)
        elseif r.op == "submit_work" then
            accepted, reason =
                Round.submitWork(r.state, r.actor, r.revision, r.challengeId, r.answers)
        elseif r.op == "message" then
            accepted, reason =
                Round.message(r.state, r.actor, r.revision, r.channel, r.target, r.speech)
        elseif r.op == "work" then
            accepted, reason = Round.work(r.state, r.revision, r.score)
        elseif r.op == "advance" then
            accepted, reason = Round.advance(r.state, r.revision)
        else
            error("Unknown MVP operation")
        end
        return { state = r.state, accepted = accepted, reason = reason }
    end)
    stdio.write(
        serde.encode(
            "json",
            if ok then { ok = true, result = result } else { ok = false, error = tostring(result) }
        ) .. "\n"
    )
end
