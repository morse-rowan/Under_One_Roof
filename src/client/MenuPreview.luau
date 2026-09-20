--!strict
-- Menu visual study. Renders the same screen content in several candidate looks
-- so the menus can be judged in the real apartment view. Nothing here reads or
-- writes game state: every value comes from `Shared.MenuPreviewData`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Kit = require(script.Parent.MenuKit)
local Blocks = require(script.Parent.MenuBlocks)
local Styles = require(shared:WaitForChild("MenuStyles"))
local Data = require(shared:WaitForChild("MenuPreviewData"))

local Preview = {}

local CANVAS = Vector2.new(1280, 720)

local function titleBlock(parent: Instance, style: any, screen: any, props: { [string]: any })
    local holder = Kit.make("Frame", {
        Name = "Title",
        Position = props.Position,
        Size = props.Size,
        BackgroundTransparency = 1,
    }, parent)
    Kit.column(holder, 2)
    Kit.text(holder, style, {
        Text = screen.title,
        FontKey = "display",
        Tone = "ink",
        TextSize = props.TextSize or 44,
        Size = UDim2.new(1, 0, 0, (props.TextSize or 44) + 8),
        TextColor3 = props.TextColor3,
        LayoutOrder = 1,
    })
    Kit.text(holder, style, {
        Text = screen.subtitle,
        FontKey = "body",
        Tone = "muted",
        TextSize = 17,
        TextWrapped = true,
        TextColor3 = props.SubColor3,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2,
    })
    return holder
end

-- Fridge door: warm paper cards pinned over the room, slightly askew.
local function renderPaper(stage: Instance, style: any, screen: any)
    local kind = screen.kind
    if kind == "stop" then
        titleBlock(stage, style, screen, {
            Position = UDim2.fromOffset(40, 24),
            Size = UDim2.fromOffset(760, 80),
            TextColor3 = Kit.tone(style, "card"),
            SubColor3 = Kit.tone(style, "line"),
        })
        Blocks.meterRow(stage, style, screen.meters, {
            Position = UDim2.fromOffset(40, 116),
            Size = UDim2.fromOffset(782, 62),
            width = 150,
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(40, 196),
            Size = UDim2.fromOffset(382, 296),
            Rotation = -1.2,
        })
        Blocks.panel(stage, style, screen.panels[2], {
            Position = UDim2.fromOffset(440, 196),
            Size = UDim2.fromOffset(382, 296),
            Rotation = 1.4,
        })
        Blocks.chat(stage, style, screen.chat, {
            Position = UDim2.fromOffset(852, 116),
            Size = UDim2.fromOffset(388, 500),
            Rotation = -0.8,
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(40, 512),
            Size = UDim2.fromOffset(782, 46),
        })
    elseif kind == "action" then
        Blocks.timer(stage, style, screen.timer, {
            Position = UDim2.fromOffset(40, 24),
            Size = UDim2.fromOffset(196, 92),
            Rotation = -1.5,
        })
        Blocks.meterRow(stage, style, screen.meters, {
            Position = UDim2.fromOffset(252, 40),
            Size = UDim2.fromOffset(600, 60),
            width = 114,
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(40, 132),
            Size = UDim2.fromOffset(352, 232),
            Rotation = 1.1,
        })
        Blocks.panel(stage, style, screen.panels[2], {
            Position = UDim2.fromOffset(40, 380),
            Size = UDim2.fromOffset(352, 176),
            Rotation = -1.1,
        })
        Blocks.prompt(stage, style, screen.prompt, {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromOffset(700, 620),
            Size = UDim2.fromOffset(470, 78),
            Rotation = 0.8,
        })
        Blocks.choices(stage, style, screen.choices, {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromOffset(1240, 132),
            Size = UDim2.fromOffset(240, 148),
            vertical = true,
        })
    elseif kind == "work" then
        titleBlock(stage, style, screen, {
            Position = UDim2.fromOffset(40, 24),
            Size = UDim2.fromOffset(700, 86),
            TextColor3 = Kit.tone(style, "card"),
            SubColor3 = Kit.tone(style, "line"),
        })
        Blocks.symbols(stage, style, screen.grid, {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(640, 150),
            Size = UDim2.fromOffset(640, 214),
            Rotation = -0.7,
        })
        Blocks.panel(stage, style, screen.panels[1], {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(640, 382),
            Size = UDim2.fromOffset(460, 168),
            Rotation = 1,
        })
        Blocks.choices(stage, style, screen.choices, {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(640, 566),
            Size = UDim2.fromOffset(240, 46),
        })
    else
        Blocks.verdict(stage, style, screen.verdict, {
            Position = UDim2.fromOffset(60, 90),
            Size = UDim2.fromOffset(600, 330),
            Rotation = -1,
        })
        Blocks.meterRow(stage, style, screen.meters, {
            Position = UDim2.fromOffset(60, 440),
            Size = UDim2.fromOffset(782, 62),
            width = 150,
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(700, 90),
            Size = UDim2.fromOffset(520, 330),
            Rotation = 1.3,
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(60, 528),
            Size = UDim2.fromOffset(520, 46),
        })
    end
