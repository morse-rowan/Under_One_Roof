--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local buildInfo = require(shared:WaitForChild("BuildInfo"))
if buildInfo.menuPreview then
    -- Spawned so the study's own WaitForChild never delays the running mode.
    task.spawn(function()
        require(script.Parent.MenuPreview).start()
    end)
end
if buildInfo.mode == "visual-sandbox" then
    require(script.Parent.VisualSandbox).start()
    return
end
local config = require(shared:WaitForChild("Apartment"))
local remote = ReplicatedStorage:WaitForChild("ApartmentAction") :: RemoteEvent
local state: any = nil
local selectedTask: string? = nil
local offer = 0
local room = "Kitchen"
local nearestTask: string? = nil
local holdingTask: string? = nil
local holdStarted = 0
local colors = {
    ink = Color3.fromRGB(31, 44, 51),
    panel = Color3.fromRGB(247, 239, 220),
    muted = Color3.fromRGB(87, 101, 104),
    accent = Color3.fromRGB(231, 176, 91),
    green = Color3.fromRGB(96, 147, 122),
    white = Color3.fromRGB(255, 251, 240),
}
local screen = Instance.new("ScreenGui")
screen.Name = "ApartmentHUD"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")
local canvas = Instance.new("Frame")
canvas.Name = "Canvas"
canvas.Size = UDim2.fromOffset(1000, 650)
canvas.AnchorPoint = Vector2.new(0.5, 0.5)
canvas.Position = UDim2.fromScale(0.5, 0.5)
canvas.BackgroundTransparency = 1
canvas.Parent = screen
local scale = Instance.new("UIScale")
scale.Parent = canvas

local function corner(target: GuiObject, radius: number)
    local rounding = Instance.new("UICorner")
    rounding.CornerRadius = UDim.new(0, radius)
    rounding.Parent = target
end
local function panel(
    parent: Instance,
    name: string,
    x: number,
    y: number,
    w: number,
    h: number,
    color: Color3
): Frame
    local item = Instance.new("Frame")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(w, h)
    item.BackgroundColor3 = color
    item.BorderSizePixel = 0
    item.Parent = parent
    corner(item, 12)
    return item
end
local function label(
    parent: Instance,
    name: string,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    size: number,
    color: Color3?
): TextLabel
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(w, h)
    item.BackgroundTransparency = 1
    item.Text = text
    item.TextColor3 = color or colors.ink
    item.TextSize = size
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextYAlignment = Enum.TextYAlignment.Center
    item.Font = Enum.Font.GothamMedium
    item.Parent = parent
    return item
end
local function button(
    parent: Instance,
    name: string,
    text: string,
    x: number,
    y: number,
    w: number,
    h: number,
    callback: () -> ()
): TextButton
    local item = Instance.new("TextButton")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(w, h)
    item.Text = text
    item.TextSize = 16
    item.Font = Enum.Font.GothamBold
    item.TextColor3 = colors.ink
    item.BackgroundColor3 = colors.accent
    item.BorderSizePixel = 0
    item.Parent = parent
    corner(item, 8)
    item.Activated:Connect(callback)
    return item
end
local function request(kind: string, extra: any?)
    local payload = extra or {}
    payload.kind = kind
    remote:FireServer(payload)
end
local header = panel(canvas, "Header", 20, 12, 960, 68, colors.ink)
label(header, "Title", "UNDER ONE ROOF", 20, 8, 305, 27, 24, colors.white)
local phaseLabel =
    label(header, "Phase", "Connecting to the apartment...", 20, 37, 380, 22, 14, colors.accent)
