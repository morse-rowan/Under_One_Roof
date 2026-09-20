--!strict
local Interactions = require("../src/shared/RoundInteractions")
local World = require("../src/shared/RoundWorld")
local Grid = require("../src/shared/GridMovement")
local Visual = require("../src/shared/VisualStudy")

local function expect(condition: any, message: string)
    assert(condition, message)
end

return function()
    local first = Interactions.clueCell(Visual, 7)
    local second = Interactions.clueCell(Visual, 7)
    local blocked = Grid.blocked(Visual)
    expect(Grid.key(first) == Grid.key(second), "clue locations are deterministic")
    expect(not blocked[Grid.key(first)], "clue location is walkable")

    local observation = {
        actor = { id = "blue" },
        items = {},
        candidates = {
            { kind = "inspect", reference = 7 },
            { kind = "wait" },
        },
    }
    local markers = Interactions.markers(Visual, observation)
    expect(#markers == 1, "only legal inspect candidates get markers")
    expect(
        markers[1].label == "! Clue #7" and markers[1].kind == "inspect",
        "clue marker has the public label and kind"
    )
    expect(markers[1].owner == nil, "clue marker does not expose an owner")

    local clueCell = markers[1].cell
    local nearby = Interactions.reachable(Visual, observation, clueCell)
    expect(nearby ~= nil and nearby.action.kind == "inspect", "adjacent clue is reachable")
    expect(nearby.prompt == "Investigate clue #7", "clue has an investigation prompt")
    local afar = {
        c = if clueCell.c < 6 then clueCell.c + 4 else clueCell.c - 4,
        r = clueCell.r,
    }
    expect(
        Interactions.reachable(Visual, observation, afar) == nil,
        "an afar clue is not reachable"
    )

    local noBudget = {
        actor = { id = "blue" },
        items = {},
        candidates = {},
    }
    expect(#Interactions.markers(Visual, noBudget) == 0, "no action budget means no clue marker")
    expect(
        Interactions.reachable(Visual, noBudget, clueCell) == nil,
        "no budget means no clue action"
    )

    local chores = {
        actor = { id = "blue" },
        items = {
            { id = 3, kind = "dishes", creator = "green", resolved = false },
        },
        candidates = {
            { kind = "finish_chore", reference = 3 },
            { kind = "inspect", reference = 7 },
        },
    }
    local sink = World.fixture(Visual, "Sink")
    local chore = Interactions.reachable(Visual, chores, sink)
    expect(chore ~= nil and chore.action.kind == "finish_chore", "chores retain priority")

    local inspected = {
        actor = { id = "blue" },
        items = {},
        candidates = { { kind = "wait" } },
    }
    expect(#Interactions.markers(Visual, inspected) == 0, "inspected clue has no marker")
end
