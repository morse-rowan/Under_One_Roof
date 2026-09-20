--!strict
-- Live-state rendering, message alignment/privacy, and real callback wiring.
local Env = require("./support/roblox-env")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")
local Data = require("../src/shared/HousepadData")

local function expect(condition: any, reason: string?)
    assert(condition, reason or "round-hud contract failed")
end

return function()
    local View = Env.new()("src/client/HousepadView.luau")
    local clicks = {}
    View.connect = function(item, callback)
        clicks[item] = callback
    end
    View.onEnter = function() end
    View.measure = function(text, width)
        return 18 * math.max(1, math.ceil(#text * 8 / width))
    end
    local canvas = Env.Instance.new("Frame")
    local view = { channel = "group", drafts = {} }
    local fired = {}
    local actions = {}
    for _, name in { "act", "ready", "say", "restart", "apartment", "command", "channel", "metric" } do
        actions[name] = function(value)
            fired[name] = value or true
        end
    end
    local state = Round.new(Setup.actors, 13, { days = 3, eviction = 1000 })
    expect(
        Round.decide(
            state,
            "blue",
            state.revision,
            nil,
            { channel = "group", speech = "Hello house" }
        )
    )
    expect(
        Round.decide(
            state,
            "green",
            state.revision,
            nil,
            { channel = "group", speech = "Hello Blue" }
        )
    )
    -- These envelopes use the atomic API, as the server does.
    expect(
        Round.decide(
            state,
            "blue",
            state.revision,
            nil,
            { channel = "private", target = "red", speech = "Private note" }
        )
    )
    expect(
        Round.decide(
            state,
            "red",
            state.revision,
            nil,
            { channel = "private", target = "green", speech = "Not for Blue" }
        )
    )
    local observation = Round.observe(state, "blue")
    expect(#Data.messages(observation, "red") == 1)
    expect(#Data.messages(observation, "green") == 0)
    local count = 0
    while state.status == "running" do
        observation = Round.observe(state, "blue")
        local payload = { observation = observation, developer = true }
        local handles = View.render(canvas, payload, view, actions)
        expect(handles.scale)
        for _, node in canvas:GetDescendants() do
            if node:IsA("TextLabel") then
                expect(not string.find(node.Text, "Not for Blue", 1, true))
            end
        end
        for _, name in { "Metric_landlord", "Metric_rent", "Metric_cleanliness" } do
            local metric = canvas:FindFirstChild(name)
            expect(metric and metric:IsA("TextButton"))
            clicks[metric]()
            expect(fired.metric)
        end
        local nextButton = canvas:FindFirstChild("Next", true)
        expect(nextButton)
        clicks[nextButton]()
        expect(fired.ready)
        if state.phase == "morning" then
            local mine = canvas:FindFirstChild("MessageMine", true)
            local other = canvas:FindFirstChild("MessageOther", true)
            if count == 0 then
                expect(mine and other, "both sides of the conversation should render")
                expect(
                    mine.Position.X.Offset < other.Position.X.Offset,
                    "own messages must be on the left"
                )
                expect(mine.BackgroundColor3.B > mine.BackgroundColor3.R, "own bubble must be blue")
            end
            clicks[canvas:FindFirstChild("Channel_red", true)]()
            expect(fired.channel == "red")
        elseif state.phase == "work" then
            expect(canvas:FindFirstChild("Work"))
            expect(not handles.chat)
            expect(canvas:FindFirstChild("Todo_parcel", true))
            expect(canvas:FindFirstChild("Todo_cup", true))
            expect(canvas:FindFirstChild("Todo_sort", true))
            for _, node in canvas:FindFirstChild("Work"):GetDescendants() do
                expect(not node:IsA("TextButton"), "minigames must not be playable")
            end
        end
        view.apartment = true
        View.render(canvas, payload, view, actions)
        expect(not canvas:FindFirstChild("Bezel"))
        expect(canvas:FindFirstChild("OpenPad"))
        view.apartment = false
        expect(Flow.advance(Round, Policy, state))
        count += 1
        expect(count <= 18)
    end
    View.render(canvas, { observation = Round.observe(state, "blue") }, view, actions)
    expect(canvas:FindFirstChild("Result"))
    clicks[canvas:FindFirstChild("Restart", true)]()
    expect(fired.restart)
    expect(not canvas:FindFirstChild("Next", true))
    print(
        string.format(
            "HousePad: %d manual phases rendered, privacy/alignment/actions/TODOs verified",
            count
        )
    )
end
