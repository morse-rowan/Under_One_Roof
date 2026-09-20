--!strict
-- Engine-independent authority. Config and the roommate adapter are injected.
local Simulation = {}

export type Task = { status: string, owner: string, payment: number }
export type Conversation = { roommate: string, messages: number, finalized: boolean }
export type State = {
    day: number,
    phase: string,
    cash: number,
    property: number,
    heat: number,
    conversationsLeft: number,
    effort: number,
    remaining: number,
    tasks: { [string]: Task },
    trust: { [string]: number },
    conversation: Conversation?,
    log: { string },
    report: { string },
}

local function log(state: State, message: string)
    table.insert(state.log, message)
    if #state.log > 16 then
        table.remove(state.log, 1)
    end
end

local function prepare(state: State, config: any)
    state.phase = "planning"
    state.conversationsLeft = config.conversations
    state.effort = config.effort
    state.remaining = config.actionSeconds
    state.conversation = nil
    state.tasks = {}
    for _, id in config.taskOrder do
        state.tasks[id] = { status = "open", owner = "", payment = 0 }
    end
    log(
        state,
        "Day "
            .. state.day
            .. ": the leak is back, dishes are piling up, and Red has invited friends."
    )
end

function Simulation.new(config: any): State
    local state: State = {
        day = 1,
        phase = "planning",
        cash = config.startingCash,
        property = 100,
        heat = 10,
        conversationsLeft = 0,
        effort = 0,
        remaining = 0,
        tasks = {},
        trust = { Blue = 0, Green = 0, Red = 0 },
        conversation = nil,
        log = {},
        report = {},
    }
    prepare(state, config)
    return state
end

function Simulation.openConversation(state: State, roommate: any, config: any): (boolean, string)
    if state.phase ~= "planning" then
        return false, "Conversations happen during planning."
    end
    if type(roommate) ~= "string" or not config.roommates[roommate] then
        return false, "Choose a roommate."
    end
    if state.conversation and state.conversation.roommate == roommate then
        return true, "Conversation resumed."
    end
    if state.conversationsLeft <= 0 then
        return false, "No conversations left today."
    end
    state.conversationsLeft -= 1
    state.conversation = { roommate = roommate, messages = 0, finalized = false }
    return true, config.roommates[roommate].hint
end

function Simulation.message(
    state: State,
    text: any,
    terms: any,
    config: any,
    adapter: any
): (boolean, string)
    local conversation = state.conversation
    if state.phase ~= "planning" or not conversation then
        return false, "Open a conversation first."
    end
    if conversation.finalized then
        return false, "This conversation already finalized a deal."
    end
    if conversation.messages >= config.messages then
        return false, "Three messages used. Choose your next priority."
    end
    if type(text) ~= "string" or #text > 240 then
        return false, "Use at most 240 bytes of text."
    end
    if terms ~= nil then
        if
            type(terms) ~= "table"
            or type(terms.task) ~= "string"
            or not state.tasks[terms.task]
            or type(terms.amount) ~= "number"
            or terms.amount ~= terms.amount
            or terms.amount < 0
            or terms.amount > 100
            or terms.amount % 5 ~= 0
        then
            return false, "Attach a valid task and an offer from $0 to $100 in $5 steps."
        end
        if state.tasks[terms.task].status ~= "open" then
            return false, "That task already has an owner."
        end
        if state.cash < terms.amount then
            return false, "You cannot afford that offer."
        end
    elseif not string.find(text, "%S") then
        return false, "Write a message or attach a task."
    end

    -- Adapter failure never spends a message or creates a deal. Prose alone is inert.
    local ok, reply = pcall(adapter.respond, {
        roommate = conversation.roommate,
        trust = state.trust[conversation.roommate],
        text = text,
        task = if terms then terms.task else nil,
        amount = if terms then terms.amount else 0,
    }, config)
    if
        not ok
        or type(reply) ~= "table"
        or type(reply.text) ~= "string"
        or #reply.text > 500
        or type(reply.accept) ~= "boolean"
        or type(reply.trustDelta) ~= "number"
        or reply.trustDelta ~= reply.trustDelta
        or math.abs(reply.trustDelta) > 2
    then
        return false, "Roommate unavailable. Your message budget and money are unchanged."
    end
    conversation.messages += 1
    local roommate = conversation.roommate
    state.trust[roommate] = math.clamp(state.trust[roommate] + reply.trustDelta, -5, 5)
    log(state, roommate .. ": " .. reply.text)
    if terms and reply.accept and config.roommates[roommate].task == terms.task then
        state.cash -= terms.amount
        state.tasks[terms.task] = { status = "assigned", owner = roommate, payment = terms.amount }
        conversation.finalized = true
        log(
            state,
            "Deal recorded: "
                .. roommate
                .. " / "
                .. config.tasks[terms.task].name
                .. " / $"
                .. terms.amount
                .. " reserved."
        )
    end
    return true, reply.text
