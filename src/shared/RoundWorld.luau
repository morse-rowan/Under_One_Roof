--!strict
-- Puts abstract `MvpRound` issues somewhere in the apartment and says where the
-- player has to stand to touch them. Pure: it reads the grid config and an issue
-- record, never a rendered part, so the server stays the authority on reach.
local Grid = require(if script then script.Parent.GridMovement else "./GridMovement")

local World = {}

export type Cell = { c: number, r: number }

-- Fixture each issue kind belongs to. Trash is the one two-step chore: the pile
-- starts on the floor and only the bin finishes it (contract M06).
World.stations = {
    dishes = "Sink",
    leak = "Sink",
    roaches = "Trash",
    trash = "Trash",
}

function World.fixture(config: any, name: string): Cell?
    for _, item in config.fixtures do
        if item.name == name then
            return { c = item.c, r = item.r }
        end
    end
    return nil
end

-- Walkable cells in a stable order, used to scatter floor litter reproducibly.
function World.floorCells(config: any): { Cell }
    local blocked = Grid.blocked(config)
    local cells = {}
    for c = 0, config.columns - 1 do
        for r = 0, config.rows - 1 do
            local cell = { c = c, r = r }
            if not blocked[Grid.key(cell)] then
                table.insert(cells, cell)
            end
        end
    end
    return cells
end

-- Same issue ID always lands on the same tile, so a replayed round looks the same.
function World.litterCell(config: any, id: number): Cell
    local cells = World.floorCells(config)
    local pick = (id * 7919 + 104729) % 2147483647
    return cells[1 + pick % #cells]
end

-- Where the prop rests when nobody is holding it. A bagged sack stays where it was
-- tied up: only carrying it to the bin finishes the chore.
function World.homeCell(config: any, item: any): Cell?
    if item.kind == "trash" then
        return World.litterCell(config, item.id)
    end
    local station = World.stations[item.kind]
    return if station then World.fixture(config, station) else nil
end

-- Where the player must stand next to for the physical chore. Leaks and roaches
-- have no player-side chore: they are paid service only.
function World.actionCell(config: any, item: any): Cell?
    if item.kind == "dishes" then
        return World.fixture(config, "Sink")
    elseif item.kind == "trash" then
        return if item.stage == "open"
            then World.litterCell(config, item.id)
            else World.fixture(config, "Trash")
    end
    return nil
end

function World.adjacent(a: Cell?, b: Cell?): boolean
    if not a or not b then
        return false
    end
    return math.abs(a.c - b.c) + math.abs(a.r - b.r) <= 1
end

-- The single hands-on action available for an issue, matching `MvpRound.candidates`.
function World.chore(item: any): any?
    if item.resolved then
        return nil
    elseif item.kind == "dishes" then
        return { kind = "finish_chore", reference = item.id }
    elseif item.kind == "trash" then
        return if item.stage == "open"
            then { kind = "pickup_trash", reference = item.id }
            else { kind = "finish_chore", reference = item.id }
    end
    return nil
end

World.prompts = {
    pickup_trash = "Bag the trash",
    finish_chore = "Finish the chore",
}

-- The reachable chore for `actor` right now, or nil. `candidates` keeps this
-- honest: the world never offers something the rules would reject.
function World.reachable(config: any, items: any, cell: Cell?, candidates: any, actor: string): any?
    for _, item in items do
        local chore = World.chore(item)
        if
            chore
            and item.creator ~= actor
            and World.adjacent(cell, World.actionCell(config, item))
        then
            for _, candidate in candidates do
                if candidate.kind == chore.kind and candidate.reference == chore.reference then
                    return {
                        item = item,
                        action = chore,
                        prompt = if item.kind == "trash" and item.stage == "open"
                            then World.prompts.pickup_trash
                            elseif item.kind == "trash" then "Take the bag out"
                            else "Wash the dishes",
                    }
                end
            end
        end
    end
    return nil
end

return World
