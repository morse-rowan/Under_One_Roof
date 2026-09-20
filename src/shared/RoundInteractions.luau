--!strict
-- Audience-filtered physical interactions for the action phase. This module only
-- consumes the observation sent to one actor; private plans never cross this seam.
local World = require(if script then script.Parent.RoundWorld else "./RoundWorld")
local Grid = require(if script then script.Parent.GridMovement else "./GridMovement")

local Interactions = {}

export type Cell = { c: number, r: number }

-- A clue has a stable, walkable location derived from its public reference.
function Interactions.clueCell(config: any, reference: number): Cell
    local cells = World.floorCells(config)
    local pick = (reference * 7919 + 104729) % 2147483647
    return cells[1 + pick % #cells]
end

-- Markers are generated only from legal, already-filtered inspect candidates.
function Interactions.markers(config: any, o: any): { any }
    local out = {}
    for _, candidate in o.candidates or {} do
        if candidate.kind == "inspect" and type(candidate.reference) == "number" then
            table.insert(out, {
                reference = candidate.reference,
                cell = Interactions.clueCell(config, candidate.reference),
                label = "! Clue #" .. tostring(candidate.reference),
                kind = "inspect",
            })
        end
    end
    return out
end

-- Chores retain priority. If none is reachable, expose the first legal clue at
-- the actor's cell, with the same action/prompt shape plus its world cell.
function Interactions.reachable(config: any, o: any, cell: Cell?): any?
    local actor = o.actor and o.actor.id
    local chore = World.reachable(config, o.items or {}, cell, o.candidates or {}, actor)
    if chore then
        return chore
    end
    for _, marker in Interactions.markers(config, o) do
        if World.adjacent(cell, marker.cell) then
            return {
                action = { kind = "inspect", reference = marker.reference },
                prompt = "Investigate clue #" .. tostring(marker.reference),
                cell = marker.cell,
            }
        end
    end
    return nil
end

function Interactions.targets(config: any, o: any, cell: Cell?): { any }
    local out = {}
    if not cell then
        return out
    end
    local function add(reference, target, prompt)
        if target then
            table.insert(out, {
                reference = reference,
                prompt = prompt,
                room = Grid.room(config, target),
                distance = math.abs(cell.c - target.c) + math.abs(cell.r - target.r),
            })
        end
    end
    for _, candidate in o.candidates do
        if candidate.kind == "inspect" then
            add(
                candidate.reference,
                Interactions.clueCell(config, candidate.reference),
                "! Clue #" .. candidate.reference
            )
        elseif candidate.kind == "pickup_trash" or candidate.kind == "finish_chore" then
            for _, item in o.items do
                if item.id == candidate.reference then
                    local prompt = if item.kind == "dishes"
                        then "Wash dishes"
                        elseif item.stage == "open" then "Bag trash"
                        else "Take bag to bin"
                    add(item.id, World.actionCell(config, item), prompt .. " · #" .. item.id)
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return if a.distance == b.distance then a.prompt < b.prompt else a.distance < b.distance
    end)
    return out
end

return Interactions
