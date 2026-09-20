--!strict
-- Roommate speech, shown over the bean that said it.
--
-- The HousePad already carries every message the player may read. This puts the
-- newest line above the roommate in the room as well, so a live model's reply is
-- visible where the player is looking instead of only in a chat list. The text is
-- the same message the round emitted; nothing here decides what is said.
--
-- Audience filtering is not repeated here. The events come from
-- `Round.observe(state, playerId)`, which has already removed every private
-- exchange the player is not part of, so a bubble can only ever show a line the
-- player is allowed to read.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Link = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NemotronLink"))

local Voices = {}

-- Long enough to read a sentence, short enough that four roommates at one stop do
-- not leave the room covered in text.
Voices.holdSeconds = 7
Voices.maxCharacters = 120

local function bubble(bean: Model): TextLabel?
    local head = bean:FindFirstChild("Head") :: BasePart?
    local anchor = head or bean.PrimaryPart
    if not anchor then
        return nil
    end
    local existing = bean:FindFirstChild("RoundVoice")
    if existing then
        return existing:FindFirstChild("Line", true) :: TextLabel?
    end

    local gui = Instance.new("BillboardGui")
    gui.Name = "RoundVoice"
    gui.Adornee = anchor
    gui.Size = UDim2.fromOffset(240, 74)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 200
    -- The client owns `Enabled`, because only it knows which room the viewer is
    -- looking at. The server states the intent through the `Speaking` attribute;
    -- an always-on-top bubble would otherwise hang over the other room.
    gui.Enabled = false
    gui:SetAttribute("Speaking", false)
    gui.Parent = bean

    local frame = Instance.new("Frame")
    frame.Name = "Bubble"
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
    label.Name = "Line"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(69, 62, 54)
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    -- Model output is untrusted: show it literally, never as markup.
    label.RichText = false
    label.Text = ""
    label.Parent = frame
    return label
end

-- `beans` maps an actor ID to the bean model's name in the scene.
function Voices.new(scene: Instance, beans: { [string]: string }): any
    local shown: { [string]: number } = {}
    local service = {}

    local function hide(id: string)
        local bean = scene:FindFirstChild(beans[id] or "")
        local gui = if bean then bean:FindFirstChild("RoundVoice") else nil
        if gui then
            gui:SetAttribute("Speaking", false)
        end
        shown[id] = nil
    end

    local function say(id: string, speech: string)
        local bean = scene:FindFirstChild(beans[id] or "") :: Model?
        if not bean then
            return
        end
        local label = bubble(bean)
        if not label then
            return
        end
        local text = Link.clip(speech)
        if utf8.len(text) and (utf8.len(text) :: number) > Voices.maxCharacters then
            local cut = utf8.offset(text, Voices.maxCharacters) or Voices.maxCharacters
            text = string.sub(text, 1, cut - 1) .. "\u{2026}"
        end
        label.Text = text
        local gui = label.Parent.Parent :: BillboardGui
        gui:SetAttribute("Speaking", true)
        shown[id] = os.clock() + Voices.holdSeconds
    end

    -- Show every roommate line the player has not seen yet. Called whenever the
    -- round changes, so a stop that produces four replies shows all four.
    function service.sync(session: any, observation: any)
        session.spokenTo = session.spokenTo or 0
        for _, event in observation.events do
            if
                event.id > session.spokenTo
                and event.kind == "message"
                and beans[event.data.actor]
                and type(event.data.speech) == "string"
            then
                say(event.data.actor, event.data.speech)
            end
            if event.id > session.spokenTo then
                session.spokenTo = event.id
            end
        end
    end

    function service.expire()
        local now = os.clock()
        for id, until_ in shown do
            if now >= until_ then
                hide(id)
            end
        end
    end

    function service.clear(session: any)
        for id in beans do
            hide(id)
        end
        session.spokenTo = 0
    end

    RunService.Heartbeat:Connect(service.expire)
    return service
end

return Voices
