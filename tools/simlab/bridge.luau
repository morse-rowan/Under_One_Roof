local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local Lab = require("../../src/shared/Lab")
while true do
    local line = stdio.readLine()
    if not line or line == "" then
        break
    end
    local ok, result = pcall(function()
        local request = serde.decode("json", line)
        if request.op == "new" then
            return { state = Lab.new(request.config, request.seed) }
        end
        local state = Lab.load(request.state)
        if request.op == "observe" then
            return {
                observation = Lab.observe(state, request.config, request.actor or Lab.actor(state)),
            }
        elseif request.op == "step" then
            local accepted, reason
            if request.proposal then
                accepted, reason = Lab.apply(state, request.config, request.proposal)
            else
                accepted, reason = Lab.advance(state, request.config)
            end
            return { state = state, accepted = accepted, reason = reason }
        elseif request.op == "modules" then
            local modules = {}
            for _, module in Lab.modules do
                table.insert(modules, {
                    name = module.name,
                    actions = module.actions,
                    metrics = module.metrics,
                    configuration = module.configuration,
                    observation = module.observation,
                })
            end
            return { modules = modules }
        end
        error("Unknown bridge operation")
    end)
    stdio.write(
        serde.encode(
            "json",
            if ok then { ok = true, result = result } else { ok = false, error = tostring(result) }
        ) .. "\n"
    )
end
