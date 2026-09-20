--!strict
-- The action-window driver, with a fake apartment standing in for the sandbox.
-- Hops land instantly here, so what is checked is the decision loop: a roommate
-- picks a legal errand, walks to where it happens, commits it once, and goes home.
-- The beans, the hop timing and the client's view of them need a Studio playtest.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")
local Grid = require("../src/shared/GridMovement")
local Routine = require("../src/shared/RoundRoutine")
local Errands = require("../src/server/RoundErrands")
local config = require("../src/shared/VisualStudy")

local function expect(condition: any, message: string)
    assert(condition, message)
end

-- A grid the roommates can move on, with none of Roblox's timing.
local function apartment()
    local cells: { [string]: any } = {}
    local blocked = Grid.blocked(config, false)
    for _, data in config.roommates do
        cells[data.name] = { cell = { c = data.c, r = data.r }, home = { c = data.c, r = data.r } }
    end
    local taken = function(cell: any, mover: string): boolean
        for name, actor in cells do
            if name ~= mover and Grid.key(actor.cell) == Grid.key(cell) then
                return true
            end
        end
        return false
    end
    return {
        config = config,
        steps = 0,
        roommates = {
            enabled = true,
            blocked = blocked,
            blockedFor = function(name: string): any
                local occupied = table.clone(blocked)
                for other, actor in cells do
                    if other ~= name then
                        occupied[Grid.key(actor.cell)] = true
                    end
                end
                return occupied
            end,
            cellOf = function(name: string): any?
                return if cells[name] then cells[name].cell else nil
            end,
            homeOf = function(name: string): any?
                return if cells[name] then cells[name].home else nil
            end,
            busy = function(): boolean
                return false
            end,
            step = function(name: string, direction: any): boolean
                local actor = cells[name]
                local destination = Grid.destination(config, actor.cell, direction, blocked)
                if not destination or taken(destination, name) then
                    return false
                end
                actor.cell = destination
                return true
            end,
        },
        cells = cells,
    }
end

return function()
    local previousStep, previousThink = Errands.stepSeconds, Errands.thinkSeconds
    Errands.stepSeconds, Errands.thinkSeconds = 0, 0

    local sandbox = apartment()
    local state = Round.new(Setup.actors, 13, Setup.rules)
    expect(Flow.advance(Round, Policy, state), "morning must advance")
    expect(state.phase == "action_one", "expected the first action window")

    local id = #state.items + 1
    table.insert(state.items, {
        id = id,
        kind = "dishes",
        creator = "red",
        age = 2,
        resolved = false,
        stage = "open",
        day = state.day,
    })
    state.actors.green.cash = 20
    state.revision += 1

    local commits = 0
    local notified = 0
    local session = { state = state }
    local errands = Errands.new({
        sandbox = sandbox,
        round = Round,
        policy = Policy,
        routine = Routine,
        beans = Setup.beans,
        commit = function(target: any, actor: string, action: any): boolean
            local ok = Round.decide(target.state, actor, target.state.revision, action, nil)
            if ok then
                commits += 1
            end
            return ok
        end,
        changed = function()
            notified += 1
        end,
    })

    local cash = state.actors.green.cash
    for _ = 1, 60 do
        errands.update(session)
    end
    local item
    for _, candidate in state.items do
        if candidate.id == id then
            item = candidate
        end
    end
    expect(item.resolved, "a roommate must actually clear the mess it walked to")
    expect(
        state.actors.green.cash == cash - state.config.cleanup,
        "the cleanup was paid for through the round, not conjured"
    )
    expect(commits >= 1 and notified >= 1, "committing an errand refreshes the client")

    -- One action each: the budget is the round's, not the errand loop's.
    expect(Round.actionBudget(state, "green") == 0, "the roommate spent its one action")
    local before = commits
    for _ = 1, 40 do
        errands.update(session)
    end
    expect(commits == before, "an errand is never committed twice")

    ------------------------------------------------ they go home between windows

    expect(Flow.advance(Round, Policy, state), "the window must close")
    expect(state.phase == "work", "expected the work shift")
    for _ = 1, 80 do
        errands.update(session)
    end
    for _, data in config.roommates do
        expect(
            Grid.key(sandbox.cells[data.name].cell) == Grid.key({ c = data.c, r = data.r }),
            data.name .. " did not return to its own tile between windows"
        )
    end

    ------------------------------------------- a finished household stands still

    state.status = "evicted"
    local resting = {}
    for name, actor in sandbox.cells do
        resting[name] = Grid.key(actor.cell)
    end
    for _ = 1, 20 do
        errands.update(session)
    end
    for name, key in resting do
        expect(
            Grid.key(sandbox.cells[name].cell) == key,
            name .. " moved after the household ended"
        )
    end

    ------------------------------------------------------- the switch turns it off
    local still = apartment()
    still.roommates.enabled = false
    local quiet = Errands.new({
        sandbox = still,
        round = Round,
        policy = Policy,
        routine = Routine,
        beans = Setup.beans,
        commit = function(): boolean
            error("a disabled errand loop must not act")
        end,
        changed = function()
            error("a disabled errand loop must not notify")
        end,
    })
    local other = { state = Round.new(Setup.actors, 13, Setup.rules) }
    Flow.advance(Round, Policy, other.state)
    for _ = 1, 20 do
        quiet.update(other)
    end
    for _, data in config.roommates do
        expect(
            Grid.key(still.cells[data.name].cell) == Grid.key({ c = data.c, r = data.r }),
            "a disabled roommate never leaves its tile"
        )
    end

    Errands.stepSeconds, Errands.thinkSeconds = previousStep, previousThink
end
