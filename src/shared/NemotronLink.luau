--!strict
-- Engine-independent rules for the Nemotron sanity check: what we are willing to
-- send, and what we are willing to display. Roblox services, HTTP and UI live in
-- `src/server/NemotronSanity.luau`; the credential never leaves the local bridge.
local Link = {}

Link.url = "http://127.0.0.1:8787/ask"
Link.speaker = "Green"
Link.maxPrompt = 300
Link.maxReply = 200
Link.cooldownSeconds = 2

local function collapse(text: string): string
    return (string.gsub(string.gsub(text, "%s+", " "), "^ *(.-) *$", "%1"))
end

-- Accepts a typed line, or returns nil with a short reason to show in the bubble.
function Link.prompt(value: any): (string?, string)
    if type(value) ~= "string" then
        return nil, "Send a short line of text."
    end
    if string.find(value, "[%z\1-\8\11\12\14-\31\127]") then
        return nil, "That line has characters I cannot send."
    end
    local text = collapse(value)
    if #text == 0 then
        return nil, "Send a short line of text."
    end
    if #text > Link.maxPrompt then
        return nil, string.format("Keep it under %d characters.", Link.maxPrompt)
    end
    return text, ""
end

function Link.body(prompt: string): { [string]: any }
    return { prompt = prompt, speaker = Link.speaker }
end

-- Counted in code points, since a model reply may contain non-ASCII characters.
function Link.clip(text: string): string
    local tidy = collapse(text)
    local length = utf8.len(tidy)
    if not length then
        return "(unreadable reply)"
    end
    if length <= Link.maxReply then
        return tidy
    end
    local cut = utf8.offset(tidy, Link.maxReply) or Link.maxReply
    return string.sub(tidy, 1, cut - 1) .. "\u{2026}"
end

-- Turns a bridge response into (displayText, ok). Any unexpected shape is a
-- deterministic fallback rather than an error: the sanity check must stay visible.
function Link.reply(status: any, decoded: any): (string, boolean)
    if status == 429 then
        return "The bridge hit its call cap.", false
    end
    if type(decoded) ~= "table" then
        return "The bridge sent something I could not read.", false
    end
    if decoded.ok ~= true or type(decoded.text) ~= "string" or #collapse(decoded.text) == 0 then
        local detail = if type(decoded.error) == "string" and #decoded.error > 0
            then " (" .. Link.clip(decoded.error) .. ")"
            else ""
        return "Nemotron did not answer" .. detail .. ".", false
    end
    if status ~= 200 then
        return "The bridge reported HTTP " .. tostring(status) .. ".", false
    end
    return Link.clip(decoded.text), true
end

return Link
