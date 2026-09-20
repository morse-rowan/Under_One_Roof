--!strict
-- Functional HUD for the playable round. It is deliberately plain: the menu
-- visual study owns how the game should eventually look, and this exists so the
-- locked mechanics can be played and felt before a look is chosen. Every value
-- here comes from the server's audience-filtered observation; the client never
-- decides what is legal, only which legal option the player clicked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = {}

local shared = ReplicatedStorage:WaitForChild("Shared")
local Setup = require(shared:WaitForChild("RoundSetup"))
local Text = require(shared:WaitForChild("RoundText"))

local CANVAS = Vector2.new(1280, 720)
local CHORE = { finish_chore = true, pickup_trash = true }
local STOPS = { morning = true, midday = true, night = true }
local SHORTCUTS = 5
local INK = Color3.fromRGB(46, 40, 34)
local PAPER = Color3.fromRGB(247, 240, 224)
local MUTED = Color3.fromRGB(126, 113, 95)
local ACCENT = Color3.fromRGB(214, 146, 68)
local BAD = Color3.fromRGB(190, 88, 72)
local GOOD = Color3.fromRGB(92, 143, 118)

local function new(class: string, props: { [string]: any }, parent: Instance?): any
    local item = Instance.new(class)
    for key, value in props do
        (item :: any)[key] = value
    end
    item.Parent = parent
    return item
end

local function card(parent: Instance, props: { [string]: any }): Frame
    local frame = new("Frame", {
        BackgroundColor3 = PAPER,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint or Vector2.zero,
        Name = props.Name or "Card",
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, frame)
    return frame
end

local function label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
    local settings = props or {}
    return new("TextLabel", {
        BackgroundTransparency = 1,
        Font = settings.Font or Enum.Font.Gotham,
        Text = text,
        TextSize = settings.TextSize or 14,
        TextColor3 = settings.TextColor3 or INK,
        TextXAlignment = settings.TextXAlignment or Enum.TextXAlignment.Left,
        TextYAlignment = settings.TextYAlignment or Enum.TextYAlignment.Top,
        TextWrapped = settings.TextWrapped ~= false,
        Size = settings.Size or UDim2.new(1, 0, 0, 18),
        Position = settings.Position or UDim2.new(),
        AutomaticSize = settings.AutomaticSize or Enum.AutomaticSize.None,
        LayoutOrder = settings.LayoutOrder or 1,
        RichText = settings.RichText == true,
    }, parent)
end

-- Signals do not exist in Lune's reflection database, so the headless render test
-- replaces this with a recorder and presses the buttons itself. In the client it
-- is the real connection and nothing is swallowed.
function Hud.connect(item: TextButton, onClick: () -> ())
    item.Activated:Connect(onClick)
end

-- Same seam for the chat box's Enter key.
function Hud.onEnter(box: TextBox, submit: () -> ())
    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            submit()
        end
    end)
end

local function button(parent: Instance, text: string, props: { [string]: any }, onClick: () -> ())
    local item = new("TextButton", {
        BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(238, 228, 206),
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextSize = props.TextSize or 14,
        TextColor3 = props.TextColor3 or INK,
        TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = props.Size or UDim2.new(1, 0, 0, 30),
        Position = props.Position or UDim2.new(),
        AnchorPoint = props.AnchorPoint or Vector2.zero,
        LayoutOrder = props.LayoutOrder or 1,
        Name = props.Name or "Button",
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, item)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, item)
    Hud.connect(item, onClick)
    return item
end

local function column(parent: Instance, gap: number)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap),
    }, parent)
end

local function meter(
    parent: Instance,
    name: string,
    value: number,
    maximum: number,
    tone: Color3,
    order: number
)
    local holder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 34),
        LayoutOrder = order,
    }, parent)
    label(holder, name, { TextSize = 12, TextColor3 = MUTED, Size = UDim2.new(1, 0, 0, 14) })
    label(holder, tostring(value), {
        TextSize = 12,
        TextColor3 = INK,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(1, 0, 0, 14),
    })
    local track = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(223, 212, 188),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, 0, 0, 8),
    }, holder)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, track)
    local fill = new("Frame", {
        BackgroundColor3 = tone,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(math.clamp(value / math.max(1, maximum), 0, 1), 1),
    }, track)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, fill)
end

------------------------------------------------------------------ panel parts

