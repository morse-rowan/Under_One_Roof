--!strict
local U = {}

function U.copy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in value do
        result[key] = U.copy(item)
    end
    return result
end

function U.equal(a: any, b: any): boolean
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for key, value in a do
        if not U.equal(value, b[key]) then
            return false
        end
    end
    for key in b do
        if a[key] == nil then
            return false
        end
    end
    return true
end

function U.random(state: any, stream: string, maximum: number): number
    -- Park-Miller with products below the exact-integer limit of a double.
    state.rng[stream] = (state.rng[stream] * 16807) % 2147483647
    return 1 + state.rng[stream] % maximum
end

function U.emit(state: any, kind: string, actor: string, data: any, audience: any?, causes: any?)
    local event = {
        id = "e" .. (#state.events + 1),
        kind = kind,
        actor = actor,
        day = state.day,
        phase = state.phase,
        revision = state.revision,
        data = U.copy(data),
        audience = audience or { "*" },
        causes = causes or {},
    }
    table.insert(state.events, event)
    for _, id in state.order do
        if table.find(event.audience, "*") or table.find(event.audience, id) then
            table.insert(state.actors[id].memory, event.id)
        end
    end
    return event.id
end

function U.visible(event: any, actor: string): boolean
    return table.find(event.audience, "*") ~= nil or table.find(event.audience, actor) ~= nil
end

function U.relate(state: any, observer: string, target: string, delta: number)
    local relationships = state.actors[observer].relationships
    relationships[target] = math.clamp((relationships[target] or 0) + delta, -100, 100)
end

return U
