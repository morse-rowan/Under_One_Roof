--!strict
-- Sanity check only: typed prompt -> local bridge -> Nemotron -> speech bubble.
-- Server-authoritative; the API key lives in `tools/nemotron_proxy.py`, never here.
-- Nothing calls out until a prompt is sent, so normal play stays inference-free.
local Sanity = {}

local IDLE = "Ask me something."
local WAITING = "\u{2026}"

local function bubble(speaker: Model): TextLabel
    local head = speaker:FindFirstChild("Head") :: BasePart?
    local gui = Instance.new("BillboardGui")
    gui.Name = "NemotronBubble"
    gui.Adornee = head or speaker.PrimaryPart
    gui.Size = UDim2.fromOffset(280, 86)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 200
    gui.Parent = speaker

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(248, 241, 225)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    local padding = Instance.new("UIPadding")
    for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
        (padding :: any)[side] = UDim.new(0, 8)
    end
    padding.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "Reply"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(69, 62, 54)
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.RichText = false -- The reply is untrusted model output: show it literally.
    label.Text = IDLE
    label.Parent = frame
    return label
end

function Sanity.start(scene: Instance)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ServerStorage = game:GetService("ServerStorage")
    local HttpService = game:GetService("HttpService")
    local Link = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NemotronLink"))

    local speaker = scene:FindFirstChild(Link.speaker, true) :: Model?
    if not speaker then
        warn("[Nemotron] No " .. Link.speaker .. " roommate found; sanity check disabled.")
        return
    end
    local label = bubble(speaker)

    local busy = false
    local lastAt = -math.huge
    local function ask(value: any)
        local prompt, reason = Link.prompt(value)
        if not prompt then
            label.Text = reason
            warn("[Nemotron] Rejected prompt: " .. reason)
            return
        end
        local now = os.clock()
        if busy or now - lastAt < Link.cooldownSeconds then
            warn("[Nemotron] Ignored: one question at a time.")
            return
        end
        busy = true
        lastAt = now
        label.Text = WAITING
        print('[Nemotron] Asking: "' .. prompt .. '"')
        task.spawn(function()
            local started = os.clock()
            local ok, result = pcall(function()
                return HttpService:RequestAsync({
                    Url = Link.url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(Link.body(prompt)),
                })
            end)
            local elapsed = os.clock() - started
            local text, answered
            if not ok then
                local message = tostring(result)
                text = if string.find(message, "Http requests are not enabled")
                    then "Enable HTTP requests in Studio."
                    else "The local bridge is not reachable."
                answered = false
                warn("[Nemotron] Request failed: " .. message)
            else
                local decoded
                local parsed, payload = pcall(HttpService.JSONDecode, HttpService, result.Body)
                if parsed then
                    decoded = payload
                end
                text, answered = Link.reply(result.StatusCode, decoded)
            end
            label.Text = text
            print(
                string.format(
                    "[Nemotron] %s in %.2fs: %s",
                    if answered then "Replied" else "Failed",
                    elapsed,
                    text
                )
            )
            busy = false
        end)
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = "NemotronAsk"
    remote.Parent = ReplicatedStorage
    remote.OnServerEvent:Connect(function(_player: Player, value: any)
        ask(value)
    end)

    -- Same entry point for a command bar switched to the Server context.
    local bindable = Instance.new("BindableEvent")
    bindable.Name = "NemotronAsk"
    bindable.Parent = ServerStorage
    bindable.Event:Connect(ask)

    print("[Nemotron] Sanity check ready. Fire ReplicatedStorage.NemotronAsk with a prompt.")
end

return Sanity
