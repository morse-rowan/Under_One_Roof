--!strict
-- Keeps the menu visual study honest: the mockups must describe the mechanics
-- that already exist, and every candidate look must be complete.
local Round = require("../src/simulation/MvpRound")
local Data = require("../src/shared/MenuPreviewData")
local Styles = require("../src/shared/MenuStyles")

local function expect(condition: any, message: string)
    assert(condition, "Menu preview: " .. message)
end

local function keysOf(value: any): { string }
    local keys = {}
    for key in value do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

-- A real observation and the real item/plan records to compare the mockups with.
local function reference(): (any, any, any)
    local actors = {
        { id = "blue", role = "player", cash = 20, income = 15, goal = 40, expense = 5 },
        { id = "green", role = "npc", cash = 10, income = 10, goal = 25, expense = 5 },
        { id = "red", role = "npc", cash = 15, income = 15, goal = 30, expense = 5 },
    }
    local state = Round.new(actors, 7, { messPercent = 100, partyPercent = 100 })
    expect(Round.advance(state, state.revision), "advance to action one")
    expect(Round.advance(state, state.revision), "advance to work")
    return Round.observe(state, "blue"), state.items[1], state.plans[1]
end

return function()
    local observation, realItem, realPlan = reference()
    expect(realItem ~= nil and realPlan ~= nil, "the fixture must produce an issue and a plan")

    for _, id in Data.screens do
        local snapshot = Data.snapshots[id]
        expect(snapshot ~= nil, id .. " needs a snapshot")
        for _, key in keysOf(snapshot) do
            expect(
                observation[key] ~= nil,
                string.format("%s snapshot field %q is not produced by Round.observe", id, key)
            )
            expect(
                type(snapshot[key]) == type(observation[key]),
                string.format("%s snapshot field %q has the wrong type", id, key)
            )
        end
        for _, key in keysOf(snapshot.actor) do
            expect(observation.actor[key] ~= nil, id .. " actor field is not real: " .. key)
        end
        for _, entry in snapshot.items do
            for _, key in keysOf(entry) do
                expect(realItem[key] ~= nil, id .. " issue field is not real: " .. key)
            end
            expect(entry.stage == "open" or entry.stage == "bagged", id .. " uses a real stage")
        end
        for _, entry in snapshot.plans do
            for _, key in keysOf(entry) do
                expect(realPlan[key] ~= nil, id .. " plan field is not real: " .. key)
            end
        end
    end

    -- Screens must be renderable: the layouts index these fields directly.
    for _, id in Data.screens do
        local screen = Data.screen(id)
        expect(screen.id == id, id .. " must report its own id")
        expect(#screen.title > 0 and #screen.subtitle > 0, id .. " needs a title and subtitle")
        expect(#screen.meters == 5, id .. " needs the five meters the layouts expect")
        expect(#screen.choices > 0, id .. " needs at least one choice")
        expect(type(screen.footer) == "string", id .. " needs a footer")
        if screen.kind == "stop" then
            expect(#screen.panels == 2, id .. " stop screens use two panels")
            expect(Data.threads[screen.chat.activeTab] ~= nil, id .. " opens a missing thread")
            local found = false
            for _, tab in screen.chat.tabs do
                found = found or tab.id == screen.chat.activeTab
            end
            expect(found, id .. " active tab is not in its own tab list")
        elseif screen.kind == "action" then
            expect(screen.timer ~= nil and screen.prompt ~= nil, id .. " needs a timer and prompt")
            expect(#screen.panels == 2, id .. " action screens use two panels")
        elseif screen.kind == "work" then
            expect(#screen.grid.symbols == screen.grid.length, id .. " grid length must match")
            expect(#screen.panels == 1, id .. " work screens use one panel")
        else
            expect(#screen.verdict.lines > 0, id .. " needs verdict lines")
            expect(#screen.panels == 1, id .. " result screens use one panel")
        end
        for _, panel in screen.panels do
            expect(#panel.rows > 0, id .. " panel " .. panel.key .. " is empty")
        end
    end

    -- Log speakers and chat participants must be household colors.
    for key, lines in Data.logs do
        expect(#lines > 0, "log " .. key .. " is empty")
        for _, line in lines do
            expect(
                line.actor == nil or Data.colorNames[line.actor] ~= nil,
                "log " .. key .. " names a non-roommate"
            )
        end
    end
    for key, thread in Data.threads do
        for _, line in thread do
            expect(Styles.identity[line.from] ~= nil, "thread " .. key .. " names a non-roommate")
        end
    end

    -- Every candidate look must be complete and cycle in both directions.
    local template = Styles.list[Styles.order[1]]
    for _, id in Styles.order do
        local style = Styles.get(id)
        expect(style.id == id, id .. " must report its own id")
        expect(#style.name > 0 and #style.blurb > 0, id .. " needs a name and blurb")
        for _, key in keysOf(template.colors) do
            expect(style.colors[key] ~= nil, id .. " is missing color " .. key)
            expect(#style.colors[key] == 3, id .. " color " .. key .. " needs three channels")
        end
        for _, key in keysOf(template.fonts) do
            expect(style.fonts[key] ~= nil, id .. " is missing font " .. key)
        end
        expect(Styles.step(Styles.step(id, 1), -1) == id, id .. " must cycle back to itself")
    end
    expect(Styles.step(Styles.order[#Styles.order], 1) == Styles.order[1], "looks must wrap")

    local text, detail = Data.issueLine(Data.snapshots.night.items[1])
    expect(text == "#3  Sink full of dishes", "issue title reads: " .. text)
    expect(string.find(detail, "2 days old") == 1, "issue age reads: " .. detail)
    expect(Data.money(5) == "$5", "money formatting")
end
