--!strict
-- Home screen: one character, one colour choice, one button, and the separate
-- how-to-play section. Nothing here may start or advance a household by itself.
local Env = require("./support/roblox-env")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")

local function expect(condition: any, reason: string?)
    assert(condition, reason or "home-screen contract failed")
end

-- Every box drawn with explicit offsets must sit inside the box that holds it.
-- Studio still owns how text wraps inside those boxes; this only proves the
-- layout itself cannot hang off a card or off the tablet.
local function auditBounds(root: any, width: number, height: number, path: string)
    for _, child in root:GetChildren() do
        if child:IsA("GuiObject") and child.Rotation == 0 then
            local x, y = child.Position.X.Offset, child.Position.Y.Offset
            local w, h = child.Size.X.Offset, child.Size.Y.Offset
            local where = path .. "/" .. child.Name
            expect(
                x >= 0 and y >= 0 and x + w <= width and y + h <= height,
                string.format(
                    "%s (%d,%d %dx%d) escapes its %dx%d parent",
                    where,
                    x,
                    y,
                    w,
                    h,
                    width,
                    height
                )
            )
            -- Scrolling content and auto-sized text grow on purpose.
            local read, automatic = pcall(function()
                return child.AutomaticSize
            end)
            local grows = read and tostring(automatic) ~= "Enum.AutomaticSize.None"
            if not child:IsA("ScrollingFrame") and not grows then
                auditBounds(child, w, h, where)
            end
        end
    end
end

