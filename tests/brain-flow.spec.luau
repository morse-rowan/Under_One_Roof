--!strict
-- How the round behaves when a model is driving the roommates. The adapter here is
-- a fake, so no bridge, key or inference is involved: what is checked is that a live
-- decision is used when there is one, and that every way of not having one — silence,
-- a thrown error, an illegal action, an exhausted budget — leaves a household that
-- still plays itself to an ending.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")

local function expect(condition: any, message: string)
    assert(condition, message)
end

local function spoken(state: any, speech: string): boolean
    for _, event in state.events do
        if event.kind == "message" and event.data.speech == speech then
            return true
        end
    end
    return false
end

-- Plays a whole household the way `RoundSession` does, deferring work like the
-- live build. Returns the number of phases it took to end.
local function play(state: any, brain: any?): number
    local phases = 0
    while state.status == "running" do
        phases += 1
        expect(phases < 400, "the household never ended")
        Flow.advance(Round, Policy, state, brain)
    end
    return phases
end

return function()
    --------------------------------------------------- a live decision is preferred

    local calls = { communication = 0, action = 0, prefetch = 0 }
    local live = {
        prefetch = function(_round: any, _state: any, mode: string)
            calls.prefetch += 1
            expect(mode == "communication" or mode == "action", "unknown prefetch mode")
        end,
        decide = function(observation: any, mode: string, id: string): any?
            calls[mode] += 1
            expect(observation.actor.id == id, "the adapter is asked about one roommate")
            if mode == "communication" then
                if observation.messagesRemaining > 0 then
                    return { action = nil, message = { channel = "group", speech = "Live line." } }
                end
                return nil
            end
            return { action = observation.candidates[1], message = nil }
        end,
    }
    local state = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, state, live)
    expect(calls.prefetch == 1, "the adapter is offered the whole batch first")
    expect(calls.communication == 4, "every roommate is asked once")
    expect(spoken(state, "Live line."), "a live line must reach the board")

    ------------------------------------------------------- failures are absorbed

    local broken = {
        decide = function(): any?
            error("bridge exploded")
        end,
    }
    local brokenState = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, brokenState, broken)
    expect(#brokenState.events > 0, "a thrown adapter must not stop the stop")
    local offline = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, offline, nil)
    expect(
        #brokenState.events == #offline.events,
        "a thrown adapter must produce exactly the offline household"
    )

    local badPrefetch = {
        prefetch = function()
            error("prefetch exploded")
        end,
        decide = function(): any?
            return nil
        end,
    }
    local prefetchState = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, prefetchState, badPrefetch)
    expect(
        #prefetchState.events == #offline.events,
        "a thrown prefetch must also fall back to the offline household"
    )

    ------------------------------------------------- an illegal reply is refused

    local forging = {
        decide = function(_observation: any, mode: string): any?
            if mode == "action" then
                -- A validated decision can still go stale; the round is the authority.
                return { action = { kind = "contribute", amount = 9999 }, message = nil }
            end
            return nil
        end,
    }
    local forged = Round.new(Setup.actors, 13, Setup.rules)
    local cash = forged.actors.green.cash
    expect(Flow.advance(Round, Policy, forged, forging), "an illegal NPC action must not block")
    expect(forged.actors.green.cash == cash, "an illegal amount must never be paid")

    ------------------------------------------------ mixed live/offline still ends

    local flaky = {
        turns = 0,
        decide = function(observation: any, mode: string): any?
            -- Every third turn answers; the rest fall back to the deterministic policy.
            local answered = observation.day % 3 == 0
            if not answered then
                return nil
            end
            if mode == "communication" then
                if observation.messagesRemaining > 0 then
                    return { action = nil, message = { channel = "group", speech = "Still here." } }
                end
                return nil
            end
            return { action = observation.candidates[#observation.candidates], message = nil }
        end,
    }
    local mixed = Round.new(Setup.actors, 13, Setup.rules)
    local phases = play(mixed, flaky)
    expect(mixed.status ~= "running" and phases > 6, "a mixed household must reach an ending")
    expect(spoken(mixed, "Still here."), "the live turns must have been used")
    expect(mixed.survived >= 0, "days survived stays defined")

    ------------------------------------------------------- the developer switch

    local parsed = Flow.parse("/brain on")
    expect(parsed and parsed.kind == "brain" and parsed.enabled == true, "/brain on parses")
    expect(Flow.parse("/brain off").enabled == false, "/brain off parses")
    for _, bad in { "/brain", "/brain maybe", "/brain on off" } do
        expect(Flow.parse(bad) == nil, "invalid brain command accepted: " .. bad)
    end
    expect(string.find(Flow.help, "/brain", 1, true) ~= nil, "the switch is documented in help")
end
