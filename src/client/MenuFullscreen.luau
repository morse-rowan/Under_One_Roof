--!strict
-- Native UI mockups, not game authority. All interaction is disposable preview state.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit = require(script.Parent.MenuKit)
local Blocks = require(script.Parent.MenuBlocks)
local Styles = require(shared:WaitForChild("MenuStyles"))
local Data = require(shared:WaitForChild("MenuPreviewData"))

local Fullscreen = {}

local function box(
    parent: Instance,
    style: any,
    name: string,
    x: number,
    y: number,
    w: number,
    h: number,
    tone: string?
): Frame
    return Kit.card(parent, style, {
        Name = name,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = Kit.tone(style, tone or "card"),
    })
end

local function label(
    parent: Instance,
    style: any,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    size: number?,
    tone: string?
): TextLabel
    return Kit.text(parent, style, {
        Text = text,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        TextSize = size or 16,
        FontKey = "heading",
        Tone = tone or "ink",
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
end

local function button(
    parent: Instance,
    style: any,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    active: boolean,
    callback: (() -> ())?
): TextButton
    local result = Kit.button(parent, style, {
        Name = string.gsub(text, "%W", ""),
        Text = text,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        TextSize = 15,
        TextWrapped = true,
        Solid = active,
        Tone = if active then "accent" else "muted",
    })
    if callback then
        result.Activated:Connect(callback)
    end
    return result
end

-- Original two-eyed bean portraits made from native shapes, matching the room cast.
local function bean(parent: Instance, style: any, who: string, x: number, y: number, size: number)
    local holder = Kit.make("Frame", {
        Name = who .. "Portrait",
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
    }, parent)
    local body = box(holder, style, "Bean", size * 0.18, size * 0.08, size * 0.64, size * 0.76)
    body.BackgroundColor3 = Kit.color(Styles.identity[who])
    Kit.corner(body, size * 0.32)
    for _, offset in { 0.27, 0.57 } do
        local eye = Kit.dot(body, Kit.tone(style, "ink"), math.max(4, size * 0.085), 0)
        eye.Position = UDim2.fromScale(offset, 0.34)
    end
    for _, offset in { 0.22, 0.57 } do
        local foot = Kit.dot(holder, Kit.color(Styles.identity[who]), size * 0.23, 0)
        foot.Position = UDim2.fromScale(offset, 0.72)
        Kit.stroke(foot, Kit.tone(style, "line"), 2)
    end
end

local function details(
    parent: Instance,
    style: any,
    screen: any,
    x: number,
    y: number,
    w: number,
    h: number
)
    local snap = Data.snapshots[screen.id]
    local wallet = box(parent, style, "YourPocket", x, y, w, 78, "cardAlt")
    bean(wallet, style, "blue", 10, 12, 50)
    label(wallet, style, "YOUR POCKET", 74, 10, w - 86, 20, 12, "muted")
    label(
        wallet,
        style,
        Data.money(snap.actor.cash) .. "  /  " .. Data.money(snap.actor.goal) .. " goal",
        74,
        32,
        w - 86,
        30,
        21
    )
    local count = #screen.panels
    local panelH = (h - 92 - (count - 1) * 12) / count
    for i, panel in screen.panels do
        Blocks.panel(parent, style, panel, {
            Position = UDim2.fromOffset(x, y + 92 + (i - 1) * (panelH + 12)),
            Size = UDim2.fromOffset(w, panelH),
        })
    end
end

local function messenger(
    parent: Instance,
    style: any,
    screen: any,
    x: number,
    y: number,
    w: number,
    h: number,
    interactive: boolean?,
    rail: boolean
)
    local shell = box(parent, style, "Messenger", x, y, w, h)
    local active = screen.chat.activeTab
    local draw
    draw = function()
        shell:ClearAllChildren()
        Kit.corner(shell, style.corner)
        Kit.stroke(shell, Kit.tone(style, "line"), 2)
        local inset = if rail then 184 else 16
        local tabs = { { "house", "Group chat" }, { "green", "Green" }, { "red", "Red" } }
        for i, tab in tabs do
            local bx = if rail then 12 else 16 + (i - 1) * ((w - 44) / 3 + 6)
            local by = if rail then 70 + (i - 1) * 68 else 54
            local bw = if rail then 154 else (w - 44) / 3
            button(
                shell,
                style,
                tab[2],
                bx,
                by,
                bw,
                42,
                active == tab[1],
                if interactive
                    then function()
                        active = tab[1]
                        draw()
                    end
                    else nil
            )
            if rail and i > 1 then
                label(shell, style, "Private conversation", bx + 4, by + 42, bw, 20, 10, "muted")
            end
        end
        if rail then
            label(shell, style, "MESSAGES", 18, 22, 150, 22, 16)
            bean(shell, style, "blue", 42, h - 132, 80)
            label(shell, style, "Blue / you", 32, h - 48, 120, 22, 14, "muted")
        end
        label(
            shell,
            style,
            if active == "house" then "The apartment" else "You + " .. active,
            inset + 12,
            12,
            w - inset - 24,
            30,
            24
        )
        local top = if rail then 57 else 111
        if rail then
            label(
                shell,
                style,
                "GROUP CHAT + PRIVATE MESSAGES",
                inset + 12,
                41,
                w - inset - 24,
                17,
                10,
                "muted"
            )
        end
        local messages = Kit.scroller(shell, {
            Name = "Conversation",
            Position = UDim2.fromOffset(inset + 10, top + 8),
            Size = UDim2.fromOffset(w - inset - 24, h - top - 124),
        })
        local rowY = 4
        for _, entry in Data.threads[active] do
            local available = w - inset - 44
            local bubbleH = if available < 400 then 96 else 80
            local row = box(
                messages,
                style,
                "Message",
                4,
                rowY,
                available,
                bubbleH,
                if entry.mine then "bubbleMine" else "bubbleOther"
            )
            bean(row, style, entry.from, 8, 12, 42)
            label(
                row,
                style,
                string.upper(entry.from) .. (if entry.mine then " / YOU" else ""),
                60,
                8,
                available - 70,
                18,
                11,
                "muted"
            )
            local body = label(row, style, entry.text, 60, 28, available - 76, bubbleH - 36, 15)
            body.Font = Kit.font("gotham")
            rowY += bubbleH + 12
        end
        label(
            shell,
            style,
            tostring(screen.chat.remaining) .. " messages left this stop",
            inset + 14,
            h - 112,
            w - inset - 28,
            22,
            12,
            "muted"
        )
        local composer =
            box(shell, style, "Composer", inset + 12, h - 82, w - inset - 26, 44, "cardAlt")
        label(composer, style, "Write a message...", 12, 0, w - inset - 62, 44, 14, "muted")
        label(
            shell,
            style,
            "SAMPLE CHAT / select a channel to explore",
            inset + 14,
            h - 30,
            w - inset - 28,
            20,
            10,
            "muted"
        )
    end
    draw()
end

local function choiceStrip(
    parent: Instance,
    style: any,
    screen: any,
    x: number,
    y: number,
    w: number
)
    local width = (w - (#screen.choices - 1) * 12) / #screen.choices
    for i, choice in screen.choices do
        button(
            parent,
            style,
            choice.text,
            x + (i - 1) * (width + 12),
            y,
            width,
            42,
            choice.primary == true,
            nil
        )
    end
end

local function work(parent: Instance, style: any, screen: any, interactive: boolean?)
    local laptop = style.id == "laptop"
    local arcade = style.id == "arcade"
    local title = if laptop then "ORDER UP!" elseif arcade then "SORTING SHIFT" else "PARCEL DESK"
    label(parent, style, title, 54, 35, 740, 58, 42)
    label(parent, style, "Clocked in. A little focus goes a long way.", 56, 97, 810, 28, 19)
    local machine = box(parent, style, "ShiftMachine", 46, 146, 836, 472, "cardAlt")
    details(parent, style, screen, 906, 146, 328, 472)
    bean(parent, style, "blue", 1156, 35, 72)
    local target = screen.grid.symbols
    local answers = {}
    local phase = "preview"
    local symbols = if laptop
        then { "TEA", "BUN", "SOUP", "PIE" }
        elseif arcade then { "A", "B", "C", "D" }
        else { "MOON", "LEAF", "SUN", "STAR" }
    local colors = { "cool", "good", "warn", "bad" }
    local redraw
    redraw = function()
        machine:ClearAllChildren()
        Kit.corner(machine, style.corner)
        Kit.stroke(machine, Kit.tone(style, "line"), 3)
        label(
            machine,
            style,
            if phase == "preview"
                then "01 / MEMORIZE THE ORDER"
                elseif phase == "recall" then "02 / PLAY IT BACK"
                else "03 / SHIFT COMPLETE",
            24,
            14,
            776,
            34,
            24
        )
        label(machine, style, screen.subtitle, 24, 49, 770, 24, 14, "muted")
        local score = 0
        for i, value in answers do
            if value == target[i] then
                score += 1
            end
        end
        for i = 1, #target do
            local value = if phase == "preview" then target[i] else answers[i]
            local ticket = box(machine, style, "Slot" .. i, 26 + (i - 1) * 158, 92, 146, 94, "card")
            label(ticket, style, string.format("%02d", i), 12, 6, 100, 20, 11, "muted")
            label(
                ticket,
                style,
                if value then symbols[value] else "?",
                12,
                28,
                126,
                54,
                if laptop then 22 else 26,
                if value then colors[value] else "muted"
            )
        end
        if phase == "preview" then
            label(
                machine,
                style,
                if laptop
                    then "Read the ticket. Then rebuild the order."
                    elseif arcade then "Remember the labels. Tap the sorter in the same order."
                    else "Check the parcel labels. Repeat their delivery order.",
                38,
                207,
                if arcade then 340 else 750,
                72,
                23
            )
        elseif phase == "done" then
            label(
                machine,
                style,
                tostring(score) .. " / " .. tostring(#target) .. " matched",
                38,
                202,
                if arcade then 335 else 750,
                48,
                32,
                "good"
            )
            label(
                machine,
                style,
                "Practice complete. Your real wallet is unchanged.",
                38,
                254,
                if arcade then 330 else 750,
                50,
                16,
                "muted"
            )
        else
            label(
                machine,
                style,
                "Select label " .. tostring(#answers + 1) .. " of " .. tostring(#target),
                38,
                211,
                if arcade then 330 else 750,
                40,
                25
            )
        end
        for i = 1, 4 do
            local x = if arcade then 416 + ((i - 1) % 2) * 192 else 28 + (i - 1) * 197
            local y = if arcade then 211 + math.floor((i - 1) / 2) * 99 else 314
            local pad = button(
                machine,
                style,
                symbols[i],
                x,
                y,
                if arcade then 178 else 182,
                if arcade then 84 else 70,
                false,
                if interactive and phase == "recall"
                    then function()
                        table.insert(answers, i)
                        if #answers == #target then
                            phase = "done"
                        end
                        redraw()
                    end
                    else nil
            )
            pad.TextSize = 24
            pad.TextColor3 = Kit.tone(style, colors[i])
            pad.BackgroundColor3 = Kit.tone(style, "card")
            Kit.stroke(pad, Kit.tone(style, colors[i]), 3)
        end
        if phase ~= "recall" then
            button(
                machine,
                style,
                if phase == "preview" then "Ready / hide the order" else "Try again",
                28,
                412,
                if arcade then 346 else 780,
                42,
                true,
                if interactive
                    then function()
                        answers = {}
                        phase = if phase == "preview" then "recall" else "preview"
                        redraw()
                    end
                    else nil
            )
        else
            label(
                machine,
                style,
                "PREVIEW PRACTICE / no timer or payout",
                28,
                421,
                if arcade then 346 else 780,
                27,
                12,
                "muted"
            )
        end
    end
    redraw()
end

local function otherScreen(
    parent: Instance,
    style: any,
    screen: any,
    x: number,
    y: number,
    w: number,
    h: number
)
    if screen.kind == "result" then
        Blocks.verdict(
            parent,
            style,
            screen.verdict,
            { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w * 0.63, h - 54) }
        )
        bean(parent, style, "blue", x + w * 0.63 - 100, y + h - 180, 100)
        details(parent, style, screen, x + w * 0.65, y, w * 0.35, h - 54)
    else
        Blocks.timer(
            parent,
            style,
            screen.timer,
            { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(210, 98) }
        )
        label(parent, style, "YOUR NEXT MOVE", x, y + 124, w * 0.46, 56, 32)
        Blocks.prompt(
            parent,
            style,
            screen.prompt,
            { Position = UDim2.fromOffset(x, y + 190), Size = UDim2.fromOffset(w * 0.46, 120) }
        )
        details(parent, style, screen, x + w * 0.5, y, w * 0.5, h - 54)
    end
    choiceStrip(parent, style, screen, x, y + h - 42, w)
end

function Fullscreen.render(stage: Instance, style: any, screen: any, interactive: boolean?)
    -- The root and viewport scrim are both opaque: no apartment bleed, even with letterboxing.
    local root = Kit.make("Frame", {
        Name = "Fullscreen",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Kit.tone(style, "bg"),
        BorderSizePixel = 0,
    }, stage)
    -- Warm square-grid wallpaper echoes the apartment's graphic floor.
    for i = 0, 15 do
        local stripe = Kit.make("Frame", {
            Position = UDim2.fromOffset(i * 86, 0),
            Size = UDim2.new(0, 2, 1, 0),
            BackgroundColor3 = Kit.tone(style, "card"),
            BackgroundTransparency = 0.88,
            BorderSizePixel = 0,
        }, root)
        stripe.Name = "WallpaperLine"
    end
    for i = 0, 8 do
        Kit.make("Frame", {
            Position = UDim2.fromOffset(0, i * 86),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = Kit.tone(style, "card"),
            BackgroundTransparency = 0.88,
            BorderSizePixel = 0,
        }, root)
    end
    if screen.kind == "work" then
        work(root, style, screen, interactive)
        label(
            root,
            style,
            "WORK STUDY / " .. style.name .. " / try the recall buttons",
            48,
            634,
            1160,
            30,
            13
        )
        return
    end

    local snapshot = Data.snapshots[screen.id]
    local status = string.format(
        "RENT %d/%d   /   PRESSURE %d   /   CLEAN %d%%",
        snapshot.rentPaid,
        snapshot.rent,
        snapshot.heat,
        snapshot.cleanliness
    )
    if style.id == "tablet" then
        local shell = box(root, style, "TabletBezel", 28, 24, 1224, 640, "ink")
        Kit.corner(shell, 38)
        local glass = box(shell, style, "TabletScreen", 20, 20, 1184, 600, "cardAlt")
        label(glass, style, "HousePad", 22, 10, 220, 44, 29)
        label(
            glass,
            style,
            screen.title .. " / DAY " .. Data.snapshots[screen.id].day,
            260,
            10,
            430,
            44,
            21
        )
        label(glass, style, status, 716, 10, 444, 44, 12, "muted")
        if screen.kind == "stop" then
            messenger(glass, style, screen, 18, 68, 794, 450, interactive, true)
            details(glass, style, screen, 828, 68, 336, 450)
            choiceStrip(glass, style, screen, 18, 538, 1146)
        else
            otherScreen(glass, style, screen, 20, 74, 1144, 502)
        end
    elseif style.id == "laptop" then
        local lid = box(root, style, "LaptopLid", 34, 34, 1212, 568, "ink")
        local desktop = box(lid, style, "Desktop", 16, 18, 1180, 532, "cardAlt")
        label(desktop, style, "roomie OS", 20, 4, 200, 36, 22)
        label(desktop, style, screen.title .. " / DAY " .. snapshot.day, 254, 4, 330, 36, 16)
        label(desktop, style, status, 688, 4, 474, 36, 12, "muted")
        if screen.kind == "stop" then
            messenger(desktop, style, screen, 16, 52, 712, 408, interactive, false)
            details(desktop, style, screen, 746, 52, 416, 408)
            choiceStrip(desktop, style, screen, 16, 478, 1146)
        else
            otherScreen(desktop, style, screen, 20, 52, 1140, 468)
        end
        local keyboard = box(root, style, "KeyboardDeck", 8, 612, 1264, 61, "cardAlt")
        for row = 0, 1 do
            for i = 0, 18 do
                box(keyboard, style, "Key", 34 + i * 41 + row * 6, 8 + row * 24, 30, 16, "card")
            end
        end
        box(keyboard, style, "Trackpad", 872, 9, 270, 42, "card")
    else
        label(root, style, string.upper(screen.title) .. "!", 46, 27, 860, 62, 46)
        label(root, style, status, 48, 91, 850, 30, 17)
        for i, who in { "blue", "green", "red" } do
            bean(root, style, who, 972 + (i - 1) * 88, 30, 74)
        end
        if screen.kind == "stop" then
            local roster = box(root, style, "Housemates", 42, 146, 174, 450, "cardAlt")
            label(roster, style, "HOUSEMATES", 16, 12, 148, 28, 16)
            for i, who in { "blue", "green", "red" } do
                bean(roster, style, who, 48, 52 + (i - 1) * 124, 74)
                label(roster, style, string.upper(who), 48, 130 + (i - 1) * 124, 120, 22, 14)
            end
            messenger(root, style, screen, 236, 146, 602, 450, interactive, false)
            details(root, style, screen, 858, 146, 380, 450)
            choiceStrip(root, style, screen, 42, 618, 1196)
        else
            otherScreen(root, style, screen, 42, 146, 1196, 514)
        end
    end
end

return Fullscreen
