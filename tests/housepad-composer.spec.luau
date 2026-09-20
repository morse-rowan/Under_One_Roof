--!strict
-- Verifies deliberate selection/dispatch, not pixel layout or typography.
local Env = require("./support/roblox-env")
local Round = require("../src/simulation/MvpRound")
local Setup = require("../src/shared/RoundSetup")

return function()
    local load = Env.new()
    local View = load("src/client/HousepadView.luau")
    local Composer = load("src/client/HousepadComposer.luau")
    local clicks, sent = {}, {}
    View.connect = function(node, callback)
        clicks[node] = callback
    end
    View.onEnter = function() end
    local panel = Env.Instance.new("Frame")
    local s = Round.new(Setup.actors, 13)
    local o = Round.observe(s, "blue")
    local view = { channel = "group", drafts = {} }
    local selectedChannel
    local actions = {
        say = function(channel, speech, chip)
            table.insert(sent, { channel = channel, speech = speech, chip = chip })
        end,
        channel = function(channel)
            selectedChannel = channel
        end,
    }
    local box = Composer.render(panel, o, view, actions, View)
    clicks[panel:FindFirstChild("Picker_#", true)]()
    local option = panel:FindFirstChild("Attach_2", true)
    assert(option, "rent is discoverable in the money picker")
    clicks[option]()
    assert(#sent == 0 and view.attachments.group.kind == "contribute", "selection only attaches")
    box.Text = "I can cover this part."
    clicks[panel:FindFirstChild("Send", true)]()
    assert(#sent == 1 and sent[1].chip.kind == "contribute", "explicit send includes attachment")
    assert(sent[1].speech == box.Text and sent[1].channel == "group", "prose and channel preserved")
    clicks[panel:FindFirstChild("RemoveChip", true)]()
    assert(view.attachments.group == nil, "attachment is removable before submission")
    clicks[panel:FindFirstChild("Picker_@", true)]()
    clicks[panel:FindFirstChild("Recipient_green", true)]()
    assert(selectedChannel == "green", "recipient picker selects the private conversation")
    box.Text = "#"
    clicks[panel:FindFirstChild("Send", true)]()
    assert(#sent == 1, "symbol-only input opens discovery without spending or sending")
    assert(panel:FindFirstChild("ActionPicker", true).Visible, "discovery is visible")
end