return function()
    local load = Env.new()
    local View = load("src/client/HousepadView.luau")
    local clicks = {}
    View.connect = function(item, callback)
        clicks[item] = callback
    end
    View.onEnter = function() end
    View.measure = function(text, width)
        return 18 * math.max(1, math.ceil(#text * 8 / width))
    end
    local Home = load("src/client/HomeScreen.luau")
    local canvas = Env.Instance.new("Frame")
    local view: any = { channel = "group", drafts = {}, home = true, homeTab = "home" }
    local fired: any = {}
    local actions: any = {}
    for _, name in
        {
            "act",
            "ready",
            "say",
            "restart",
            "apartment",
            "command",
            "channel",
            "metric",
            "play",
            "home",
            "homeTab",
            "newRound",
            "color",
        }
    do
        actions[name] = function(value)
            fired[name] = value or true
        end
    end

    -- Before the first server state the screen still draws, and starts nothing.
    local handles = Home.render(canvas, nil, view, actions)
    expect(handles.scale, "the home screen must scale with the viewport")
    expect(canvas:FindFirstChild("Bezel"), "the home screen is the same tablet as HousePad")
    auditBounds(canvas, 1280, 720, "home")
    clicks[canvas:FindFirstChild("Play", true)]()
    expect(not fired.play and not fired.newRound, "no household can start before state arrives")

    -- It stays a home screen, not a tutorial: no key list and no roommate roster.
    local words = 0
    for _, node in canvas:GetDescendants() do
        if node:IsA("TextLabel") then
            for _ in string.gmatch(node.Text, "%S+") do
                words += 1
            end
        end
    end
    expect(words < 40, "the front screen should stay almost empty, found " .. words .. " words")
    for _, npc in Setup.npcs do
        for _, node in canvas:GetDescendants() do
            if node:IsA("TextLabel") then
                expect(
                    not string.find(string.lower(node.Text), npc.id, 1, true),
                    "roommates are not introduced on the home screen"
                )
            end
        end
    end

    local state = Round.new(Setup.household("blue"), 13, Setup.rules)
    local payload: any =
        { observation = Round.observe(state, "blue"), color = "blue", best = 4, entered = false }

    -- The character and every colour choice are there, and picking one is a request.
    Home.render(canvas, payload, view, actions)
    auditBounds(canvas, 1280, 720, "home/front")
    expect(canvas:FindFirstChild("Character", true), "the home screen shows your character")
    expect(canvas:FindFirstChild("Body", true), "the character needs a body")
    for _, choice in Setup.playerColors do
        expect(canvas:FindFirstChild("Swatch_" .. choice.id, true), "missing colour " .. choice.id)
    end
    clicks[canvas:FindFirstChild("Swatch_coral", true)]()
    expect(fired.color == "coral", "a swatch must request that colour")
    local best = canvas:FindFirstChild("Best", true)
    expect(best, "the best run is on the home screen")
    local shown = false
    for _, node in best:GetDescendants() do
        if node:IsA("TextLabel") and string.find(node.Text, "4 days", 1, true) then
            shown = true
        end
    end
    expect(shown, "the best run must be shown in days")
    clicks[canvas:FindFirstChild("Play", true)]()
    expect(fired.play, "the button must open the household")

    -- Once the player has moved in, the colour is locked but the run is reachable.
    fired.color = nil
    payload.entered = true
    Home.render(canvas, payload, view, actions)
    clicks[canvas:FindFirstChild("Swatch_mint", true)]()
    expect(not fired.color, "the colour cannot change once the player has moved in")

    -- How to play is its own section, reached and left by its own buttons.
    clicks[canvas:FindFirstChild("HowTo", true)]()
    expect(fired.homeTab == "howto")
    view.homeTab = "howto"
    Home.render(canvas, payload, view, actions)
    auditBounds(canvas, 1280, 720, "home/howto")
    expect(not canvas:FindFirstChild("Character", true), "the guide replaces the front screen")
    expect(canvas:FindFirstChild("Control_T", true), "the guide lists the keys")
    fired.homeTab = nil
    clicks[canvas:FindFirstChild("Back", true)]()
    expect(fired.homeTab == "home", "the guide must lead back home")
    view.homeTab = "home"

    -- The running pad holds a five-person household without spilling its rails.
    view.home = false
    View.render(canvas, payload, view, actions)
    auditBounds(canvas, 1280, 720, "pad/running")
    for _, npc in Setup.npcs do
        expect(
            canvas:FindFirstChild("Channel_" .. npc.id, true),
            "every roommate needs a channel: " .. npc.id
        )
    end
    local header = canvas:FindFirstChild("Header", true)
    local dayShown = false
    for _, node in header:GetDescendants() do
        if node:IsA("TextLabel") and node.Text == "Day " .. payload.observation.day then
            dayShown = true
        end
    end
    expect(dayShown, "the running score is the day, shown on the pad")
    expect(canvas:FindFirstChild("Score", true), "the best run is shown while playing")
    view.home = true

    -- An evicted household offers a new one, and reports the run's length.
    local guard = 0
    while state.status == "running" and guard < 400 do
        Flow.advance(Round, Policy, state)
        guard += 1
    end
    expect(state.status == "evicted", "an endless household ends by eviction")
    expect(state.survived >= 1, "the run must have lasted at least a day")
    payload =
        { observation = Round.observe(state, "blue"), color = "blue", best = 4, entered = true }
    Home.render(canvas, payload, view, actions)
    fired.newRound, fired.play = nil, nil
    clicks[canvas:FindFirstChild("Play", true)]()
    expect(fired.newRound and not fired.play, "a finished run starts a new household")

    -- The pad reports the score and offers the way home.
    view.home = false
    View.render(canvas, payload, view, actions)
    auditBounds(canvas, 1280, 720, "pad")
    local record = canvas:FindFirstChild("Result", true)
    expect(record, "an ended household shows its result")
    local lasted = false
    for _, node in record:GetDescendants() do
        if node:IsA("TextLabel") and string.find(node.Text, tostring(state.survived), 1, true) then
            lasted = true
        end
    end
    expect(lasted, "the result must show the days survived")
    clicks[canvas:FindFirstChild("Home", true)]()
    expect(fired.home, "the pad's home button must return to the home screen")
    print(
        string.format(
            "Home screen: character, %d colours, locked colour, guide section and a %d-day run verified",
            #Setup.playerColors,
            state.survived
        )
    )
end
