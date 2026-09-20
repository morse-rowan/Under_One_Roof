--!strict
-- Where roommates walk during an action window, and whether they can get there.
-- Pure grid and rules only: the beans, the hop animation and the client's view of
-- them are Roblox behaviour and still need a Studio playtest.
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")
local Policy = require("../src/shared/RoundPolicy")
local Flow = require("../src/shared/HousepadFlow")
local Grid = require("../src/shared/GridMovement")
local World = require("../src/shared/RoundWorld")
local Routine = require("../src/shared/RoundRoutine")
local config = require("../src/shared/VisualStudy")

local function expect(condition: any, message: string)
    assert(condition, message)
end

local walkable = Grid.blocked(config, false)
local parked = Grid.blocked(config, true)

-- Walk a roommate to its goal the way the server does: one step of the path per
-- beat, recomputing each time. Returns the cell it ended on and the step count.
local function walk(from: any, goal: any): (any, number)
    local cell = { c = from.c, r = from.r }
    for steps = 1, 60 do
        if Grid.key(cell) == Grid.key(goal) then
            return cell, steps - 1
        end
        local path = Routine.path(config, cell, goal, walkable)
        expect(path ~= nil, "no route from " .. Grid.key(cell) .. " to " .. Grid.key(goal))
        local next = Grid.destination(config, cell, (path :: any)[1], walkable)
        expect(next ~= nil, "the path proposed a step the grid refuses")
        cell = next :: any
    end
    error("the roommate never arrived at " .. Grid.key(goal))
end

