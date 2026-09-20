--!strict
-- Deterministic roommate behaviour. This is the offline stand-in that makes the
-- loop playable with no inference, no key and no network: the server calls it
-- exactly where a model adapter will later be plugged in, with the same
-- audience-filtered observation as its only input.
local Policy = {}

Policy.version = "round-policy-1"

-- Two legible attitudes, so a player can learn who is worth negotiating with.
Policy.styles = { green = "household", red = "cash" }

local function pick(candidates: any, kind: string): any?
    for _, candidate in candidates do
        if candidate.kind == kind then
            return candidate
        end
    end
    return nil
end

local function itemById(observation: any, id: number): any?
    for _, item in observation.items do
        if item.id == id then
            return item
        end
    end
    return nil
end

-- Oldest first: leaks and stale dishes cost the household most.
local function worstCleanup(observation: any): any?
    local best, bestAge = nil, -1
    for _, candidate in observation.candidates do
        if candidate.kind == "pay_cleanup" then
            local item = itemById(observation, candidate.reference)
            local age = if item then item.age * 2 + (if item.kind == "leak" then 3 else 0) else 0
            if age > bestAge then
                best, bestAge = candidate, age
            end
        end
    end
    return best
end

-- Who asked me, today, to drop a plan I can still cancel?
local function pendingRequest(observation: any): (any?, string?)
    local cancel = pick(observation.candidates, "cancel_plan")
    if not cancel then
        return nil, nil
    end
    for index = #observation.events, 1, -1 do
        local event = observation.events[index]
        if
            event.kind == "cancel_requested"
            and event.day == observation.day
            and event.data.target == observation.actor.id
            and event.data.reference == cancel.reference
        then
            return cancel, event.data.actor
        end
    end
    return nil, nil
end

-- Public rent receipts are the only fairness signal the `cash` style trusts.
local function paidRentToday(observation: any, actor: string?): boolean
    if not actor then
        return false
    end
    for _, event in observation.events do
        if
            event.kind == "action"
            and event.day == observation.day
            and event.data.actor == actor
            and event.data.action.kind == "contribute"
        then
            return true
        end
    end
    return false
end

local function choose(observation: any, style: string): (any?, string?)
    local candidates = observation.candidates
    if #candidates == 0 then
        return nil, nil
    end
    local cancel, asker = pendingRequest(observation)
    local rentOwed = observation.rent - observation.rentPaid
    local contribute = pick(candidates, "contribute")
    local cash = observation.actor.cash
    if style == "household" then
        if cancel then
            return cancel, "agreed"
        end
        local cleanup = worstCleanup(observation)
        if cleanup and cash - cleanup.amount >= 4 then
            return cleanup, "cleaned"
        end
        if contribute and rentOwed > 0 then
            return contribute, "rent"
        end
    else
        if cancel and paidRentToday(observation, asker) then
            return cancel, "agreed"
        elseif cancel then
            return nil, "refused"
        end
        local urgent = observation.heat >= 40 or observation.phase == "night"
        if contribute and rentOwed > 0 and urgent then
            return contribute, "rent"
        end
        local cleanup = worstCleanup(observation)
        if cleanup and observation.heat >= 60 and cash - cleanup.amount >= 8 then
            return cleanup, "cleaned"
        end
    end
    return pick(candidates, "wait"), "waited"
end

local function complaint(observation: any): any?
    local worst, age = nil, -1
    for _, item in observation.items do
        if not item.resolved and item.creator ~= observation.actor.id and item.age > age then
            worst, age = item, item.age
        end
    end
    return worst
end

-- One short line per turn, from the roommate's own visible evidence only.
local function speak(observation: any, style: string, note: string?): any?
    if observation.messagesRemaining <= 0 then
        return nil
    end
    local _, asker = pendingRequest(observation)
    if asker and note == "agreed" then
        return { channel = "private", target = asker, speech = "Fine. I'll drop it this once." }
    elseif asker and note == "refused" then
        return {
            channel = "private",
            target = asker,
            speech = "Put something toward rent first, then I'll think about it.",
        }
    end
    local owed = observation.rent - observation.rentPaid
    if owed > 0 and observation.phase == "night" then
        return {
            channel = "group",
            speech = string.format("Rent is still $%d short and it settles tonight.", owed),
        }
    end
    local mess = complaint(observation)
    if mess and style == "household" then
        return {
            channel = "group",
            speech = string.format(
                "Requirement #%d is still sitting there. Someone deal with it.",
                mess.id
            ),
        }
    end
    if observation.heat >= 40 then
        return {
            channel = "group",
            speech = "The landlord is paying attention to us. Keep it quiet.",
        }
    end
    if style == "cash" then
        return { channel = "group", speech = "I'm keeping my money where it is for now." }
    end
    return { channel = "group", speech = "Morning. Let's not let this place fall apart today." }
end

-- The seam a model adapter replaces: observation in, one legal decision out.
function Policy.decide(observation: any, style: string, allowMessage: boolean?): any
    if observation.status ~= "running" then
        return { action = nil, message = nil }
    end
    local action, note = choose(observation, style)
    local message = if allowMessage then speak(observation, style, note) else nil
    return { action = action, message = message, note = note }
end

function Policy.styleFor(id: string): string
    return Policy.styles[id] or "household"
end

return Policy