local meters = label(header, "Meters", "", 410, 12, 530, 44, 18, colors.white)
local planning = panel(canvas, "Planning", 20, 94, 960, 460, colors.panel)
label(planning, "Heading", "THE MORNING PLAN", 24, 18, 365, 32, 23)
label(
    planning,
    "Goal",
    "Survive 3 days. Eviction at 0 property or 100 heat. You can't handle everything alone.",
    24,
    54,
    353,
    46,
    15,
    colors.muted
)
local taskSummary = label(planning, "TaskSummary", "", 24, 105, 355, 210, 15)
taskSummary.TextYAlignment = Enum.TextYAlignment.Top
local budgets = label(planning, "Budgets", "", 24, 316, 355, 32, 15)
label(
    planning,
    "Rules",
    "Opening a different chat spends 1 conversation. Offers reserve cash now; roommates deliver at day's end.",
    24,
    352,
    352,
    42,
    14,
    colors.muted
)
button(planning, "StartAction", "START THE DAY  >", 24, 400, 353, 40, function()
    request("start")
end)
local composer = panel(planning, "Composer", 400, 16, 542, 426, colors.white)
label(composer, "Heading", "ROOMMATE MESSAGES", 18, 12, 420, 23, 17)
local recipientButtons: { [string]: TextButton } = {}
for index, name in config.roommateOrder do
    recipientButtons[name] = button(
        composer,
        name,
        "@" .. name,
        18 + (index - 1) * 172,
        46,
        162,
        36,
        function()
            request("talk", { roommate = name })
        end
    )
end
local conversationLabel = label(
    composer,
    "Conversation",
    "Choose a roommate to open a conversation.",
    18,
    90,
    506,
    28,
    15
)
local replyLabel = label(
    composer,
    "Reply",
    "Blue can fix things. Green wants fairness. Red wants a party. Who needs your attention?",
    18,
    124,
    506,
    55,
    16,
    colors.muted
)
replyLabel.TextYAlignment = Enum.TextYAlignment.Top
local messageBox = Instance.new("TextBox")
messageBox.Name = "Message"
messageBox.Position = UDim2.fromOffset(18, 184)
messageBox.Size = UDim2.fromOffset(506, 56)
messageBox.BackgroundColor3 = colors.panel
messageBox.TextColor3 = colors.ink
messageBox.TextSize = 16
messageBox.Font = Enum.Font.Gotham
messageBox.PlaceholderText = "Optional wording (try 'please')..."
messageBox.Text = ""
messageBox.ClearTextOnFocus = false
messageBox.TextWrapped = true
messageBox.MultiLine = false
messageBox.Parent = composer
corner(messageBox, 8)
label(
    composer,
    "ChipHelp",
    "Attach a task explicitly. Text alone never creates a deal.",
    18,
    246,
    506,
    22,
    13,
    colors.muted
)
local chipButtons: { [string]: TextButton } = {}
local function updateChips()
    for id, item in chipButtons do
        item.BackgroundColor3 = if selectedTask == id then colors.green else colors.panel
        item.TextColor3 = if selectedTask == id then colors.white else colors.ink
    end
end
for index, id in { "leak", "dishes", "party" } do
    chipButtons[id] = button(
        composer,
        id,
        "#" .. id,
        18 + (index - 1) * 172,
        275,
        162,
        32,
        function()
            selectedTask = if selectedTask == id then nil else id
            updateChips()
        end
    )
end
local offerLabel = label(composer, "Offer", "Offer: $0", 62, 320, 124, 32, 18)
button(composer, "Less", "-", 18, 318, 36, 36, function()
    offer = math.max(0, offer - 5)
    offerLabel.Text = "Offer: $" .. offer
end)
button(composer, "More", "+", 188, 318, 36, 36, function()
    offer = math.min(100, offer + 5)
    offerLabel.Text = "Offer: $" .. offer
end)
button(composer, "Polite", "Ask politely", 238, 318, 286, 36, function()
    messageBox.Text = "Could you please help with this?"
end)
button(composer, "Send", "SEND MESSAGE + ATTACHED TERMS", 18, 369, 506, 40, function()
    request("message", {
        text = messageBox.Text,
        terms = if selectedTask then { task = selectedTask, amount = offer } else nil,
    })
end)
local actionPanel = panel(canvas, "Action", 20, 94, 265, 345, colors.panel)
local roomLabel = label(actionPanel, "Room", "KITCHEN", 18, 12, 230, 26, 21)
local clockLabel = label(actionPanel, "Clock", "", 18, 44, 230, 26, 20)
local actionTasks = label(actionPanel, "Tasks", "", 18, 80, 230, 194, 14)
actionTasks.TextYAlignment = Enum.TextYAlignment.Top
label(
    actionPanel,
    "Controls",
    "WASD to move / hold E at a station\nDoorway connects the rooms.",
    18,
    287,
    230,
    42,
    13,
    colors.muted
)
local finish = button(canvas, "Finish", "END DAY EARLY  >", 742, 508, 238, 46, function()
    request("finish")
end)
local interact = button(canvas, "Interact", "HOLD E", 302, 508, 420, 46, function() end)
interact.Visible = false
local function beginHold()
    if nearestTask and not holdingTask then
        holdingTask = nearestTask
        holdStarted = os.clock()
        request("beginChore", { id = holdingTask })
    end
