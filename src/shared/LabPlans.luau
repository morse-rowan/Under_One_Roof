--!strict
local U = require(if script then script.Parent.LabUtil else "./LabUtil")
local Plans = {
    name = "plans",
    configuration = { "plans" },
    actions = { "plan", "mediate", "repair" },
    metrics = { "conflicts", "mediation", "personal_progress", "repairs" },
    observation = "own intended activity; execution and mediation are public",
}

function Plans.candidates(state: any, config: any, id: string, out: any)
    if not config.mechanics.plans then
        return
    end
    if state.phase == "social" then
        for _, target in state.order do
            if target ~= id then
                table.insert(out, { kind = "mediate", target = target })
            end
        end
    elseif state.phase == "action" then
        table.insert(out, { kind = "plan", value = "party" })
        table.insert(out, { kind = "plan", value = "quiet" })
        if state.actors[id].cash >= config.plans.repair_cost then
            table.insert(out, { kind = "repair" })
        end
    end
end

function Plans.apply(state: any, config: any, id: string, action: any): boolean
    if action.kind == "plan" then
        state.actors[id].plan = action.value
        U.emit(state, "plan_chosen", id, { value = action.value }, { id })
    elseif action.kind == "mediate" then
        -- Mediation is an invitation, never forced control of another actor.
        state.actors[action.target].mediation = { source = id, day = state.day }
        state.totals.mediation += 1
        U.emit(state, "mediation_requested", id, action)
    elseif action.kind == "repair" then
        state.actors[id].cash -= config.plans.repair_cost
        state.totals.expenses += config.plans.repair_cost
        state.property = math.min(100, state.property + config.plans.repair_gain)
        state.totals.repairs += 1
        U.emit(state, "repaired", id, { gain = config.plans.repair_gain })
    else
        return false
    end
    return true
end

function Plans.settle(state: any, config: any)
    if not config.mechanics.plans then
        return
    end
    local parties = 0
    for _, id in state.order do
        if state.actors[id].plan == "party" then
            parties += 1
        end
    end
    for _, id in state.order do
        local actor = state.actors[id]
        local achieved = actor.plan == actor.preference
            and (actor.preference ~= "quiet" or parties == 0)
        if achieved then
            actor.progress += 1
        end
        if parties > 0 and actor.preference == "quiet" then
            state.totals.conflicts += 1
            actor.stress = math.min(100, actor.stress + config.plans.stress)
            for _, other in state.order do
                if state.actors[other].plan == "party" then
                    U.relate(state, id, other, -config.plans.conflict_trust)
                end
            end
        else
            actor.stress = math.max(0, actor.stress - config.plans.stress)
        end
        U.emit(state, "plan_executed", id, { plan = actor.plan, achieved = achieved })
    end
    if parties > 0 then
        state.heat += config.plans.party_heat * parties
        table.insert(
            state.scheduled,
            { day = state.day + 1, kind = "damage", amount = parties * config.plans.party_damage }
        )
    end
end

return Plans
