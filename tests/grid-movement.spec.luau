--!strict
local Grid = require("../src/shared/GridMovement")
local config = require("../src/shared/VisualStudy")

return function()
    local blocked = Grid.blocked(config)
    local function actor(c: number, r: number): any
        return { cell = { c = c, r = r }, target = nil, landsAt = 0 }
    end
    local blue = actor(2, 4)
    local actors = { blue = blue }
    assert(Grid.begin(config, blue, "up", 0, blocked, actors), "One adjacent step must start")
    assert(blue.cell.r == 4, "Logical cell stays at source until landing")
    assert(not Grid.begin(config, blue, "left", 0.05, blocked, actors), "No mid-hop queue")
    assert(not Grid.finish(blue, 0.129), "Cannot finish early")
    assert(Grid.finish(blue, 0.13), "Must land on time")
    assert(blue.cell.r == 3 and not blue.target, "Landing commits exact destination")
    assert(not Grid.finish(blue, 1), "Landing is applied once")
    assert(not Grid.destination(config, { c = 2, r = 1 }, "up", blocked), "Sink blocks entry")
    assert(not Grid.destination(config, { c = 1, r = 2 }, "up", blocked), "Roommate blocks entry")
    assert(
        not Grid.destination(config, { c = 0, r = 4 }, "left", blocked),
        "Room bounds block entry"
    )
    assert(not Grid.destination(config, blue.cell, "diagonal", blocked), "No diagonal requests")
    assert(not Grid.destination(config, blue.cell, {}, blocked), "Malformed input is inert")
    assert(not Grid.destination(config, { c = 5, r = 2 }, "right", {}), "Cannot cross divider")
    local entrance = Grid.destination(config, { c = 5, r = 4 }, "right", blocked)
    assert(entrance and entrance.c == 6 and entrance.r == 4, "Door connects adjacent cells")
    local exit = Grid.destination(config, entrance, "left", blocked)
    assert(exit and exit.c == 5, "Door works both ways")
    local x1, z1 = Grid.point(config, { c = 5, r = 4 })
    local x2, z2 = Grid.point(config, entrance)
    assert(x2 - x1 == config.cellSize and z1 == z2, "Door retains grid scale")

    local a, b = actor(2, 4), actor(4, 4)
    local traffic = { a, b }
    assert(Grid.begin(config, a, "right", 2, blocked, traffic))
    assert(not Grid.begin(config, b, "left", 2, blocked, traffic), "Reserve in-flight destination")
    b.cell = { c = 1, r = 4 }
    assert(not Grid.begin(config, b, "right", 2, blocked, traffic), "Reserve in-flight source")
    assert(Grid.finish(a, 3))
    assert(Grid.begin(config, b, "right", 3, blocked, traffic), "Release source on landing")

    -- Every unoccupied floor tile must be reachable, including both room entrances.
    local queue = { config.spawn }
    local seen = { [Grid.key(config.spawn)] = true }
    local index = 1
    while index <= #queue do
        local cell = queue[index]
        index += 1
        for _, direction in { "up", "right", "down", "left" } do
            local nextCell = Grid.destination(config, cell, direction, blocked)
            if nextCell and not seen[Grid.key(nextCell)] then
                seen[Grid.key(nextCell)] = true
                table.insert(queue, nextCell)
            end
        end
    end
    for c = 0, config.columns - 1 do
        for r = 0, config.rows - 1 do
            local key = Grid.key({ c = c, r = r })
            assert(blocked[key] or seen[key], "Unreachable floor tile " .. key)
        end
    end
end