local function drawStatus(parent: Instance, observation: any): TextLabel
    local top = card(parent, {
        Position = UDim2.fromOffset(18, 14),
        Size = UDim2.fromOffset(330, 74),
        Name = "Status",
    })
    label(
        top,
        string.format(
            "Day %d of %d  ·  %s",
            observation.day,
            observation.rules.days,
            Setup.labels[observation.phase] or observation.phase
        ),
        { Font = Enum.Font.GothamBold, TextSize = 18, Size = UDim2.new(1, 0, 0, 22) }
    )
    local clock = label(top, "", {
        TextSize = 13,
        TextColor3 = MUTED,
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 0, 16),
    })
    label(top, "T ends the phase early  ·  E does the chore you are standing at", {
        TextSize = 11,
        TextColor3 = MUTED,
        Position = UDim2.fromOffset(0, 46),
        Size = UDim2.new(1, 0, 0, 14),
    })
    return clock
end

local function drawMeters(parent: Instance, observation: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(18, 98),
        Size = UDim2.fromOffset(330, 232),
        Name = "Meters",
    })
    column(panel, 6)
    local heatTone = if observation.heat >= 70
        then BAD
        elseif observation.heat >= 35 then ACCENT
        else GOOD
    meter(
        panel,
        "Landlord pressure (eviction at " .. observation.rules.eviction .. ")",
        observation.heat,
        observation.rules.eviction,
        heatTone,
        1
    )
    meter(
        panel,
        "Cleanliness",
        observation.cleanliness,
        100,
        if observation.cleanliness < observation.rules.inspectionCleanliness then ACCENT else GOOD,
        2
    )
    meter(
        panel,
        string.format("Rent tonight  $%d of $%d", observation.rentPaid, observation.rent),
        observation.rentPaid,
        observation.rent,
        ACCENT,
        3
    )
    local actor = observation.actor
    label(
        panel,
        string.format(
            "Your money $%d   ·   reserve goal $%d%s",
            actor.cash,
            actor.goal,
            if actor.debt > 0 then string.format("   ·   bills owed $%d", actor.debt) else ""
        ),
        {
            TextSize = 13,
            Font = Enum.Font.GothamMedium,
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, 18),
        }
    )
    label(
        panel,
        if observation.goalMet
            then "Reserve goal reached — survive to the end and it counts."
            else "Keep the apartment first; the reserve only counts if you are still here.",
        { TextSize = 11, TextColor3 = MUTED, LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 28) }
    )
end

local function drawIssues(parent: Instance, observation: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(18, 340),
        Size = UDim2.fromOffset(330, 172),
        Name = "Issues",
    })
    column(panel, 4)
    label(panel, "OUTSTANDING", {
        TextSize = 11,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 14),
    })
    local order = 2
    for _, item in observation.items do
        if not item.resolved and order < 8 then
            label(panel, "· " .. Text.issue(item, Setup.player), {
                TextSize = 12,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 16),
            })
            order += 1
        end
    end
    if order == 2 then
        label(panel, "Nothing is rotting right now.", {
            TextSize = 12,
            TextColor3 = MUTED,
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 16),
        })
    end
end

local function drawLog(parent: Instance, observation: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(920, 14),
        Size = UDim2.fromOffset(342, 498),
        Name = "Log",
    })
    label(panel, "WHAT HAPPENED", {
        TextSize = 11,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
        Size = UDim2.new(1, 0, 0, 16),
    })
    local scroller = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, 0, 1, -20),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        VerticalScrollBarInset = Enum.ScrollBarInset.Always,
    }, panel)
    column(scroller, 5)
    local lines = Text.log(observation, Setup.player)
    local first = math.max(1, #lines - 40)
    for index = first, #lines do
        label(scroller, lines[index], {
            TextSize = 12,
            LayoutOrder = index,
            Size = UDim2.new(1, -6, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
    end
    -- Roblox clamps this to the canvas, so it simply means "pin to the newest line".
    task.defer(function()
        if scroller.Parent then
            scroller.CanvasPosition = Vector2.new(0, 1e6)
        end
    end)
end

-- Chores are not buttons on purpose: the apartment is where you do them.
-- Only the first few options get a number key; the rest scroll.
local function drawChoices(parent: Instance, observation: any, actions: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(366, 386),
        Size = UDim2.fromOffset(536, 126),
        Name = "Choices",
    })
    local scroller = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -32),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        VerticalScrollBarInset = Enum.ScrollBarInset.Always,
        Name = "Options",
    }, panel)
    column(scroller, 4)
    local offered = 0
    for _, candidate in observation.candidates do
        if not CHORE[candidate.kind] then
            offered += 1
            local index = offered
            local prefix = if index <= SHORTCUTS then string.format("[%d]  ", index) else "     "
            button(scroller, prefix .. Text.action(candidate), {
                LayoutOrder = index,
                Size = UDim2.new(1, -6, 0, 26),
            }, function()
                actions.act(candidate)
            end)
        end
    end
    if offered == 0 then
        label(
            scroller,
            if observation.phase == "work"
                then "You are at work. The household waits."
                else "No effort left this window.",
            {
                TextSize = 12,
                TextColor3 = MUTED,
                LayoutOrder = 1,
                Size = UDim2.new(1, -6, 0, 16),
            }
        )
    end
    button(panel, "[T]  Done — move the day on", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Color3.fromRGB(228, 214, 186),
    }, actions.ready)
