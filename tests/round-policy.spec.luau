--!strict
local Policy = require("../src/shared/RoundPolicy")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Flow = require("../src/shared/HousepadFlow")

local function expect(condition: any, message: string)
    assert(condition, message)
end

local function observation(events: any): any
    return {
        status = "running",
        day = 2,
        phase = "midday",
        heat = 45,
        rent = 30,
        rentPaid = 10,
        messagesRemaining = 3,
        actor = { id = "green", cash = 12 },
        items = {
            { id = 7, kind = "dishes", creator = "red", age = 1, resolved = false },
        },
        candidates = {
            { kind = "contribute", amount = 5 },
            { kind = "pay_cleanup", reference = 7, amount = 5 },
            { kind = "cancel_plan", reference = 4 },
            { kind = "wait" },
        },
        events = events,
    }
end

local function message(actor: string, channel: string, target: string?, speech: string): any
    return {
        kind = "message",
        day = 2,
        phase = "midday",
        data = { actor = actor, channel = channel, target = target, speech = speech },
    }
end

return function()
    local privateRent = observation({ message("blue", "private", "green", "Can you cover rent?") })
    local green = Policy.decide(privateRent, "household", true).message
    expect(green ~= nil, "a current private request should receive a response")
    expect(
        green.channel == "private" and green.target == "blue",
        "private replies stay with the sender"
    )
    expect(
        string.find(green.speech, "We still need $20", 1, true) ~= nil,
        "rent response needs current state"
    )
    expect(
        string.find(green.speech, "I will", 1, true) == nil,
        "dialogue must not bind a future action"
    )

    privateRent.heat = 0
    local red = Policy.decide(privateRent, "cash", true).message
    expect(
        red ~= nil and string.find(red.speech, "hang on to my cash", 1, true) ~= nil,
        "style changes rent dialogue"
    )

    local noRent = observation({ message("blue", "private", "green", "Please pay rent") })
    noRent.candidates = { { kind = "wait" } }
    local unavailable = Policy.decide(noRent, "household", true).message
    expect(
        unavailable and string.find(unavailable.speech, "cannot put money", 1, true) ~= nil,
        "rent response cannot offer an unavailable action"
    )

    local cleanup =
        observation({ message("blue", "private", "green", "Can you clean the dishes?") })
    local cleanupReply = Policy.decide(cleanup, "household", true).message
    expect(cleanupReply ~= nil and cleanupReply.target == "blue", "cleanup remains private")
    expect(
        string.find(cleanupReply.speech, "could pay", 1, true) ~= nil,
        "cleanup names a legal option"
    )
    expect(
        string.find(string.lower(cleanupReply.speech), "cleaned", 1, true) == nil,
        "dialogue cannot claim cleanup happened"
    )

    local duplicate = observation({
        message("blue", "private", "green", "Can you help with rent?"),
        message("green", "private", "blue", "We still need $20. I can spare $5."),
    })
    expect(
        Policy.decide(duplicate, "household", true).message == nil,
        "the same request gets one reply"
    )

    local old = observation({
        {
            kind = "message",
            day = 2,
            phase = "morning",
            data = {
                actor = "blue",
                channel = "private",
                target = "green",
                speech = "Can you help?",
            },
        },
    })
    local oldReply = Policy.decide(old, "household", true).message
    expect(
        oldReply == nil or oldReply.channel ~= "private",
        "a previous-stop private message must not be answered again"
    )

    local hiddenElsewhere =
        observation({ message("blue", "private", "red", "Can you cover rent?") })
    local hiddenReply = Policy.decide(hiddenElsewhere, "household", true).message
    expect(
        hiddenReply == nil or hiddenReply.channel ~= "private",
        "a message not addressed to this roommate must not receive a private reply"
    )

    local groupRent = observation({ message("blue", "group", nil, "Can someone cover rent?") })
    local groupReply = Policy.decide(groupRent, "household", true).message
    expect(
        groupReply ~= nil and groupReply.channel == "group" and groupReply.target == nil,
        "group reply stays public"
    )

    -- Flow calls policies repeatedly at entry, after player speech and before
    -- continuation. Real event history must keep one opener and one request
    -- reply, without an NPC-to-NPC acknowledgement chain.
    local live = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, live)
    local initialMessages = #live.events
    Flow.speak(Round, Policy, live)
    expect(#live.events == initialMessages, "ambient openers repeat in the same stop")
    expect(Round.message(live, "blue", live.revision, "group", nil, "Can someone cover rent?"))
    Flow.speak(Round, Policy, live)
    local afterRequest = #live.events
    Flow.speak(Round, Policy, live)
    expect(#live.events == afterRequest, "a group request should receive one bounded response wave")
    local replies = 0
    for _, event in live.events do
        if event.kind == "message" and event.day == 1 and event.phase == "morning" then
            replies += 1
            if event.data.actor ~= "blue" then
                expect(
                    not string.find(string.lower(event.data.speech), "can someone", 1, true),
                    "an NPC copied a request into a ping-pong reply"
                )
            end
        end
    end
    -- One opener and one reply per roommate, plus the player's own request.
    expect(
        replies == 2 * #Setup.npcs + 1,
        "expected one opener and one group reply per roommate, plus the request"
    )

    local privateLive = Round.new(Setup.actors, 13, Setup.rules)
    Flow.speak(Round, Policy, privateLive)
    expect(
        Round.message(
            privateLive,
            "blue",
            privateLive.revision,
            "private",
            "green",
            "Could you help with rent?"
        )
    )
    Flow.speak(Round, Policy, privateLive)
    local afterPrivate = #privateLive.events
    Flow.speak(Round, Policy, privateLive)
    expect(
        #privateLive.events == afterPrivate,
        "a private request should receive one bounded reply"
    )
    local privateReplies = 0
    for _, event in privateLive.events do
        if
            event.kind == "message"
            and event.data.actor == "green"
            and event.data.target == "blue"
        then
            privateReplies += 1
            expect(event.data.channel == "private", "private request leaked to the group")
        end
    end
    expect(privateReplies == 1, "private request should have exactly one response")
end
