--!strict
-- Text-composer pickers for the audience-filtered round observation. These helpers
-- never decide legality: they only return candidates the server already exposed.
local Guide = require(if script then script.Parent.RoundGuide else "./RoundGuide")

local Actions = {}

local tokenByKind = {
    contribute = function(_action: any): string
        return "#rent"
    end,
    pay_cleanup = function(action: any): string
        return "#service:" .. tostring(action.reference)
    end,
    wait = function(_action: any): string
        return "#wait"
    end,
    inspect = function(action: any): string
        return "!inspect:" .. tostring(action.reference)
    end,
    request_cancel = function(action: any): string
        return "!request-cancel:" .. tostring(action.reference)
    end,
    cancel_plan = function(action: any): string
        return "!cancel:" .. tostring(action.reference)
    end,
}

local modeByKind = {
    contribute = "#",
    pay_cleanup = "#",
    wait = "#",
    inspect = "!",
    request_cancel = "!",
    cancel_plan = "!",
}

-- Returns display data for legal, non-physical candidates in the requested picker.
-- The `action` field is the original candidate, ready to be sent back to the server.
function Actions.options(o: any, mode: string): { any }
    local out = {}
    for _, action in o.candidates or {} do
        local kind = action.kind
        local token = tokenByKind[kind]
        if token and modeByKind[kind] == mode then
            table.insert(out, {
                action = action,
                label = Guide.choice(action, o),
                token = token(action),
            })
        end
    end
    return out
end

-- Rechecks a chip against the current observation. `pay_rent` is only a text
-- alias for the round's established `contribute` candidate; no new deal exists.
function Actions.resolve(o: any, kind: any, reference: any, amount: any?): any?
    if kind == "pay_rent" then
        kind = "contribute"
    end
    if type(kind) ~= "string" or not tokenByKind[kind] then
        return nil
    end
    for _, action in o.candidates or {} do
        if
            action.kind == kind
            and action.reference == reference
            and (amount == nil or action.amount == amount)
        then
            return action
        end
    end
    return nil
end

-- Actor IDs are already part of the public observation. Keep private plans and
-- message history out of recipient lookup so this cannot reveal new identities.
function Actions.recipients(o: any): { string }
    local out, seen = {}, {}
    local selfId = o.actor and o.actor.id
    for _, id in o.actorIds or {} do
        if type(id) == "string" and id ~= selfId and not seen[id] then
            seen[id] = true
            table.insert(out, id)
        end
    end
    return out
end

-- A composer hint only. It has no action field and cannot execute typed prose.
function Actions.preview(o: any, text: any): any?
    if type(text) ~= "string" then
        return nil
    end
    local mode, query = string.match(text, "([@#!])([^%s]*)$")
    if mode == "@" then
        return { mode = mode, query = query, recipients = Actions.recipients(o) }
    elseif mode == "#" or mode == "!" then
        return { mode = mode, query = query, options = Actions.options(o, mode) }
    end
    return nil
end

return Actions
