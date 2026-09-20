--!strict
-- One server-side transaction for prose plus an explicitly attached legal chip.
local Actions = require(if script then script.Parent.HousepadActions else "./HousepadActions")
local Send = {}

function Send.submit(round: any, state: any, actor: string, request: any): (boolean, string)
    if type(request) ~= "table" or type(request.speech) ~= "string" then
        return false, "Enter a message or attach an action."
    end
    local speech = string.match(request.speech, "^%s*(.-)%s*$") or ""
    if #speech > state.config.speechBytes then
        return false, "That message is too long. Shorten it before sending."
    end
    local candidate
    if request.attachment ~= nil then
        if type(request.attachment) ~= "table" or request.revision ~= state.revision then
            return false, "The household changed. Review your action and send again."
        end
        local chip = request.attachment
        candidate =
            Actions.resolve(round.observe(state, actor), chip.kind, chip.reference, chip.amount)
        if not candidate then
            return false, "That action is no longer available. Choose another chip."
        end
    end
    local envelope
    if #speech > 0 then
        envelope = {
            channel = request.channel,
            target = request.target,
            speech = speech,
        }
    elseif not candidate then
        return false, "Enter a message or attach an action."
    end
    local ok, reason = round.decide(state, actor, state.revision, candidate, envelope)
    if not ok then
        return false,
            if reason == "message_budget" or reason == "wrong_phase_or_actor"
                then "Chat is closed or used up. Your action was not spent."
                else "That message or action is no longer legal. Nothing was spent."
    end
    return true,
        if candidate then "Action completed. See activity for the receipt." else "Message sent."
end

return Send
