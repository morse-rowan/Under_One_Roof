--!strict
-- Live roommate decisions: the transport half of the model boundary.
--
-- `RoundBrain` decides what a model may see and what it may send back; this module
-- only carries the bytes, counts the calls and enforces the wall-clock budget. The
-- credential lives in `tools/nemotron_proxy.py` and never reaches Roblox.
--
-- Every failure path returns nil, which `HousepadFlow` reads as "use the
-- deterministic policy for this turn". A missing bridge, a spent budget, a slow
-- model or an illegal reply all degrade to the offline household rather than
-- stalling it, so the demo never depends on inference being up.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brain = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RoundBrain"))

local Service = {}

Service.defaults = {
    url = "http://127.0.0.1:8787/decide",
    -- Per household. Generous enough for a demo run, small enough that a runaway
    -- loop cannot quietly spend an account's quota.
    maxCalls = 120,
    -- Seconds to wait for a whole phase's roommates before giving up on the
    -- stragglers. One `Continue` press must stay responsive.
    deadline = 8,
}

local function now(): number
    return os.clock()
end

-- Re-bind a decision taken against a slightly older candidate list. Roommates in
-- one phase decide simultaneously, so an earlier contribution may have changed the
-- amount left to pay. Matching on kind and reference keeps the intent; a candidate
-- that no longer exists is dropped and the turn falls back.
local function rebind(observation: any, action: any): any?
    if action == nil then
        return nil
    end
    for _, candidate in observation.candidates do
        if candidate.kind == action.kind and candidate.reference == action.reference then
            return candidate
        end
    end
    return nil
end

-- `options` overrides `Service.defaults`. `isEnabled` is a function so a developer
-- toggle can turn inference on and off mid-session without rebuilding the session.
function Service.new(options: any?): any
    local config = table.clone(Service.defaults)
    for key, value in options or {} do
        config[key] = value
    end
    local isEnabled = config.isEnabled or function()
        return config.enabled == true
    end

    local calls = 0
    local failures = 0
    local cache: { [string]: any } = {}
    local generation = 0

    local function key(id: string, mode: string): string
        return mode .. "|" .. id
    end

    -- One request. Returns the validated decision, or nil with a short reason.
    local function ask(observation: any, mode: string, id: string): (any?, string)
        local packet = Brain.packet(observation, mode)
        local body = HttpService:JSONEncode({
            system = packet.system,
            observation = packet.observation,
            maxTokens = packet.responseTokens,
            version = packet.version,
        })
        local started = now()
        local ok, result = pcall(function()
            local headers: any = { ["Content-Type"] = "application/json" }
            if config.secretName then
                assert(string.match(config.url, "^https://"), "Hosted gateway requires HTTPS")
                headers.Authorization = HttpService:GetSecret(config.secretName)
                    :AddPrefix("Bearer ")
            end
            return HttpService:RequestAsync({
                Url = config.url,
                Method = "POST",
                Headers = headers,
                Body = body,
            })
        end)
        local elapsed = now() - started
        if not ok then
            return nil, "unreachable: " .. tostring(result)
        end
        local parsed, payload = pcall(HttpService.JSONDecode, HttpService, result.Body)
        if not parsed or type(payload) ~= "table" then
            return nil, "unreadable bridge response"
        end
        if payload.ok ~= true or type(payload.decision) ~= "table" then
            return nil, "bridge: " .. tostring(payload.error or result.StatusCode)
        end
        local decision, reason = Brain.validate(payload.decision, observation, mode)
        if not decision then
            return nil, "rejected: " .. reason
        end
        -- The assessment is the model's own self-report, not evidence. It stays in
        -- the server log and never reaches a roommate, the client or another prompt.
        print(
            string.format(
                "[Brain] %s %s %s in %.2fs%s",
                id,
                mode,
                if decision.action
                    then decision.action.kind
                    else (if decision.message
                        then decision.message.channel .. " message"
                        else "silence"),
                elapsed,
                if type(decision.assessment) == "string" and #decision.assessment > 0
                    then " | self-report: " .. decision.assessment
                    else ""
            )
        )
        decision.assessment = nil
        return decision, "ok"
    end

    local adapter = {}

    -- Ask every roommate who still has a turn at once, then wait for the batch.
    -- Sequential calls would add a second per roommate to a single button press.
    function adapter.prefetch(round: any, state: any, mode: string)
        generation += 1
        local batchGeneration = generation
        cache = {}
        local batchCache = cache
        local accepting = true
        if not isEnabled() or calls >= config.maxCalls or state.status ~= "running" then
            return
        end
        local pending = 0
        for _, id in state.order do
            if state.actors[id].role == "npc" and calls < config.maxCalls then
                local observation = round.observe(state, id)
                if Brain.needsTurn(observation, mode) then
                    calls += 1
                    pending += 1
                    local slot = key(id, mode)
                    task.spawn(function()
                        local succeeded, decision, reason = pcall(ask, observation, mode, id)
                        pending -= 1
                        -- A timed-out request may finish during another phase or
                        -- after reset. It must never populate that phase's cache.
                        if not accepting or generation ~= batchGeneration then
                            return
                        end
                        if not succeeded then
                            reason, decision = tostring(decision), nil
                        end
                        if decision then
                            batchCache[slot] = decision
                        else
                            failures += 1
                            warn(string.format("[Brain] %s %s fell back (%s)", id, mode, reason))
                        end
                    end)
                end
            end
        end
        local limit = now() + config.deadline
        while pending > 0 and now() < limit do
            task.wait(0.05)
        end
        accepting = false
        if pending > 0 and generation == batchGeneration then
            failures += pending
            warn(string.format("[Brain] %d roommate(s) missed the %s deadline", pending, mode))
        end
    end

    -- Cache lookup only: the wait already happened in `prefetch`.
    function adapter.decide(observation: any, mode: string, id: string): any?
        local decision = cache[key(id, mode)]
        if not decision then
            return nil
        end
        cache[key(id, mode)] = nil
        if mode == "action" then
            local action = rebind(observation, decision.action)
            if not action then
                return nil
            end
            return { action = action, message = nil }
        end
        return { action = nil, message = decision.message }
    end

    function adapter.status(): string
        return string.format(
            "%s · %d/%d calls · %d fallback(s)",
            if isEnabled() then "live" else "offline",
            calls,
            config.maxCalls,
            failures
        )
    end

    function adapter.reset()
        generation += 1
        calls, failures, cache = 0, 0, {}
    end

    adapter.config = config
    return adapter
end

return Service