end

-- Action windows have no chat (the rules only accept messages at a stop), so the
-- same space explains the chores that are waiting out in the apartment.
local function drawChores(parent: Instance, observation: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(366, 246),
        Size = UDim2.fromOffset(536, 128),
        Name = "Chores",
    })
    column(panel, 4)
    label(panel, "IN THE APARTMENT", {
        TextSize = 11,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 14),
    })
    local order = 2
    for _, candidate in observation.candidates do
        if CHORE[candidate.kind] and order < 6 then
            label(
                panel,
                string.format(
                    "· #%d — %s. Walk to it and press E.",
                    candidate.reference,
                    if candidate.kind == "pickup_trash" then "bag it up" else "finish it off"
                ),
                { TextSize = 12, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 16) }
            )
            order += 1
        end
    end
    if order == 2 then
        label(panel, "Nothing out there needs your hands right now.", {
            TextSize = 12,
            TextColor3 = MUTED,
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 16),
        })
    end
end

local function drawChat(parent: Instance, observation: any, view: any, actions: any): TextBox
    local panel = card(parent, {
        Position = UDim2.fromOffset(366, 246),
        Size = UDim2.fromOffset(536, 128),
        Name = "Chat",
    })
    label(
        panel,
        string.format(
            "SAY SOMETHING  ·  %d message%s left this stop",
            observation.messagesRemaining,
            if observation.messagesRemaining == 1 then "" else "s"
        ),
        {
            TextSize = 11,
            TextColor3 = MUTED,
            Font = Enum.Font.GothamBold,
            Size = UDim2.new(1, 0, 0, 16),
        }
    )
    local targets = { "group" }
    for _, id in observation.actorIds do
        if id ~= Setup.player then
            table.insert(targets, id)
        end
    end
    if not table.find(targets, view.channel) then
        view.channel = "group"
    end
    for index, id in targets do
        local active = id == view.channel
        button(panel, if id == "group" then "Group board" else "To " .. Text.name(id, nil), {
            Position = UDim2.fromOffset((index - 1) * 124, 22),
            Size = UDim2.fromOffset(118, 24),
            TextXAlignment = Enum.TextXAlignment.Center,
            BackgroundColor3 = if active then ACCENT else Color3.fromRGB(233, 222, 199),
            TextColor3 = if active then PAPER else MUTED,
        }, function()
            actions.setChannel(id)
        end)
    end
    local box = new("TextBox", {
        BackgroundColor3 = Color3.fromRGB(255, 251, 242),
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderText = "Y to type  ·  Enter to send",
        Text = "",
        TextSize = 13,
        TextColor3 = INK,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.new(1, -96, 0, 30),
    }, panel)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
    local function submit()
        local speech = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
        if #speech > 0 and observation.messagesRemaining > 0 then
            actions.say(view.channel, speech)
            box.Text = ""
        end
    end
    Hud.onEnter(box, submit)
    button(panel, "Send", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 54),
        Size = UDim2.fromOffset(88, 30),
        TextXAlignment = Enum.TextXAlignment.Center,
    }, submit)
    return box
end

