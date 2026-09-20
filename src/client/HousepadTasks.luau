--!strict
-- Uses the existing HousePad widget vocabulary for the playable action checklist.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Guide = require(shared:WaitForChild("RoundGuide"))
local Kit = require(script.Parent.MenuKit)
local Tasks = {}

function Tasks.render(parent: Instance, o: any, actions: any, ui: any)
    local c = ui.palette
    local summary = Guide.summary(o)
    local panel = ui.frame(parent, "ActionTasks", 240, 170, 627, 430)
    ui.label(panel, "Make yourself at home", 22, 14, 580, 32, 25, c.ink, true)
    ui.label(panel, summary.choices .. " · " .. summary.rent, 22, 52, 580, 22, 14, c.good, true)
    ui.label(panel, summary.hint, 22, 80, 580, 35, 12, c.muted)
    local inspection = ui.frame(panel, "Inspection", 20, 123, 587, 35, c.rail, 10)
    ui.label(inspection, summary.inspection, 12, 0, 563, 35, 12, c.ink, true)
    local scroll = Kit.scroller(panel, {
        Name = "TaskList",
        Position = UDim2.fromOffset(20, 169),
        Size = UDim2.fromOffset(587, 241),
    })
    Kit.column(scroll, 9)
    local tasks = Guide.tasks(o)
    if #tasks == 0 then
        ui.label(
            scroll,
            "The apartment is tidy for now.\nInvestigate a clue, contribute to rent, or keep your money.\nContinue to see what the household does next.",
            12,
            20,
            551,
            100,
            16,
            c.muted
        )
    end
    for i, task in tasks do
        local row = ui.frame(scroll, "Task_" .. task.id, 0, 0, 571, 112, c.rail, 12)
        row.LayoutOrder = i
        ui.label(row, task.title, 14, 10, 360, 22, 16, c.ink, true)
        ui.label(row, task.detail, 14, 39, 535, 56, 13, c.muted)
        if task.canWalk then
            ui.button(row, "Walk", "Go do it [M]", 395, 8, 160, 29, true, actions.apartment)
        end
    end
end

return Tasks
