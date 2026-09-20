--!strict
-- MVP mechanics v1, intentionally outside Rojo mappings. Numeric defaults remain tunable.
local U = require("../shared/LabUtil")
local Round = {}
Round.mechanicsVersion = "mvp-1"

Round.phases = { "morning", "action_one", "work", "midday", "action_two", "night" }
Round.defaults = {
    days = 3,
    rent = 30,
    payment = 5,
    cleanup = 5,
    repair = 10,
    eviction = 100,
    unpaidHeat = 20,
    paidCooling = 5,
    inspectionHeat = 15,
    inspectionCleanliness = 70,
    inspectionDay = 2,
    randomInspectionPercent = 10,
    messPercent = 65,
    partyPercent = 40,
    leakPercent = 10,
    roachPercent = 5,
    pressurePerDay = 5,
    messDirt = 10,
    ageDirt = 5,
    leakHeat = 5,
    partyHeat = 5,
    tiredPenalty = 5,
    hostBonus = 5,
    workBonus = 5,
    playerActions = 2,
    npcActions = 1,
    messages = 3,
    speechBytes = 400,
    stopActions = 1,
    workRestedLength = 3,
    workTiredLength = 5,
    workSymbols = 4,
}

local function emit(s, kind, data, audience)
    local event = {
        id = #s.events + 1,
        day = s.day,
        phase = s.phase,
        kind = kind,
        data = U.copy(data),
        audience = audience or { "*" },
    }
    table.insert(s.events, event)
end

local function actionPhase(s)
    return s.phase == "action_one" or s.phase == "action_two"
end

local function stopPhase(s)
    return s.phase == "morning" or s.phase == "midday" or s.phase == "night"
end

local function roll(s, chance)
    s.rng = (s.rng * 16807) % 2147483647
    return s.rng % 100 < math.clamp(chance, 0, 100)
end

local function cleanliness(s)
    local dirt = 0
    for _, item in s.items do
        if not item.resolved and item.kind ~= "leak" then
            dirt += s.config.messDirt + item.age * s.config.ageDirt
        end
    end
    return math.clamp(100 - dirt, 0, 100)
end

local function itemById(s, id)
    for _, item in s.items do
        if item.id == id then
            return item
        end
    end
    return nil
end

local function planById(s, id)
    for _, plan in s.plans do
        if plan.id == id then
            return plan
        end
    end
    return nil
end

local function addItem(s, kind, creator)
    local item = {
        id = #s.items + 1,
        kind = kind,
        creator = creator,
        day = s.day,
        stage = "open",
        age = 0,
        resolved = false,
    }
    table.insert(s.items, item)
    emit(s, "issue_created", item)
end

local function queuePlan(s, kind, actor, due)
    local plan = {
        id = #s.plans + 1,
        kind = kind,
        actor = actor,
        due = due,
        day = s.day,
        status = "pending",
        seenBy = { actor },
    }
    table.insert(s.plans, plan)
    emit(s, "plan_created", plan, { actor })
end

local function checkpoint(s)
    local ids = {}
    for i = s.lastCheckpoint + 1, #s.events do
        table.insert(ids, i)
    end
    local outstanding = {}
    for _, item in s.items do
        if not item.resolved then
            table.insert(outstanding, U.copy(item))
        end
    end
    table.insert(s.checkpoints, {
        day = s.day,
        phase = s.phase,
        eventIds = ids,
        cleanliness = cleanliness(s),
        heat = s.heat,
        rentPaid = s.rentPaid,
        outstanding = outstanding,
    })
    s.lastCheckpoint = #s.events
end

local function morning(s)
    s.rentPaid = 0
    for _, id in s.order do
        local actor = s.actors[id]
        local charge = actor.expense
        actor.debt += charge
        local paid = math.min(actor.cash, actor.debt)
        actor.cash -= paid
        actor.debt -= paid
        emit(s, "expense", { actor = id, due = charge, paid = paid, debt = actor.debt }, { id })
        actor.modifier = if s.lastHost == id
            then s.config.hostBonus
            elseif s.lastHost then -s.config.tiredPenalty
            else 0
        actor.tired = s.lastHost ~= nil and s.lastHost ~= id
        emit(s, "work_forecast", {
            actor = id,
            income = math.max(0, actor.income + actor.modifier),
            modifier = actor.modifier,
            tired = actor.tired,
            nextExpense = actor.expense,
            reason = if s.lastHost then "party" else "rested",
        }, { id })
    end
    if s.lastHost then
        emit(s, "party_effects", {
            host = s.lastHost,
            hostBonus = s.config.hostBonus,
            othersPenalty = s.config.tiredPenalty,
        })
    end
    s.lastHost = nil
    emit(s, "day_started", { rent = s.config.rent, inspectionDay = s.config.inspectionDay })
    checkpoint(s)