end
local function endHold()
    holdingTask = nil
end
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.E then
        beginHold()
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.E then
        endHold()
    end
end)
interact.InputBegan:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        beginHold()
    end
end)
interact.InputEnded:Connect(function(input)
    if
        input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        endHold()
    end
end)
UserInputService.WindowFocusReleased:Connect(endHold)
local results = panel(canvas, "Results", 145, 106, 710, 448, colors.panel)
local resultTitle = label(results, "Heading", "DAY COMPLETE", 28, 22, 654, 38, 28)
local resultBody = label(results, "Report", "", 28, 80, 654, 230, 18)
resultBody.TextYAlignment = Enum.TextYAlignment.Top
local relationships = label(results, "Relationships", "", 28, 316, 654, 48, 15, colors.muted)
local nextButton = button(results, "Continue", "NEXT MORNING  >", 28, 380, 654, 44, function()
    request(if state and state.phase == "results" then "next" else "restart")
end)
local toast = panel(canvas, "Toast", 20, 570, 960, 62, colors.ink)
local toastLabel = label(toast, "Text", "Connecting...", 18, 9, 924, 44, 16, colors.white)
planning.Visible = false
actionPanel.Visible = false
results.Visible = false
finish.Visible = false

local function render(newState: any, message: string?)
    local prior = state
    state = newState
    if not state then
        return
    end
    local phase = state.phase
    local planningNow = phase == "planning"
    planning.Visible = planningNow
    actionPanel.Visible = phase == "action"
    finish.Visible = phase == "action"
    results.Visible = phase == "results" or phase == "won" or phase == "lost"
    phaseLabel.Text =
        string.format("DAY %d / %d   |   %s", state.day, config.days, string.upper(phase))
    meters.Text = string.format(
        "$%d cash    |    Property %d    |    Heat %d",
        state.cash,
        state.property,
        state.heat
    )
    budgets.Text = string.format(
        "%d chats left  /  %d efforts when the day starts",
        state.conversationsLeft,
        state.effort
    )
    clockLabel.Text =
        string.format("%ds  /  %d efforts left", math.ceil(state.remaining), state.effort)
    local planLines = {}
    local actionLines = {}
    for _, id in config.taskOrder do
        local taskState = state.tasks[id]
        local data = config.tasks[id]
        local status = if taskState.status == "open"
            then data.warning
            elseif taskState.status == "assigned" then taskState.owner
                .. " agreed ($"
                .. taskState.payment
                .. ")"
            else "Done by " .. taskState.owner
        table.insert(
            planLines,
            data.name .. (if data.cost > 0 then " ($" .. data.cost .. ")" else "") .. "\n" .. status
        )
        table.insert(
            actionLines,
            (if taskState.status == "open" then "[ ] " else "[+] ")
                .. data.name
                .. "\n"
                .. (if taskState.status == "open" then data.room else taskState.owner)
        )
    end
    taskSummary.Text = table.concat(planLines, "\n\n")
    actionTasks.Text = table.concat(actionLines, "\n\n")
    local conversation = state.conversation
    conversationLabel.Text = if conversation
        then string.format(
            "@%s  /  %d of 3 messages  /  %s",
            conversation.roommate,
            conversation.messages,
            if conversation.finalized then "deal recorded" else "one deal available"
        )
        else "Choose a roommate to open a conversation."
    for name, item in recipientButtons do
        item.BackgroundColor3 = if conversation and conversation.roommate == name
            then colors.green
            else colors.accent
    end
    if
        not prior
        or prior.day ~= state.day
        or (
            conversation
            and (not prior.conversation or prior.conversation.roommate ~= conversation.roommate)
        )
    then
        messageBox.Text = ""
        selectedTask = nil
        offer = 0
        offerLabel.Text = "Offer: $0"
        updateChips()
    end
    if message and message ~= "" then
        toastLabel.Text = message
        if planningNow then
            replyLabel.Text = message
        end
    end
    resultTitle.Text = if phase == "won"
        then "STILL UNDER ONE ROOF!"
        elseif phase == "lost" then "EVICTED"
        else "DAY " .. state.day .. " / THE FALLOUT"
    resultBody.Text = table.concat(state.report, "\n\n")
    relationships.Text = string.format(
        "Relationships carry forward: Blue %+d / Green %+d / Red %+d\nCash and household damage carry forward too.",
        state.trust.Blue,
        state.trust.Green,
        state.trust.Red
    )
    nextButton.Text = if phase == "results" then "NEXT MORNING  >" else "PLAY AGAIN  >"
    local apartment = workspace:FindFirstChild("DevStage")
    local scene = if apartment then apartment:FindFirstChild("Apartment") else nil
    if scene then
        for _, id in config.taskOrder do
            local station = scene:FindFirstChild(id) :: BasePart?
            if station then
                station.Color = if state.tasks[id].status == "done"
                    then colors.green
                    elseif state.tasks[id].status == "assigned" then colors.accent
                    else Color3.fromRGB(113, 137, 136)
            end
        end
        local puddle = scene:FindFirstChild("Puddle") :: BasePart?
        if puddle then
            puddle.Transparency = if state.tasks.leak.status == "done" then 1 else 0.25
        end
    end
