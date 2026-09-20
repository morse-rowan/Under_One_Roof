--!strict
-- HousePad is the live UI. Rendering and client/server transport are separate.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Data = require(shared:WaitForChild("HousepadData"))
local Text = require(shared:WaitForChild("RoundText"))
local Guide = require(shared:WaitForChild("RoundGuide"))
local Setup = require(shared:WaitForChild("RoundSetup"))
local Kit = require(script.Parent.MenuKit)
local Tasks = require(script.Parent.HousepadTasks)
local Composer = require(script.Parent.HousepadComposer)
local Apartment = require(script.Parent.HousepadApartment)
local View = {}
View.size = Vector2.new(1280, 720)
local C = {
    bg = Color3.fromRGB(216, 173, 126),
    bezel = Color3.fromRGB(60, 53, 48),
    paper = Color3.fromRGB(255, 250, 239),
    rail = Color3.fromRGB(241, 234, 220),
    ink = Color3.fromRGB(48, 46, 43),
    muted = Color3.fromRGB(112, 108, 99),
    line = Color3.fromRGB(223, 217, 205),
    blue = Color3.fromRGB(0, 122, 255),
    bubble = Color3.fromRGB(232, 231, 228),
    white = Color3.new(1, 1, 1),
    good = Color3.fromRGB(66, 132, 94),
    warn = Color3.fromRGB(171, 112, 31),
    bad = Color3.fromRGB(192, 71, 64),
}
View.background = C.bg
local CHORES = { finish_chore = true, pickup_trash = true }

function View.connect(button: TextButton, callback: () -> ())
    button.Activated:Connect(callback)
end

function View.onEnter(box: TextBox, callback: () -> ())
    box.FocusLost:Connect(function(enter)
        if enter then
            callback()
        end
    end)
end

function View.measure(text: string, width: number): number
    return game:GetService("TextService")
        :GetTextSize(text, 15, Enum.Font.Gotham, Vector2.new(width, 10000)).Y
end

local function frame(
    parent: Instance,
    name: string,
    x: number,
    y: number,
    w: number,
    h: number,
    color: Color3?,
    radius: number?
): Frame
    local result = Kit.make("Frame", {
        Name = name,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BorderSizePixel = 0,
        BackgroundColor3 = color or C.paper,
    }, parent)
    Kit.corner(result, radius or 14)
    return result
end

local function label(
    parent: Instance,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    size: number?,
    color: Color3?,
    bold: boolean?
): TextLabel
    return Kit.make("TextLabel", {
        Name = "Label",
        Text = text,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1,
        TextSize = size or 14,
        TextColor3 = color or C.ink,
        Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true,
        RichText = false,
    }, parent)
end

local function button(
    parent: Instance,
    name: string,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    active: boolean,
    callback: () -> ()
): TextButton
    local item = Kit.make("TextButton", {
        Name = name,
        Text = text,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = if active then C.good else C.rail,
        BorderSizePixel = 0,
        TextColor3 = if active then C.white else C.ink,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextWrapped = true,
        AutoButtonColor = true,
    }, parent)
    Kit.corner(item, 12)
    View.connect(item, callback)
    return item
end

