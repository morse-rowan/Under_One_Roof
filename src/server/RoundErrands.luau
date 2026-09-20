--!strict
-- Walks the roommates through the action windows.
--
-- `RoundRoutine` decides where a roommate is going and why; this module owns the
-- pacing and the Roblox side: one hop at a time through the sandbox handle, then a
-- single replayed action when it arrives. The action is an ordinary legal candidate,
-- committed through `MvpRound` exactly as a player's click is, so watching Green
-- cross the kitchen and clear the sink and reading "Green handled outstanding
-- requirement #3" are the same event.
--
-- Deliberately deterministic: the errands come from `RoundPolicy`, not from a model.
-- With the bridge off, the apartment still looks busy.
local Errands = {}

-- Slower than a player's hop on purpose: roommates should read as moving around the
-- room, not racing the player to the sink.
Errands.stepSeconds = 0.34
-- A beat before anyone sets off, staggered so four beans do not start in lockstep.
Errands.thinkSeconds = 0.7

function Errands.new(deps: any): any
    local sandbox = deps.sandbox
    local Round = deps.round
    local Policy = deps.policy
    local Routine = deps.routine
    local beans = deps.beans
    local roommates = sandbox.roommates
    local config = sandbox.config
    local ACTION_PHASES = { action_one = true, action_two = true }
    -- Stable order, so the same round always staggers the same roommates the same way.
    local order = {}
    for id in beans do
        table.insert(order, id)
    end
    table.sort(order)

    local service = {}

    local function phaseKey(state: any): string
        return state.day .. "|" .. state.phase .. "|" .. tostring(state.status)
    end

    -- One roommate's plan for this window, rebuilt whenever it goes stale.
    local function plan(session: any, id: string): any
        local observation = Round.observe(session.state, id)
        local home = roommates.homeOf(beans[id])
        if not home then
            return nil
        end
        local errand = Routine.errand(config, observation, Policy, home, roommates.blocked)
        errand.done = false
        return errand
    end

    -- Called every heartbeat. Cheap when nothing is due: one clock comparison.
    function service.update(session: any)
        if not roommates.enabled or session.busy then
            return
        end
        local state = session.state
        session.errands = session.errands or {}
        local errands = session.errands
        local key = phaseKey(state)
        if errands.key ~= key then
            errands.key = key
            errands.actors = {}
            for index, id in order do
                errands.actors[id] = {
                    startsAt = os.clock() + Errands.thinkSeconds * index,
                    nextStep = 0,
                    errand = nil,
                }
            end
        end

        local acting = state.status == "running" and ACTION_PHASES[state.phase] == true
        local now = os.clock()
        for _, id in order do
            local bean = beans[id]
            local slot = errands.actors[id]
            local cell = roommates.cellOf(bean)
            if slot and cell and now >= slot.startsAt and now >= slot.nextStep then
                slot.nextStep = now + Errands.stepSeconds
                if not roommates.busy(bean) then
                    service.tick(session, id, bean, slot, cell, acting)
                end
            end
        end
    end

    -- One roommate, one beat: arrive and act, take a step, or stand still.
    function service.tick(
        session: any,
        id: string,
        bean: string,
        slot: any,
        cell: any,
        acting: boolean
    )
        local home = roommates.homeOf(bean)
        if not acting then
            -- Between windows everyone drifts back to their own spot, so a stop
            -- always looks the same way twice.
            slot.errand = nil
            if home and not Routine.arrived(cell, home) then
                service.walk(bean, cell, home)
            end
            return
        end

        local observation = Round.observe(session.state, id)
        local errand = slot.errand
        if errand and not errand.done then
            -- The player may have cleared the mess first, or spent the roommate's
            -- budget elsewhere. A retired errand is replaced, never forced through.
            if errand.action and not Routine.stillLegal(observation, errand.action) then
                errand = nil
            end
        end
        if not errand then
            errand = plan(session, id)
            slot.errand = errand
            if not errand then
                return
            end
        end

        if not Routine.arrived(cell, errand.goal) then
            service.walk(bean, cell, errand.goal)
            return
        end
        if errand.done or not errand.action or errand.action.kind == "wait" then
            -- Home again, or nothing worth doing. A wait is left for the end of the
            -- phase: spending the budget on it now would stop the roommate reacting
            -- to whatever the player does next.
            return
        end
        errand.done = true
        if deps.commit(session, id, errand.action) then
            print(
                string.format(
                    "[Errand] %s %s%s",
                    id,
                    errand.action.kind,
                    if errand.action.reference
                        then " #" .. tostring(errand.action.reference)
                        else ""
                )
            )
            deps.changed(session)
        end
        -- Whatever happened, head back rather than loitering at the sink.
        slot.errand = { action = nil, goal = home, station = nil, done = true }
    end

    function service.walk(bean: string, cell: any, goal: any)
        local steps = Routine.path(config, cell, goal, roommates.blocked)
        if steps and steps[1] then
            roommates.step(bean, steps[1])
        end
    end

    return service
end

return Errands