local function drawWork(parent: Instance, work: any, view: any, actions: any)
    local panel = card(parent, {
        Position = UDim2.fromOffset(366, 246),
        Size = UDim2.fromOffset(536, 266),
        Name = "Work",
    })
    local showing = work.stage == "preview"
    label(panel, if showing then "MEMORISE THE ORDER" else "TYPE IT BACK", {
        TextSize = 11,
        TextColor3 = MUTED,
        Font = Enum.Font.GothamBold,
        Size = UDim2.new(1, 0, 0, 16),
    })
    label(
        panel,
        if showing
            then "The shift pays either way. Getting this right is the bonus on top."
            else string.format(
                "%d of %d entered. Wrong guesses simply score nothing.",
                #view.answers,
                work.length
            ),
        {
            TextSize = 12,
            TextColor3 = MUTED,
            Position = UDim2.fromOffset(0, 18),
            Size = UDim2.new(1, 0, 0, 16),
        }
    )
    local strip = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 46),
        Size = UDim2.new(1, 0, 0, 54),
    }, panel)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, strip)
    for index = 1, work.length do
        local value = if showing then work.sequence[index] else view.answers[index]
        local slot = new("Frame", {
            BackgroundColor3 = if value
                then Color3.fromRGB(70 + value * 38, 120 + value * 22, 190 - value * 26)
                else Color3.fromRGB(233, 222, 199),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(54, 54),
            LayoutOrder = index,
        }, strip)
        new("UICorner", { CornerRadius = UDim.new(0, 8) }, slot)
        label(slot, if value then tostring(value) else "", {
            Font = Enum.Font.GothamBold,
            TextSize = 26,
            TextColor3 = PAPER,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
    end
    if showing then
        return
    end
    local pad = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 112),
        Size = UDim2.new(1, 0, 0, 48),
    }, panel)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, pad)
    for value = 1, work.symbols do
        button(pad, tostring(value), {
            Size = UDim2.fromOffset(48, 48),
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Center,
            BackgroundColor3 = Color3.fromRGB(70 + value * 38, 120 + value * 22, 190 - value * 26),
            TextColor3 = PAPER,
            LayoutOrder = value,
        }, function()
            actions.addSymbol(value)
        end)
    end
    button(panel, "Undo", {
        Position = UDim2.fromOffset(0, 172),
        Size = UDim2.fromOffset(120, 32),
        TextXAlignment = Enum.TextXAlignment.Center,
    }, actions.undo)
    button(panel, "Hand in the shift", {
        Position = UDim2.fromOffset(132, 172),
        Size = UDim2.fromOffset(200, 32),
        TextXAlignment = Enum.TextXAlignment.Center,
        BackgroundColor3 = ACCENT,
        TextColor3 = PAPER,
    }, actions.submit)
end

local function drawPrompt(parent: Instance, reachable: any)
    local banner = card(parent, {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromOffset(634, 706),
        Size = UDim2.fromOffset(420, 40),
        Name = "Prompt",
    })
    banner.BackgroundColor3 = ACCENT
    label(banner, string.format("E  —  %s  (#%d)", reachable.prompt, reachable.reference), {
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = PAPER,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
end

local function drawResult(parent: Instance, observation: any, actions: any)
    local panel = card(parent, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(520, 260),
        Name = "Result",
    })
    local outcome = observation.outcome
    label(panel, if outcome.survived then "You kept the apartment." else "Evicted.", {
        Font = Enum.Font.GothamBold,
        TextSize = 30,
        TextColor3 = if outcome.survived then GOOD else BAD,
        Size = UDim2.new(1, 0, 0, 38),
    })
    label(
        panel,
        string.format(
            "Day %d  ·  landlord pressure %d  ·  your money $%d of a $%d reserve.",
            observation.day,
            observation.heat,
            observation.actor.cash,
            observation.actor.goal
        ),
        {
            TextSize = 14,
            TextColor3 = MUTED,
            Position = UDim2.fromOffset(0, 46),
            Size = UDim2.new(1, 0, 0, 20),
        }
    )
    label(
        panel,
        if outcome.success
            then "You survived and hit your own reserve. Both halves counted."
            elseif outcome.survived then "You survived, but your own goal went unmet."
            else "The household lost the apartment, so nothing else counted.",
        {
            TextSize = 14,
            Position = UDim2.fromOffset(0, 74),
            Size = UDim2.new(1, 0, 0, 40),
        }
    )
    button(panel, "Play it again", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.fromScale(0.5, 1),
        Size = UDim2.fromOffset(220, 38),
        TextXAlignment = Enum.TextXAlignment.Center,
        BackgroundColor3 = ACCENT,
        TextColor3 = PAPER,
    }, actions.restart)
end

--------------------------------------------------------------------- render

-- The nth menu choice, skipping the chores that are done in the apartment.
function Hud.shortcut(observation: any, wanted: number): any?
    if wanted > SHORTCUTS then
        return nil
    end
    local seen = 0
    for _, candidate in observation.candidates do
        if not CHORE[candidate.kind] then
            seen += 1
            if seen == wanted then
                return candidate
            end
        end
    end
    return nil
end

