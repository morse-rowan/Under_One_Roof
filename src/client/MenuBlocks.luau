--!strict
-- Style-aware building blocks. Each renderer in `MenuPreview` positions these
-- differently; the blocks themselves never decide where a screen puts them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Kit = require(script.Parent.MenuKit)
local Styles = require(shared:WaitForChild("MenuStyles"))
local Data = require(shared:WaitForChild("MenuPreviewData"))

local Blocks = {}

local function identity(name: string?): Color3?
    local rgb = if name then Styles.identity[name] else nil
    return if rgb then Kit.color(rgb) else nil
end

function Blocks.heading(parent: Instance, style: any, text: string, order: number): TextLabel
    return Kit.text(parent, style, {
        Text = string.upper(text),
        FontKey = "heading",
        Tone = "muted",
        TextSize = 13,
        Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = order,
    })
end

function Blocks.row(parent: Instance, style: any, entry: any, order: number): Frame
    local holder = Kit.make("Frame", {
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order,
    }, parent) :: Frame
    local mark = identity(entry.actor)
    if mark then
        local dot = Kit.dot(holder, mark, 8, 0)
        dot.Position = UDim2.fromOffset(0, 7)
    end
    local body = Kit.make("Frame", {
        Position = UDim2.fromOffset(if mark then 16 else 0, 0),
        Size = UDim2.new(1, if mark then -16 else 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, holder) :: Frame
    Kit.column(body, 1)
    Kit.text(body, style, {
        Text = entry.text,
        FontKey = "body",
        Tone = entry.tone or "ink",
        TextSize = 16,
        TextWrapped = true,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
    })
    if entry.detail then
        Kit.text(body, style, {
            Text = entry.detail,
            FontKey = "data",
            Tone = "muted",
            TextSize = 13,
            TextWrapped = true,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 2,
        })
    end
    return holder
end

function Blocks.panel(parent: Instance, style: any, panel: any, props: { [string]: any }): Frame
    local tilt = props.Rotation
    local card = Kit.card(parent, style, {
        Name = panel.key,
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        Rotation = tilt,
        BackgroundColor3 = props.BackgroundColor3,
    })
    Kit.pad(card, 14, 16, 14, 16)
    local list = Kit.scroller(card, { Size = UDim2.fromScale(1, 1) })
    Kit.column(list, 10)
    Blocks.heading(list, style, panel.heading, 0)
    for index, entry in panel.rows do
        Blocks.row(list, style, entry, index)
    end
    if panel.note then
        Kit.text(list, style, {
            Text = panel.note,
            FontKey = "data",
            Tone = "muted",
            TextSize = 12,
            TextWrapped = true,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 900,
        })
    end
    return card
end

-- Compact meter pills laid out horizontally.
function Blocks.meterRow(
    parent: Instance,
    style: any,
    entries: any,
    props: { [string]: any }
): Frame
    local holder = Kit.make("Frame", {
        Name = "Meters",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
    }, parent) :: Frame
    Kit.row(holder, props.gap or 8)
    for index, entry in entries do
        local pill = Kit.card(holder, style, {
            Size = UDim2.new(0, props.width or 148, 1, 0),
            LayoutOrder = index,
            BackgroundColor3 = if props.flat then Kit.tone(style, "chipOff") else nil,
        })
        Kit.pad(pill, 8, 12, 8, 12)
        Kit.column(pill, 1)
        Kit.text(pill, style, {
            Text = string.upper(entry.label),
            FontKey = "heading",
            Tone = "muted",
            TextSize = 11,
            Size = UDim2.new(1, 0, 0, 13),
            LayoutOrder = 1,
        })
        Kit.text(pill, style, {
            Text = entry.value,
            FontKey = "data",
            Tone = entry.tone,
            TextSize = 19,
            Size = UDim2.new(1, 0, 0, 22),
            LayoutOrder = 2,
        })
    end
    return holder
end

-- Stacked meters with bars, for the denser layouts.
function Blocks.meterStack(
    parent: Instance,
    style: any,
    entries: any,
    props: { [string]: any }
): Frame
    local holder = Kit.make("Frame", {
        Name = "Meters",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
    }, parent) :: Frame
    Kit.column(holder, 10)
    for index, entry in entries do
        local line = Kit.make("Frame", {
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
            LayoutOrder = index,
        }, holder) :: Frame
        Kit.text(line, style, {
            Text = string.upper(entry.label),
            FontKey = "heading",
            Tone = "muted",
            TextSize = 11,
            Size = UDim2.new(1, -70, 0, 13),
        })
        Kit.text(line, style, {
            Text = entry.value,
            FontKey = "data",
            Tone = entry.tone,
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Right,
            Size = UDim2.fromOffset(70, 13),
            Position = UDim2.new(1, -70, 0, 0),
        })
        Kit.bar(line, style, props.fractions[entry.key] or 0, Kit.tone(style, entry.tone), {
            Size = UDim2.new(1, 0, 0, 6),
            Position = UDim2.fromOffset(0, 20),
        })
    end
    return holder
end

function Blocks.fractions(screen: any): { [string]: number }
    local snapshot = Data.snapshots[screen.id] or Data.snapshots.morning
    return {
        cash = math.clamp(snapshot.actor.cash / 60, 0, 1),
        goal = math.clamp(snapshot.actor.cash / snapshot.actor.goal, 0, 1),
        rent = math.clamp(snapshot.rentPaid / snapshot.rent, 0, 1),
        heat = math.clamp(snapshot.heat / 100, 0, 1),
        clean = math.clamp(snapshot.cleanliness / 100, 0, 1),
    }
end

function Blocks.chat(parent: Instance, style: any, chat: any, props: { [string]: any }): Frame
    local card = Kit.card(parent, style, {
        Name = "Chat",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        Rotation = props.Rotation,
        BackgroundColor3 = props.BackgroundColor3,
    })
    Kit.pad(card, 12, 14, 12, 14)

    local tabs = Kit.make("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
    }, card) :: Frame
    Kit.row(tabs, 6)
    for index, tab in chat.tabs do
        local active = tab.id == chat.activeTab
        local chip = Kit.make("TextLabel", {
            Size = UDim2.new(0, 96, 1, 0),
            BackgroundColor3 = if active
                then Kit.tone(style, "chipOn")
                else Kit.tone(style, "chipOff"),
            BorderSizePixel = 0,
            Text = tab.label,
            TextSize = 14,
            Font = Kit.font(style.fonts.heading),
            TextColor3 = if active
                then Kit.color(
                    if style.layout == "board" then { 24, 27, 31 } else { 255, 252, 246 }
                )
                else Kit.tone(style, "muted"),
            LayoutOrder = index,
        }, tabs) :: TextLabel
        Kit.corner(chip, math.min(style.corner, 12))
    end

    local thread = Kit.scroller(card, {
        Position = UDim2.fromOffset(0, 38),
        Size = UDim2.new(1, 0, 1, -142),
    })
    Kit.column(thread, 8)
    for index, line in chat.thread do
        local bubble = Kit.make("Frame", {
            Size = UDim2.fromScale(0.86, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = if line.mine
                then Kit.tone(style, "bubbleMine")
                else Kit.tone(style, "bubbleOther"),
            BorderSizePixel = 0,
            LayoutOrder = index,
            Position = if line.mine then UDim2.fromScale(0.14, 0) else UDim2.new(),
        }, thread) :: Frame
        Kit.corner(bubble, math.min(style.corner, 12))
        Kit.pad(bubble, 8, 10, 8, 10)
        Kit.column(bubble, 2)
        Kit.text(bubble, style, {
            Text = if line.mine then "You" else (Data.colorNames[line.from] or line.from),
            FontKey = "heading",
            TextSize = 12,
            TextColor3 = identity(line.from) or Kit.tone(style, "muted"),
            Size = UDim2.new(1, 0, 0, 14),
            LayoutOrder = 1,
        })
        Kit.text(bubble, style, {
            Text = line.text,
            FontKey = "body",
            Tone = "ink",
            TextSize = 15,
            TextWrapped = true,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 2,
        })
    end

    local composer = Kit.make("Frame", {
        Position = UDim2.new(0, 0, 1, -98),
        Size = UDim2.new(1, 0, 0, 98),
        BackgroundTransparency = 1,
    }, card) :: Frame
    Kit.column(composer, 8)
    local box = Kit.make("TextBox", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Kit.tone(style, "chipOff"),
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = chat.placeholder,
        PlaceholderColor3 = Kit.tone(style, "muted"),
        TextColor3 = Kit.tone(style, "ink"),
        TextSize = 15,
        Font = Kit.font(style.fonts.body),
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
    }, composer) :: TextBox
    Kit.corner(box, math.min(style.corner, 12))
    Kit.pad(box, 0, 10, 0, 10)
    local chips = Kit.make("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = 2,
    }, composer) :: Frame
    Kit.row(chips, 6)
    for index, chipText in chat.chips do
        Kit.button(chips, style, {
            Text = chipText,
            TextSize = 13,
            Size = UDim2.new(0, 108, 1, 0),
            Tone = "cool",
            Solid = false,
            LayoutOrder = index,
        })
    end
    Kit.text(composer, style, {
        Text = chat.remaining .. " messages left this stop",
        FontKey = "data",
        Tone = "muted",
        TextSize = 12,
        Size = UDim2.new(1, 0, 0, 14),
        LayoutOrder = 3,
    })
    return card