end

local function openAction(s)
    local npcs = {}
    for _, id in s.order do
        if s.actors[id].role == "npc" then
            table.insert(npcs, id)
        end
    end
    if #npcs == 0 then
        return
    end
    local extra = (s.day - 1) * s.config.pressurePerDay
    if roll(s, s.config.messPercent + extra) then
        local creator = npcs[1 + s.rng % #npcs]
        local kind = if roll(s, 50) then "trash" else "dishes"
        queuePlan(s, kind, creator, s.phase)
    end
    if s.phase == "action_two" and s.day < s.config.days and roll(s, s.config.partyPercent + extra) then
        queuePlan(s, "party", npcs[1 + s.rng % #npcs], "overnight")
    end
end

function Round.new(actors: any, seed: number?, overrides: any?): any
    local config = U.copy(Round.defaults)
    for key, value in overrides or {} do
        assert(config[key] ~= nil, "Unknown configuration: " .. key)
        assert(
            type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0,
            "Invalid configuration"
        )
        config[key] = value
    end
    assert(config.days > 0 and config.payment > 0 and config.eviction > 0, "Invalid limits")
    assert(
        config.workRestedLength > 0 and config.workTiredLength >= config.workRestedLength
            and config.workTiredLength <= 100 and config.workSymbols >= 2 and config.workSymbols <= 100,
        "Invalid work challenge limits"
    )
    for _, key in { "messPercent", "partyPercent", "leakPercent", "roachPercent", "randomInspectionPercent" } do
        assert(config[key] <= 100, "Invalid probability")
    end
    assert(config.inspectionCleanliness <= 100, "Invalid cleanliness threshold")
    local initialSeed = seed or 1
    assert(initialSeed > 0 and initialSeed < 2147483647 and initialSeed % 1 == 0, "Invalid seed")
    local s = {
        version = 2,
        mechanicsVersion = Round.mechanicsVersion,
        config = config,
        initialSeed = initialSeed,
        rng = initialSeed,
        day = 1,
        phase = "morning",
        revision = 0,
        actors = {},
        order = {},
        events = {},
        checkpoints = {},
        items = {},
        plans = {},
        used = {},
        messageCounts = {},
        heat = 0,
        rentPaid = 0,
        lastCheckpoint = 0,
        status = "running",
        workSubmitted = false,
    }
    local players = 0
    for _, input in actors do
        assert(
            type(input.id) == "string"
                and input.id ~= ""
                and input.id ~= "*"
                and not s.actors[input.id],
            "Invalid actor ID"
        )
        assert(input.role == "player" or input.role == "npc", "Invalid role")
        local actor = U.copy(input)
        for _, key in { "cash", "income", "goal", "expense" } do
            assert(
                type(actor[key]) == "number"
                    and actor[key] >= 0
                    and actor[key] < math.huge
                    and actor[key] % 1 == 0,
                "Invalid economy"
            )
        end
        actor.debt, actor.modifier, actor.tired = 0, 0, false
        s.actors[actor.id] = actor
        table.insert(s.order, actor.id)
        if actor.role == "player" then
            players += 1
        end
    end
    assert(#s.order > 0 and players <= 1, "Expected a household with at most one player")
    morning(s)
    return s
end

function Round.candidates(s: any, id: string): any
    local actor = s.actors[id]
    if not actor or s.status ~= "running" or s.phase == "work" then
        return {}
    end
    local limit = if actionPhase(s)
        then (if actor.role == "player" then s.config.playerActions else s.config.npcActions)
        else s.config.stopActions
    if (s.used[id] or 0) >= limit then
        return {}
    end
    local out = { { kind = "wait" } }
    if actor.cash > 0 and s.rentPaid < s.config.rent then
        table.insert(out, {
            kind = "contribute",
            amount = math.min(s.config.payment, actor.cash, s.config.rent - s.rentPaid),
        })
    end
    for _, plan in s.plans do
        if plan.day == s.day and plan.status == "pending" then
            if plan.actor == id then
                table.insert(out, { kind = "cancel_plan", reference = plan.id })
            elseif
                actionPhase(s)
                and actor.role == "player"
                and not table.find(plan.seenBy, id)
            then
                table.insert(out, { kind = "inspect", reference = plan.id })
            elseif actionPhase(s) and actor.role == "player" and table.find(plan.seenBy, id) then
                table.insert(out, { kind = "request_cancel", reference = plan.id })
            end
        end
    end
    if actionPhase(s) then
        for _, item in s.items do
            if not item.resolved and item.creator ~= id then
                local cost = if item.kind == "leak" or item.kind == "roaches"
                    then s.config.repair
                    else s.config.cleanup
                if actor.cash >= cost then
                    table.insert(out, { kind = "pay_cleanup", reference = item.id, amount = cost })
                end
                if actor.role == "player" and (item.kind == "trash" or item.kind == "dishes") then
                    table.insert(out, {
                        kind = if item.kind == "trash" and item.stage == "open"
                            then "pickup_trash"
                            else "finish_chore",
                        reference = item.id,
                    })
                end
            end
        end
    end
    return out
end

function Round.apply(s: any, id: string, revision: number, action: any): (boolean, string)
    if revision ~= s.revision then
        return false, "stale_revision"
    end
    local legal = false
    for _, candidate in Round.candidates(s, id) do
        if U.equal(candidate, action) then
            legal = true
            break
        end
    end
    if not legal then
        return false, "illegal_action"
    end
    s.used[id] = (s.used[id] or 0) + 1
    if action.kind == "contribute" then
        s.actors[id].cash -= action.amount
        s.rentPaid += action.amount
    elseif action.kind == "cancel_plan" then
        planById(s, action.reference).status = "cancelled"
    elseif action.kind == "request_cancel" then
        local plan = planById(s, action.reference)
        emit(
            s,
            "cancel_requested",
            { actor = id, target = plan.actor, reference = plan.id },
            { id, plan.actor }
        )
    elseif action.kind == "inspect" then
        local plan = planById(s, action.reference)
        table.insert(plan.seenBy, id)
        emit(
            s,
            "clue",
            { plan = plan.id, actor = plan.actor, kind = plan.kind, due = plan.due },
            { id }
        )
    elseif action.kind == "pay_cleanup" or action.kind == "finish_chore" then
        local item = itemById(s, action.reference)
        s.actors[id].cash -= action.amount or 0
        item.resolved = true
    elseif action.kind == "pickup_trash" then
        itemById(s, action.reference).stage = "bagged"
    end
    emit(
        s,
        "action",
        { actor = id, action = action },
        if action.kind == "inspect"
                or action.kind == "cancel_plan"
                or action.kind == "request_cancel"
            then { id }
            else nil
    )
    s.revision += 1
    return true, "accepted"
end

function Round.message(
    s: any,
    id: string,
    revision: number,
    channel: string,
    target: string?,
    speech: string
): (boolean, string)
    if s.status ~= "running" or not stopPhase(s) or revision ~= s.revision or not s.actors[id] then
        return false, "wrong_phase_or_actor"
    end
    if channel ~= "group" and channel ~= "private" then
        return false, "invalid_channel"
    end
    if
        (channel == "group" and target ~= nil)
        or (channel == "private" and (not s.actors[target] or target == id))
    then
        return false, "invalid_recipient"
    end
    if
        type(speech) ~= "string"
        or #speech == 0
        or #speech > s.config.speechBytes
        or (s.messageCounts[id] or 0) >= s.config.messages
    then
        return false, "message_budget"
    end
    s.messageCounts[id] = (s.messageCounts[id] or 0) + 1
    emit(
        s,
        "message",
        { actor = id, channel = channel, target = target, speech = speech },
        if channel == "private" then { id, target } else nil
    )
    s.revision += 1
    return true, "accepted"
end

-- Apply one validated decision atomically. Invalid dialogue must not leave a payment behind.
-- A nil action is a communication-only turn and consumes no action effort.
function Round.decide(s: any, id: string, revision: number, action: any?, message: any?): (boolean, string)
    if revision ~= s.revision or s.status ~= "running" or not s.actors[id] then
        return false, "stale_or_finished"
    end
    if action == nil and (not stopPhase(s) or message == nil) then
        return false, "empty_decision"
    end
    local draft = U.copy(s)
    if action ~= nil then
        local ok, reason = Round.apply(draft, id, draft.revision, action)
        if not ok then
            return false, reason
        end
    end
    if message ~= nil then
        if type(message) ~= "table" then
            return false, "invalid_message"
        end
        local ok, reason = Round.message(draft, id, draft.revision, message.channel, message.target, message.speech)
        if not ok then
            return false, reason
        end
    end
    for key, value in draft do
        s[key] = value
    end
    return true, "accepted"
end

local function closeAction(s)
    for _, item in s.items do
        if not item.resolved then
            item.age += 1
            if item.kind == "leak" then
                s.heat += s.config.leakHeat * item.age
            end
            emit(s, "issue_aged", { reference = item.id, age = item.age, heat = s.heat })
        end
    end
    for _, plan in s.plans do
        if plan.day == s.day and plan.status == "pending" and plan.due == s.phase then
            plan.status = "executed"
            addItem(s, plan.kind, plan.actor)
        end
    end
    if roll(s, s.config.leakPercent) then
        addItem(s, "leak", "system")
    end
    if roll(s, s.config.roachPercent + math.floor((100 - cleanliness(s)) / 4)) then
        addItem(s, "roaches", "system")
    end
    local scheduled = s.day == s.config.inspectionDay and s.phase == "action_two"
    if scheduled or roll(s, s.config.randomInspectionPercent) then
        local failed = cleanliness(s) < s.config.inspectionCleanliness
        if failed then
            s.heat += s.config.inspectionHeat
        end
        emit(
            s,
            "inspection",
            { scheduled = scheduled, cleanliness = cleanliness(s), failed = failed, heat = s.heat }
        )
    end
end

function Round.work(s: any, revision: number, score: number): (boolean, string)
    -- Trusted simulation override only; network adapters must use submitWork with answers.
    if s.status ~= "running" or s.phase ~= "work" or revision ~= s.revision or s.workSubmitted then
        return false, "wrong_phase"
    end
    if type(score) ~= "number" or score ~= score or score < 0 or score > 1 then
        return false, "invalid_score"
    end
    for _, id in s.order do
        local actor = s.actors[id]
        local bonus = if actor.role == "player" then math.floor(score * s.config.workBonus) else 0
        local income = math.max(0, actor.income + actor.modifier) + bonus
        actor.cash += income
        local paid = math.min(actor.cash, actor.debt)
        actor.cash -= paid
        actor.debt -= paid
        emit(s, "income", {
            actor = id,
            amount = income,
            modifier = actor.modifier,
            bonus = bonus,
            expenseDebtPaid = paid,
        }, { id })
    end
    s.workSubmitted = true
    if s.workChallenge then
        s.workChallenge.stage = "submitted"
    end
    s.revision += 1
    return true, "accepted"
end

local function prepareWork(s)
    for _, id in s.order do
        if s.actors[id].role == "player" then
            local length = if s.actors[id].tired then s.config.workTiredLength else s.config.workRestedLength
            -- Independent stream: changing work difficulty cannot reroll household incidents.
            local rng = (s.initialSeed + s.day * 7919) % 2147483647
            local sequence = {}
            for _ = 1, length do
                rng = (rng * 16807) % 2147483647
                table.insert(sequence, 1 + rng % s.config.workSymbols)
            end
            s.workChallenge = { id = s.day, actor = id, stage = "preview", sequence = sequence }
        end
    end
end

function Round.workView(s: any, id: string): any
    local c = s.workChallenge
    if s.status ~= "running" or s.phase ~= "work" or not c or c.actor ~= id then
        return nil
    end
    return {
        id = c.id, stage = c.stage, length = #c.sequence, symbols = s.config.workSymbols,
        sequence = if c.stage == "preview" then U.copy(c.sequence) else nil,
    }
end

function Round.beginRecall(s: any, id: string, revision: number, challengeId: number): (boolean, string)
    local c = s.workChallenge
    if s.status ~= "running" or s.phase ~= "work" or s.workSubmitted or revision ~= s.revision
        or not c or c.actor ~= id or c.id ~= challengeId or c.stage ~= "preview" then
        return false, "invalid_challenge"
    end
    c.stage = "recall"
    s.revision += 1
    return true, "accepted"
end

function Round.submitWork(s: any, id: string, revision: number, challengeId: number, answers: any): (boolean, string)
    local c = s.workChallenge
    if s.status ~= "running" or s.phase ~= "work" or s.workSubmitted or revision ~= s.revision
        or not c or c.actor ~= id or c.id ~= challengeId or c.stage ~= "recall" then
        return false, "invalid_challenge"
    end
    if type(answers) ~= "table" or #answers > #c.sequence then
        return false, "invalid_answers"
    end
    for key, value in answers do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #answers
            or type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > s.config.workSymbols then
            return false, "invalid_answers"
        end
    end
    local correct = 0
    for index, answer in answers do
        if c.sequence[index] == answer then
            correct += 1
        end
    end
    local ok, reason = Round.work(s, revision, correct / #c.sequence)
    if ok then
        c.stage = "submitted"
    end
    return ok, reason
end

function Round.outcome(s: any, id: string): any
    local actor = s.actors[id]
    assert(actor, "Unknown actor")
    local goalMet = actor.cash >= actor.goal and actor.debt == 0
    return {
        final = s.status ~= "running", survived = s.status == "horizon", goalMet = goalMet,
        success = s.status == "horizon" and goalMet,
    }
end

function Round.advance(s: any, revision: number): (boolean, string)
    if s.status ~= "running" or revision ~= s.revision then
        return false, "stale_or_finished"
    end
    if s.phase == "work" and not s.workSubmitted then
        return false, "work_result_required"
    end
    emit(s, "phase_closed", { actionsUsed = s.used, messagesSent = s.messageCounts })
    if actionPhase(s) then
        closeAction(s)
    end
    if s.phase == "night" then
        if s.rentPaid < s.config.rent then
            s.heat += s.config.unpaidHeat
        else
            s.heat = math.max(0, s.heat - s.config.paidCooling)
        end
        emit(s, "rent_settled", { due = s.config.rent, paid = s.rentPaid, heat = s.heat })
        for _, plan in s.plans do
            if plan.day == s.day and plan.status == "pending" and plan.due == "overnight" then
                plan.status = "executed"
                s.lastHost = plan.actor
                s.heat += s.config.partyHeat
                emit(s, "party", { host = plan.actor, heat = s.heat })
            end
        end
    end
    s.revision += 1
    if s.heat >= s.config.eviction then
        s.status = "evicted"
        checkpoint(s)
        return true, "evicted"
    end
    if s.phase == "night" and s.day >= s.config.days then
        s.status = "horizon"
        checkpoint(s)
        return true, "horizon"
    end
    local index = table.find(Round.phases, s.phase)
    s.phase = Round.phases[1 + index % #Round.phases]
    s.used, s.messageCounts = {}, {}
    if s.phase == "morning" then
        s.day += 1
        s.workSubmitted = false
        morning(s)
    elseif actionPhase(s) then
        openAction(s)
    elseif s.phase == "work" then
        prepareWork(s)
    elseif stopPhase(s) then
        checkpoint(s)
    end
    return true, "advanced"
end

function Round.observe(s: any, id: string): any
    assert(s.actors[id], "Unknown actor")
    local events, plans, recaps = {}, {}, {}
    for _, event in s.events do
        if U.visible(event, id) then
            table.insert(events, U.copy(event))
        end
    end
    for _, plan in s.plans do
        if plan.day == s.day and table.find(plan.seenBy, id) then
            local visible = U.copy(plan)
            visible.seenBy = nil
            table.insert(plans, visible)
        end
    end
    for _, stop in s.checkpoints do
        local recap = U.copy(stop)
        recap.eventIds = {}
        for _, eventId in stop.eventIds do
            if U.visible(s.events[eventId], id) then
                table.insert(recap.eventIds, eventId)
            end
        end
        table.insert(recaps, recap)
    end
    return {
        actor = U.copy(s.actors[id]),
        actorIds = U.copy(s.order),
        revision = s.revision,
        day = s.day,
        phase = s.phase,
        status = s.status,
        cleanliness = cleanliness(s),
        heat = s.heat,
        rent = s.config.rent,
        rentPaid = s.rentPaid,
        items = U.copy(s.items),
        plans = plans,
        events = events,
        recaps = recaps,
        candidates = Round.candidates(s, id),
        rules = U.copy(s.config),
        messagesRemaining = if s.status == "running" and stopPhase(s)
            then math.max(0, s.config.messages - (s.messageCounts[id] or 0)) else 0,
        work = {
            difficulty = if s.actors[id].tired then s.config.workTiredLength else s.config.workRestedLength,
            bonusCap = s.config.workBonus,
        },
        outcome = Round.outcome(s, id),
        goalMet = s.actors[id].cash >= s.actors[id].goal and s.actors[id].debt == 0,
    }
end

return Round
