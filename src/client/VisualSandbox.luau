--!strict
local Sandbox = {}

-- `options.paletteKeys = false` leaves the number keys unbound so a gameplay HUD
-- can claim them; the palette comparison only belongs to the visual study.
function Sandbox.start(options: any?)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ContextActionService = game:GetService("ContextActionService")
    local StarterGui = game:GetService("StarterGui")
    local GuiService = game:GetService("GuiService")
    local player = Players.LocalPlayer
    local shared = ReplicatedStorage:WaitForChild("Shared")
    local config = require(shared:WaitForChild("VisualStudy"))
    local Grid = require(shared:WaitForChild("GridMovement"))
    local remote = ReplicatedStorage:WaitForChild("VisualStudyMove") :: RemoteEvent
    local scene = workspace:WaitForChild("DevStage"):WaitForChild("VisualStudy")
    local controls = require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
    controls:Disable()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
    end)
    task.spawn(function()
        for _ = 1, 10 do
            if
                pcall(function()
                    StarterGui:SetCore("ResetButtonCallback", false)
                end)
            then
                break
            end
            task.wait(0.3)
        end
    end)
    local paletteKeys = not (options and options.paletteKeys == false)
    local actors: { [number]: any } = {}
    local held: { Enum.KeyCode } = {}
    local pending = false
    local pendingAt = 0
    local nextRepeat = 0
    local room = ""
    local paletteName = "Warm"
    local keyDirections = {
        [Enum.KeyCode.W] = "up",
        [Enum.KeyCode.Up] = "up",
        [Enum.KeyCode.D] = "right",
        [Enum.KeyCode.Right] = "right",
        [Enum.KeyCode.S] = "down",
        [Enum.KeyCode.Down] = "down",
        [Enum.KeyCode.A] = "left",
        [Enum.KeyCode.Left] = "left",
    }
    local function clearInput()
        table.clear(held)
        nextRepeat = 0
    end
    local function stylePart(part: Instance)
        if not part:IsA("BasePart") then
            return
        end
        local tone = part:GetAttribute("VisualTone")
        if tone then
            local value = config.palettes[paletteName][tone]
            part.Color = Color3.fromRGB(value[1], value[2], value[3])
        end
        local owner: Instance? = part.Parent
        local partRoom = nil
        while owner and owner ~= scene do
            partRoom = owner:GetAttribute("Room")
            if partRoom then
                break
            end
            owner = owner.Parent
        end
        local doorwayPreview = part:GetAttribute("Row") == config.doorwayRow
            and (
                (room == "Kitchen" and part:GetAttribute("Column") == 6)
                or (room == "Lounge" and part:GetAttribute("Column") == 5)
            )
        part.LocalTransparencyModifier = if partRoom
                and partRoom ~= room
                and not doorwayPreview
            then 1
            else 0
    end
    local function refreshScene()
        for _, item in scene:GetDescendants() do
            stylePart(item)
        end
    end
    scene.DescendantAdded:Connect(stylePart)

    local function busy(): boolean
        local actor = actors[player.UserId]
        return pending or not actor or actor.target ~= nil
    end
    local function step(direction: string)
        if busy() then
            return
        end
        pending = true
        pendingAt = os.clock()
        remote:FireServer({ kind = "step", direction = direction })
    end
    remote.OnClientEvent:Connect(function(message: any)
        if message.kind == "snapshot" then
            table.clear(actors)
            for _, entry in message.actors do
                actors[entry.userId] = entry
            end
            pending = false
            room = ""
        elseif message.kind == "hop" then
            actors[message.userId] = message
            if message.userId == player.UserId then
                pending = false
            end
        elseif message.kind == "rejected" then
            pending = false
        end
    end)
    local function input(_name: string, state: Enum.UserInputState, object: InputObject)
        local key = object.KeyCode
        if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
            local index = table.find(held, key)
            if index then
                table.remove(held, index)
            end
            return Enum.ContextActionResult.Sink
        end
        if
            state ~= Enum.UserInputState.Begin
            or UserInputService:GetFocusedTextBox()
            or GuiService.MenuIsOpen
            or player:GetAttribute("HousepadOpen")
        then
            return Enum.ContextActionResult.Sink
        end
        if keyDirections[key] then
            if not table.find(held, key) then
                table.insert(held, key)
                step(keyDirections[key])
                nextRepeat = os.clock() + config.holdDelay
            end
        elseif paletteKeys and (key == Enum.KeyCode.One or key == Enum.KeyCode.Two) then
            paletteName = if key == Enum.KeyCode.One then "Warm" else "LightWarm"
            scene:SetAttribute("PreviewPalette", paletteName)
            refreshScene()
        elseif key == Enum.KeyCode.R then
            clearInput()
            if not busy() then
                pending = true
                pendingAt = os.clock()
                remote:FireServer({ kind = "reset" })
            end
        end
        return Enum.ContextActionResult.Sink
    end
    local bound = {
        Enum.KeyCode.W,
        Enum.KeyCode.A,
        Enum.KeyCode.S,
        Enum.KeyCode.D,
        Enum.KeyCode.Up,
        Enum.KeyCode.Left,
        Enum.KeyCode.Down,
        Enum.KeyCode.Right,
        Enum.KeyCode.R,
    }
    if paletteKeys then
        table.insert(bound, Enum.KeyCode.One)
        table.insert(bound, Enum.KeyCode.Two)
        table.insert(bound, Enum.KeyCode.Space)
    end
    ContextActionService:BindActionAtPriority(
        "VisualStudyKeys",
        input,
        false,
        3000,
        table.unpack(bound)
    )
    UserInputService.WindowFocusReleased:Connect(clearInput)
    GuiService.MenuOpened:Connect(clearInput)
    player:GetAttributeChangedSignal("HousepadOpen"):Connect(clearInput)

    RunService:BindToRenderStep("VisualStudy", Enum.RenderPriority.Camera.Value + 1, function()
        local now = workspace:GetServerTimeNow()
        for _, actor in actors do
            local model = scene:FindFirstChild(actor.modelName) :: Model?
            if model then
                local cell = actor.cell
                local x, z = Grid.point(config, cell)
                local y = config.floorY
                if actor.target then
                    local t = math.clamp((now - actor.startsAt) / config.hopSeconds, 0, 1)
                    local targetX, targetZ = Grid.point(config, actor.target)
                    x += (targetX - x) * t
                    z += (targetZ - z) * t
                    y += math.sin(t * math.pi) * config.hopHeight
                    if t >= 1 then
                        actor.cell = actor.target
                        actor.target = nil
                        y = config.floorY
                    end
                end
                model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, actor.angle, 0))
                local activeRoom = Grid.room(config, actor.cell)
                -- The player's view changes only on landing at the doorway's next cell.
                if actor.userId == player.UserId and room ~= activeRoom then
                    room = activeRoom
                    refreshScene()
                end
                for _, part in model:GetDescendants() do
                    if part:IsA("BasePart") then
                        part.LocalTransparencyModifier = if activeRoom == room then 0 else 1
                    end
                end
                -- A roommate's speech bubble belongs to the room its speaker is
                -- standing in. It is always on top, so the server states the intent
                -- and the viewer's own room decides whether it is drawn.
                local voice = model:FindFirstChild("RoundVoice") :: BillboardGui?
                if voice then
                    voice.Enabled = activeRoom == room and voice:GetAttribute("Speaking") == true
                end
            end
        end
        local clockNow = os.clock()
        if #held > 0 and clockNow >= nextRepeat and not busy() then
            step(keyDirections[held[#held]])
            nextRepeat = clockNow + config.repeatSeconds
        end
        if pending and clockNow - pendingAt > 2 then
            clearInput()
            pendingAt = clockNow
            remote:FireServer({ kind = "sync" })
        end
        local camera = workspace.CurrentCamera
        if camera and room ~= "" then
            local center = Vector3.new(if room == "Kitchen" then -12 else 12, 1.3, 0)
            local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
            local zoom = math.max(1, 1.3 / aspect)
            camera.CameraType = Enum.CameraType.Scriptable
            camera.FieldOfView = 32
            camera.CFrame = CFrame.lookAt(center + Vector3.new(31, 34, 43) * zoom, center)
            camera.Focus = CFrame.new(center)
        end
    end)
    scene:SetAttribute("PreviewPalette", paletteName)
    remote:FireServer({ kind = "sync" })
    print(
        if paletteKeys
            then "[Roommate] Client ready (visual-sandbox-1): WASD/arrows hop; 1 warm; 2 lighter warm; R reset"
            else "[Roommate] Client ready: WASD/arrows hop; R reset"
    )
end

return Sandbox
