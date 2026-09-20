--!strict
-- Manual orchestration only: no clock, scheduled beats or paid inference.
local Flow = {}
local STOPS = { morning = true, midday = true, night = true }

function Flow.speak(round: any, policy: any, state: any)
    if not STOPS[state.phase] or state.status ~= "running" then
        return
    end
    for _, id in state.order do
        if state.actors[id].role == "npc" then
            local decision = policy.decide(round.observe(state, id), policy.styleFor(id), true)
            if decision.message then
                round.decide(state, id, state.revision, nil, decision.message)
            end
        end
    end
end

function Flow.advance(round: any, policy: any, state: any): (boolean, string)
    if state.status ~= "running" then
        return false, "The household has finished. Use /reset."
    end
    -- All remaining stop replies precede consequential choices. Player input has
    -- already been applied when this explicit continuation arrives.
    Flow.speak(round, policy, state)
    for _, id in state.order do
        if state.actors[id].role == "npc" then
            local decision = policy.decide(round.observe(state, id), policy.styleFor(id), false)
            if decision.action then
                round.decide(state, id, state.revision, decision.action, nil)
            end
        end
    end
    if state.phase == "work" and not state.workSubmitted then
        -- Deferred minigames pay the guaranteed wage and no performance bonus.
        round.work(state, state.revision, 0)
    end
    local ok, reason = round.advance(state, state.revision)
    if ok then
        Flow.speak(round, policy, state)
    end
    return ok, reason
end

Flow.help = "/next · /day · /set landlord|heat|rent|cleanliness|cash N · /reset [seed]"

function Flow.parse(raw: any): (any?, string?)
    if type(raw) ~= "string" or #raw > 120 then
        return nil, "Enter a command under 120 characters."
    end
    local words = {}
    for word in string.gmatch(string.lower(raw), "%S+") do
        table.insert(words, word)
    end
    local command = string.gsub(words[1] or "", "^/", "")
    if (command == "next" or command == "day" or command == "help") and #words == 1 then
        return { kind = command }, nil
    elseif command == "reset" and #words <= 2 then
        local seed = if words[2] then tonumber(words[2]) else 13
        if seed and seed >= 1 and seed < 2147483647 and seed % 1 == 0 then
            return { kind = "reset", seed = seed }, nil
        end
    elseif command == "set" and #words == 3 then
        local maximum = ({
            landlord = 100,
            heat = 1000,
            rent = 100000,
            cleanliness = 100,
            cash = 100000,
        })[words[2]]
        local value = tonumber(words[3])
        if
            maximum
            and value
            and value == value
            and value >= 0
            and value <= maximum
            and value % 1 == 0
        then
            return { kind = "set", stat = words[2], value = value }, nil
        end
    end
    return nil, "Invalid command. " .. Flow.help
end

-- The transport must gate this with RunService:IsStudio(). No gameplay request
-- can call it. Cleanliness is a dev offset, so later mess/cleaning still matters.
function Flow.setStat(round: any, state: any, player: string, stat: string, value: number): string
    if stat == "landlord" then
        state.heat = math.floor(state.config.eviction * (1 - value / 100) + 0.5)
    elseif stat == "heat" then
        state.heat = value
    elseif stat == "rent" then
        state.rentPaid = math.min(value, state.config.rent)
    elseif stat == "cash" then
        state.actors[player].cash = value
    elseif stat == "cleanliness" then
        state.debugCleanlinessOffset = nil
        local natural = round.observe(state, player).cleanliness
        -- Recompute unclamped dirt so even a very dirty household can be reset.
        local dirt = 0
        for _, item in state.items do
            if not item.resolved and item.kind ~= "leak" then
                dirt += state.config.messDirt + item.age * state.config.ageDirt
            end
        end
        state.debugCleanlinessOffset = value - (100 - dirt)
        if value == natural then
            state.debugCleanlinessOffset = nil
        end
    end
    state.revision += 1
    return string.format(
        "%s set to %d%s",
        stat,
        if stat == "rent" then state.rentPaid else value,
        if stat == "cleanliness" then " (development adjustment)" else ""
    )
end

return Flow
