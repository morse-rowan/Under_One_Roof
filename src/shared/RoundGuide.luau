--!strict
-- Player-facing guidance derived only from the current audience-filtered state.
local Text = require(if script then script.Parent.RoundText else "./RoundText")
local Guide = {}

local names = { dishes = "Dishes", trash = "Trash", leak = "Leaking sink", roaches = "Roaches" }

function Guide.choice(action: any, o: any): string
    if action.kind == "inspect" then
        return "Investigate clue #" .. action.reference
    elseif action.kind == "request_cancel" then
        for _, plan in o.plans do
            if plan.id == action.reference then
                return "Ask " .. Text.name(plan.actor) .. " to cancel " .. plan.kind
            end
        end
    elseif action.kind == "pay_cleanup" then
        for _, item in o.items do
            if item.id == action.reference then
                return string.format(
                    "%s service · $%d · #%d",
                    names[item.kind] or item.kind,
                    action.amount,
                    item.id
                )
            end
        end
    elseif action.kind == "wait" then
        return "Keep my money · spend 1 choice"
    end
    return Text.action(action)
end

function Guide.tasks(o: any): { any }
    local tasks = {}
    for _, item in o.items do
        if not item.resolved then
            local physical, service
            for _, action in o.candidates do
                if action.reference == item.id then
                    if action.kind == "finish_chore" or action.kind == "pickup_trash" then
                        physical = action
                    elseif action.kind == "pay_cleanup" then
                        service = action
                    end
                end
            end
            local instruction
            if item.creator == o.actor.id then
                instruction = "Your mess needs another roommate's help."
            elseif item.kind == "dishes" then
                instruction = "Walk to the kitchen sink. Press E to wash."
            elseif item.kind == "trash" and item.stage == "bagged" then
                instruction = "Take the bag to the kitchen bin. Press E to finish."
            elseif item.kind == "trash" then
                instruction =
                    "Press E at the floor pile, then E at the kitchen bin. Two choices total."
            else
                instruction = "Needs a paid service. Use the matching choice on the right."
            end
            if item.creator ~= o.actor.id and not physical and not service then
                instruction ..= if (o.actionsRemaining or 0) == 0
                    then " Choices reopen next phase."
                    else " You need more money for the service."
            end
            table.insert(tasks, {
                id = item.id,
                title = string.format("%s · #%d", names[item.kind] or item.kind, item.id),
                detail = instruction,
                canWalk = physical ~= nil,
                age = item.age,
            })
        end
    end
    table.sort(tasks, function(a, b)
        return if a.age == b.age then a.id < b.id else a.age > b.age
    end)
    return tasks
end

function Guide.summary(o: any): any
    local remaining = o.actionsRemaining or 0
    local inspection = if o.day == o.rules.inspectionDay
        then string.format(
            "Inspection today · aim for %d cleanliness",
            o.rules.inspectionCleanliness
        )
        else string.format("Scheduled inspection: day %d", o.rules.inspectionDay)
    if o.day > o.rules.inspectionDay then
        inspection = "Surprise inspections can still happen"
    end
    for _, event in o.events do
        if event.day == o.day and event.kind == "inspection" and event.data.scheduled then
            inspection = if event.data.failed
                then "Scheduled inspection failed today"
                else "Scheduled inspection passed today"
        end
    end
    return {
        choices = string.format("%d / %d choices left", remaining, o.actionLimit or 0),
        inspection = inspection,
        objective = string.format(
            "Finish day %d housed, with $%d saved and no personal debt.",
            o.rules.days,
            o.actor.goal
        ),
        goalFraction = if o.actor.goal <= 0
            then 1
            else math.clamp(o.actor.cash / o.actor.goal, 0, 1),
        hint = if remaining == 0
            then "Your choices are used up. Continue when you're ready."
            else "Each chore step, investigation or money choice uses one choice. Chat is separate.",
        rent = string.format("$%d rent still needed tonight", math.max(0, o.rent - o.rentPaid)),
    }
end

return Guide
