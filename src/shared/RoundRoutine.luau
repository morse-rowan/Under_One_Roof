--!strict
-- What a roommate physically does during an action window.
--
-- The action windows used to be the player's alone: the roommates stood still and
-- their choices appeared, already resolved, when the player pressed Continue. This
-- module gives each roommate an errand instead — a legal action it has picked, and
-- the tile it has to reach to carry it out — so the player can watch someone cross
-- the kitchen and clear the sink while the window is still open.
--
-- Deliberately deterministic and separate from `RoundBrain`. The errand comes from
-- `RoundPolicy`, so the apartment behaves the same with or without a model, and
-- turning inference off changes what roommates say and choose at the stops, not
-- whether the place looks alive. Pure: no Roblox service, no rendered part. The
-- server still replays the action through `MvpRound`, which owns legality.
local Grid = require(if script then script.Parent.GridMovement else "./GridMovement")
local World = require(if script then script.Parent.RoundWorld else "./RoundWorld")

local Routine = {}

Routine.version = "roommate-routine-1"

-- Fixed order, so an identical round produces identical walking.
local DIRECTIONS = { "up", "right", "down", "left" }

export type Cell = { c: number, r: number }

local function itemById(items: any, id: any): any?
    for _, item in items or {} do
        if item.id == id then
            return item
        end
    end
    return nil
end

-- The tile an errand happens at, or nil for an action that needs no journey.
-- Rent goes to the kitchen table, which is where the household's money is settled;
-- cleanup goes to the mess itself, or to the fixture it belongs to.
function Routine.station(config: any, action: any, items: any): Cell?
    if type(action) ~= "table" then
        return nil
    end
    if action.kind == "contribute" then
        return World.fixture(config, "KitchenTable")
    end
    if action.kind == "pay_cleanup" then
        local item = itemById(items, action.reference)
        return if item then World.homeCell(config, item) else nil
    end
    return nil
end

-- Somewhere the roommate can actually stand to reach `station`: the tile itself when
-- it is floor, otherwise the first free neighbour in the fixed direction order. A
-- fixture is never walkable, so cleaning the sink means standing beside it.
function Routine.approach(config: any, station: Cell?, blocked: any): Cell?
    if not station then
        return nil
    end
    if not blocked[Grid.key(station)] then
        return station
    end
    for _, direction in DIRECTIONS do
        local neighbour = Grid.destination(config, station, direction, blocked)
        if neighbour then
            return neighbour
        end
    end
    return nil
end

-- Breadth-first over the same `Grid.destination` the player's hops use, so the
-- doorway rule and the room boundary are respected by construction. Returns the
-- directions to walk, shortest first and deterministic; an empty list means
-- "already there", and nil means no route exists right now.
function Routine.path(config: any, from: Cell, goal: Cell, blocked: any): { string }?
    if Grid.key(from) == Grid.key(goal) then
        return {}
    end
    local queue = { from }
    local cameFrom: { [string]: { cell: Cell, direction: string } } = {}
    local seen = { [Grid.key(from)] = true }
    local head = 1
    while head <= #queue do
        local cell = queue[head]
        head += 1
        for _, direction in DIRECTIONS do
            local nextCell = Grid.destination(config, cell, direction, blocked)
            if nextCell and not seen[Grid.key(nextCell)] then
                seen[Grid.key(nextCell)] = true
                cameFrom[Grid.key(nextCell)] = { cell = cell, direction = direction }
                if Grid.key(nextCell) == Grid.key(goal) then
                    local steps = {}
                    local walk = Grid.key(goal)
                    while cameFrom[walk] do
                        table.insert(steps, 1, cameFrom[walk].direction)
                        walk = Grid.key(cameFrom[walk].cell)
                    end
                    return steps
                end
                table.insert(queue, nextCell)
            end
        end
    end
    return nil
end

-- Pick this window's errand. `observation` is the roommate's own audience-filtered
-- view, so it can only chase a mess it is actually allowed to know about, and
-- `candidates` means the action is legal at the moment it is picked.
--
-- A roommate with nothing to walk to goes home and waits: an idle wander would read
-- as activity the round never took.
function Routine.errand(config: any, observation: any, policy: any, home: Cell, blocked: any): any
    local decision = policy.decide(observation, policy.styleFor(observation.actor.id), false)
    local action = decision.action
    local station = Routine.station(config, action, observation.items)
    local goal = Routine.approach(config, station, blocked)
    if not goal then
        -- Includes `wait`, `cancel_plan` and anything with no place in the room.
        return { action = if station then nil else action, goal = home, station = nil }
    end
    return { action = action, goal = goal, station = station }
end

-- Is the errand still worth walking? A mess the player cleared first, or an action
-- the round would now refuse, retires the errand rather than finishing it silently.
function Routine.stillLegal(observation: any, action: any): boolean
    if type(action) ~= "table" then
        return false
    end
    for _, candidate in observation.candidates do
        if
            candidate.kind == action.kind
            and candidate.reference == action.reference
            and candidate.amount == action.amount
        then
            return true
        end
    end
    return false
end

function Routine.arrived(cell: Cell?, goal: Cell?): boolean
    return cell ~= nil and goal ~= nil and Grid.key(cell) == Grid.key(goal)
end

return Routine
