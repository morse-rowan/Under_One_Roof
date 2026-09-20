--!strict
local Link = require("../src/shared/NemotronLink")
local roommates = require("../src/shared/VisualStudy").roommates

return function()
    local named = false
    for _, data in roommates do
        named = named or data.name == Link.speaker
    end
    assert(named, "The bubble speaker must be a roommate the scene actually builds")

    local prompt = Link.prompt("  Whose turn\n is the sink?  ")
    assert(prompt == "Whose turn is the sink?", "Whitespace is collapsed, not rejected")
    assert(Link.body(prompt :: string).speaker == Link.speaker, "Requests name the speaker")
    assert(Link.body(prompt :: string).prompt == prompt, "Requests send the cleaned prompt")

    for _, bad in { "", "   ", "\n\t", 7, {}, "hi\0there", "bell\7" } do
        local value, reason = Link.prompt(bad)
        assert(value == nil and #reason > 0, "Empty/control/non-string input must be refused")
    end
    assert(Link.prompt(nil) == nil, "A missing prompt is refused")
    local long, reason = Link.prompt(string.rep("x", Link.maxPrompt + 1))
    assert(long == nil and string.find(reason, tostring(Link.maxPrompt)), "Length cap is explained")
    assert(Link.prompt(string.rep("x", Link.maxPrompt)) ~= nil, "The cap itself is allowed")

    local text, ok = Link.reply(200, { ok = true, text = "  Not mine.\nYours. " })
    assert(ok and text == "Not mine. Yours.", "A good reply is collapsed and shown")
    assert(utf8.len(Link.clip(string.rep("y", 400))) == Link.maxReply, "Long replies are clipped")
    assert(
        utf8.len(Link.clip(string.rep("é", 400))) == Link.maxReply,
        "Clipping counts characters"
    )
    assert(Link.clip("bad \xff bytes") == "(unreadable reply)", "Invalid UTF-8 is not displayed")
    assert(select(2, Link.reply(200, { ok = true, text = "   " })) == false, "Blank text fails")

    for _, case in
        {
            { 200, { ok = false, error = "http 401" } },
            { 200, { ok = true, text = 42 } },
            { 200, "not a table" },
            { 200, nil },
            { 429, { ok = false, error = "call cap reached" } },
            { 502, { ok = true, text = "ignored" } },
        }
    do
        local message, answered = Link.reply(case[1], case[2])
        assert(not answered, "Unexpected responses must not count as answers")
        local size = utf8.len(message)
        assert(size and size > 0 and size <= Link.maxReply, "Failures still show readable text")
    end
    assert(string.find(select(1, Link.reply(200, { ok = false, error = "http 401" })), "401"))

    assert(string.find(Link.url, "^http://127%.0%.0%.1:%d+/"), "Only the loopback bridge is called")
    assert(Link.cooldownSeconds > 0, "Repeat asks are throttled")
end
