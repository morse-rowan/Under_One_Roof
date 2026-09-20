--!strict
-- Headless render check for the playable HUD. It draws every phase of a real
-- seeded round from real `MvpRound.observe` output, so a misspelled property, a
-- nil layout value or a field the rules never produce fails from the CLI.
-- It does not check legibility, wrapping or viewport behaviour: those still
-- need a Studio playtest.
local Env = require("./support/roblox-env")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")

local Instance = Env.Instance

local function expect(condition: any, message: string)
    assert(condition, "Round HUD: " .. message)
end

local STOPS = { morning = true, midday = true, night = true }

return function()
    local requireModule = Env.new()
    local Hud = requireModule("src/client/RoundHud.luau")

    -- Lune has no signals, so record the wiring and press the buttons directly.
    local clicks: { [any]: () -> () } = {}
    function Hud.connect(item: any, onClick: () -> ())
        clicks[item] = onClick
    end
    local entered: (() -> ())? = nil
    function Hud.onEnter(_box: any, submit: () -> ())
        entered = submit
    end

    local function press(name: string, text: string?): boolean
        for item, handler in clicks do
            if item.Parent and item.Parent.Name == name and (not text or item.Text == text) then
                handler()
                return true
            end
        end
        return false
    end

    local root = Instance.new("ScreenGui")
    local canvas = Instance.new("Frame")
    canvas.Parent = root

    -- Every callback the HUD can fire, recorded rather than sent anywhere.
    local fired = {}
    local view = { channel = "group", answers = { 1, 2 } }
    local actions
    actions = {
        act = function(candidate: any)
            fired.act = candidate
        end,
        ready = function()
            fired.ready = true
        end,
        say = function(channel: string, speech: string)
            fired.say = channel .. ":" .. speech
        end,
        restart = function()
            fired.restart = true
        end,
        setChannel = function(id: string)
            view.channel = id
        end,
        addSymbol = function(value: number)
            fired.symbol = value
        end,
        undo = function()
            fired.undo = true
        end,
        submit = function()
            fired.submit = true
        end,
    }

    local function draw(payload: any): (number, number)
        local handles = Hud.render(canvas, payload, view, actions)
        local texts, buttons = 0, 0
        for _, item in canvas:GetDescendants() do
            if item:IsA("TextButton") then
                buttons += 1
                expect(#item.Text > 0, "a button has no label")
            elseif item:IsA("TextLabel") then
                if #item.Text > 0 then
                    texts += 1
                end
                expect(not string.find(item.Text, "nil"), "a label leaked a nil: " .. item.Text)
            end
        end
        expect(handles.scale ~= nil, "the canvas must always get its scale")
        return texts, buttons
    end

    expect(#canvas:GetChildren() == 0, "the canvas starts empty")
    Hud.render(canvas, nil, view, actions)
    expect(#canvas:GetChildren() == 1, "an empty payload draws only the scale")

    -- A full seeded day, phase by phase, plus the ending.
    local state = Round.new(Setup.actors, 13, Setup.rules)
    local phases = {}
    local guard = 0
    while state.status == "running" and guard < 40 do
        guard += 1
        local phase = state.phase
        local work = Round.workView(state, Setup.player)
        local payload = {
            observation = Round.observe(state, Setup.player),
            startedAt = 0,
            endsAt = 60,
            work = work,
            reachable = if phase == "action_one"
                then { reference = 1, prompt = "Wash the dishes" }
                else nil,
        }
        local texts, buttons = draw(payload)
        expect(texts >= 10, string.format("%s drew only %d labels", phase, texts))
        phases[phase] = (phases[phase] or 0) + 1

        if phase == "work" then
            expect(canvas:FindFirstChild("Work") ~= nil, "the work phase needs its panel")
            expect(canvas:FindFirstChild("Chat") == nil, "there is no chatting at work")
            expect(work ~= nil and work.stage == "preview", "the shift opens on a preview")
            Round.beginRecall(state, Setup.player, state.revision, work.id)
            local recall = Round.workView(state, Setup.player)
            payload.work = recall
            local _, recallButtons = draw(payload)
            expect(recall.sequence == nil, "the sequence must be hidden once recall starts")
            expect(recallButtons >= recall.symbols, "recall needs a pad to type on")
            Round.submitWork(state, Setup.player, state.revision, recall.id, {})
        else
            expect(buttons > 0, phase .. " gave the player nothing to press")
            if STOPS[phase] then
                expect(canvas:FindFirstChild("Chat") ~= nil, phase .. " must allow talking")
                expect(entered ~= nil, "the chat box must be wired to its Enter key")
                expect(press("Choices", "[T]  Done — move the day on"), "no way to end the phase")
                expect(fired.ready == true, "ending the phase must reach the server")
                expect(press("Chat", "To Green"), "a private channel must be selectable")
                expect(view.channel == "green", "choosing a channel must stick")
                view.channel = "group"
            else
                expect(canvas:FindFirstChild("Chat") == nil, "action windows are not for chatting")
                expect(
                    canvas:FindFirstChild("Chores") ~= nil,
                    "an action window should point at the apartment"
                )
                expect(
                    (canvas:FindFirstChild("Prompt") ~= nil) == (payload.reachable ~= nil),
                    "the E prompt must appear exactly when a chore is in reach"
                )
            end
            for _, id in state.order do
                local observation = Round.observe(state, id)
                local decision = Policy.decide(observation, Policy.styleFor(id), STOPS[phase])
                if decision.action then
                    Round.decide(state, id, state.revision, decision.action, nil)
                end
            end
        end
        Round.advance(state, state.revision)
    end
    expect(state.status ~= "running", "the seeded round must reach an ending")
    for _, phase in Round.phases do
        expect(phases[phase] ~= nil, "the HUD never drew the " .. phase .. " phase")
    end

    -- The ending replaces the choices with a verdict the player can act on.
    local final = { observation = Round.observe(state, Setup.player), startedAt = 0, endsAt = 0 }
    draw(final)
    expect(canvas:FindFirstChild("Result") ~= nil, "a finished round needs its verdict")
    expect(canvas:FindFirstChild("Choices") == nil, "a finished round offers no more actions")

    expect(press("Result", "Play it again"), "the verdict must offer another run")
    expect(fired.restart == true, "pressing it must ask the server for a fresh round")

    -- Number shortcuts must line up with the buttons, skipping apartment chores.
    local observation = {
        candidates = {
            { kind = "wait" },
            { kind = "finish_chore", reference = 4 },
            { kind = "contribute", amount = 5 },
        },
    }
    expect(Hud.shortcut(observation, 1).kind == "wait", "the first shortcut is the first button")
    expect(
        Hud.shortcut(observation, 2).kind == "contribute",
        "chores are done in the apartment, not from the menu"
    )
    expect(Hud.shortcut(observation, 3) == nil, "there is no third button to press")

    print(string.format("Round HUD: %d phases drawn from live round state without error", guard))
end
