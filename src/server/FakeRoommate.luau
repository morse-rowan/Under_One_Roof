--!strict
-- Replaceable server adapter: bounded replies, no services or state mutations.
local FakeRoommate = {}

function FakeRoommate.respond(context: any, config: any)
    local person = config.roommates[context.roommate]
    local words = string.lower(context.text)
    local polite = string.find(words, "please", 1, true) ~= nil
        or string.find(words, "thank", 1, true) ~= nil
    local hostile = string.find(words, "lazy", 1, true) ~= nil
        or string.find(words, "stupid", 1, true) ~= nil
    local delta = if hostile then -1 elseif polite then 1 else 0
    local price = math.max(
        0,
        person.price
            - (if polite then 5 else 0)
            + (if hostile then 10 else 0)
            - (if context.trust >= 3 then 5 else 0)
            + (if context.trust <= -2 then 5 else 0)
    )
    local memory = if context.trust >= 3
        then "You've been fair to me. "
        elseif context.trust <= -2 then "I remember how you treated me. "
        else ""
    if not context.task then
        return {
            accept = false,
            trustDelta = delta,
            text = memory
                .. person.hint
                .. " Attach #"
                .. person.task
                .. " and offer $"
                .. price
                .. ".",
        }
    end
    if context.task ~= person.task then
        return {
            accept = false,
            trustDelta = delta,
            text = "That's not my thing. I can help with #" .. person.task .. ".",
        }
    end
    local accept = context.amount >= price
    return {
        accept = accept,
        trustDelta = delta,
        text = memory .. (if accept
            then "Deal. I'll handle it before the day ends."
            else "I'll do it for $" .. price .. ". Try a fair offer, and ask nicely."),
    }
end

return FakeRoommate
