--!strict
-- Illustrative menu content for the visual preview only.
--
-- `snapshots` mirror the field names and shapes that `src/simulation/MvpRound.luau`
-- already produces from `Round.observe`, so the mockups cannot quietly invent
-- mechanics. `tests/menu-preview.spec.luau` checks that every snapshot field
-- exists on a real observation. Fields marked "preview copy" below are wording
-- choices for this study, not rules: the log lines, chat threads and clue text
-- are written by hand to show how a screen reads when it is full.
--
-- Numbers follow `Round.defaults` (rent 30, payment 5, cleanup 5, repair 10,
-- eviction 100, workBonus 5). They are trial values, not balance decisions.
local Data = {}

Data.screens = { "morning", "action", "work", "midday", "night", "result" }

local function actor(cash: number, goal: number, tired: boolean, modifier: number): any
    return {
        id = "blue",
        role = "player",
        cash = cash,
        income = 15,
        goal = goal,
        expense = 5,
        debt = 0,
        modifier = modifier,
        tired = tired,
    }
end

-- Outstanding issues use the real item shape: id, kind, creator, day, stage, age, resolved.
local function item(
    id: number,
    kind: string,
    creator: string,
    day: number,
    stage: string,
    age: number
): any
    return {
        id = id,
        kind = kind,
        creator = creator,
        day = day,
        stage = stage,
        age = age,
        resolved = false,
    }
end

-- Plans the player has already inspected use the real plan shape.
local function plan(id: number, kind: string, who: string, due: string, day: number): any
    return { id = id, kind = kind, actor = who, due = due, day = day, status = "pending" }
end

Data.snapshots = {
    morning = {
        day = 2,
        phase = "morning",
        status = "running",
        actor = actor(18, 40, true, -5),
        actorIds = { "blue", "green", "red" },
        heat = 25,
        cleanliness = 72,
        rent = 30,
        rentPaid = 0,
        messagesRemaining = 3,
        items = { item(3, "dishes", "green", 1, "open", 1) },
        plans = {},
        work = { difficulty = 5, bonusCap = 5 },
        outcome = { final = false, survived = false, goalMet = false },
        goalMet = false,
    },
    action = {
        day = 2,
        phase = "action_one",
        status = "running",
        actor = actor(18, 40, true, -5),
        actorIds = { "blue", "green", "red" },
        heat = 25,
        cleanliness = 64,
        rent = 30,
        rentPaid = 5,
        messagesRemaining = 0,
        items = { item(3, "dishes", "green", 1, "open", 1), item(4, "trash", "red", 2, "open", 0) },
        plans = { plan(2, "party", "red", "overnight", 2) },
        work = { difficulty = 5, bonusCap = 5 },
        outcome = { final = false, survived = false, goalMet = false },
        goalMet = false,
    },
    work = {
        day = 2,
        phase = "work",
        status = "running",
        actor = actor(13, 40, true, -5),
        actorIds = { "blue", "green", "red" },
        heat = 25,
        cleanliness = 64,
        rent = 30,
        rentPaid = 10,
        messagesRemaining = 0,
        items = { item(3, "dishes", "green", 1, "open", 1) },
        plans = { plan(2, "party", "red", "overnight", 2) },
        work = { difficulty = 5, bonusCap = 5 },
        outcome = { final = false, survived = false, goalMet = false },
        goalMet = false,
    },
    midday = {
        day = 2,
        phase = "midday",
        status = "running",
        actor = actor(26, 40, true, -5),
        actorIds = { "blue", "green", "red" },
        heat = 25,
        cleanliness = 64,
        rent = 30,
        rentPaid = 10,
        messagesRemaining = 3,
        items = { item(3, "dishes", "green", 1, "open", 1) },
        plans = { plan(2, "party", "red", "overnight", 2) },
        work = { difficulty = 5, bonusCap = 5 },
        outcome = { final = false, survived = false, goalMet = false },
        goalMet = false,
    },
    night = {
        day = 2,
        phase = "night",
        status = "running",
        actor = actor(31, 40, false, 0),
        actorIds = { "blue", "green", "red" },
        heat = 40,
        cleanliness = 58,
        rent = 30,
        rentPaid = 25,
        messagesRemaining = 2,
        items = {
            item(3, "dishes", "green", 1, "open", 2),
            item(5, "leak", "system", 2, "open", 0),
        },
        plans = { plan(2, "party", "red", "overnight", 2) },
        work = { difficulty = 3, bonusCap = 5 },
        outcome = { final = false, survived = false, goalMet = false },
        goalMet = false,
    },
    result = {
        day = 3,
        phase = "night",
        status = "horizon",
        actor = actor(44, 40, false, 5),
        actorIds = { "blue", "green", "red" },
        heat = 65,
        cleanliness = 61,
        rent = 30,
        rentPaid = 30,
        messagesRemaining = 0,
        items = {},
        plans = {},
        work = { difficulty = 3, bonusCap = 5 },
        outcome = { final = true, survived = true, goalMet = true },
        goalMet = true,
    },
}