end

function Blocks.choices(parent: Instance, style: any, choices: any, props: { [string]: any }): Frame
    local holder = Kit.make("Frame", {
        Name = "Choices",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        LayoutOrder = props.LayoutOrder,
        BackgroundTransparency = 1,
    }, parent) :: Frame
    if props.vertical then
        Kit.column(holder, 8)
    else
        Kit.row(holder, 8, Enum.VerticalAlignment.Center)
    end
    for index, choice in choices do
        Kit.button(holder, style, {
            Text = choice.text,
            TextSize = if choice.primary then 17 else 15,
            Size = if props.vertical
                then UDim2.new(1, 0, 0, 40)
                else UDim2.new(0, if choice.primary then 240 else 210, 1, 0),
            Tone = choice.tone,
            Solid = choice.primary == true,
            LayoutOrder = index,
        })
    end
    return holder
end

function Blocks.symbols(parent: Instance, style: any, grid: any, props: { [string]: any }): Frame
    local shapes = { "\u{25CF}", "\u{25A0}", "\u{25B2}", "\u{2726}" }
    local tones = { "cool", "good", "warn", "bad" }
    local card = Kit.card(parent, style, {
        Name = "Recall",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        Rotation = props.Rotation,
    })
    Kit.pad(card, 18, 20, 18, 20)
    Kit.column(card, 12, Enum.HorizontalAlignment.Center)
    Kit.text(card, style, {
        Text = grid.prompt,
        FontKey = "display",
        Tone = "ink",
        TextSize = 26,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 30),
        LayoutOrder = 1,
    })
    local strip = Kit.make("Frame", {
        Size = UDim2.new(1, 0, 0, 84),
        BackgroundTransparency = 1,
        LayoutOrder = 2,
    }, card) :: Frame
    local stripLayout = Kit.row(strip, 10, Enum.VerticalAlignment.Center)
    stripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    for index, symbol in grid.symbols do
        local tile = Kit.card(strip, style, {
            Size = UDim2.fromOffset(78, 84),
            LayoutOrder = index,
            BackgroundColor3 = Kit.tone(style, "chipOff"),
        })
        Kit.text(tile, style, {
            Text = shapes[symbol] or "?",
            FontKey = "display",
            Tone = tones[symbol] or "ink",
            TextSize = 36,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
    end
    Kit.text(card, style, {
        Text = string.format("%d symbols because you are tired. Rested is 3.", grid.length),
        FontKey = "data",
        Tone = "muted",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = 3,
    })
    return card
end

function Blocks.verdict(parent: Instance, style: any, verdict: any, props: { [string]: any }): Frame
    local card = Kit.card(parent, style, {
        Name = "Verdict",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        Rotation = props.Rotation,
    })
    Kit.pad(card, 22, 24, 22, 24)
    Kit.column(card, 10)
    Kit.text(card, style, {
        Text = verdict.headline,
        FontKey = "display",
        Tone = "good",
        TextSize = 38,
        TextWrapped = true,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
    })
    for index, line in verdict.lines do
        Kit.text(card, style, {
            Text = "\u{2022}  " .. line,
            FontKey = "body",
            Tone = "ink",
            TextSize = 17,
            TextWrapped = true,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 1 + index,
        })
    end
    return card
end

function Blocks.prompt(parent: Instance, style: any, prompt: any, props: { [string]: any }): Frame
    local card = Kit.card(parent, style, {
        Name = "Prompt",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        Rotation = props.Rotation,
        BackgroundColor3 = Kit.tone(style, "cardAlt"),
    })
    Kit.pad(card, 10, 14, 10, 14)
    Kit.column(card, 2)
    Kit.text(card, style, {
        Text = prompt.text,
        FontKey = "heading",
        Tone = "ink",
        TextSize = 19,
        Size = UDim2.new(1, 0, 0, 22),
        LayoutOrder = 1,
    })
    Kit.text(card, style, {
        Text = prompt.detail,
        FontKey = "data",
        Tone = "muted",
        TextSize = 13,
        TextWrapped = true,
        Size = UDim2.fromScale(1, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2,
    })
    return card
end

function Blocks.timer(parent: Instance, style: any, timer: any, props: { [string]: any }): Frame
    local card = Kit.card(parent, style, {
        Name = "Timer",
        Position = props.Position,
        Size = props.Size,
        AnchorPoint = props.AnchorPoint,
        Rotation = props.Rotation,
    })
    Kit.pad(card, 10, 14, 10, 14)
    Kit.text(card, style, {
        Text = timer.seconds .. "s",
        FontKey = "display",
        Tone = "accent",
        TextSize = 34,
        Size = UDim2.new(1, 0, 0, 36),
        LayoutOrder = 1,
    })
    Kit.text(card, style, {
        Text = string.format("%d of %d actions left", timer.actions, timer.actionsTotal),
        FontKey = "data",
        Tone = "muted",
        TextSize = 13,
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.fromOffset(0, 38),
    })
    Kit.bar(card, style, timer.seconds / timer.total, Kit.tone(style, "accent"), {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 1, -6),
    })
    return card
end

return Blocks