-- Native shapes stay crisp at every scale and require no uploaded image assets.
local function icon(parent: Instance, kind: string, x: number, y: number, color: Color3)
    local tile = frame(parent, "Icon_" .. kind, x, y, 38, 38, C.rail, 12)
    local function shape(name, sx, sy, w, h, rotation)
        local p = frame(tile, name, sx, sy, w, h, color, 2)
        p.Rotation = rotation or 0
        return p
    end
    if kind == "house" then
        shape("RoofLeft", 6, 9, 18, 5, -38)
        shape("RoofRight", 18, 9, 18, 5, 38)
        shape("Walls", 10, 15, 21, 17)
        frame(tile, "Door", 18, 22, 6, 10, C.rail, 1)
    elseif kind == "coin" then
        local coin = frame(tile, "Coin", 5, 5, 28, 28, color, 28)
        local t = label(coin, "$", 0, 0, 28, 28, 21, C.white, true)
        t.TextXAlignment = Enum.TextXAlignment.Center
    elseif kind == "sparkle" then
        shape("Sparkle", 12, 12, 17, 17, 45)
        shape("SmallSparkle", 5, 5, 7, 7, 45)
        shape("TinySparkle", 29, 6, 5, 5, 45)
    elseif kind == "cup" then
        shape("Cup", 9, 15, 19, 17)
        local handle = shape("Handle", 25, 18, 9, 10)
        frame(handle, "Hole", 2, 2, 5, 6, C.rail, 2)
        shape("Steam", 13, 5, 3, 7, 12)
        shape("SteamTwo", 22, 5, 3, 7, 12)
    elseif kind == "sort" then
        for i = 0, 3 do
            shape("Key", 6 + i % 2 * 15, 6 + math.floor(i / 2) * 15, 12, 12)
        end
    else
        shape("Parcel", 6, 9, 27, 23)
        frame(tile, "Tape", 17, 9, 5, 23, C.paper, 0)
    end
end

-- The same two-eyed bean the person controls in the apartment, so a face in the
-- rail, above a bubble and in the room all read as one identity. Sizes round to
-- whole pixels because the badge is drawn small.
local function faceSize(scale: number?): (number, number)
    local k = scale or 1
    return math.round(27 * k), math.round(32 * k)
end

local function portrait(parent: Instance, who: string, x: number, y: number, scale: number?): Frame
    local rgb = Setup.rgb(who)
    local k = scale or 1
    local w, h = faceSize(k)
    local body = frame(
        parent,
        "Portrait_" .. who,
        x,
        y,
        w,
        h,
        Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
        math.max(2, math.round(13 * k))
    )
    local eyeW, eyeH = math.max(2, math.round(4 * k)), math.max(2, math.round(6 * k))
    local eyeY = math.round(11 * k)
    frame(body, "Eye", math.round(7 * k), eyeY, eyeW, eyeH, C.white, math.max(1, math.round(3 * k)))
    frame(
        body,
        "EyeRight",
        w - math.round(7 * k) - eyeW,
        eyeY,
        eyeW,
        eyeH,
        C.white,
        math.max(1, math.round(3 * k))
    )
    return body
end

