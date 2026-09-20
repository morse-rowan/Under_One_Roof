--!strict
-- Play a household with model-driven roommates from the command line.
--
--   ./tools/nemotron_proxy.ps1 -Offline      # deterministic stub, no key, no inference
--   lune run tools/live_round.luau -- --days 3
--   lune run tools/live_round.luau -- --days 3 --say "Can someone cover rent tonight?"
--
-- This exercises the same shared modules the Roblox server uses: `MvpRound` owns the
-- rules, `RoundBrain` builds the prompt and validates the reply, `HousepadFlow`
-- schedules the turns, and `RoundPolicy` takes any turn the model does not.
--
-- What it does NOT cover: `RoundBrainService` (Roblox HTTP, parallel prefetch and the
-- call budget live there), the apartment, the HousePad UI and input. Those still need
-- a Studio playtest.
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")
local Brain = require("../src/shared/RoundBrain")

local options = {
    url = "http://127.0.0.1:8787/decide",
    seed = 13,
    days = 3,
    maxCalls = 200,
    say = nil :: string?,
    quiet = false,
}

local index = 1
while index <= #process.args do
    local flag = process.args[index]
    local value = process.args[index + 1]
    if flag == "--url" and value then
        options.url = value
    elseif flag == "--seed" and value then
        options.seed = assert(tonumber(value), "--seed needs a number")
    elseif flag == "--days" and value then
        options.days = assert(tonumber(value), "--days needs a number")
    elseif flag == "--max-calls" and value then
        options.maxCalls = assert(tonumber(value), "--max-calls needs a number")
    elseif flag == "--say" and value then
        options.say = value
    elseif flag == "--quiet" or flag == "--" then
        -- Lune forwards the separator itself; ignore it.
        options.quiet, value = options.quiet or flag == "--quiet", nil
    else
        error("Unknown argument: " .. tostring(flag))
    end
    index += if value == nil then 1 else 2
end

local stats = { calls = 0, answered = 0, rejected = 0, unreachable = 0, seconds = 0 }

-- The Lune counterpart of `RoundBrainService`: same contract, sequential transport.
local brain = {
    decide = function(observation: any, mode: string, id: string): any?
        if stats.calls >= options.maxCalls or not Brain.needsTurn(observation, mode) then
            return nil
        end
        stats.calls += 1
        local packet = Brain.packet(observation, mode)
        local ok, response = pcall(net.request, {
            url = options.url,
            method = "POST",
            headers = { ["Content-Type"] = "application/json" },
            body = serde.encode("json", {
                system = packet.system,
                observation = packet.observation,
                maxTokens = packet.responseTokens,
                version = packet.version,
            }),
        })
        if not ok then
            stats.unreachable += 1
            print(string.format("  ! %s %s: bridge unreachable (%s)", id, mode, tostring(response)))
            return nil
        end
        local decoded = (pcall(serde.decode, "json", response.body))
                and serde.decode("json", response.body)
            or nil
        if type(decoded) ~= "table" or decoded.ok ~= true or type(decoded.decision) ~= "table" then
            stats.rejected += 1
            print(
                string.format(
                    "  ! %s %s: bridge refused (%s)",
                    id,
                    mode,
                    tostring(if type(decoded) == "table" then decoded.error else response.statusCode)
                )
            )
            return nil
        end
        stats.seconds += tonumber(decoded.seconds) or 0
        local decision, reason = Brain.validate(decoded.decision, observation, mode)
        if not decision then
            stats.rejected += 1
            print(string.format("  ! %s %s: %s, falling back", id, mode, reason))
            return nil
        end
        stats.answered += 1
        if not options.quiet and type(decision.assessment) == "string" and #decision.assessment > 0
        then
            -- The model's own summary. Diagnostic only: it is never shown in game.
            print(string.format("  · %s self-report: %s", id, decision.assessment))
        end
        decision.assessment = nil
        return decision
    end,
}

local state = Round.new(Setup.actors, options.seed, Setup.rules)
local seen = 0

local function drain()
    for position = seen + 1, #state.events do
        local event = state.events[position]
        if event.kind == "message" then
            print(
                string.format(
                    "  %s [%s] %s: %s",
                    event.phase,
                    if event.data.channel == "group"
                        then "board"
                        else "to " .. tostring(event.data.target),
                    event.data.actor,
                    event.data.speech
                )
            )
        elseif event.kind == "action" and event.data.action.kind ~= "wait" then
            print(
                string.format(
                    "  %s %s -> %s%s",
                    event.phase,
                    event.data.actor,
                    event.data.action.kind,
                    if event.data.action.reference
                        then " #" .. tostring(event.data.action.reference)
                        else ""
                )
            )
        elseif event.kind == "rent_settled" or event.kind == "inspection" then
            print(string.format("  %s %s %s", event.phase, event.kind, serde.encode("json", event.data)))
        end
    end
    seen = #state.events
end

print(
    string.format(
        "Live round: seed %d, %d day(s), bridge %s\n%s",
        options.seed,
        options.days,
        options.url,
        "The player waits; roommates decide. Rules: " .. Round.mechanicsVersion
    )
)
Flow.speak(Round, Policy, state, brain)
drain()

if options.say then
    local ok, reason = Round.decide(
        state,
        Setup.player,
        state.revision,
        nil,
        { channel = "group", target = nil, speech = options.say }
    )
    print(string.format('  player says "%s" (%s)', options.say, reason))
    if ok then
        -- Give the roommates their reply turn, exactly as `RoundSession` does.
        Flow.speak(Round, Policy, state, brain)
        drain()
    end
end

local guard = 0
while state.status == "running" and state.day <= options.days do
    guard += 1
    if guard > 400 then
        error("The household did not end")
    end
    local phase = state.phase
    local ok, reason = Flow.advance(Round, Policy, state, brain)
    if not ok then
        print("  advance refused: " .. reason)
        break
    end
    drain()
    if phase == "night" then
        print(
            string.format(
                "-- day %d closed: cleanliness %d, landlord heat %d, rent %d/%d",
                state.day - (if state.phase == "morning" then 1 else 0),
                Round.observe(state, Setup.player).cleanliness,
                state.heat,
                state.rentPaid,
                state.config.rent
            )
        )
    end
end

print(
    string.format(
        "\nEnded: %s after %d day(s) survived.\nBrain: %d call(s), %d answered, %d rejected, "
            .. "%d unreachable, %.2fs of model time.",
        state.status,
        state.survived,
        stats.calls,
        stats.answered,
        stats.rejected,
        stats.unreachable,
        stats.seconds
    )
)
