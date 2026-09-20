--!strict
local U = require(if script then script.Parent.LabUtil else "./LabUtil")
local Economy = {
    name = "economy",
    configuration = { "economy" },
    actions = { "contribute", "transfer", "lend", "repay" },
    metrics = { "paid", "unpaid", "income", "expenses", "transfers", "contributions" },
    observation = "own finances; public obligations; debts visible to participants",
}

function Economy.startDay(state: any, config: any)
    local amount = config.economy.bill
    if config.economy.bill_jitter > 0 then
        amount += U.random(state, "events", config.economy.bill_jitter + 1) - 1
    end
    state.bill = { amount = amount, paid = 0, day = state.day }
    for _, id in state.order do
        local actor = state.actors[id]
        actor.cash += actor.income
        state.totals.income += actor.income
        U.emit(state, "income", id, { amount = actor.income }, { id })
    end
    U.emit(state, "bill_opened", "world", state.bill)
end

function Economy.candidates(state: any, config: any, id: string, out: any)
    if state.phase ~= "action" then
        return
    end
    local actor = state.actors[id]
    local amount = math.min(config.economy.unit, actor.cash, state.bill.amount - state.bill.paid)
    if amount > 0 then
        table.insert(out, { kind = "contribute", amount = amount })
    end
    for _, target in state.order do
        if target ~= id and actor.cash >= config.economy.unit then
            table.insert(out, { kind = "transfer", target = target, amount = config.economy.unit })
            if config.mechanics.debt then
                table.insert(out, { kind = "lend", target = target, amount = config.economy.unit })
            end
        end
    end
    for _, debt in state.debts do
        if debt.borrower == id and debt.balance > 0 and actor.cash > 0 then
            table.insert(out, {
                kind = "repay",
                reference = debt.id,
                amount = math.min(actor.cash, debt.balance, config.economy.unit),
            })
        end
    end
end

function Economy.apply(state: any, config: any, id: string, action: any): boolean
    local actor = state.actors[id]
    if action.kind == "contribute" then
        actor.cash -= action.amount
        actor.contributed += action.amount
        state.bill.paid += action.amount
        state.totals.expenses += action.amount
        U.emit(state, "contributed", id, { amount = action.amount })
    elseif action.kind == "transfer" or action.kind == "lend" then
        actor.cash -= action.amount
        state.actors[action.target].cash += action.amount
        state.totals.transfers += action.amount
        U.emit(state, action.kind, id, action, { id, action.target })
        if action.kind == "lend" then
            table.insert(state.debts, {
                id = "d" .. (#state.debts + 1),
                lender = id,
                borrower = action.target,
                balance = action.amount,
                due = state.day + config.economy.debt_days,
            })
        end
    elseif action.kind == "repay" then
        for _, debt in state.debts do
            if debt.id == action.reference then
                actor.cash -= action.amount
                state.actors[debt.lender].cash += action.amount
                debt.balance -= action.amount
                state.totals.transfers += action.amount
                U.relate(state, debt.lender, id, config.social.fulfilled_trust)
                U.emit(state, "repaid", id, action, { id, debt.lender })
            end
        end
    else
        return false
    end
    return true
end

function Economy.settle(state: any, config: any)
    if state.bill.paid < state.bill.amount then
        state.heat += config.economy.unpaid_heat
        state.totals.unpaid += 1
        U.emit(state, "bill_unpaid", "world", state.bill)
    else
        state.heat = math.max(0, state.heat - config.economy.paid_cooling)
        state.totals.paid += 1
        U.emit(state, "bill_paid", "world", state.bill)
    end
    for _, debt in state.debts do
        if debt.balance > 0 and debt.due == state.day then
            U.relate(state, debt.lender, debt.borrower, -config.social.breach_trust)
            U.emit(state, "debt_overdue", debt.borrower, debt, { debt.lender, debt.borrower })
        end
    end
end

return Economy