Data.colorNames = { blue = "Blue", green = "Green", red = "Red" }

local issueNames = {
    trash = "Trash bags piling up",
    dishes = "Sink full of dishes",
    leak = "Leak under the sink",
    roaches = "Roaches in the kitchen",
}

local issueCost = { trash = 5, dishes = 5, leak = 10, roaches = 10 }

function Data.issueLine(entry: any): (string, string)
    local name = issueNames[entry.kind] or entry.kind
    local age = if entry.age == 0
        then "new today"
        elseif entry.age == 1 then "1 day old"
        else entry.age .. " days old"
    local stage = if entry.stage == "open" then "" else " / " .. entry.stage
    return string.format("#%d  %s", entry.id, name),
        string.format("%s%s / pay %s to clear", age, stage, Data.money(issueCost[entry.kind] or 5))
end

function Data.money(amount: number): string
    return "$" .. string.format("%d", amount)
end

-- Preview copy. The real recap comes from checkpoint events and must stay
-- color-attributed with no controller or cost disclosure.
Data.logs = {
    morning = {
        { actor = "green", text = "Green handled outstanding requirement #1." },
        { actor = "red", text = "Red hosted overnight. Everyone else starts tired." },
        { actor = nil, text = "Rent settled 30 of 30. Landlord pressure eased by 5." },
        { actor = nil, text = "Requirement #3 is still outstanding and aging." },
    },
    midday = {
        { actor = "blue", text = "Blue handled outstanding requirement #4." },
        { actor = "red", text = "Red contributed $5 toward rent." },
        { actor = nil, text = "Shift pay recorded. Rest affected the result." },
    },
    night = {
        { actor = nil, text = "A leak opened under the kitchen sink." },
        { actor = "blue", text = "Blue contributed $5 toward rent." },
        { actor = nil, text = "Rent stands at 25 of 30 with the day closing." },
    },
    result = {
        { actor = nil, text = "Day 3 closed with the household still housed." },
        { actor = nil, text = "Landlord pressure finished at 65 of 100." },
    },
}

-- Preview copy for the messaging surfaces.
Data.threads = {
    house = {
        { from = "red", text = "Having a few people over tonight. It'll be quiet, promise." },
        { from = "green", text = "The sink is still full and I did it last time." },
        {
            from = "blue",
            text = "I'll take the dishes if someone covers my $5 of rent.",
            mine = true,
        },
    },
    green = {
        { from = "green", text = "I can't cover rent this week. My card got charged twice." },
        {
            from = "blue",
            text = "Tell me before it happens next time and I'll plan around it.",
            mine = true,
        },
        { from = "green", text = "Fair. I'll clear the sink tonight." },
    },
    red = {
        {
            from = "blue",
            text = "Cancel the party and I'll cover your share tomorrow.",
            mine = true,
        },
        { from = "red", text = "Tempting. Make it tonight and we have a deal." },
    },
}

local function meter(key: string, label: string, value: string, tone: string): any
    return { key = key, label = label, value = value, tone = tone }
end

local function meters(s: any): any
    return {
        meter("cash", "Cash", Data.money(s.actor.cash), "good"),
        meter(
            "goal",
            "Personal goal",
            Data.money(s.actor.cash) .. " / " .. Data.money(s.actor.goal),
            "cool"
        ),
        meter(
            "rent",
            "Rent",
            s.rentPaid .. " / " .. s.rent,
            if s.rentPaid >= s.rent then "good" else "warn"
        ),
        meter("heat", "Landlord", s.heat .. " / 100", if s.heat >= 60 then "bad" else "warn"),
        meter(
            "clean",
            "Cleanliness",
            s.cleanliness .. "%",
            if s.cleanliness < 70 then "warn" else "good"
        ),
    }
end

local function issuePanel(s: any): any
    local rows = {}
    for _, entry in s.items do
        local text, detail = Data.issueLine(entry)
        table.insert(rows, {
            text = text,
            detail = detail,
            tone = if entry.age >= 2 then "bad" else "warn",
        })
    end
    if #rows == 0 then
        table.insert(
            rows,
            { text = "Nothing outstanding", detail = "The apartment is clear", tone = "good" }
        )
    end
    return { key = "issues", heading = "Outstanding", rows = rows }
end

local function logPanel(heading: string, key: string): any
    local rows = {}
    for _, line in Data.logs[key] do
        table.insert(
            rows,
            { text = line.text, tone = if line.actor then "ink" else "muted", actor = line.actor }
        )
    end
    return {
        key = "log",
        heading = heading,
        rows = rows,
        note = "Shared log. No one sees who paid or how.",
    }
end