-- The household board gets the whole cast as one badge.
local function groupFace(parent: Instance, o: any, x: number, y: number, scale: number?): Frame
    local w, h = faceSize(scale)
    local tile = Kit.make("Frame", {
        Name = "GroupFace",
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, parent) :: Frame
    local small = (scale or 1) * 0.46
    local sw, sh = faceSize(small)
    local placed = 0
    for _, id in o.actorIds do
        if placed >= 4 then
            break
        end
        portrait(tile, id, placed % 2 * (w - sw), math.floor(placed / 2) * (h - sh), small)
        placed += 1
    end
    return tile
end

-- The log is not a person, so it carries a receipt instead of a face.
local function receiptFace(parent: Instance, x: number, y: number, scale: number?): Frame
    local w, h = faceSize(scale)
    local sheet = frame(
        parent,
        "ReceiptFace",
        x + math.round(w * 0.08),
        y,
        math.round(w * 0.84),
        h,
        C.white,
        4
    )
    Kit.stroke(sheet, C.line, 1)
    for i = 0, 2 do
        frame(
            sheet,
            "Line",
            4,
            math.round(h * 0.2) + i * math.round(h * 0.22),
            math.round(w * 0.5),
            2,
            C.muted,
            1
        )
    end
    return sheet
end

-- One badge per conversation stop, whoever or whatever that stop is.
local function channelFace(
    parent: Instance,
    o: any,
    id: string,
    x: number,
    y: number,
    scale: number?
): Frame
    if id == "group" then
        return groupFace(parent, o, x, y, scale)
    elseif id == "activity" then
        return receiptFace(parent, x, y, scale)
    end
    return portrait(parent, id, x, y, scale)
end

-- The tablet itself. The home screen draws the same device, so it lives here.
local function shell(parent: Instance)
    frame(parent, "Shadow", 23, 46, 1234, 618, Color3.fromRGB(163, 123, 85), 35)
    frame(parent, "Bezel", 16, 38, 1248, 618, C.bezel, 35)
    frame(parent, "Screen", 30, 52, 1220, 590, C.rail, 24)
end

-- Shared with HomeScreen so both surfaces use one palette and one widget set.
View.palette = C
View.frame = frame
View.label = label
View.button = button
View.icon = icon
View.portrait = portrait
View.face = channelFace
View.shell = shell

local function stat(parent: Instance, metric: any, index: number, actions: any)
    local card = button(
        parent,
        "Metric_" .. metric.id,
        "",
        422 + (index - 1) * 264,
        64,
        250,
        91,
        false,
        function()
            actions.metric(metric.id)
        end
    )
    card.BackgroundColor3 = C.paper
    icon(card, metric.icon, 11, 13, C[metric.tone])
    label(card, metric.title, 58, 9, 177, 18, 12, C.muted, true)
    label(card, metric.value, 58, 29, 177, 24, 21, C.ink, true)
    label(card, metric.state, 12, 60, 219, 16, 11, C[metric.tone])
    local track = frame(card, "Track", 12, 79, 226, 5, C.line, 3)
    local fill =
        frame(track, "Fill", 0, 0, 226 * math.clamp(metric.fraction, 0, 1), 5, C[metric.tone], 3)
    fill:SetAttribute("Fraction", math.clamp(metric.fraction, 0, 1))
end

local function chat(parent: Instance, o: any, view: any, actions: any): any
    local panel = frame(parent, "Chat", 240, 170, 627, 430)
    local channel = view.channel or "group"
    channelFace(panel, o, channel, 20, 13, 1.15)
    label(
        panel,
        if channel == "group" then "The apartment" else Text.name(channel) .. " & you",
        62,
        10,
        450,
        27,
        22,
        C.ink,
        true
    )
    label(
        panel,
        if channel == "group" then "GROUP MESSAGE" else "PRIVATE CONVERSATION",
        62,
        40,
        545,
        16,
        10,
        C.muted,
        true
    )
    local scroll = Kit.scroller(panel, {
        Name = "Conversation",
        Position = UDim2.fromOffset(16, 68),
        Size = UDim2.fromOffset(595, 209),
    })
    local rowY = 0
    local messages = Data.messages(o, channel)
    if #messages == 0 then
        label(
            scroll,
            "A little communication goes a long way.\nStart the conversation below.",
            50,
            82,
            495,
            75,
            15,
            C.muted
        )
    end
    -- Every bubble is answered by its sender's face on the outer edge of the row,
    -- so a long conversation stays readable without reading the names.
    local faceW, faceH = faceSize(0.74)
    local gap = 8
    for _, entry in messages do
        local width = math.min(426, math.max(120, #entry.text * 7.5 + 26))
        local height = math.max(20, View.measure(entry.text, width - 26)) + 18
        local x = if entry.mine then 4 + faceW + gap else 579 - faceW - gap - width
        portrait(
            scroll,
            entry.actor,
            if entry.mine then 4 else 579 - faceW,
            rowY + 19 + height - faceH,
            0.74
        )
        label(
            scroll,
            Text.name(entry.actor, o.actor.id) .. " · Day " .. entry.day,
            x + 3,
            rowY,
            width - 6,
            17,
            10,
            C.muted
        )
        local bubble = frame(
            scroll,
            if entry.mine then "MessageMine" else "MessageOther",
            x,
            rowY + 19,
            width,
            height,
            if entry.mine then C.blue else C.bubble,
            17
        )
        label(
            bubble,
            entry.text,
            13,
            8,
            width - 26,
            height - 16,
            15,
            if entry.mine then C.white else C.ink
        )
        rowY += height + 28
    end
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
    scroll.CanvasSize = UDim2.fromOffset(0, rowY)
    scroll.CanvasPosition = Vector2.new(0, math.max(0, rowY - 209))
    return Composer.render(panel, o, view, actions, View)
end

local function sidebar(parent: Instance, o: any, view: any, actions: any)
    local rail = frame(parent, "Sidebar", 42, 170, 184, 430, C.rail)
    label(rail, "MESSAGES", 14, 12, 156, 18, 11, C.muted, true)
    local channels = { "group" }
    for _, id in o.actorIds do
        if id ~= o.actor.id then
            table.insert(channels, id)
        end
    end
    table.insert(channels, "activity")
    -- The list grows with the household, so the rail scrolls rather than spills.
    local list = Kit.scroller(rail, {
        Name = "Channels",
        Position = UDim2.fromOffset(10, 36),
        Size = UDim2.fromOffset(166, 232),
    })
    Kit.column(list, 6)
    for i, id in channels do
        local active = view.channel == id
        -- The row carries the badge; the name is a separate label so the face can
        -- sit beside it instead of behind centred button text.
        local item = button(list, "Channel_" .. id, "", 0, 0, 160, 40, active, function()
            actions.channel(id)
        end)
        item.LayoutOrder = i
        channelFace(item, o, id, 8, 7, 0.8)
        label(
            item,
            if id == "group"
                then "Group chat"
                elseif id == "activity" then "Activity & receipts"
                else Text.name(id),
            38,
            0,
            114,
            40,
            13,
            if active then C.white else C.ink,
            active
        )
    end
    portrait(rail, o.actor.id, 17, 281)
    label(rail, "YOUR POCKET", 56, 282, 119, 18, 10, C.muted, true)
    label(rail, "$" .. o.actor.cash, 56, 301, 119, 26, 23, C.ink, true)
    label(
        rail,
        string.format("Reserve goal $%d · bills owed $%d", o.actor.goal, o.actor.debt),
        17,
        331,
        156,
        30,
        11,
        C.muted
    )
    local goal = frame(rail, "ReserveProgress", 17, 362, 150, 5, C.line, 3)
    frame(goal, "Fill", 0, 0, 150 * Guide.summary(o).goalFraction, 5, C.good, 3)
    button(
        rail,
        "Apartment",
        if view.apartment then "Open HousePad [M]" else "Walk around [M]",
        10,
        378,
        164,
        40,
        false,
        actions.apartment
    )
end

local function details(parent: Instance, o: any, view: any, actions: any)
    local rail = frame(parent, "Details", 881, 170, 347, 430, C.paper)
    local metric
    for _, candidate in Data.metrics(o) do
        if candidate.id == view.metric then
            metric = candidate
        end
    end
    label(
        rail,
        if metric then metric.title else "Household notes",
        16,
        12,
        315,
        25,
        18,
        C.ink,
        true
    )
    local notes = Kit.scroller(
        rail,
        { Name = "Notes", Position = UDim2.fromOffset(16, 46), Size = UDim2.fromOffset(315, 172) }
    )
    Kit.column(notes, 8)
    local order = 0
    local function note(text, tone)
        order += 1
        local row = label(notes, text, 0, 0, 303, 48, 12, tone or C.muted)
        row.LayoutOrder = order
        row.AutomaticSize = Enum.AutomaticSize.Y
        row.TextYAlignment = Enum.TextYAlignment.Top
    end
    if metric then
        note(metric.detail)
    end
    local summary = Guide.summary(o)
    note(summary.objective, C.ink)
    note(summary.inspection)
    for _, item in o.items do
        if not item.resolved then
            note(Text.issue(item, o.actor.id), C.ink)
        end
    end
    for _, plan in o.plans do
        if plan.status == "pending" then
            note(
                string.format(
                    "%s is planning %s (%s).",
                    Text.name(plan.actor, o.actor.id),
                    plan.kind,
                    plan.due
                )
            )
        end
    end
    label(rail, string.upper(summary.choices), 16, 230, 315, 19, 11, C.muted, true)
    local choices = Kit.scroller(rail, {
        Name = "Choices",
        Position = UDim2.fromOffset(16, 257),
        Size = UDim2.fromOffset(315, 157),
    })
    Kit.column(choices, 7)
    local index = 0
    for _, action in o.candidates do
        if not CHORES[action.kind] then
            index += 1
            local item = button(
                choices,
                "Choice_" .. index,
                Guide.choice(action, o),
                0,
                0,
                303,
                39,
                false,
                function()
                    actions.act(action)
                end
            )
            item.LayoutOrder = index
        end
    end
    if index == 0 then
        label(
            choices,
            "Nothing else to choose here. Continue when you're ready.",
            0,
            0,
            303,
            62,
            13,
            C.muted
        )
    end
end

local function work(parent: Instance, o: any)
    local panel = frame(parent, "Work", 240, 170, 627, 430)
    label(panel, "Your shift", 22, 16, 580, 33, 26, C.ink, true)
    label(panel, "Minigames · coming later", 22, 51, 580, 23, 15, C.muted)
    for i, gameInfo in Data.minigames do
        local card = frame(panel, "Todo_" .. gameInfo.icon, 20, 88 + (i - 1) * 89, 587, 77, C.rail)
        icon(card, gameInfo.icon, 13, 18, C.muted)
        label(card, gameInfo.title, 65, 11, 420, 23, 17, C.ink, true)
        label(card, gameInfo.detail, 65, 36, 490, 29, 13, C.muted)
        label(card, "TO DO", 505, 10, 70, 22, 10, C.muted, true)
    end
    label(
        panel,
        string.format(
            "Continue to collect base pay ($%d before bills).\nThe recall bonus is paused until minigames are implemented.",
            math.max(0, o.actor.income + o.actor.modifier)
        ),
        22,
        365,
        583,
        48,
        13,
        C.muted
    )
end

local function result(parent: Instance, o: any, payload: any, actions: any)
    local panel = frame(parent, "Result", 240, 170, 627, 430)
    local days = o.outcome.days
    local best = math.max(payload.best or 0, days)
    local beatBest = payload.record == true
    icon(panel, "house", 28, 24, if o.outcome.survived then C.good else C.bad)
    label(panel, "YOU LASTED", 28, 72, 300, 16, 11, C.muted, true)
    label(
        panel,
        string.format("%d %s", days, if days == 1 then "day" else "days"),
        26,
        90,
        400,
        62,
        50,
        C.ink,
        true
    )
    label(
        panel,
        if o.outcome.survived
            then "The household made it to the end of the run."
            else "The landlord's patience ran out. Try a different plan and go further.",
        28,
        158,
        570,
        50,
        18,
        C.muted
    )
    local record = frame(panel, "Record", 28, 214, 570, 74, C.rail)
    label(record, "BEST RUN", 18, 12, 200, 16, 11, C.muted, true)
    label(
        record,
        string.format(
            "%d %s%s",
            best,
            if best == 1 then "day" else "days",
            if beatBest then "  ·  new record" else ""
        ),
        18,
        30,
        340,
        30,
        24,
        if beatBest then C.good else C.ink,
        true
    )
    label(
        record,
        string.format("$%d saved · $%d owed", o.actor.cash, o.actor.debt),
        392,
        30,
        166,
        30,
        14,
        C.muted
    )
    button(panel, "Restart", "Start a new household", 28, 306, 290, 48, true, actions.restart)
    button(panel, "BackHome", "Home screen [H]", 334, 306, 264, 48, false, actions.home)
end

local function activity(parent: Instance, o: any)
    local panel = frame(parent, "Activity", 240, 170, 627, 430)
    label(panel, "A little time at home", 22, 16, 580, 34, 25, C.ink, true)
    label(
        panel,
        "Walk around to do chores, or use your choices to help from here.",
        22,
        55,
        580,
        42,
        15,
        C.muted
    )
    local scroll = Kit.scroller(panel, {
        Name = "ActivityLog",
        Position = UDim2.fromOffset(22, 111),
        Size = UDim2.fromOffset(583, 295),
    })
    Kit.column(scroll, 9)
    local lines = Text.log(o, o.actor.id)
    for i = #lines, math.max(1, #lines - 16), -1 do
        local row = label(scroll, lines[i], 0, 0, 567, 40, 14, C.muted)
        row.LayoutOrder = #lines - i
        row.AutomaticSize = Enum.AutomaticSize.Y
    end
end

function View.render(canvas: Instance, payload: any, view: any, actions: any): any
    canvas:ClearAllChildren()
    local handles: any = { scale = Kit.make("UIScale", {}, canvas) }
    if not payload then
        return handles
    end
    local o = payload.observation
    local apartment = view.apartment and o.status == "running"
    if not apartment then
        shell(canvas)
    end
    local title = frame(canvas, "Header", 42, 64, 366, 91, C.paper)
    label(title, "DAY", 18, 10, 60, 16, 11, C.muted, true)
    label(title, "Day " .. o.day, 18, 24, 210, 38, 34, C.ink, true)
    label(
        title,
        if o.rules.days > 0
            then string.format(
                "%s · day %d of %d",
                Data.labels[table.find(Data.phases, o.phase) or 1],
                o.day,
                o.rules.days
            )
            else Data.labels[table.find(Data.phases, o.phase) or 1] .. " · " .. Data.rentLine(
                o
            ),
        18,
        66,
        330,
        18,
        13,
        C.muted
    )
    local scoreCard = frame(title, "Score", 236, 12, 114, 60, C.rail)
    label(scoreCard, "BEST RUN", 12, 7, 96, 14, 10, C.muted, true)
    label(
        scoreCard,
        string.format(
            "%d %s",
            payload.best or 0,
            if (payload.best or 0) == 1 then "day" else "days"
        ),
        12,
        24,
        96,
        26,
        20,
        C.ink,
        true
    )
    for i, metric in Data.metrics(o) do
        stat(canvas, metric, i, actions)
    end
    if apartment then
        Apartment.render(canvas, payload, actions, View)
    else
        sidebar(canvas, o, view, actions)
        details(canvas, o, view, actions)
        if o.status ~= "running" then
            result(canvas, o, payload, actions)
        elseif o.phase == "work" then
            work(canvas, o)
        elseif view.channel == "activity" then
            activity(canvas, o)
        elseif (o.phase == "action_one" or o.phase == "action_two") and not view.actionChat then
            Tasks.render(canvas, o, actions, View)
        else
            handles.chat = chat(canvas, o, view, actions)
        end
    end
    local footer = frame(canvas, "Timeline", 42, 610, 1186, 31, C.paper, 12)
    for i, phase in Data.phases do
        local active = o.phase == phase
        label(
            footer,
            (if active then "• " else "") .. Data.labels[i],
            12 + (i - 1) * 133,
            3,
            130,
            24,
            12,
            if active then C.good else C.muted,
            active
        )
    end
    if actions.home then
        button(footer, "Home", "Home [H]", 815, 0, 145, 31, false, actions.home)
    end
    if o.status == "running" then
        button(
            footer,
            "Next",
            if payload.busy
                then "Roommates are thinking…"
                elseif o.phase == "night" and (o.rentDueIn or 0) == 0 then "Settle rent [T]  →"
                elseif o.phase == "night" then "End day [T]  →"
                elseif o.phase == "work" then "Collect pay [T]  →"
                else "Continue [T]  →",
            974,
            0,
            212,
            31,
            true,
            function()
                if not payload.busy then
                    actions.ready()
                end
            end
        )
    end
    if not payload.developer and payload.notice then
        label(canvas, payload.notice, 42, 657, 1186, 38, 13, C.ink)
    end
    if payload.developer then
        local box = Kit.make("TextBox", {
            Name = "Command",
            Position = UDim2.fromOffset(42, 671),
            Size = UDim2.fromOffset(580, 30),
            BackgroundColor3 = C.paper,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Text = view.commandDraft or "",
            PlaceholderText = "/next · /day · /set landlord 80 · /help",
            TextSize = 13,
            TextColor3 = C.ink,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, canvas)
        Kit.corner(box, 10)
        Kit.pad(box, 0, 12, 0, 12)
        View.onEnter(box, function()
            actions.command(box.Text)
        end)
        handles.command = box
        button(canvas, "RunCommand", "Run", 632, 671, 65, 30, false, function()
            actions.command(box.Text)
        end)
        label(
            canvas,
            payload.notice or "Studio controls · /help lists commands",
            711,
            665,
            517,
            42,
            11,
            C.ink
        )
    end
    return handles
end

return View
