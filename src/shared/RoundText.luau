--!strict
-- Turns audience-filtered `MvpRound` events into the lines a player reads.
-- It is the Luau counterpart of `tools/simlab/mvp_context.py`: colors only, no
-- controller identity, and completed chores/services normalise to the same
-- "handled outstanding requirement" wording whether they were worked or bought.
local Text = {}

local function title(id: string): string
    return (string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2))
end

function Text.name(id: string?, viewer: string?): string
    if id == nil or id == "system" then
        return "The building"
    elseif id == viewer then
        return "You"
    end
    return title(id)
end

local kindWords = {
    dishes = "dishes in the sink",
    trash = "trash on the floor",
    leak = "a leak",
    roaches = "roaches",
}

function Text.issue(item: any, viewer: string?): string
    local words = kindWords[item.kind] or item.kind
    if item.kind == "trash" and item.stage == "bagged" then
        words = "a bagged trash sack"
    end
    local age = if item.age > 0
        then string.format(" · %d window%s old", item.age, if item.age == 1 then "" else "s")
        else ""
    local blame = if item.creator == "system"
        then ""
        else " · " .. Text.name(item.creator, viewer) .. "'s"
    return string.format("#%d %s%s%s", item.id, words, blame, age)
end

local function actionLine(data: any, viewer: string?): string?
    local action = data.action
    local who = Text.name(data.actor, viewer)
    local kind = action.kind
    if kind == "pay_cleanup" or kind == "finish_chore" then
        return string.format("%s handled outstanding requirement #%d.", who, action.reference)
    elseif kind == "pickup_trash" then
        return string.format(
            "%s made progress on outstanding requirement #%d.",
            who,
            action.reference
        )
    elseif kind == "contribute" then
        return string.format("%s put $%d toward rent.", who, action.amount)
    elseif kind == "inspect" then
        return "You worked out what someone is about to do."
    elseif kind == "cancel_plan" then
        return string.format("%s dropped a plan.", who)
    elseif kind == "request_cancel" then
        return nil
    end
    return nil
end

-- Returns a display line, or nil when the event should not be shown at all.
function Text.line(event: any, viewer: string?): string?
    local data = event.data
    local kind = event.kind
    if kind == "action" then
        return actionLine(data, viewer)
    elseif kind == "message" then
        local who = Text.name(data.actor, viewer)
        if data.channel == "group" then
            return string.format("%s · group: %s", who, data.speech)
        elseif data.actor == viewer then
            return string.format("You → %s: %s", Text.name(data.target, viewer), data.speech)
        end
        return string.format("%s → you: %s", who, data.speech)
    elseif kind == "day_started" then
        local left = data.rentDueIn or 0
        if left == 0 then
            return string.format("Day %d. Rent due tonight: $%d.", event.day, data.rent)
        end
        return string.format(
            "Day %d. Rent of $%d due in %d %s; $%d in so far.",
            event.day,
            data.rent,
            left,
            if left == 1 then "night" else "nights",
            data.rentPaid or 0
        )
    elseif kind == "expense" then
        local paid = string.format("Bills: $%d due, $%d paid", data.due, data.paid)
        return if data.debt > 0
            then string.format("%s, $%d still owed.", paid, data.debt)
            else paid .. "."
    elseif kind == "work_forecast" then
        local note = if data.tired
            then " You are tired, so the shift is harder."
            elseif data.modifier > 0 then " You slept well after hosting."
            else ""
        return string.format("Shift forecast: $%d before any bonus.%s", data.income, note)
    elseif kind == "party_effects" then
        return string.format(
            "%s hosted last night: the host earns +$%d, everyone else loses $%d and works tired.",
            Text.name(data.host, viewer),
            data.hostBonus,
            data.othersPenalty
        )
    elseif kind == "income" then
        local bonus = if (data.bonus or 0) > 0
            then string.format(" (including a $%d recall bonus)", data.bonus)
            else ""
        local debt = if data.expenseDebtPaid > 0
            then string.format(" $%d went straight to your bills.", data.expenseDebtPaid)
            else ""
        return string.format("Payday: $%d in%s.%s", data.amount, bonus, debt)
    elseif kind == "issue_created" then
        if data.creator == "system" then
            return string.format(
                "%s appeared in the apartment (#%d).",
                if data.kind == "leak" then "A leak" else "Roaches",
                data.id
            )
        end
        return string.format(
            "%s left %s (#%d).",
            Text.name(data.creator, viewer),
            kindWords[data.kind] or data.kind,
            data.id
        )
    elseif kind == "clue" then
        return string.format(
            "You worked out that %s is about to leave %s.",
            Text.name(data.actor, viewer),
            kindWords[data.kind] or data.kind
        )
    elseif kind == "cancel_requested" then
        if data.actor == viewer then
            return string.format("You asked %s to drop it.", Text.name(data.target, viewer))
        end
        return string.format("%s asked you to drop it.", Text.name(data.actor, viewer))
    elseif kind == "inspection" then
        return string.format(
            "%s inspection: cleanliness %d. %s Landlord pressure %d.",
            if data.scheduled then "Scheduled" else "Surprise",
            data.cleanliness,
            if data.failed then "Failed." else "Passed.",
            data.heat
        )
    elseif kind == "rent_pending" then
        return string.format(
            "Rent not due yet: $%d of $%d in, %d %s to go.",
            data.paid,
            data.due,
            data.nights,
            if data.nights == 1 then "night" else "nights"
        )
    elseif kind == "rent_settled" then
        return string.format(
            "Rent settled: $%d of $%d. Landlord pressure %d.",
            data.paid,
            data.due,
            data.heat
        )
    elseif kind == "party" then
        return string.format(
            "%s threw a party. Landlord pressure %d.",
            Text.name(data.host, viewer),
            data.heat
        )
    end
    -- plan_created, issue_aged and phase_closed are administrative or too noisy.
    return nil
end

-- All visible lines for one observation, oldest first.
function Text.log(observation: any, viewer: string?): { string }
    local lines = {}
    for _, event in observation.events do
        local line = Text.line(event, viewer)
        if line then
            table.insert(lines, line)
        end
    end
    return lines
end

Text.actionLabels = {
    wait = "Hold on to your money",
    contribute = "Pay toward rent",
    pay_cleanup = "Pay to have it dealt with",
    finish_chore = "Finish the chore yourself",
    pickup_trash = "Bag up the trash",
    inspect = "Look into what they are planning",
    cancel_plan = "Drop your own plan",
    request_cancel = "Ask them to drop it",
}

function Text.action(action: any): string
    local label = Text.actionLabels[action.kind] or action.kind
    if action.amount then
        label ..= string.format(" ($%d)", action.amount)
    end
    if action.reference then
        label ..= string.format(" · #%d", action.reference)
    end
    return label
end

return Text
