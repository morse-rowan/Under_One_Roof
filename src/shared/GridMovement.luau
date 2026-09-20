--!strict
-- Engine-independent authority: never derive walkability from rendered parts.
local Grid = {}
export type Cell = { c: number, r: number }
export type Actor = { cell: Cell, target: Cell?, landsAt: number }
local directions = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

function Grid.key(cell: Cell): string
    return cell.c .. "," .. cell.r
end

function Grid.room(config: any, cell: Cell): string
    return if cell.c < config.roomColumns then "Kitchen" else "Lounge"
end

function Grid.point(config: any, cell: Cell): (number, number)
    return (cell.c - (config.columns - 1) / 2) * config.cellSize,
        (cell.r - (config.rows - 1) / 2) * config.cellSize
end

-- Furniture, and by default the roommates' standing spots. Pass `false` once the
-- roommates walk: their cells are then reserved dynamically like any other actor's,
-- and treating them as permanent walls would trap them where they started.
-- Everything that scatters litter keeps the default, so issue placement is unchanged.
function Grid.blocked(config: any, includeRoommates: boolean?): { [string]: boolean }
    local result = {}
    for _, fixture in config.fixtures do
        for c = fixture.c, fixture.c + fixture.w - 1 do
            for r = fixture.r, fixture.r + fixture.h - 1 do
                result[Grid.key({ c = c, r = r })] = true
            end
        end
    end
    if includeRoommates ~= false then
        for _, roommate in config.roommates do
            result[Grid.key(roommate)] = true
        end
    end
    return result
end

function Grid.destination(
    config: any,
    cell: Cell,
    direction: any,
    blocked: { [string]: boolean }
): Cell?
    local delta = if type(direction) == "string" then directions[direction] else nil
    if not delta then
        return nil
    end
    local nextCell = { c = cell.c + delta[1], r = cell.r + delta[2] }
    if
        nextCell.c < 0
        or nextCell.c >= config.columns
        or nextCell.r < 0
        or nextCell.r >= config.rows
    then
        return nil
    end
    if Grid.room(config, cell) ~= Grid.room(config, nextCell) and cell.r ~= config.doorwayRow then
        return nil
    end
    return if blocked[Grid.key(nextCell)] then nil else nextCell
end

function Grid.finish(actor: Actor, now: number): boolean
    if actor.target and now >= actor.landsAt then
        actor.cell = actor.target
        actor.target = nil
        return true
    end
    return false
end

function Grid.begin(
    config: any,
    actor: Actor,
    direction: any,
    now: number,
    blocked: { [string]: boolean },
    actors: { [any]: Actor }
): Cell?
    if actor.target then
        return nil
    end
    local destination = Grid.destination(config, actor.cell, direction, blocked)
    if not destination then
        return nil
    end
    -- Reserve source and destination until landing: no overlap or swaps mid-hop.
    for _, other in actors do
        if
            other ~= actor
            and (
                Grid.key(other.cell) == Grid.key(destination)
                or (other.target and Grid.key(other.target) == Grid.key(destination))
            )
        then
            return nil
        end
    end
    actor.target = destination
    actor.landsAt = now + config.hopSeconds
    return destination
end

return Grid
