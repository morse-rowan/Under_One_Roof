--!strict
local U = require(if script then script.Parent.LabUtil else "./LabUtil")
local Social = {
    name = "social",
    configuration = { "social", "communication", "memory" },
    actions = {
        "offer",
        "accept",
        "reject",
        "fulfill",
        "breach",
        "disclose",
        "claim",
        "ally",
        "leave",
    },
    metrics = { "commitments_due", "fulfilled", "breached", "alliances_formed", "disclosures" },
    observation = "participant deals, witnessed speech, sourced beliefs; no omniscient truth",
}

function Social.candidates(state: any, config: any, id: string, out: any)
    local actor = state.actors[id]
    if state.phase == "social" then
        for _, target in state.order do
            if target ~= id then
                if config.mechanics.promises then
                    table.insert(out, {
                        kind = "offer",
                        target = target,
                        amount = config.economy.unit,
                        purpose = "bill",
                    })
                    if config.mechanics.plans then
                        table.insert(out, {
                            kind = "offer",
                            target = target,
                            amount = config.plans.compensation,
                            purpose = "quiet",
                        })
                    end
                end
                if config.mechanics.alliances and not actor.allies[target] then
                    table.insert(out, { kind = "ally", target = target })
                end
                if actor.allies[target] then
                    table.insert(out, { kind = "leave", target = target })
                end
                if config.mechanics.information then
                    table.insert(
                        out,
                        { kind = "disclose", target = target, fact = id .. ":savings" }
                    )
                    table.insert(
                        out,
                        { kind = "claim", target = target, topic = "cash", value = "cannot_afford" }
                    )
                    for fact in actor.knowledge do
                        if fact ~= id .. ":savings" then
                            table.insert(out, { kind = "disclose", target = target, fact = fact })
                        end
                    end
                end
            end
        end
        for _, deal in state.commitments do
            if deal.target == id and deal.status == "offered" then
                table.insert(out, { kind = "accept", reference = deal.id })
                table.insert(out, { kind = "reject", reference = deal.id })
            end
        end
    elseif state.phase == "action" then
        for _, deal in state.commitments do
            if deal.actor == id and deal.status == "accepted" and deal.purpose ~= "alliance" then
                if
                    actor.cash >= deal.amount
                    and (
                        deal.purpose ~= "bill"
                        or state.bill.paid + deal.amount <= state.bill.amount
                    )
                then
                    table.insert(out, { kind = "fulfill", reference = deal.id })
                end
                table.insert(out, { kind = "breach", reference = deal.id })
            end
        end
    end
end

function Social.apply(state: any, config: any, id: string, action: any): boolean
    local actor = state.actors[id]
    if action.kind == "offer" or action.kind == "ally" then
        local purpose = if action.kind == "ally" then "alliance" else action.purpose
        local deal = {
            id = "c" .. (#state.commitments + 1),
            actor = id,
            target = action.target,
            amount = action.amount or 0,
            purpose = purpose,
            due = state.day,
            status = "offered",
        }
        table.insert(state.commitments, deal)
        deal.event = U.emit(state, "offered", id, deal, { id, action.target })
    elseif
        action.kind == "accept"
        or action.kind == "reject"
        or action.kind == "fulfill"
        or action.kind == "breach"
    then
        for _, deal in state.commitments do
            if deal.id == action.reference then
                if action.kind == "accept" then
                    deal.status = "accepted"
                    if deal.purpose == "alliance" then
                        state.actors[deal.actor].allies[id] = state.day
                        actor.allies[deal.actor] = state.day
                        deal.status = "fulfilled"
                        state.totals.alliances_formed += 1
                    elseif deal.purpose == "quiet" then
                        -- Acceptance changes the target's plan, but it remains voluntary until settlement.
                        actor.plan = "quiet"
                    end
                elseif action.kind == "reject" then
                    deal.status = "rejected"
                elseif action.kind == "fulfill" then
                    actor.cash -= deal.amount
                    if deal.purpose == "bill" then
                        state.bill.paid += deal.amount
                        state.totals.expenses += deal.amount
                        actor.contributed += deal.amount
                    else
                        state.actors[deal.target].cash += deal.amount
                        state.totals.transfers += deal.amount
                    end
                    deal.status = "delivered"
                else
                    deal.status = "breached"
                end
                U.emit(
                    state,
                    action.kind,
                    id,
                    { commitment = deal.id, purpose = deal.purpose },
                    { deal.actor, deal.target },
                    { deal.event }
                )
            end
        end
    elseif action.kind == "disclose" then
        local truth = actor.knowledge[action.fact]
        state.actors[action.target].knowledge[action.fact] = U.copy(truth)
        state.totals.disclosures += 1
        U.emit(state, "disclosed", id, { fact = action.fact, value = truth }, { id, action.target })
    elseif action.kind == "claim" then
        local eventId = U.emit(state, "claimed", id, action, { id, action.target })
        state.actors[action.target].beliefs[id .. ":" .. action.topic] = {
            source = id,
            event = eventId,
            value = action.value,
            confidence = 0.5,
        }
    elseif action.kind == "leave" then
        actor.allies[action.target] = nil
        state.actors[action.target].allies[id] = nil
        U.relate(state, action.target, id, -config.social.breach_trust)
        U.emit(state, "alliance_left", id, action, { id, action.target })
    else
        return false
    end
    return true
end

function Social.settle(state: any, config: any)
    for _, deal in state.commitments do
        if deal.due == state.day and deal.purpose ~= "alliance" then
            if deal.status == "offered" then
                deal.status = "expired"
            elseif
                deal.status == "accepted"
                or deal.status == "delivered"
                or deal.status == "breached"
            then
                state.totals.commitments_due += 1
                local kept = deal.status == "delivered"
                if deal.purpose == "quiet" and state.actors[deal.target].plan ~= "quiet" then
                    kept = false
                    U.relate(state, deal.actor, deal.target, -config.social.breach_trust)
                end
                deal.status = if kept then "fulfilled" else "breached"
                state.totals[if kept then "fulfilled" else "breached"] += 1
                U.relate(
                    state,
                    deal.target,
                    deal.actor,
                    if kept then config.social.fulfilled_trust else -config.social.breach_trust
                )
                U.emit(
                    state,
                    "commitment_" .. deal.status,
                    deal.actor,
                    { commitment = deal.id },
                    { deal.actor, deal.target },
                    { deal.event }
                )
            end
        elseif
            deal.due == state.day
            and deal.purpose == "alliance"
            and deal.status == "offered"
        then
            deal.status = "expired"
        end
    end
end

return Social
