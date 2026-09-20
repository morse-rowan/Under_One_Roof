--!strict
-- Pure authoritative rules. All adapters (including Roblox) pass through this boundary.
local U = require(if script then script.Parent.LabUtil else "./LabUtil")
local Economy = require(if script then script.Parent.LabEconomy else "./LabEconomy")
local Social = require(if script then script.Parent.LabSocial else "./LabSocial")
local Plans = require(if script then script.Parent.LabPlans else "./LabPlans")
local Lab = { schema = 1, rules = "roommate-lab-1", modules = { Economy, Social, Plans } }

local function dayStart(state: any, config: any)
    state.phase = "social"
    state.slot = 1
    state.turn = 1
    for index = #state.order, 2, -1 do
        local swap = U.random(state, "order", index)
        state.order[index], state.order[swap] = state.order[swap], state.order[index]
    end
    for _, id in state.order do
        state.actors[id].plan = state.actors[id].preference
        state.actors[id].mediation = {}
    end
    for _, event in state.scheduled do
        if event.day == state.day then
            state.property = math.max(0, state.property - event.amount)
            U.emit(state, "delayed_damage", "world", event)
        end
    end
    Economy.startDay(state, config)
    if config.time.social_rounds == 0 then
        state.phase = "action"
    end
end

function Lab.new(config: any, seed: number): any
    local state = {
        schema = Lab.schema,
        rules = Lab.rules,
        revision = 0,
        day = 1,
        phase = "social",
        turn = 1,
        slot = 1,
        status = "active",
        heat = 0,
        property = 100,
        actors = {},
        order = {},
        events = {},
        commitments = {},
        debts = {},
        scheduled = {},
        rng = {
            events = seed % 2147483646 + 1,
            order = (seed + 17) % 2147483646 + 1,
            policy = (seed + 97) % 2147483646 + 1,
        },
        totals = {
            initial = 0,
            income = 0,
            expenses = 0,
            transfers = 0,
            paid = 0,
            unpaid = 0,
            commitments_due = 0,
            fulfilled = 0,
            breached = 0,
            alliances_formed = 0,
            disclosures = 0,
            conflicts = 0,
            mediation = 0,
            repairs = 0,
        },
    }
    for _, spec in config.actors do
        table.insert(state.order, spec.id)
        state.totals.initial += spec.cash
        state.actors[spec.id] = {
            id = spec.id,
            role = spec.role,
            cash = spec.cash,
            income = spec.income,
            goal = spec.goal,
            preference = spec.preference,
            stats = U.copy(spec.stats),
            contributed = 0,
            progress = 0,
            stress = 0,
            relationships = {},
            allies = {},
            knowledge = { [spec.id .. ":savings"] = spec.goal },
            beliefs = {},
            memory = {},
            plan = spec.preference,
            mediation = {},
        }
    end
    dayStart(state, config)
    return state
end

function Lab.actor(state: any): string?
    return if state.status == "active" and state.phase ~= "settlement"
        then state.order[state.turn]
        else nil
end

function Lab.candidates(state: any, config: any, id: string): any
    local out = { { kind = "wait" } }
    if Lab.actor(state) ~= id then
        return out
    end
    for _, module in Lab.modules do
        module.candidates(state, config, id, out)
    end
    -- Module iteration must not make candidate IDs depend on hash-table iteration order.
    table.sort(out, function(a, b)
        local function key(v)
            return v.kind
                .. ":"
                .. (v.target or "")
                .. ":"
                .. (v.reference or "")
                .. ":"
                .. (v.fact or "")
                .. ":"
                .. (v.purpose or "")
                .. ":"
                .. (v.value or "")
        end
        return key(a) < key(b)
    end)
    return out
end

function Lab.observe(state: any, config: any, id: string): any
    assert(state.actors[id], "Unknown actor")
    local actor = U.copy(state.actors[id])
    actor.memory = nil
    local events, deals, debts = {}, {}, {}
    for _, event in state.events do
        if U.visible(event, id) then
            table.insert(events, U.copy(event))
        end
    end
    for _, deal in state.commitments do
        if deal.actor == id or deal.target == id then
            table.insert(deals, U.copy(deal))
        end
    end
    for _, debt in state.debts do
        if debt.lender == id or debt.borrower == id then
            table.insert(debts, U.copy(debt))
        end
    end
    return {
        actor = actor,
        actor_ids = U.copy(state.order),
        revision = state.revision,
        day = state.day,
        phase = state.phase,
        heat = state.heat,
        property = state.property,
        bill = U.copy(state.bill),
        events = events,
        commitments = deals,
        debts = debts,
        candidates = Lab.candidates(state, config, id),
    }
end

function Lab.apply(state: any, config: any, proposal: any): (boolean, string)
    if type(proposal) ~= "table" then
        return false, "invalid_proposal"
    end
    for key in proposal do
        if
            key ~= "actor"
            and key ~= "revision"
            and key ~= "action"
            and key ~= "speech"
            and key ~= "channel"
        then
            return false, "unknown_field"
        end
    end
    local id = Lab.actor(state)
    if not id or proposal.actor ~= id or proposal.revision ~= state.revision then
        return false, "stale_or_wrong_actor"
    end
    if
        type(proposal.speech) ~= "string"
        or #proposal.speech > config.communication.speech_bytes
    then
        return false, "speech_limit"
    end
    if proposal.channel ~= "private" and proposal.channel ~= "public" then
        return false, "invalid_channel"
    end
    if proposal.channel == "private" and not config.communication.private then
        return false, "private_disabled"
    end
    local found = false
    for _, action in Lab.candidates(state, config, id) do
        if U.equal(action, proposal.action) then
            found = true
        end
    end
    if not found then
        return false, "illegal_action"
    end
    local action = proposal.action
    if proposal.channel == "private" and not action.target then
        return false, "private_requires_target"
    end
    state.revision += 1
    if action.kind ~= "wait" then
        local applied = false
        for _, module in Lab.modules do
            if module.apply(state, config, id, action) then
                applied = true
                break
            end
        end
        assert(applied, "Registered action has no handler")
    end
    if proposal.speech ~= "" then
        U.emit(
            state,
            "speech",
            id,
            { text = proposal.speech, target = action.target or "*" },
            if proposal.channel == "private" then { id, action.target } else { "*" }
        )
    end
    U.emit(state, "acted", id, { kind = action.kind }, { id })
    state.turn += 1
    if state.turn > #state.order then
        state.turn = 1
        state.slot += 1
        local rounds = if state.phase == "social"
            then config.time.social_rounds
            else config.time.action_rounds
        if state.slot > rounds then
            state.slot = 1
            state.phase = if state.phase == "social" then "action" else "settlement"
        end
    end
    return true, "applied"
end

function Lab.advance(state: any, config: any): (boolean, string)
    if state.status ~= "active" or state.phase ~= "settlement" then
        return false, "not_settlement"
    end
    state.revision += 1
    for _, module in Lab.modules do
        module.settle(state, config)
    end
    state.heat = math.clamp(state.heat, 0, 100)
    U.emit(state, "day_settled", "world", { heat = state.heat, property = state.property })
    if state.heat >= 100 or state.property <= 0 then
        state.status = "evicted"
    elseif state.day >= config.time.days then
        state.status = "horizon"
    else
        state.day += 1
        dayStart(state, config)
    end
    return true, "advanced"
end

function Lab.save(state: any): any
    return U.copy(state)
end
function Lab.load(state: any): any
    assert(state.schema == Lab.schema and state.rules == Lab.rules, "Incompatible checkpoint")
    return U.copy(state)
end

return Lab