return function()
    -------------------------------------------------------------- the walkable set

    for _, roommate in config.roommates do
        local home = { c = roommate.c, r = roommate.r }
        expect(parked[Grid.key(home)], "a parked roommate blocks its own tile")
        expect(not walkable[Grid.key(home)], "a walking roommate must not block itself")
    end
    -- Litter placement must not move: it reads the default, roommates included.
    expect(
        Grid.key(World.litterCell(config, 3)) == Grid.key(World.litterCell(config, 3)),
        "litter placement is stable"
    )

    ------------------------------------------------------------------------ paths

    expect(#(Routine.path(config, { c = 1, r = 1 }, { c = 1, r = 1 }, walkable) :: any) == 0)
    local across = Routine.path(config, { c = 1, r = 1 }, { c = 10, r = 1 }, walkable)
    expect(across ~= nil, "the two rooms must be connected")
    -- The only link is the doorway row, so any crossing has to pass through it.
    local cell = { c = 1, r = 1 }
    local usedDoorway = false
    for _, direction in across :: any do
        local next = Grid.destination(config, cell, direction, walkable) :: any
        expect(next ~= nil, "every step of a path is a legal hop")
        if Grid.room(config, cell) ~= Grid.room(config, next) then
            usedDoorway = cell.r == config.doorwayRow
        end
        cell = next
    end
    expect(usedDoorway, "crossing rooms must use the doorway row")
    expect(Grid.key(cell) == "10,1", "the path ends at the goal")
    expect(
        Routine.path(config, { c = 1, r = 1 }, { c = 2, r = 0 }, walkable) == nil,
        "a fixture tile has no route: you stand beside it"
    )

    ------------------------------------------------------------------- stations

    expect(
        Grid.key(Routine.station(config, { kind = "contribute", amount = 5 }, {}) :: any) == "3,2",
        "rent is settled at the kitchen table"
    )
    local dishes = { id = 4, kind = "dishes", creator = "red", age = 0, resolved = false }
    expect(
        Grid.key(
            Routine.station(config, { kind = "pay_cleanup", reference = 4 }, { dishes }) :: any
        ) == "2,0",
        "dishes belong at the sink"
    )
    expect(Routine.station(config, { kind = "wait" }, {}) == nil, "waiting needs no journey")
    expect(Routine.station(config, nil, {}) == nil, "a missing action needs no journey")
    expect(
        Routine.station(config, { kind = "pay_cleanup", reference = 99 }, { dishes }) == nil,
        "an unknown issue has no station"
    )

    local beside = Routine.approach(config, { c = 2, r = 0 }, walkable)
    expect(beside and not walkable[Grid.key(beside)], "the approach tile is walkable")
    expect(World.adjacent(beside, { c = 2, r = 0 }), "the approach tile touches the station")
    local litter = World.litterCell(config, 7)
    local occupied = table.clone(walkable)
    occupied["4,2"] = true -- Amber's home beside the rent table.
    local from = { c = 2, r = 3 }
    local rentApproach = Routine.approach(config, { c = 3, r = 2 }, occupied, from)
    expect(
        rentApproach ~= nil and Grid.key(rentApproach) == "2,2",
        "use the reachable side of the rent table"
    )
    expect(Routine.path(config, from, rentApproach, occupied) ~= nil, "do not route through Amber")
    expect(
        Grid.key(Routine.approach(config, litter, walkable) :: any) == Grid.key(litter),
        "floor litter is stood on, not approached"
    )

    ------------------------------------------- every errand is somewhere reachable

    for _, roommate in config.roommates do
        local home = { c = roommate.c, r = roommate.r }
        for _, station in { { c = 2, r = 0 }, { c = 5, r = 0 }, { c = 3, r = 2 } } do
            local goal = Routine.approach(config, station, walkable)
            expect(goal ~= nil, "no approach tile for " .. Grid.key(station))
            local landed, steps = walk(home, goal :: any)
            expect(Grid.key(landed) == Grid.key(goal :: any), "the roommate arrived")
            -- Zero is legitimate: Amber already stands beside the kitchen table.
            expect(steps >= 0 and steps < 40, "the walk is a sane length: " .. steps)
            walk(landed, home)
        end
    end

    --------------------------------------------------- errands from a real round

    local state = Round.new(Setup.actors, 13, Setup.rules)
    Flow.advance(Round, Policy, state)
    expect(state.phase == "action_one", "expected the first action window")
    local id = #state.items + 1
    table.insert(state.items, {
        id = id,
        kind = "dishes",
        -- Red's mess: green may pay to clear it and the player may wash it.
        creator = "red",
        age = 2,
        resolved = false,
        stage = "open",
        day = state.day,
    })
    state.actors.green.cash = 20
    state.revision += 1

    local home = { c = config.roommates[1].c, r = config.roommates[1].r }
    local errand = Routine.errand(config, Round.observe(state, "green"), Policy, home, walkable)
    expect(errand.action ~= nil, "a roommate with money and a dirty sink has something to do")
    expect(errand.action.kind == "pay_cleanup" and errand.action.reference == id)
    expect(World.adjacent(errand.goal, { c = 2, r = 0 }), "it walks to the sink")
    expect(
        Routine.stillLegal(Round.observe(state, "green"), errand.action),
        "the errand it just picked is legal"
    )

    -- The player clears the mess first: the errand must retire, not be forced.
    expect(
        Round.decide(state, Setup.player, state.revision, {
            kind = "finish_chore",
            reference = id,
        }, nil),
        "the player can finish the chore"
    )
    expect(
        not Routine.stillLegal(Round.observe(state, "green"), errand.action),
        "a cleared mess retires the errand"
    )
    local replacement =
        Routine.errand(config, Round.observe(state, "green"), Policy, home, walkable)
    expect(Grid.key(replacement.goal) ~= "", "a replacement errand still has a destination")
    expect(
        replacement.action == nil
            or Routine.stillLegal(Round.observe(state, "green"), replacement.action),
        "a replacement errand is legal or empty"
    )

    -- A roommate that cannot afford anything simply stays on its own tile.
    state.actors.red.cash = 0
    state.revision += 1
    local broke = Routine.errand(
        config,
        Round.observe(state, "red"),
        Policy,
        { c = config.roommates[2].c, r = config.roommates[2].r },
        walkable
    )
    expect(Grid.key(broke.goal) == "11,2", "a roommate with nothing to do goes home")
end