end
remote.OnClientEvent:Connect(render)
request("sync")
RunService:BindToRenderStep("ApartmentCamera", Enum.RenderPriority.Camera.Value + 1, function()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    local viewport = camera.ViewportSize
    scale.Scale = math.min((viewport.X - 24) / 1000, (viewport.Y - 50) / 650, 1.3)
    local character = player.Character
    local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart else nil
    if root then
        if root.Position.X > 2 then
            room = "Lounge"
        elseif root.Position.X < -2 then
            room = "Kitchen"
        end
    end
    roomLabel.Text = string.upper(room)
    local focus = Vector3.new(if room == "Kitchen" then -15 else 15, 0, 0)
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 50
    camera.CFrame = CFrame.lookAt(focus + Vector3.new(24, 35, 34), focus)
    camera.Focus = CFrame.new(focus)
    nearestTask = nil
    local nearestDistance = 8
    if root and state and state.phase == "action" and state.effort > 0 then
        for _, id in config.taskOrder do
            local data = config.tasks[id]
            local distance = (root.Position - Vector3.new(data.x, 1.3, data.z)).Magnitude
            if state.tasks[id].status == "open" and distance <= nearestDistance then
                nearestDistance = distance
                nearestTask = id
            end
        end
    end
    interact.Visible = nearestTask ~= nil
    if holdingTask and holdingTask ~= nearestTask then
        endHold()
    end
    if nearestTask then
        local data = config.tasks[nearestTask]
        interact.Text = "HOLD E / "
            .. data.name
            .. (if data.cost > 0 then " / $" .. data.cost else "")
        if holdingTask then
            local progress = math.min(1, (os.clock() - holdStarted) / 1.15)
            interact.Text = string.format("%s ... %d%%", data.name, math.floor(progress * 100))
            if progress >= 1 then
                request("completeChore", { id = holdingTask })
                endHold()
            end
        end
    end
end)
print("[Roommate] Client ready (gameplay-prototype-1)")