-- Draws one observation into `canvas` and returns the live instances the caller
-- keeps hold of. Separate from `start` so the whole HUD can be built headlessly
-- in a test against real `MvpRound.observe` output.
function Hud.render(canvas: Instance, payload: any, view: any, actions: any): any
    canvas:ClearAllChildren()
    local handles: any = { scale = new("UIScale", {}, canvas) }
    if not payload then
        return handles
    end
    local observation = payload.observation
    handles.clock = drawStatus(canvas, observation)
    drawMeters(canvas, observation)
    drawIssues(canvas, observation)
    drawLog(canvas, observation)
    if observation.status ~= "running" then
        drawResult(canvas, observation, actions)
        return handles
    end
    if payload.work then
        drawWork(canvas, payload.work, view, actions)
    else
        if STOPS[observation.phase] then
            handles.chat = drawChat(canvas, observation, view, actions)
        else
            drawChores(canvas, observation)
        end
        drawChoices(canvas, observation, actions)
    end
    if payload.reachable then
        drawPrompt(canvas, payload.reachable)
    end
    return handles
end

---------------------------------------------------------------------- client

function Hud.start()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local remote = ReplicatedStorage:WaitForChild("RoundLink") :: RemoteEvent

    local payload: any = nil
    local view = { channel = "group", answers = {} :: { number } }
    local handles: any = {}

    local gui = new("ScreenGui", {
        Name = "RoundHud",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 20,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player:WaitForChild("PlayerGui"))
    local canvas = new("Frame", {
        Name = "Canvas",
        Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
    }, gui)

    local function send(request: any)
        remote:FireServer(request)
    end

    local redraw
    local actions
    actions = {
        act = function(candidate: any?)
            if candidate then
                send({ kind = "action", action = candidate.kind, reference = candidate.reference })
            end
        end,
        ready = function()
            send({ kind = "ready" })
        end,
        say = function(channel: string, speech: string)
            send({
                kind = "message",
                channel = if channel == "group" then "group" else "private",
                target = if channel == "group" then nil else channel,
                speech = speech,
            })
        end,
        restart = function()
            view.answers = {}
            send({ kind = "restart" })
        end,
        setChannel = function(id: string)
            view.channel = id
            redraw()
        end,
        addSymbol = function(value: number)
            local work = payload and payload.work
            if work and work.stage == "recall" and #view.answers < work.length then
                table.insert(view.answers, value)
                redraw()
            end
        end,
        undo = function()
            if #view.answers > 0 then
                table.remove(view.answers)
                redraw()
            end
        end,
        submit = function()
            send({ kind = "submit", answers = view.answers })
        end,
    }

    function redraw()
        handles = Hud.render(canvas, payload, view, actions)
    end

    remote.OnClientEvent:Connect(function(message: any)
        if type(message) ~= "table" or message.kind ~= "state" then
            return
        end
        local work = message.work
        -- A fresh challenge clears whatever was half-typed for the previous one.
        if not work or work.stage ~= "recall" then
            view.answers = {}
        end
        payload = message
        redraw()
    end)

    local numberKeys = {
        [Enum.KeyCode.One] = 1,
        [Enum.KeyCode.Two] = 2,
        [Enum.KeyCode.Three] = 3,
        [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5,
    }
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() or not payload then
            return
        end
        local observation = payload.observation
        local wanted = numberKeys[input.KeyCode]
        if input.KeyCode == Enum.KeyCode.E and payload.reachable then
            send({ kind = "chore" })
        elseif input.KeyCode == Enum.KeyCode.T and observation.status == "running" then
            actions.ready()
        elseif input.KeyCode == Enum.KeyCode.Y and handles.chat then
            handles.chat:CaptureFocus()
        elseif wanted and payload.work then
            if payload.work.stage == "recall" and wanted <= payload.work.symbols then
                actions.addSymbol(wanted)
            end
        elseif wanted then
            actions.act(Hud.shortcut(observation, wanted))
        end
    end)

    RunService:BindToRenderStep("RoundHudClock", Enum.RenderPriority.Last.Value, function()
        local camera = workspace.CurrentCamera
        if camera and handles.scale then
            local viewport = camera.ViewportSize
            handles.scale.Scale = math.min(viewport.X / CANVAS.X, viewport.Y / CANVAS.Y, 1.35)
        end
        if payload and handles.clock and handles.clock.Parent then
            local left = math.max(0, payload.endsAt - workspace:GetServerTimeNow())
            local seconds = math.ceil(left)
            handles.clock.Text = if payload.observation.status ~= "running"
                then "The run is over."
                else string.format(
                    "%d second%s left in this phase",
                    seconds,
                    if seconds == 1 then "" else "s"
                )
        end
    end)

    send({ kind = "sync" })
    print("[Round] HUD ready: number keys choose, E does the chore you stand at, T ends the phase")
end

return Hud
