--!strict
-- Deterministic roommate behaviour. This is the offline stand-in that makes the
-- loop playable with no inference, no key and no network: the server calls it
-- exactly where a model adapter will later be plugged in, with the same
-- audience-filtered observation as its only input.
local Policy = {}

Policy.version = "round-policy-1"

-- Two legible attitudes, so a player can learn who is worth negotiating with.
-- Roommates are not written characters: an unlisted colour simply alternates
-- between the two attitudes by the order it appears in.
Policy.styles = { green = "household", red = "cash", amber = "household", violet = "cash" }

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

local function contains(text: string, words: { string }): boolean
    local lower = string.lower(text)
    for _, word in words do
        if string.find(lower, word, 1, true) then
            return true
        end
    end
    return false
end

-- The player gets an answer to anything they type; a roommate only answers another
-- roommate when the line actually asks for something. Both halves matter: silence
-- after a typed message reads as a broken household, while roommates acknowledging
-- each other's ambient openers loops the stop into an endless chorus.
local function isRequest(speech: string): boolean
    return string.find(speech, "?", 1, true) ~= nil
        or contains(speech, {
            "can you",
            "could you",
            "would you",
            "will you",
            "please",
            "help",
            "what can",
            "how do",
            "should we",
            "can we",
            "could we",
            "pay rent",
            "cover rent",
            "clean ",
            "cancel ",
        })
end

-- Player colors and roommate colors are disjoint by construction in `RoundSetup`,
-- so the style table doubles as the roster of who is not the player.
local function isRoommate(id: string): boolean
    return Policy.styles[id] ~= nil
end

local ACKNOWLEDGEMENTS = {
    green = "Heard you. I'll keep that in mind before tonight.",
    red = "Noted. I'll see what my budget looks like first.",
    amber = "Sure, I'm listening. Let's sort it out together.",
    violet = "Fine, but don't expect me to carry this one alone.",
}

-- Observations retain only messages this actor is allowed to read. Find the
-- newest one from another actor in this stop. A later reply of this actor's own
-- is what stops a line being answered twice; see `alreadyReplied`.
local function currentRequest(observation: any): (any?, number?)
    for index = #observation.events, 1, -1 do
        local event = observation.events[index]
        if
            event.kind == "message"
            and event.day == observation.day
            and event.phase == observation.phase
            and event.data.actor ~= observation.actor.id
        then
            local speech = event.data.speech
            if
                (event.data.channel == "group" or event.data.target == observation.actor.id)
                and type(speech) == "string"
                and #speech > 0
                and (not isRoommate(event.data.actor) or isRequest(speech))
            then
                return event, index
            end
        end
    end
    return nil, nil
end

-- The event history is the acknowledgement record. A matching later message
-- means this observation has already produced its one bounded reply.
local function alreadyReplied(
    observation: any,
    messageIndex: number,
    sender: string,
    channel: string
): boolean
    for index = messageIndex + 1, #observation.events do
        local event = observation.events[index]
        if
            event.kind == "message"
            and event.day == observation.day
            and event.phase == observation.phase
            and event.data.actor == observation.actor.id
            and event.data.channel == channel
            and (channel == "group" or event.data.target == sender)
        then
            return true
        end
    end
    return false
end

local function hasSpokenThisStop(observation: any): boolean
    for _, event in observation.events do
        if
            event.kind == "message"
            and event.day == observation.day
            and event.phase == observation.phase
            and event.data.actor == observation.actor.id
        then
            return true
        end
    end
    return false
end

local function replyToMessage(observation: any, style: string): (any?, boolean)
    local incoming, messageIndex = currentRequest(observation)
    if not incoming or not messageIndex then
        return nil, false
    end
    local sender = incoming.data.actor
    local channel = incoming.data.channel
    if alreadyReplied(observation, messageIndex, sender, channel) then
        return nil, true
    end

    local speech = incoming.data.speech
    local contribute = pick(observation.candidates, "contribute")
    local cleanup = worstCleanup(observation)
    local cancel = pick(observation.candidates, "cancel_plan")
    local reply: string?
    local asksRent = contains(speech, { "rent", "contribute", "cover", "pay" })
    local asksCleanup = contains(speech, { "clean", "dishes", "trash", "mess", "leak", "roach" })
    local asksCancellation = contains(speech, { "cancel", "drop", "stop", "party", "plan" })

    if asksCancellation then
        if cancel then
            if style == "household" then
                reply = "I could call it off, but I have not decided yet."
            else
                reply = "I could call it off, but I need to see rent handled first."
            end
        else
            reply = "I cannot call off a plan right now."
        end
    elseif asksCleanup then
        if cleanup then
            if style == "household" then
                reply = string.format(
                    "Requirement #%d is still open. I could pay to clear it, but I have not yet.",
                    cleanup.reference
                )
            else
                reply = string.format(
                    "I could pay to clear requirement #%d, but I need to hang on to my cash until tonight.",
                    cleanup.reference
                )
            end
        else
            reply = "I cannot clear a mess right now."
        end
    elseif asksRent then
        local owed = math.max(0, observation.rent - observation.rentPaid)
        if not contribute or owed == 0 then
            reply = "I cannot put money toward rent right now."
        elseif style == "household" then
            reply = string.format("We still need $%d. I can spare $%d.", owed, contribute.amount)
        elseif observation.phase == "night" or observation.heat >= 40 then
            reply = string.format(
                "We still need $%d. Keeping the place matters more than my reserve right now.",
                owed
            )
        else
            reply = string.format(
                "We still need $%d. I need to hang on to my cash until tonight.",
                owed
            )
        end
    elseif contains(speech, { "help", "how", "what can", "could you", "can you" }) then
        local options = {}
        if contribute then
            table.insert(options, string.format("put $%d toward rent", contribute.amount))
        end
        if cleanup then
            table.insert(options, string.format("pay to clear requirement #%d", cleanup.reference))
        end
        if cancel then
            table.insert(options, "call off my pending plan")
        end
        if #options == 0 then
            reply = "I only have waiting open right now."
        else
            reply = "I could " .. table.concat(options, " or ") .. ", but I have not chosen yet."
        end
    end

    if not reply then
        -- No topic matched, so acknowledge in this roommate's own voice rather
        -- than saying nothing. Four distinct lines keep a group thread from
        -- answering the player in chorus.
        reply = ACKNOWLEDGEMENTS[observation.actor.id] or "Heard you."
    end
    return {
        channel = channel,
        target = if channel == "private" then sender else nil,
        speech = reply,
    },
        true
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
    local direct, considered = replyToMessage(observation, style)
    if considered then
        return direct
    end
    if hasSpokenThisStop(observation) then
        return nil
    end
    local owed = observation.rent - observation.rentPaid
    if owed > 0 and observation.phase == "night" and (observation.rentDueIn or 0) == 0 then
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
