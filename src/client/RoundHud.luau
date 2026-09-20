--!strict
-- Live HousePad transport. All choices and metrics come from server state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local View = require(script.Parent.HousepadView)
local Home = require(script.Parent.HomeScreen)
local Kit = require(script.Parent.MenuKit)
local Hud = {}

function Hud.start()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local remote = ReplicatedStorage:WaitForChild("RoundLink") :: RemoteEvent
    local payload: any = nil
    -- The session opens on the home screen. No phase advances while it is up,
    -- because the round only moves on an explicit request.
    local view: any = {
        channel = "group",
        apartment = false,
        metric = nil,
        drafts = {},
        home = true,
        homeTab = "home",
        visited = false,
        color = nil,
    }
    local handles: any = {}
    local sendSequence = 0
    local gui = Kit.make("ScreenGui", {
        Name = "RoundHud",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 20,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player:WaitForChild("PlayerGui"))
    local backdrop = Kit.make("Frame", {
        Name = "Backdrop",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = View.background,
        BorderSizePixel = 0,
    }, gui)
    local canvas = Kit.make("Frame", {
        Name = "Canvas",
        Size = UDim2.fromOffset(View.size.X, View.size.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1,
    }, gui)

    local function saveDraft()
        if handles.chat and handles.chat.Parent then
            view.drafts[view.channel] = handles.chat.Text
        end
        if handles.command and handles.command.Parent then
            view.commandDraft = handles.command.Text
        end
    end

    local function fit()
        local camera = workspace.CurrentCamera
        if camera and handles.scale then
            local viewport = camera.ViewportSize
            handles.scale.Scale = math.min(viewport.X / View.size.X, viewport.Y / View.size.Y)
        end
    end

    local redraw
    local actions: any = {}
    actions.act = function(candidate)
        remote:FireServer({
            kind = "action",
            action = candidate.kind,
            reference = candidate.reference,
        })
    end
    actions.ready = function()
        if payload and payload.busy then
            return
        end
        remote:FireServer({ kind = "ready" })
    end
    actions.say = function(channel, speech, attachment)
        if view.pendingMessage then
            return
        end
        sendSequence += 1
        view.pendingMessage = { channel = channel, speech = speech, requestId = sendSequence }
        remote:FireServer({
            kind = "message",
            requestId = sendSequence,
            revision = payload.observation.revision,
            attachment = attachment,
            channel = if channel == "group" then "group" else "private",
            target = if channel == "group" then nil else channel,
            speech = speech,
        })
    end
    actions.restart = function()
        remote:FireServer({ kind = "restart" })
    end
    actions.channel = function(id)
        saveDraft()
        view.channel = id
        view.actionChat = id ~= "activity"
        redraw()
    end
    actions.metric = function(id)
        saveDraft()
        view.metric = if view.metric == id then nil else id
        view.apartment = false
        redraw()
    end
    actions.apartment = function()
        saveDraft()
        view.apartment = not view.apartment
        redraw()
    end
    actions.play = function()
        view.home = false
        view.visited = true
        -- Entering settles the colour on the server; nothing else changes.
        remote:FireServer({ kind = "enter" })
        redraw()
    end
    actions.color = function(id)
        -- Optimistic: the server rebuilds the day-one household in this colour
        -- and its next state confirms it.
        view.color = id
        remote:FireServer({ kind = "color", color = id })
        redraw()
    end
    actions.home = function()
        saveDraft()
        view.home = true
        view.homeTab = "home"
        redraw()
    end
    actions.homeTab = function(id)
        view.homeTab = id
        redraw()
    end
    actions.newRound = function()
        remote:FireServer({ kind = "newRound", color = view.color })
        view.home = false
        view.visited = true
        view.apartment = false
        view.channel = "group"
        view.metric = nil
        view.drafts = {}
        redraw()
    end
    actions.command = function(text)
        remote:FireServer({ kind = "command", text = text })
        view.commandDraft = ""
        if handles.command then
            handles.command.Text = ""
        end
    end

    function redraw()
        handles = if view.home
            then Home.render(canvas, payload, view, actions)
            else View.render(canvas, payload, view, actions)
        backdrop.Visible = view.home
            or not view.apartment
            or (payload and payload.observation.status ~= "running")
        player:SetAttribute("HousepadOpen", backdrop.Visible)
        fit()
    end

    remote.OnClientEvent:Connect(function(message)
        if type(message) ~= "table" or message.kind ~= "state" then
            return
        end
        saveDraft()
        local pending = view.pendingMessage
        local receipt = message.receipt
        if pending and receipt and receipt.requestId == pending.requestId then
            if receipt.accepted then
                view.drafts[pending.channel] = ""
                if view.attachments then
                    view.attachments[pending.channel] = nil
                end
            end
            view.pendingMessage = nil
        end
        if
            payload
            and (
                payload.observation.phase ~= message.observation.phase
                or payload.observation.day ~= message.observation.day
                or payload.observation.revision > message.observation.revision
            )
        then
            view.apartment = message.observation.phase == "action_one"
                or message.observation.phase == "action_two"
            view.actionChat = false
            view.attachments = {}
        end
        payload = message
        if message.color then
            view.color = message.color
        end
        redraw()
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() or not payload then
            return
        end
        if view.home then
            -- The home screen answers to its own two keys only, so a stray
            -- gameplay key cannot advance a day from behind it.
            if input.KeyCode == Enum.KeyCode.H and view.homeTab == "howto" then
                actions.homeTab("home")
            elseif input.KeyCode == Enum.KeyCode.T or input.KeyCode == Enum.KeyCode.Return then
                if payload.observation.status == "running" then
                    actions.play()
                else
                    actions.newRound()
                end
            end
        elseif input.KeyCode == Enum.KeyCode.H then
            actions.home()
        elseif input.KeyCode == Enum.KeyCode.M then
            actions.apartment()
        elseif input.KeyCode == Enum.KeyCode.T and payload.observation.status == "running" then
            actions.ready()
        elseif input.KeyCode == Enum.KeyCode.E and view.apartment and payload.reachable then
            remote:FireServer({ kind = "chore" })
        elseif input.KeyCode == Enum.KeyCode.Y and handles.chat then
            handles.chat:CaptureFocus()
        end
    end)
    -- Layout follows viewport changes; this does not advance gameplay time.
    RunService:BindToRenderStep("HousepadLayout", Enum.RenderPriority.Last.Value, fit)
    redraw()
    remote:FireServer({ kind = "sync" })
    print(
        "[HousePad] Home screen first: T starts. In play: T continue, M apartment, Y messages, H home."
    )
end

return Hud
