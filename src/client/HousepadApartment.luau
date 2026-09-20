--!strict
-- Compact in-world guidance, using the same tablet widgets as the main interface.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(shared:WaitForChild("RoundText"))
local Guide = require(shared:WaitForChild("RoundGuide"))
local Kit = require(script.Parent.MenuKit)
local Apartment = {}

function Apartment.render(canvas: Instance, payload: any, actions: any, ui: any)
    local o, c = payload.observation, ui.palette
    local panel = ui.frame(canvas, "ApartmentAgenda", 928, 170, 300, 360, c.paper)
    local summary = Guide.summary(o)
    ui.label(panel, "Around the apartment", 14, 10, 270, 26, 18, c.ink, true)
    ui.label(panel, summary.choices, 14, 39, 270, 22, 13, c.good, true)
    local list = Kit.scroller(panel, {
        Name = "WorldTasks",
        Position = UDim2.fromOffset(12, 70),
        Size = UDim2.fromOffset(278, 171),
    })
    Kit.column(list, 7)
    local targets = payload.targets or {}
    for index, target in targets do
        local row = ui.frame(list, "Target_" .. index, 0, 0, 264, 56, c.rail, 10)
        row.LayoutOrder = index
        ui.label(row, target.prompt, 9, 5, 246, 24, 13, c.ink, true)
        ui.label(
            row,
            target.room .. " · " .. target.distance .. " tiles away",
            9,
            30,
            246,
            18,
            11,
            c.muted
        )
    end
    if #targets == 0 then
        ui.label(
            list,
            if (o.actionsRemaining or 0) == 0
                then "Choices used up. Continue to see the consequences."
                else "No chores or clues to reach. Open HousePad for money and prevention choices.",
            4,
            0,
            260,
            85,
            13,
            c.muted
        )
    end
    ui.label(panel, "JUST HAPPENED", 14, 252, 270, 16, 10, c.muted, true)
    local latest = "Walk to a gold ! to investigate. Press E next to a chore to help."
    for index = #o.events, 1, -1 do
        local event = o.events[index]
        if event.day == o.day and event.phase == o.phase and event.kind ~= "message" then
            local line = Text.line(event, o.actor.id)
            if line then
                latest = line
                break
            end
        end
    end
    ui.label(panel, latest, 14, 273, 270, 73, 13, c.ink)
    local hint = ui.frame(canvas, "ApartmentControls", 42, 540, 760, 72, c.paper)
    ui.label(
        hint,
        if payload.reachable
            then "[E] " .. payload.reachable.prompt
            else "WASD / arrows to move · E at a chore or gold !",
        16,
        8,
        730,
        26,
        16,
        c.ink,
        true
    )
    ui.label(
        hint,
        "M opens HousePad · T resolves this phase · no clock is running",
        16,
        40,
        730,
        19,
        12,
        c.muted
    )
    ui.button(canvas, "OpenPad", "Open HousePad [M]", 881, 548, 347, 48, true, actions.apartment)
end

return Apartment
