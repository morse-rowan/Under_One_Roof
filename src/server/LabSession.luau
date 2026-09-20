--!strict
-- Server integration seam. A caller binds authenticated controllers; never send exportState to clients.
local Lab =
    require(if script then game:GetService("ReplicatedStorage").Shared.Lab else "../shared/Lab")
local Session = {}
Session.__index = Session

function Session.new(config: any, seed: number)
    return setmetatable({ config = config, state = Lab.new(config, seed) }, Session)
end

function Session:observe(actorId: string)
    return Lab.observe(self.state, self.config, actorId)
end

function Session:request(actorId: string, proposal: any): (boolean, string)
    -- The outer server maps Player/controller identity to actorId, never trusts a client-supplied ID.
    if type(proposal) ~= "table" or proposal.actor ~= actorId then
        return false, "controller_actor_mismatch"
    end
    return Lab.apply(self.state, self.config, proposal)
end

function Session:advance(): (boolean, string)
    return Lab.advance(self.state, self.config)
end

function Session:exportState()
    return Lab.save(self.state)
end

return Session
