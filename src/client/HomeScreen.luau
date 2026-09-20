--!strict
-- The home screen: the same tablet as HousePad, with almost nothing on it. One
-- character in the colour you pick, the button that starts the run, and your best
-- score. How to play is a separate section behind its own button, not a wall of
-- text you have to read first.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Build = require(shared:WaitForChild("BuildInfo"))
local Setup = require(shared:WaitForChild("RoundSetup"))
local View = require(script.Parent.HousepadView)
local Kit = require(script.Parent.MenuKit)

local Home = {}
local C = View.palette
local frame, label, button = View.frame, View.label, View.button
local EYE = Color3.fromRGB(39, 54, 64)

Home.background = View.background
Home.size = View.size

local CONTROLS = {
    { key = "T", text = "Continue. The day only moves when you say so." },
    { key = "M", text = "Walk around the apartment with WASD or the arrow keys." },
    { key = "E", text = "Do the chore you are standing next to." },
    { key = "Y", text = "Jump to the message box at a conversation stop." },
    { key = "H", text = "Come back to this screen." },
}

local RULES = {
    "Rent is due every three days. Whatever the five of you put in across those days is what the landlord gets.",
    "Miss it, let the place rot, or throw one party too many and the landlord's patience runs out.",
    "Your score is the number of days the household lasts. There is no finish line.",
}

local function centered(item: TextLabel): TextLabel
    item.TextXAlignment = Enum.TextXAlignment.Center
    return item
end

-- The same bean that stands in the apartment, drawn flat and large.
local function character(parent: Instance, color: string, x: number, y: number)
    local rgb = Setup.rgb(color)
    local tone = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    local bean = Kit.make("Frame", {
        Name = "Character",
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(190, 186),
        BackgroundTransparency = 1,
    }, parent)
    frame(bean, "Shadow", 36, 168, 118, 18, C.line, 9)
    frame(bean, "HandLeft", 6, 88, 28, 42, tone, 14)
    frame(bean, "HandRight", 156, 88, 28, 42, tone, 14)
    frame(bean, "FootLeft", 52, 154, 36, 22, tone, 11)
    frame(bean, "FootRight", 102, 154, 36, 22, tone, 11)
    local body = frame(bean, "Body", 35, 0, 120, 166, tone, 60)
    frame(body, "Eye", 31, 46, 14, 20, EYE, 7)
    frame(body, "EyeRight", 75, 46, 14, 20, EYE, 7)
    return bean
end

local function swatches(parent: Instance, selected: string, locked: boolean, actions: any)
    local row = Kit.make("Frame", {
        Name = "Colors",
        Position = UDim2.fromOffset(138, 322),
        Size = UDim2.fromOffset(324, 44),
        BackgroundTransparency = 1,
    }, parent)
    for i, choice in Setup.playerColors do
        local pick = button(
            row,
            "Swatch_" .. choice.id,
            "",
            (i - 1) * 56,
            0,
            44,
            44,
            false,
            function()
                if not locked then
                    actions.color(choice.id)
                end
            end
        )
        local rgb = choice.rgb
        pick.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
        pick.BackgroundTransparency = if locked and choice.id ~= selected then 0.55 else 0
        Kit.corner(pick, 22)
        if choice.id == selected then
            Kit.stroke(pick, C.ink, 3)
        end
    end
end

local function howToPlay(parent: Instance, actions: any)
    local card = frame(parent, "HomeCard", 340, 92, 600, 510, C.paper)
    label(card, "How to play", 36, 24, 400, 44, 32, C.ink, true)
    local list = Kit.scroller(card, {
        Name = "Guide",
        Position = UDim2.fromOffset(36, 82),
        Size = UDim2.fromOffset(528, 336),
    })
    Kit.column(list, 10)
    local order = 0
    for _, rule in RULES do
        order += 1
        local line = label(list, rule, 0, 0, 516, 40, 14, C.ink)
        line.LayoutOrder = order
        line.AutomaticSize = Enum.AutomaticSize.Y
        line.TextYAlignment = Enum.TextYAlignment.Top
    end
    for _, control in CONTROLS do
        order += 1
        local row = Kit.make("Frame", {
            Name = "Control_" .. control.key,
            Size = UDim2.fromOffset(516, 40),
            BackgroundTransparency = 1,
            LayoutOrder = order,
        }, list)
        local chip = frame(row, "Key", 0, 2, 52, 34, C.rail, 10)
        centered(label(chip, control.key, 0, 0, 52, 34, 15, C.ink, true))
        label(row, control.text, 66, 0, 450, 40, 14, C.muted)
    end
    button(card, "Back", "Back", 36, 432, 190, 50, false, function()
        actions.homeTab("home")
    end)
end

local function front(parent: Instance, payload: any, view: any, actions: any)
    local card = frame(parent, "HomeCard", 340, 92, 600, 510, C.paper)
    local o = if payload then payload.observation else nil
    local color = view.color or (payload and payload.color) or Setup.defaultColor
    local best = if payload then payload.best or 0 else 0
    local entered = payload ~= nil and payload.entered == true
    local finished = o ~= nil and o.status ~= "running"

    label(card, Build.name, 36, 26, 380, 44, 34, C.ink, true)
    label(card, "Keep the apartment. Count the days.", 38, 72, 380, 20, 14, C.muted)
    local record = frame(card, "Best", 430, 24, 150, 56, C.rail)
    label(record, "BEST RUN", 14, 8, 122, 14, 10, C.muted, true)
    label(
        record,
        string.format("%d %s", best, if best == 1 then "day" else "days"),
        14,
        24,
        122,
        24,
        20,
        C.ink,
        true
    )

    character(card, color, 205, 108)
    centered(label(card, "You are " .. string.upper(color), 150, 292, 300, 22, 14, C.muted, true))
    swatches(card, color, entered and not finished, actions)

    local playText = if not o
        then "Getting things ready…"
        elseif finished then "Start a new household"
        elseif entered then "Back to your household"
        else "Move in"
    local play = button(card, "Play", playText, 140, 382, 320, 62, true, function()
        if not o then
            return
        elseif finished then
            actions.newRound()
        else
            actions.play()
        end
    end)
    play.TextSize = 22
    play.Font = Enum.Font.GothamBold
    play.BackgroundColor3 = if o then C.good else C.line
    button(card, "HowTo", "How to play", 200, 456, 200, 38, false, function()
        actions.homeTab("howto")
    end)
end

function Home.render(canvas: Instance, payload: any, view: any, actions: any): any
    canvas:ClearAllChildren()
    local handles: any = { scale = Kit.make("UIScale", {}, canvas) }
    View.shell(canvas)
    if view.homeTab == "howto" then
        howToPlay(canvas, actions)
    else
        front(canvas, payload, view, actions)
    end
    centered(label(canvas, Build.name .. " · " .. Build.version, 340, 616, 600, 18, 11, C.muted))
    return handles
end

return Home