end

function Simulation.startAction(state: State): (boolean, string)
    if state.phase ~= "planning" then
        return false, "The action phase is already underway."
    end
    state.phase = "action"
    state.conversation = nil
    return true, "Two efforts. Four problems. Walk to a station and hold E."
end

function Simulation.completeTask(state: State, id: any, config: any): (boolean, string)
    if state.phase ~= "action" then
        return false, "Start the action phase first."
    end
    local taskState = if type(id) == "string" then state.tasks[id] else nil
    if not taskState or taskState.status ~= "open" then
        return false, "That task is already handled or assigned."
    end
    if state.effort <= 0 then
        return false, "No effort left. End the day to see what your roommates do."
    end
    local taskConfig = config.tasks[id]
    if state.cash < taskConfig.cost then
        return false, "You need $" .. taskConfig.cost .. " for utilities."
    end
    state.cash -= taskConfig.cost
    state.effort -= 1
    taskState.status = "done"
    taskState.owner = "You"
    log(state, "You: " .. taskConfig.name .. ".")
    return true, taskConfig.name .. " complete."
end

function Simulation.resolve(state: State, config: any): (boolean, string)
    if state.phase ~= "action" then
        return false, "There is no action phase to resolve."
    end
    state.report = {}
    for _, id in config.taskOrder do
        local item = state.tasks[id]
        if item.status == "assigned" then
            item.status = "done"
            state.trust[item.owner] = math.min(5, state.trust[item.owner] + 1)
            table.insert(
                state.report,
                item.owner
                    .. " kept the deal: "
                    .. config.tasks[id].name
                    .. " ($"
                    .. item.payment
                    .. ")."
            )
        elseif item.status == "done" then
            table.insert(state.report, "You handled: " .. config.tasks[id].name .. ".")
        elseif id == "leak" then
            state.property -= 25
            table.insert(state.report, "The leak spread. Property -25.")
        elseif id == "dishes" then
            state.property -= 10
            state.heat += 5
            table.insert(state.report, "Dirty dishes attracted pests. Property -10; heat +5.")
        elseif id == "party" then
            state.heat += 25
            state.trust.Red = math.min(5, state.trust.Red + 1)
            table.insert(state.report, "Red threw the party. Neighbor complaint: heat +25.")
        elseif id == "bill" then
            state.heat += 20
            table.insert(state.report, "Utilities went unpaid. Landlord heat +20.")
        end
    end
    if state.tasks.party.status == "done" and state.tasks.party.owner == "You" then
        state.trust.Red = math.max(-5, state.trust.Red - 1)
        table.insert(state.report, "Red resents you cancelling the party without a deal.")
    end
    if state.tasks.party.status == "done" and state.tasks.bill.status == "done" then
        state.heat -= 5
        table.insert(state.report, "A quiet, paid-up evening cooled landlord heat by 5.")
    end
    state.property = math.clamp(state.property, 0, 100)
    state.heat = math.clamp(state.heat, 0, 100)
    state.remaining = 0
    state.phase = if state.property <= 0 or state.heat >= 100
        then "lost"
        elseif state.day >= config.days then "won"
        else "results"
    for _, line in state.report do
        log(state, line)
    end
    return true,
        if state.phase == "lost"
            then "Evicted. Try a different split of money, effort, and diplomacy."
            elseif state.phase == "won" then "You kept the apartment for three days!"
            else "Day complete. Review the consequences."
end

function Simulation.tick(state: State, elapsed: number, config: any): boolean
    if state.phase ~= "action" or elapsed <= 0 then
        return false
    end
    state.remaining = math.max(0, state.remaining - elapsed)
    if state.remaining <= 0 then
        Simulation.resolve(state, config)
    end
    return true
end

function Simulation.nextDay(state: State, config: any): (boolean, string)
    if state.phase ~= "results" then
        return false, "Finish the current day first."
    end
    state.day += 1
    prepare(state, config)
    return true, "New day. Cash, damage, landlord heat, and relationships carry over."
end

return Simulation