end

-- Roommate app: a phone holds the household, the room stays visible.
local function renderPhone(stage: Instance, style: any, screen: any)
    local kind = screen.kind
    local strip = Kit.card(stage, style, {
        Name = "Status",
        Position = UDim2.fromOffset(24, 18),
        Size = UDim2.fromOffset(1232, 64),
    })
    Kit.pad(strip, 8, 14, 8, 16)
    Kit.text(strip, style, {
        Text = screen.title,
        FontKey = "display",
        Tone = "ink",
        TextSize = 22,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.fromOffset(220, 48),
    })
    Blocks.meterRow(strip, style, screen.meters, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(720, 48),
        width = 140,
        gap = 4,
        flat = true,
    })

    if kind == "action" then
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(24, 98),
            Size = UDim2.fromOffset(340, 208),
        })
        Blocks.panel(stage, style, screen.panels[2], {
            Position = UDim2.fromOffset(24, 318),
            Size = UDim2.fromOffset(340, 158),
        })
        local sheet = Kit.card(stage, style, {
            Name = "Sheet",
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromOffset(640, 664),
            Size = UDim2.fromOffset(1000, 124),
        })
        Kit.pad(sheet, 14, 16, 14, 16)
        Blocks.timer(sheet, style, screen.timer, {
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(180, 92),
        })
        Blocks.prompt(sheet, style, screen.prompt, {
            Position = UDim2.fromOffset(196, 0),
            Size = UDim2.fromOffset(400, 92),
        })
        Blocks.choices(sheet, style, screen.choices, {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            Size = UDim2.fromOffset(240, 92),
            vertical = true,
        })
        return
    end

    local phone = Kit.card(stage, style, {
        Name = "Phone",
        Position = UDim2.fromOffset(816, 98),
        Size = UDim2.fromOffset(440, 566),
    })
    Kit.pad(phone, 14, 14, 14, 14)
    Kit.text(phone, style, {
        Text = screen.subtitle,
        FontKey = "body",
        Tone = "muted",
        TextSize = 14,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 34),
    })

    if kind == "work" then
        Blocks.symbols(stage, style, screen.grid, {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(410, 170),
            Size = UDim2.fromOffset(700, 214),
        })
        Blocks.panel(phone, style, screen.panels[1], {
            Position = UDim2.fromOffset(0, 40),
            Size = UDim2.new(1, 0, 1, -100),
            BackgroundColor3 = Kit.tone(style, "cardAlt"),
        })
        Blocks.choices(phone, style, screen.choices, {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 44),
            vertical = true,
        })
        return
    end

    if kind == "result" then
        Blocks.verdict(stage, style, screen.verdict, {
            AnchorPoint = Vector2.new(0, 0),
            Position = UDim2.fromOffset(24, 98),
            Size = UDim2.fromOffset(760, 340),
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(24, 454),
            Size = UDim2.fromOffset(760, 210),
        })
        Blocks.choices(phone, style, screen.choices, {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 92),
            vertical = true,
        })
        return
    end

    Blocks.panel(stage, style, screen.panels[1], {
        Position = UDim2.fromOffset(24, 98),
        Size = UDim2.fromOffset(372, 250),
    })
    Blocks.panel(stage, style, screen.panels[2], {
        Position = UDim2.fromOffset(24, 360),
        Size = UDim2.fromOffset(372, 220),
    })
    Blocks.chat(phone, style, screen.chat, {
        Position = UDim2.fromOffset(0, 40),
        Size = UDim2.new(1, 0, 1, -142),
        BackgroundColor3 = Kit.tone(style, "cardAlt"),
    })
    Blocks.choices(phone, style, screen.choices, {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 92),
        vertical = true,
    })
end

-- Situation board: everything that can evict you, on one dark dashboard.
local phaseNames = { "Morning", "Action 1", "Work", "Midday", "Action 2", "Night" }
local phaseForScreen = { morning = 1, action = 2, work = 3, midday = 4, night = 6, result = 6 }

