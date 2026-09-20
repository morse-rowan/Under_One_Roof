--!strict
-- Explicit attachments are separate from prose. Selecting a chip never spends it.
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Actions = require(shared:WaitForChild("HousepadActions"))
local Guide = require(shared:WaitForChild("RoundGuide"))
local Text = require(shared:WaitForChild("RoundText"))
local Kit = require(script.Parent.MenuKit)
local Composer = {}

function Composer.render(panel: Instance, o: any, view: any, actions: any, ui: any): TextBox
    local c = ui.palette
    local channel = view.channel or "group"
    view.attachments = view.attachments or {}
    local selected = view.attachments[channel]
    local available = o.messagesRemaining > 0 and o.status == "running"
    local box = Kit.make("TextBox", {
        Name = "Composer",
        Position = UDim2.fromOffset(16, 359),
        Size = UDim2.fromOffset(500, 38),
        BackgroundColor3 = c.paper,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = (view.drafts and view.drafts[channel]) or "",
        TextColor3 = c.ink,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextEditable = available,
        PlaceholderText = if available
            then "Message · attach an action below"
            else "Chat reopens at the next stop · chips still work",
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, panel)
    Kit.corner(box, 19)
    Kit.stroke(box, c.line, 1)
    Kit.pad(box, 0, 14, 0, 14)
    local attachment = ui.frame(panel, "Attachment", 16, 320, 595, 31, c.rail, 10)
    local caption = ui.label(attachment, "", 10, 0, 535, 31, 12, c.ink, true)
    local function refresh()
        selected = view.attachments[channel]
        attachment.Visible = selected ~= nil
        caption.Text = if selected then Guide.choice(selected, o) .. " · 1 choice" else ""
    end
    ui.button(attachment, "RemoveChip", "×", 550, 0, 35, 31, false, function()
        view.attachments[channel] = nil
        refresh()
    end)
    refresh()

    local picker = ui.frame(panel, "ActionPicker", 16, 67, 595, 211, c.rail, 12)
    picker.Visible = false
    picker.ZIndex = 3
    local heading = ui.label(picker, "", 12, 4, 515, 28, 14, c.ink, true)
    local list = Kit.scroller(picker, {
        Name = "PickerOptions",
        Position = UDim2.fromOffset(10, 38),
        Size = UDim2.fromOffset(575, 164),
    })
    Kit.column(list, 5)
    local function close()
        picker.Visible = false
    end
    ui.button(picker, "ClosePicker", "×", 548, 2, 35, 30, false, close)
    local function open(mode)
        list:ClearAllChildren()
        Kit.column(list, 5)
        picker.Visible = true
        heading.Text = if mode == "@"
            then "@ Choose a private conversation"
            elseif mode == "#" then "# Attach a money choice"
            else "! Investigate or prevent trouble"
        if mode == "@" then
            for _, id in o.actorIds do
                if id ~= o.actor.id then
                    ui.button(
                        list,
                        "Recipient_" .. id,
                        "@" .. Text.name(id) .. " · private",
                        0,
                        0,
                        555,
                        34,
                        false,
                        function()
                            actions.channel(id)
                        end
                    )
                end
            end
        else
            local options = Actions.options(o, mode)
            for index, option in options do
                local row = ui.button(
                    list,
                    "Attach_" .. index,
                    option.token .. " · " .. option.label,
                    0,
                    0,
                    555,
                    38,
                    false,
                    function()
                        view.attachments[channel] = option.action
                        refresh()
                        close()
                    end
                )
                row.LayoutOrder = index
            end
            if #options == 0 then
                ui.label(
                    list,
                    "No legal choices here right now. Investigations open during action phases; spent choices return next phase.",
                    8,
                    4,
                    535,
                    70,
                    13,
                    c.muted
                )
            end
        end
    end
    for index, info in { { "@", "@ Roommate" }, { "#", "# Money" }, { "!", "! Trouble" } } do
        ui.button(
            panel,
            "Picker_" .. info[1],
            info[2],
            16 + (index - 1) * 148,
            284,
            140,
            28,
            false,
            function()
                open(info[1])
            end
        )
    end
    ui.label(panel, "Pick, then send", 465, 284, 145, 28, 11, c.muted)
    local function submit()
        local speech = if available then (string.match(box.Text, "^%s*(.-)%s*$") or "") else ""
        -- Symbol-only input opens discovery. It is never interpreted as a payment.
        if not selected and (speech == "@" or speech == "#" or speech == "!") then
            open(speech)
            return
        end
        if selected or (available and #speech > 0) then
            actions.say(channel, speech, selected)
        end
    end
    ui.onEnter(box, submit)
    local send = ui.button(panel, "Send", "Send", 527, 359, 84, 38, true, submit)
    send.BackgroundColor3 = c.blue
    ui.label(
        panel,
        string.format(
            "%d messages left · attached actions use a choice · words alone do not execute",
            o.messagesRemaining
        ),
        20,
        403,
        575,
        15,
        10,
        c.muted
    )
    return box
end

return Composer