local function chat(s: any, active: string): any
    return {
        tabs = {
            { id = "house", label = "# house" },
            { id = "green", label = "@ Green" },
            { id = "red", label = "@ Red" },
        },
        activeTab = active,
        thread = Data.threads[active],
        placeholder = "Say something to the household...",
        chips = { "Offer $5", "Ask to cancel", "Promise dishes" },
        remaining = s.messagesRemaining,
    }
end

local function stopScreen(
    id: string,
    title: string,
    subtitle: string,
    logHeading: string,
    active: string,
    choices: any
): any
    local s = Data.snapshots[id]
    return {
        id = id,
        kind = "stop",
        title = title,
        subtitle = subtitle,
        meters = meters(s),
        panels = { logPanel(logHeading, id), issuePanel(s) },
        chat = chat(s, active),
        choices = choices,
        footer = string.format(
            "Day %d of 3 / %s / %d messages left",
            s.day,
            title,
            s.messagesRemaining
        ),
    }
end

function Data.screen(id: string): any
    local s = Data.snapshots[id]
    assert(s, "Unknown preview screen: " .. tostring(id))
    if id == "morning" then
        return stopScreen(
            id,
            "Morning",
            "Plan the day before anyone leaves.",
            "Overnight",
            "house",
            {
                { text = "Contribute $5 to rent", tone = "good" },
                { text = "Hold your cash", tone = "muted" },
                { text = "Start the day", tone = "accent", primary = true },
            }
        )
    elseif id == "midday" then
        return stopScreen(
            id,
            "Midday",
            "Pay is in. Half the day is left.",
            "Since morning",
            "green",
            {
                { text = "Contribute $5 to rent", tone = "good" },
                { text = "Clear requirement #3 for $5", tone = "cool" },
                { text = "Back to the apartment", tone = "accent", primary = true },
            }
        )
    elseif id == "night" then
        return stopScreen(id, "Night", "Last word before the day settles.", "Today", "red", {
            { text = "Contribute $5 to rent", tone = "warn" },
            { text = "Hold your cash", tone = "muted" },
            { text = "Sleep", tone = "accent", primary = true },
        })
    elseif id == "action" then
        local s2 = Data.snapshots.action
        return {
            id = id,
            kind = "action",
            title = "Action one",
            subtitle = "47s left / 2 actions",
            meters = meters(s2),
            panels = {
                issuePanel(s2),
                {
                    key = "clues",
                    heading = "Noticed",
                    rows = {
                        {
                            text = "Red is setting up for tonight",
                            detail = "A party would raise pressure by 5. You can ask Red to drop it.",
                            tone = "bad",
                        },
                    },
                    note = "Asking is not the same as stopping it.",
                },
            },
            choices = {
                { text = "Ask Red to cancel", tone = "warn" },
                { text = "Pay $5 to clear #3", tone = "cool" },
                { text = "Bag the trash (#4)", tone = "accent", primary = true },
            },
            prompt = {
                key = "E",
                text = "Hold E / Bag the trash",
                detail = "Step one of two. Removal still needs a trip out.",
            },
            timer = { seconds = 47, total = 60, actions = 2, actionsTotal = 2 },
            footer = "Day 2 / Action one / move with WASD",
        }
    elseif id == "work" then
        local s3 = Data.snapshots.work
        return {
            id = id,
            kind = "work",
            title = "Your shift",
            subtitle = "Tired from last night: 5 symbols instead of 3.",
            meters = meters(s3),
            panels = {
                {
                    key = "payout",
                    heading = "Today's pay",
                    rows = {
                        { text = "Base pay", detail = "$15 guaranteed", tone = "good" },
                        { text = "Tired", detail = "-$5 from last night's party", tone = "bad" },
                        {
                            text = "Recall bonus",
                            detail = "up to $5 for a perfect order",
                            tone = "cool",
                        },
                    },
                },
            },
            grid = {
                stage = "preview",
                symbols = { 2, 4, 1, 3, 1 },
                length = 5,
                palette = 4,
                prompt = "Memorize the order",
                recallPrompt = "Play it back",
            },
            choices = { { text = "I have it", tone = "accent", primary = true } },
            footer = "Day 2 / Work / sleep decides the length",
        }
    end
    local s4 = Data.snapshots.result
    return {
        id = id,
        kind = "result",
        title = "Still under one roof",
        subtitle = "Three days survived and your goal met.",
        meters = meters(s4),
        panels = { logPanel("How it ended", "result") },
        verdict = {
            headline = "Still under one roof",
            lines = {
                "Survived 3 of 3 days",
                "Landlord pressure 65 of 100",
                "Personal goal $44 of $40 met",
                "Red cancelled the day-two party after your offer",
            },
        },
        choices = {
            { text = "Play again", tone = "accent", primary = true },
            { text = "Read the day log", tone = "muted" },
        },
        footer = "Run complete",
    }
end

return Data