local function renderBoard(stage: Instance, style: any, screen: any)
    local header = Kit.card(stage, style, {
        Name = "Header",
        Position = UDim2.fromOffset(32, 22),
        Size = UDim2.fromOffset(1216, 62),
    })
    Kit.pad(header, 10, 18, 10, 18)
    Kit.text(header, style, {
        Text = string.upper(screen.title),
        FontKey = "display",
        Tone = "ink",
        TextSize = 28,
        Size = UDim2.fromOffset(420, 42),
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    Kit.text(header, style, {
        Text = screen.footer,
        FontKey = "data",
        Tone = "muted",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(520, 42),
    })

    local rail = Kit.card(stage, style, {
        Name = "Rail",
        Position = UDim2.fromOffset(32, 96),
        Size = UDim2.fromOffset(250, 512),
    })
    Kit.pad(rail, 14, 14, 14, 14)
    local railList = Kit.make("Frame", {
        Size = UDim2.new(1, 0, 0, 196),
        BackgroundTransparency = 1,
    }, rail)
    Kit.column(railList, 4)
    local current = phaseForScreen[screen.id] or 1
    for index, name in phaseNames do
        local active = index == current
        local entry = Kit.make("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = Kit.tone(style, if active then "chipOn" else "chipOff"),
            BackgroundTransparency = if active then 0 else 0.4,
            BorderSizePixel = 0,
            LayoutOrder = index,
        }, railList)
        Kit.corner(entry, 4)
        Kit.pad(entry, 0, 10, 0, 10)
        Kit.text(entry, style, {
            Text = string.upper(name),
            FontKey = "heading",
            TextSize = 14,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextColor3 = if active then Color3.fromRGB(24, 27, 31) else Kit.tone(style, "muted"),
            Size = UDim2.fromScale(1, 1),
        })
    end
    Blocks.meterStack(rail, style, screen.meters, {
        Position = UDim2.fromOffset(0, 212),
        Size = UDim2.new(1, 0, 0, 230),
        fractions = Blocks.fractions(screen),
    })

    if screen.kind == "work" then
        Blocks.symbols(stage, style, screen.grid, {
            Position = UDim2.fromOffset(298, 96),
            Size = UDim2.fromOffset(950, 240),
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(298, 348),
            Size = UDim2.fromOffset(950, 190),
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(298, 552),
            Size = UDim2.fromOffset(950, 44),
        })
        return
    end

    if screen.kind == "result" then
        Blocks.verdict(stage, style, screen.verdict, {
            Position = UDim2.fromOffset(298, 96),
            Size = UDim2.fromOffset(560, 442),
        })
        Blocks.panel(stage, style, screen.panels[1], {
            Position = UDim2.fromOffset(872, 96),
            Size = UDim2.fromOffset(376, 442),
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(298, 552),
            Size = UDim2.fromOffset(950, 44),
        })
        return
    end

    Blocks.panel(stage, style, screen.panels[1], {
        Position = UDim2.fromOffset(298, 96),
        Size = UDim2.fromOffset(556, 244),
    })
    Blocks.panel(stage, style, screen.panels[2], {
        Position = UDim2.fromOffset(298, 352),
        Size = UDim2.fromOffset(556, 256),
    })

    if screen.kind == "action" then
        Blocks.timer(stage, style, screen.timer, {
            Position = UDim2.fromOffset(866, 96),
            Size = UDim2.fromOffset(382, 96),
        })
        Blocks.prompt(stage, style, screen.prompt, {
            Position = UDim2.fromOffset(866, 204),
            Size = UDim2.fromOffset(382, 96),
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(866, 312),
            Size = UDim2.fromOffset(382, 148),
            vertical = true,
        })
    else
        Blocks.chat(stage, style, screen.chat, {
            Position = UDim2.fromOffset(866, 96),
            Size = UDim2.fromOffset(382, 512),
        })
        Blocks.choices(stage, style, screen.choices, {
            Position = UDim2.fromOffset(298, 620),
            Size = UDim2.fromOffset(950, 44),
        })
    end
end

local renderers = { paper = renderPaper, phone = renderPhone, board = renderBoard }

-- Draws one screen in one look into `stage`, replacing whatever was there.
-- Usable from the command bar on any container, not just the running client.
function Preview.render(stage: Instance, screenId: string, styleId: string): (any, any)
    local style = Styles.get(styleId)
    local screen = Data.screen(screenId)
    stage:ClearAllChildren()
    renderers[style.layout](stage, style, screen)
    return style, screen
end

function Preview.start()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer

    local screenIndex = 1
    local styleId = Styles.order[1]
    local visible = true

    local gui = Kit.make("ScreenGui", {
        Name = "MenuPreview",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 50,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player:WaitForChild("PlayerGui"))

    local scrim = Kit.make("Frame", {
        Name = "Scrim",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(),
        BorderSizePixel = 0,
    }, gui)

    local canvas = Kit.make("Frame", {
        Name = "Canvas",
        Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
    }, gui)
    local scale = Kit.make("UIScale", {}, canvas)

    local stage = Kit.make("Frame", {
        Name = "Stage",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, canvas)

    -- Deliberately neutral chrome so the study bar is never mistaken for a design.
    local bar = Kit.make("Frame", {
        Name = "StudyBar",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -2),
        Size = UDim2.fromOffset(720, 30),
        BackgroundColor3 = Color3.fromRGB(16, 18, 21),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
    }, canvas)
    Kit.corner(bar, 15)
    local barText = Kit.make("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Font = Enum.Font.RobotoMono,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(226, 223, 214),
        Text = "",
    }, bar)

    local function draw()
        local screenId = Data.screens[screenIndex]
        local style = Preview.render(stage, screenId, styleId)
        scrim.BackgroundColor3 = Kit.tone(style, "bg")
        scrim.BackgroundTransparency = 1 - style.scrim
        barText.Text = string.format(
            "  %s  (%d/%d)   \u{2022}   %s  (%d/%d)   \u{2022}   Z X screen   Q E look   M hide  ",
            screenId,
            screenIndex,
            #Data.screens,
            style.name,
            (table.find(Styles.order, styleId) or 1),
            #Styles.order
        )
        gui.Enabled = visible
        scrim.Visible = visible
    end

    local function setVisible(on: boolean)
        visible = on
        gui.Enabled = on
        scrim.Visible = on
    end

    local function stepScreen(delta: number)
        screenIndex = 1 + (screenIndex - 1 + delta) % #Data.screens
        draw()
    end

    local function stepStyle(delta: number)
        styleId = Styles.step(styleId, delta)
        draw()
    end

    function Preview.command(command: string?, first: string?, second: string?)
        local name = string.lower(command or "next")
        if name == "off" or name == "hide" then
            setVisible(false)
            return
        elseif name == "on" or (name == "show" and not first) then
            setVisible(true)
            return
        elseif name == "toggle" then
            setVisible(not visible)
            return
        elseif name == "next" then
            screenIndex = 1 + screenIndex % #Data.screens
        elseif name == "prev" then
            screenIndex = 1 + (screenIndex - 2) % #Data.screens
        elseif name == "look" or name == "style" then
            styleId = if first and Styles.list[string.lower(first)]
                then string.lower(first)
                else Styles.step(styleId, 1)
        elseif name == "list" then
            print("[Menus] screens: " .. table.concat(Data.screens, ", "))
            print("[Menus] looks: " .. table.concat(Styles.order, ", "))
            return
        else
            -- Treat anything else as "show <screen> [look]".
            local wanted = if name == "show" then string.lower(first or "") else name
            local index = table.find(Data.screens, wanted)
            if not index then
                warn("[Menus] Unknown screen: " .. wanted)
                return
            end
            screenIndex = index
            local look = if name == "show" then second else first
            if look and Styles.list[string.lower(look)] then
                styleId = string.lower(look)
            end
        end
        setVisible(true)
        draw()
    end

    local keys = {
        [Enum.KeyCode.Z] = function()
            stepScreen(-1)
        end,
        [Enum.KeyCode.X] = function()
            stepScreen(1)
        end,
        [Enum.KeyCode.Q] = function()
            stepStyle(-1)
        end,
        [Enum.KeyCode.E] = function()
            stepStyle(1)
        end,
        [Enum.KeyCode.M] = function()
            setVisible(not visible)
        end,
    }
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then
            return
        end
        local handler = keys[input.KeyCode]
        if handler then
            handler()
        end
    end)

    local remote = ReplicatedStorage:WaitForChild("MenuPreview") :: RemoteEvent
    remote.OnClientEvent:Connect(function(command, first, second)
        if type(command) == "string" then
            Preview.command(command, first, second)
        end
    end)

    RunService:BindToRenderStep("MenuPreviewScale", Enum.RenderPriority.Last.Value, function()
        local camera = workspace.CurrentCamera
        if camera then
            local viewport = camera.ViewportSize
            scale.Scale = math.min(viewport.X / CANVAS.X, viewport.Y / CANVAS.Y, 1.4)
        end
    end)

    draw()
    print(
        "[Menus] Preview ready: Z/X screen, Q/E look, M hide. "
            .. 'Command bar: game.ReplicatedStorage.MenuPreview:FireServer("show","night","phone")'
    )
end

return Preview
